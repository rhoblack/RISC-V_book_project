// =============================================================================
// CSR 유닛 (Control and Status Register Unit)
// Chapter 18.2~18.3 — CSR과 시스템 명령어
// RISC-V 프로세서 설계 완전정복
// =============================================================================
// RISC-V Privileged Architecture v1.12 기준 M-mode 핵심 CSR 구현.
// 구현 CSR: mstatus(0x300), mie(0x304), mtvec(0x305), mscratch(0x340),
//            mepc(0x341), mcause(0x342), mip(0x344) — 총 7개
//
// 설계 결정 사항:
//   - mip.MTIP/MEIP/MSIP: 외부 입력 신호로 직접 반영 (소프트웨어 직접 클리어 불가)
//   - mstatus WPRI 비트: 항상 0으로 강제 (마스크 적용)
//   - mepc 하위 1비트: 항상 0으로 강제 (4바이트 정렬)
//   - Ch19 트랩 처리 인터페이스 예약: trap_en, trap_pc, trap_cause, mret_en
// =============================================================================

module csr_unit #(
   parameter HART_ID = 0         // 하드웨어 스레드 ID (현재 미사용, 확장용)
)(
   input  logic        clk,
   input  logic        rst_n,

   // -------------------------------------------------------------------------
   // CSR 읽기/쓰기 인터페이스 (파이프라인 ID/WB 스테이지 연결)
   // -------------------------------------------------------------------------
   input  logic [11:0] csr_addr,        // CSR 주소 (12비트: 명령어 [31:20])
   input  logic        csr_we,          // CSR 쓰기 활성화 (1=쓰기 허용)
   input  logic [2:0]  csr_op,          // CSR 연산 코드 (funct3: 001~111)
   input  logic [31:0] csr_wdata,       // 쓰기 데이터 (rs1 값 또는 uimm zero-extended)
   output logic [31:0] csr_rdata,       // 읽기 데이터 (명령어 실행 이전 원래 값)

   // -------------------------------------------------------------------------
   // 인터럽트 입력 (하드웨어에서 직접 구동 — 소프트웨어 쓰기 불가)
   // -------------------------------------------------------------------------
   input  logic        timer_irq,       // 타이머 인터럽트 요청 → mip.MTIP[7]
   input  logic        ext_irq,         // 외부 인터럽트 요청   → mip.MEIP[11]
   input  logic        sw_irq,          // 소프트웨어 인터럽트  → mip.MSIP[3]

   // -------------------------------------------------------------------------
   // 트랩 처리 인터페이스 (Chapter 19 trap_unit에서 연결)
   // 현재 챕터(Ch18)에서는 0으로 고정하여 독립 동작 가능
   // -------------------------------------------------------------------------
   input  logic        trap_en,         // 트랩 진입 활성화 (예외/인터럽트 발생 시 1)
   input  logic [31:0] trap_pc,         // 트랩 발생 시점의 PC → mepc에 저장
   input  logic [31:0] trap_cause,      // 트랩 원인 코드 → mcause에 저장
   input  logic        mret_en,         // MRET 명령어 실행 신호 (트랩 복귀)

   // -------------------------------------------------------------------------
   // CSR 주요 값 출력 (파이프라인 제어 및 트랩 처리용)
   // -------------------------------------------------------------------------
   output logic [31:0] mtvec_out,       // 예외 핸들러 기저 주소 (파이프라인 제어용)
   output logic [31:0] mepc_out,        // 예외 복귀 PC (MRET 처리용)
   output logic        irq_pending      // 인터럽트 펜딩 (1=처리 필요)
);

   // =========================================================================
   // CSR funct3 연산 코드 정의 (RISC-V ISA Table 9.1)
   // =========================================================================
   localparam CSR_RW  = 3'b001;   // CSRRW:  rd = CSR;        CSR = rs1
   localparam CSR_RS  = 3'b010;   // CSRRS:  rd = CSR;        CSR = CSR | rs1
   localparam CSR_RC  = 3'b011;   // CSRRC:  rd = CSR;        CSR = CSR & ~rs1
   localparam CSR_RWI = 3'b101;   // CSRRWI: rd = CSR;        CSR = ZeroExt(uimm[4:0])
   localparam CSR_RSI = 3'b110;   // CSRRSI: rd = CSR;        CSR = CSR | ZeroExt(uimm)
   localparam CSR_RCI = 3'b111;   // CSRRCI: rd = CSR;        CSR = CSR & ~ZeroExt(uimm)

   // =========================================================================
   // CSR 주소 정의 (RISC-V Privileged Architecture v1.12)
   // =========================================================================
   localparam CSR_MSTATUS   = 12'h300;  // 머신 상태 레지스터
   localparam CSR_MIE       = 12'h304;  // 머신 인터럽트 활성화
   localparam CSR_MTVEC     = 12'h305;  // 머신 트랩 벡터 기저 주소
   localparam CSR_MSCRATCH  = 12'h340;  // 머신 스크래치 (소프트웨어 전용)
   localparam CSR_MEPC      = 12'h341;  // 머신 예외 PC
   localparam CSR_MCAUSE    = 12'h342;  // 머신 트랩 원인
   localparam CSR_MIP       = 12'h344;  // 머신 인터럽트 펜딩 (읽기 전용)

   // =========================================================================
   // mstatus 비트 마스크 (구현된 비트만 허용)
   // =========================================================================
   // 구현 비트: MIE[3]=1비트, MPIE[7]=1비트, MPP[12:11]=2비트
   // WPRI(Write-Preserve, Read-Ignore) 비트는 항상 0으로 강제
   // 0x0000_1888 = 32'b0000_0000_0000_0000_0001_1000_1000_1000
   //                                             ^^   ^    ^
   //                                             MPP MPIE MIE
   localparam MSTATUS_MASK = 32'h0000_1888;

   // =========================================================================
   // CSR 레지스터 선언 (always_ff로 구현 → 순차 논리 플립플롭)
   // =========================================================================
   logic [31:0] mstatus_reg;    // 머신 상태 레지스터
   logic [31:0] mie_reg;        // 머신 인터럽트 활성화 레지스터
   logic [31:0] mtvec_reg;      // 머신 트랩 벡터 기저 주소
   logic [31:0] mscratch_reg;   // 머신 스크래치 레지스터
   logic [31:0] mepc_reg;       // 머신 예외 PC 레지스터
   logic [31:0] mcause_reg;     // 머신 트랩 원인 레지스터

   // mip: 하드웨어 입력에서 직접 합성 (별도 레지스터 없음 — 조합 논리)
   logic [31:0] mip_wire;

   // =========================================================================
   // mip 합성: 하드웨어 인터럽트 입력 직결 (읽기 전용)
   // =========================================================================
   // mip.MSIP[3]:  소프트웨어 인터럽트 — CLINT에서 sw_irq로 구동
   // mip.MTIP[7]:  타이머 인터럽트   — CLINT 타이머 비교에서 timer_irq로 구동
   //               클리어 방법: mtimecmp 레지스터 변경 (mip 직접 쓰기 불가)
   // mip.MEIP[11]: 외부 인터럽트    — PLIC에서 ext_irq로 구동
   //               클리어 방법: PLIC completion 레지스터 쓰기
   assign mip_wire = {20'h0,
                      ext_irq,    // [11] MEIP: 외부 인터럽트 펜딩
                      3'h0,
                      timer_irq,  // [7]  MTIP: 타이머 인터럽트 펜딩
                      3'h0,
                      sw_irq,     // [3]  MSIP: 소프트웨어 인터럽트 펜딩
                      3'h0};

   // =========================================================================
   // CSR 읽기 데이터 생성 (always_comb — 명령어 실행 이전 원래 값 반환)
   // 원자적 동작 보장: 읽기는 쓰기 이전 값을 반환해야 함
   // =========================================================================
   always_comb begin
      csr_rdata = 32'h0;   // 기본값: 미구현 CSR는 0 반환
      case (csr_addr)
         CSR_MSTATUS:  csr_rdata = mstatus_reg & MSTATUS_MASK; // WPRI 마스킹
         CSR_MIE:      csr_rdata = mie_reg;
         CSR_MTVEC:    csr_rdata = mtvec_reg;
         CSR_MSCRATCH: csr_rdata = mscratch_reg;
         CSR_MEPC:     csr_rdata = mepc_reg;
         CSR_MCAUSE:   csr_rdata = mcause_reg;
         CSR_MIP:      csr_rdata = mip_wire;    // 하드웨어 직결 값 반환
         default:      csr_rdata = 32'h0;       // 미구현 CSR → 0
      endcase
   end

   // =========================================================================
   // CSR 쓰기 데이터 계산 (원자적 읽기-수정-쓰기)
   // csr_rdata(현재 CSR 값) + csr_wdata(쓰기 데이터) → csr_next(새 값)
   // =========================================================================
   logic [31:0] csr_next;   // 쓰기 후 새 CSR 값 (조합 논리로 계산)

   always_comb begin
      csr_next = csr_rdata;   // 기본값: 현재 값 유지 (쓰기 없을 때)
      case (csr_op)
         // ── 레지스터 소스 명령어 ──────────────────────────────────────────
         CSR_RW:  csr_next = csr_wdata;              // 전체 교체
         CSR_RS:  csr_next = csr_rdata | csr_wdata;  // 비트 세트 (OR)
         CSR_RC:  csr_next = csr_rdata & ~csr_wdata; // 비트 클리어 (AND NOT)
         // ── 즉시값 소스 명령어 (uimm은 csr_wdata로 zero-extend 전달) ─────
         CSR_RWI: csr_next = csr_wdata;              // 전체 교체 (즉시값)
         CSR_RSI: csr_next = csr_rdata | csr_wdata;  // 비트 세트 (즉시값)
         CSR_RCI: csr_next = csr_rdata & ~csr_wdata; // 비트 클리어 (즉시값)
         default: csr_next = csr_rdata;              // 변경 없음
      endcase
   end

   // =========================================================================
   // CSR 레지스터 쓰기 (우선순위: 트랩 진입 > MRET > 소프트웨어 명령어)
   // =========================================================================
   always_ff @(posedge clk or negedge rst_n) begin
      if (!rst_n) begin
         // 리셋 시 초기화: MIE=0으로 모든 인터럽트 차단 (안전 상태)
         mstatus_reg  <= 32'h0;
         mie_reg      <= 32'h0;
         mtvec_reg    <= 32'h0;         // 핸들러 주소: 0x0000_0000 (SW가 나중에 설정)
         mscratch_reg <= 32'h0;
         mepc_reg     <= 32'h0;
         mcause_reg   <= 32'h0;

      end else begin

         // ──────────────────────────────────────────────────────────────────
         // 우선순위 1: 트랩 진입 (하드웨어 자동 CSR 업데이트)
         // RISC-V Priv. Spec. 3.1.6.1: 트랩 발생 시 하드웨어가 자동 수행
         // Ch19에서 trap_en 신호가 연결됨
         // ──────────────────────────────────────────────────────────────────
         if (trap_en) begin
            // mstatus 업데이트:
            //   MPIE <- 현재 MIE 값 보존 (복귀 시 복원을 위해)
            //   MIE  <- 0 (트랩 처리 중 추가 인터럽트 차단)
            //   MPP  <- 2'b11 (M-mode에서 트랩 발생 -> M-mode로 표시)
            mstatus_reg <= (mstatus_reg & ~MSTATUS_MASK)
                         | ((mstatus_reg & 32'h8) << 4)  // MPIE <- MIE
                         | 32'h1800;                      // MPP = 2'b11 (M-mode)
                         // MIE는 0으로 초기화 (OR하지 않음)

            // mepc: 트랩 발생 시점 PC 저장 (하위 1비트 강제 0 — 4바이트 정렬)
            mepc_reg    <= {trap_pc[31:1], 1'b0};

            // mcause: 트랩 원인 코드 저장
            // 형식: {INT[31], Exception_Code[30:0]}
            //   INT=1: 비동기 인터럽트 (타이머/외부/소프트웨어)
            //   INT=0: 동기 예외 (불법 명령어/주소 오정렬 등)
            mcause_reg  <= trap_cause;

         // ──────────────────────────────────────────────────────────────────
         // 우선순위 2: MRET 명령어 — 트랩 복귀 (M-mode Return)
         // RISC-V Priv. Spec. 3.3.2: MRET 실행 시 하드웨어가 자동 수행
         // ──────────────────────────────────────────────────────────────────
         end else if (mret_en) begin
            // mstatus 복원:
            //   MIE  <- MPIE (트랩 진입 전 인터럽트 상태 복원)
            //   MPIE <- 1 (다음 트랩을 위해 MPIE 1로 설정)
            //   MPP  <- 2'b11 (M-mode — U-mode 미구현 시 최소 지원 권한 유지)
            //   ※ Priv Spec 3.3.2: U-mode 미지원 환경에서는 MRET 후 MPP를
            //     최소 지원 특권 수준(여기서는 M-mode=2'b11)으로 유지해야 함.
            mstatus_reg <= (mstatus_reg & ~MSTATUS_MASK)
                         | ((mstatus_reg & 32'h80) >> 4)  // MIE <- MPIE
                         | 32'h80                          // MPIE <- 1
                         | 32'h1800;                       // MPP <- 2'b11 (M-mode 유지)
            // mepc, mcause는 MRET 시 변경하지 않음 (디버깅/재트랩 처리 보존)

         // ──────────────────────────────────────────────────────────────────
         // 우선순위 3: 소프트웨어 CSR 명령어 (CSRRW/CSRRS/CSRRC 등)
         // ──────────────────────────────────────────────────────────────────
         end else if (csr_we) begin
            case (csr_addr)
               // mstatus: WPRI 비트를 마스크로 강제 0 처리
               CSR_MSTATUS:  mstatus_reg  <= csr_next & MSTATUS_MASK;

               // mie: 인터럽트 활성화 마스크 (소프트웨어 완전 제어)
               CSR_MIE:      mie_reg      <= csr_next;

               // mtvec: Base[31:2] + Mode[1:0] 구조 그대로 저장
               // 참고: Mode=2/3은 구현 정의 (이 교재에서는 0=Direct만 사용)
               CSR_MTVEC:    mtvec_reg    <= csr_next;

               // mscratch: 소프트웨어 자유 사용 (제약 없음)
               CSR_MSCRATCH: mscratch_reg <= csr_next;

               // mepc: 하위 1비트 강제 0 (4바이트 정렬, IALIGN=32)
               CSR_MEPC:     mepc_reg     <= {csr_next[31:1], 1'b0};

               // mcause: 소프트웨어도 쓰기 가능 (디버깅 목적)
               CSR_MCAUSE:   mcause_reg   <= csr_next;

               // mip: 소프트웨어 쓰기 무시 — 하드웨어 입력만 반영
               // (mip.MSIP는 CLINT MMIO를 통해 간접 설정)
               CSR_MIP:      ;   // 무시

               // 미구현 CSR: 쓰기 무시 (Ch18에서는 예외 발생 안 함)
               // 실제 구현 시 Illegal Instruction 예외 발생 필요 (Ch19)
               default:      ;
            endcase
         end

      end
   end

   // =========================================================================
   // CSR 값 출력 (파이프라인 제어 및 트랩 처리에 사용)
   // =========================================================================
   assign mtvec_out = mtvec_reg;   // 트랩 핸들러 진입 주소
   assign mepc_out  = mepc_reg;    // MRET 시 복귀 주소

   // 인터럽트 펜딩 조건:
   //   1. mstatus.MIE == 1 (전역 인터럽트 활성화)
   //   2. mie와 mip의 공통 비트가 1개 이상 (활성화된 소스가 펜딩 중)
   // |(mie_reg & mip_wire): reduction OR — 하나라도 겹치면 1
   assign irq_pending = mstatus_reg[3] & |(mie_reg & mip_wire);
   //                   ^^^^^^^^^          ^^^^^^^^^^^^^^^^^^^
   //                   MIE 비트[3]        활성화된 인터럽트 소스 펜딩 여부

endmodule
