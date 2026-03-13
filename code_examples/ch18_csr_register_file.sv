// ============================================================================
// CSR 레지스터 파일 (CSR Register File)
// Chapter 18 — CSR과 시스템 명령어
// RISC-V 프로세서 설계 완전정복
// ============================================================================
// M-mode 핵심 CSR 레지스터 구현
// mstatus, mtvec, mepc, mcause, mie, mip, mscratch
// ============================================================================

`timescale 1ns / 1ps

module csr_register_file (
   // --- 클럭 및 리셋 ---
   input  logic        clk,
   input  logic        rst_n,

   // --- CSR 읽기/쓰기 인터페이스 ---
   input  logic [11:0] csr_addr,     // CSR 주소 (12비트)
   input  logic [31:0] csr_wdata,    // CSR 쓰기 데이터
   input  logic        csr_w_en,     // CSR 쓰기 인에이블
   output logic [31:0] csr_rdata,    // CSR 읽기 데이터

   // --- 트랩 처리 인터페이스 (Ch19에서 사용) ---
   input  logic        trap_enter,   // 트랩 진입 신호
   input  logic [31:0] trap_pc,      // 트랩 발생 시 PC (→ mepc에 저장)
   input  logic [31:0] trap_cause,   // 트랩 원인 코드 (→ mcause에 저장)
   input  logic        mret_exec,    // MRET 명령어 실행 신호

   // --- 인터럽트 입력 (외부 소스) ---
   input  logic        ext_irq,      // 외부 인터럽트 (Ch17 주변 장치)
   input  logic        timer_irq,    // 타이머 인터럽트 (Ch17.5)
   input  logic        sw_irq,       // 소프트웨어 인터럽트

   // --- 인터럽트 출력 ---
   output logic [31:0] mtvec_out,    // 트랩 벡터 주소 (파이프라인 PC MUX용)
   output logic [31:0] mepc_out,     // MRET 복귀 주소
   output logic        irq_pending,  // 인터럽트 보류 상태

   // --- 접근 오류 ---
   output logic        csr_access_fault // 존재하지 않는 CSR 접근
);

   // =========================================================================
   // CSR 주소 상수 정의
   // =========================================================================
   localparam logic [11:0] ADDR_MSTATUS  = 12'h300;
   localparam logic [11:0] ADDR_MIE      = 12'h304;
   localparam logic [11:0] ADDR_MTVEC    = 12'h305;
   localparam logic [11:0] ADDR_MSCRATCH = 12'h340;
   localparam logic [11:0] ADDR_MEPC     = 12'h341;
   localparam logic [11:0] ADDR_MCAUSE   = 12'h342;
   localparam logic [11:0] ADDR_MIP      = 12'h344;

   // =========================================================================
   // CSR 레지스터 선언
   // =========================================================================
   logic [31:0] mstatus;   // 머신 상태
   logic [31:0] mie;       // 인터럽트 활성화
   logic [31:0] mtvec;     // 트랩 벡터 기저 주소
   logic [31:0] mscratch;  // 스크래치 레지스터
   logic [31:0] mepc;      // 예외 PC
   logic [31:0] mcause;    // 트랩 원인
   logic [31:0] mip;       // 인터럽트 보류

   // =========================================================================
   // mstatus 비트 필드 정의
   // =========================================================================
   // [3]     MIE   — 글로벌 머신 인터럽트 활성화
   // [7]     MPIE  — 트랩 진입 전 MIE 값 보존
   // [12:11] MPP   — 트랩 진입 전 특권 모드 (M-mode only이면 항상 2'b11)

   localparam int MIE_BIT  = 3;
   localparam int MPIE_BIT = 7;
   localparam int MPP_LO   = 11;
   localparam int MPP_HI   = 12;

   // =========================================================================
   // mip — 인터럽트 보류 상태 (읽기 전용 비트 포함)
   // =========================================================================
   // mip는 외부 신호에 의해 갱신되는 읽기 전용 비트를 포함
   always_comb begin
      mip        = 32'b0;
      mip[3]     = sw_irq;     // MSIP: 소프트웨어 인터럽트 보류
      mip[7]     = timer_irq;  // MTIP: 타이머 인터럽트 보류
      mip[11]    = ext_irq;    // MEIP: 외부 인터럽트 보류
   end

   // =========================================================================
   // 인터럽트 보류 판정
   // =========================================================================
   // 글로벌 인터럽트 활성화(mstatus.MIE) AND 개별 활성화(mie) AND 보류(mip)
   assign irq_pending = mstatus[MIE_BIT] & |(mie & mip);

   // =========================================================================
   // CSR 읽기 (조합 논리 — 비동기 읽기)
   // =========================================================================
   always_comb begin
      csr_rdata = 32'b0;
      csr_access_fault = 1'b0;

      case (csr_addr)
         ADDR_MSTATUS:  csr_rdata = mstatus;
         ADDR_MIE:      csr_rdata = mie;
         ADDR_MTVEC:    csr_rdata = mtvec;
         ADDR_MSCRATCH: csr_rdata = mscratch;
         ADDR_MEPC:     csr_rdata = mepc;
         ADDR_MCAUSE:   csr_rdata = mcause;
         ADDR_MIP:      csr_rdata = mip;
         default: begin
            csr_rdata = 32'b0;
            csr_access_fault = csr_w_en; // 쓰기 시에만 오류
         end
      endcase
   end

   // =========================================================================
   // CSR 쓰기 (동기 — 순차 논리)
   // =========================================================================
   always_ff @(posedge clk or negedge rst_n) begin
      if (!rst_n) begin
         // 리셋 초기값
         mstatus  <= 32'h0000_1800; // MPP = 2'b11 (M-mode)
         mie      <= 32'b0;
         mtvec    <= 32'b0;
         mscratch <= 32'b0;
         mepc     <= 32'b0;
         mcause   <= 32'b0;
      end
      else if (trap_enter) begin
         // ----- 트랩 진입 시퀀스 (하드웨어 자동 처리) -----
         // 1) mepc에 트랩 발생 PC 저장
         mepc <= trap_pc;
         // 2) mcause에 트랩 원인 기록
         mcause <= trap_cause;
         // 3) mstatus 갱신: MPIE=현재 MIE, MIE=0 (인터럽트 비활성화)
         mstatus[MPIE_BIT]         <= mstatus[MIE_BIT];
         mstatus[MIE_BIT]          <= 1'b0;
         mstatus[MPP_HI:MPP_LO]   <= 2'b11; // M-mode only
      end
      else if (mret_exec) begin
         // ----- MRET 실행 시 (트랩 복귀) -----
         // 1) MIE를 MPIE로 복원
         mstatus[MIE_BIT]          <= mstatus[MPIE_BIT];
         // 2) MPIE를 1로 설정
         mstatus[MPIE_BIT]         <= 1'b1;
         // 3) MPP를 가장 낮은 지원 모드로 설정 (M-mode only이면 유지)
         mstatus[MPP_HI:MPP_LO]   <= 2'b11;
      end
      else if (csr_w_en) begin
         // ----- 소프트웨어에 의한 CSR 쓰기 -----
         case (csr_addr)
            ADDR_MSTATUS: begin
               // WARL 필드: 구현된 비트만 쓰기 허용
               mstatus[MIE_BIT]        <= csr_wdata[MIE_BIT];
               mstatus[MPIE_BIT]       <= csr_wdata[MPIE_BIT];
               mstatus[MPP_HI:MPP_LO] <= 2'b11; // M-mode only
            end
            ADDR_MIE:      mie      <= csr_wdata & 32'h0000_0888; // MSIE, MTIE, MEIE만
            ADDR_MTVEC:    mtvec    <= {csr_wdata[31:2], 2'b00};  // 4바이트 정렬
            ADDR_MSCRATCH: mscratch <= csr_wdata;
            ADDR_MEPC:     mepc     <= {csr_wdata[31:2], 2'b00};  // 4바이트 정렬
            ADDR_MCAUSE:   mcause   <= csr_wdata;
            // ADDR_MIP: mip는 소프트웨어 쓰기 불가 (읽기 전용)
            default: ; // 존재하지 않는 CSR — 쓰기 무시
         endcase
      end
   end

   // =========================================================================
   // 출력 포트 할당
   // =========================================================================
   assign mtvec_out = mtvec;
   assign mepc_out  = mepc;

endmodule