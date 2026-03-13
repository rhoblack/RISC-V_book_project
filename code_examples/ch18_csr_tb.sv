// =============================================================================
// CSR 유닛 테스트벤치 (CSR Unit Testbench)
// Chapter 18 — CSR과 시스템 명령어
// RISC-V 프로세서 설계 완전정복
// =============================================================================
// 3단계 테스트 시나리오:
//   1단계: 기본 CSR 쓰기/읽기 (CSRRW 명령어)
//   2단계: 비트 마스크 조작 (CSRRS로 세트, CSRRC로 클리어)
//   3단계: 인터럽트 마스킹 (mie.MTIE 세트 → timer_irq → irq_pending 확인)
//
// 시뮬레이션 방법 (VCS):
//   vcs -sverilog ch18_csr_unit.sv ch18_csr_tb.sv -o sim_csr && ./sim_csr
// =============================================================================

`timescale 1ns / 1ps

module ch18_csr_tb;

   // =========================================================================
   // DUT 연결 신호 선언
   // =========================================================================
   logic        clk;
   logic        rst_n;

   // CSR 읽기/쓰기 인터페이스
   logic [11:0] csr_addr;
   logic        csr_we;
   logic [2:0]  csr_op;
   logic [31:0] csr_wdata;
   logic [31:0] csr_rdata;

   // 인터럽트 입력
   logic        timer_irq;
   logic        ext_irq;
   logic        sw_irq;

   // 트랩 인터페이스 (Ch18에서는 기본값 0 사용)
   logic        trap_en;
   logic [31:0] trap_pc;
   logic [31:0] trap_cause;
   logic        mret_en;

   // CSR 출력
   logic [31:0] mtvec_out;
   logic [31:0] mepc_out;
   logic        irq_pending;

   // =========================================================================
   // CSR 명령어 연산 코드 상수
   // =========================================================================
   localparam CSR_OP_RW  = 3'b001;   // CSRRW:  CSR = rs1 (전체 교체)
   localparam CSR_OP_RS  = 3'b010;   // CSRRS:  CSR = CSR | rs1 (비트 세트)
   localparam CSR_OP_RC  = 3'b011;   // CSRRC:  CSR = CSR & ~rs1 (비트 클리어)
   localparam CSR_OP_RWI = 3'b101;   // CSRRWI: CSR = ZeroExt(uimm)
   localparam CSR_OP_RSI = 3'b110;   // CSRRSI: CSR = CSR | ZeroExt(uimm)
   localparam CSR_OP_RCI = 3'b111;   // CSRRCI: CSR = CSR & ~ZeroExt(uimm)

   // =========================================================================
   // CSR 주소 상수
   // =========================================================================
   localparam MSTATUS  = 12'h300;
   localparam MIE      = 12'h304;
   localparam MTVEC    = 12'h305;
   localparam MSCRATCH = 12'h340;
   localparam MEPC     = 12'h341;
   localparam MCAUSE   = 12'h342;
   localparam MIP      = 12'h344;

   // =========================================================================
   // DUT 인스턴스화
   // =========================================================================
   csr_unit #(
      .HART_ID(0)
   ) dut (
      .clk         (clk),
      .rst_n       (rst_n),
      .csr_addr    (csr_addr),
      .csr_we      (csr_we),
      .csr_op      (csr_op),
      .csr_wdata   (csr_wdata),
      .csr_rdata   (csr_rdata),
      .timer_irq   (timer_irq),
      .ext_irq     (ext_irq),
      .sw_irq      (sw_irq),
      .trap_en     (trap_en),
      .trap_pc     (trap_pc),
      .trap_cause  (trap_cause),
      .mret_en     (mret_en),
      .mtvec_out   (mtvec_out),
      .mepc_out    (mepc_out),
      .irq_pending (irq_pending)
   );

   // =========================================================================
   // 클럭 생성 (10ns 주기 = 100MHz)
   // =========================================================================
   initial clk = 0;
   always #5 clk = ~clk;

   // =========================================================================
   // 테스트 통계 변수
   // =========================================================================
   integer pass_cnt = 0;
   integer fail_cnt = 0;

   // =========================================================================
   // 태스크: CSR 쓰기 (1클럭 후 완료)
   // =========================================================================
   task csr_write(
      input [11:0] addr,    // CSR 주소
      input [2:0]  op,      // 연산 코드 (CSR_OP_*)
      input [31:0] wdata    // 쓰기 데이터
   );
      csr_addr  = addr;
      csr_we    = 1'b1;
      csr_op    = op;
      csr_wdata = wdata;
      @(posedge clk);       // 클럭 엣지에서 레지스터에 기록됨
      #1;                   // 셋업 타임 마진
   endtask

   // =========================================================================
   // 태스크: CSR 읽기 (조합 논리 — 즉시 반환)
   // =========================================================================
   task csr_read(
      input  [11:0] addr,   // CSR 주소
      output [31:0] rdata   // 읽기 데이터
   );
      csr_addr = addr;
      csr_we   = 1'b0;
      csr_op   = 3'b000;
      #1;                   // 조합 논리 안정화 대기
      rdata = csr_rdata;
   endtask

   // =========================================================================
   // 태스크: 결과 확인 및 PASS/FAIL 출력
   // =========================================================================
   task check(
      input [31:0] actual,       // 실제 값
      input [31:0] expected,     // 기대 값
      input [127:0] test_name    // 테스트 이름 (최대 16문자)
   );
      if (actual === expected) begin
         $display("[PASS] %-20s : got 0x%08X", test_name, actual);
         pass_cnt++;
      end else begin
         $display("[FAIL] %-20s : expected 0x%08X, got 0x%08X",
                  test_name, expected, actual);
         fail_cnt++;
      end
   endtask

   // =========================================================================
   // 태스크: 단일 비트 확인
   // =========================================================================
   task check_bit(
      input actual,
      input expected,
      input [127:0] test_name
   );
      if (actual === expected) begin
         $display("[PASS] %-20s : got %b", test_name, actual);
         pass_cnt++;
      end else begin
         $display("[FAIL] %-20s : expected %b, got %b", test_name, expected, actual);
         fail_cnt++;
      end
   endtask

   // =========================================================================
   // 메인 테스트 시나리오
   // =========================================================================
   logic [31:0] read_val;

   initial begin
      // ─────────────────────────────────────────────────────────────────────
      // 초기화
      // ─────────────────────────────────────────────────────────────────────
      rst_n     = 1'b0;
      csr_addr  = 12'h0;
      csr_we    = 1'b0;
      csr_op    = 3'b000;
      csr_wdata = 32'h0;
      timer_irq = 1'b0;
      ext_irq   = 1'b0;
      sw_irq    = 1'b0;
      trap_en   = 1'b0;
      trap_pc   = 32'h0;
      trap_cause= 32'h0;
      mret_en   = 1'b0;

      // 2클럭 리셋
      repeat(2) @(posedge clk);
      #1;
      rst_n = 1'b1;
      @(posedge clk); #1;

      $display("");
      $display("================================================");
      $display(" Chapter 18 CSR 유닛 테스트벤치");
      $display("================================================");

      // =================================================================
      // 1단계: 기본 CSR 쓰기/읽기 (CSRRW)
      // =================================================================
      $display("");
      $display("--- 1단계: 기본 CSR 쓰기/읽기 (CSRRW) ---");

      // mtvec 설정: 핸들러 주소 0x0000_1000, Mode=Direct(0)
      // CSRRW mtvec, x0, 0x0000_1000 → mtvec = 0x0000_1000
      csr_write(MTVEC, CSR_OP_RW, 32'h0000_1000);

      // 읽기로 확인
      csr_read(MTVEC, read_val);
      check(read_val, 32'h0000_1000, "mtvec CSRRW");

      // mtvec_out 포트 확인 (파이프라인 출력)
      check(mtvec_out, 32'h0000_1000, "mtvec_out port");

      // mscratch 설정: 임시 저장용 주소 0xDEAD_BEEF
      csr_write(MSCRATCH, CSR_OP_RW, 32'hDEAD_BEEF);
      csr_read(MSCRATCH, read_val);
      check(read_val, 32'hDEAD_BEEF, "mscratch CSRRW");

      // mstatus 직접 읽기 (리셋 후 0이어야 함)
      csr_read(MSTATUS, read_val);
      check(read_val, 32'h0, "mstatus reset val");

      // =================================================================
      // 2단계: 비트 마스크 조작 (CSRRS/CSRRC)
      // =================================================================
      $display("");
      $display("--- 2단계: 비트 마스크 조작 (CSRRS/CSRRC) ---");

      // CSRRS로 mstatus.MIE[3] 세트
      // CSRRS mstatus, x?, 0x8 → mstatus.MIE = 1
      csr_write(MSTATUS, CSR_OP_RS, 32'h8);   // 0x8 = bit[3]

      // mstatus.MIE 확인 (MSTATUS_MASK = 0x1888, 세트 후 0x8이어야 함)
      csr_read(MSTATUS, read_val);
      check(read_val, 32'h8, "mstatus MIE set");

      // CSRRC로 mstatus.MIE[3] 클리어
      // CSRRC mstatus, x?, 0x8 → mstatus.MIE = 0
      csr_write(MSTATUS, CSR_OP_RC, 32'h8);   // 0x8 = bit[3] 클리어

      csr_read(MSTATUS, read_val);
      check(read_val, 32'h0, "mstatus MIE clear");

      // CSRRS로 mstatus.MPP[12:11] + MPIE[7] + MIE[3] 동시 세트
      // 0x1888 = MIE[3] + MPIE[7] + MPP[12:11] 모두 세트
      csr_write(MSTATUS, CSR_OP_RS, 32'h1888);

      csr_read(MSTATUS, read_val);
      check(read_val, 32'h1888, "mstatus all bits set");

      // CSRRW로 mstatus 전체 초기화 (0으로 교체)
      csr_write(MSTATUS, CSR_OP_RW, 32'h0);
      csr_read(MSTATUS, read_val);
      check(read_val, 32'h0, "mstatus full clear");

      // mie 비트 조작: MEIE[11], MTIE[7], MSIE[3] 개별 세트/클리어
      // CSRRS로 MTIE[7] 세트 → 타이머 인터럽트 활성화
      csr_write(MIE, CSR_OP_RS, 32'h80);      // 0x80 = bit[7]
      csr_read(MIE, read_val);
      check(read_val, 32'h80, "mie MTIE set");

      // CSRRC로 MTIE[7] 클리어
      csr_write(MIE, CSR_OP_RC, 32'h80);
      csr_read(MIE, read_val);
      check(read_val, 32'h0, "mie MTIE clear");

      // =================================================================
      // 3단계: 인터럽트 마스킹 및 irq_pending 확인
      // =================================================================
      $display("");
      $display("--- 3단계: 인터럽트 마스킹 및 irq_pending ---");

      // 초기 상태: 인터럽트 없음 (mstatus.MIE=0, timer_irq=0)
      check_bit(irq_pending, 1'b0, "irq_pending init");

      // 타이머 인터럽트 외부 신호 활성화 (하드웨어 입력)
      timer_irq = 1'b1;
      #1;

      // mip.MTIP[7]이 1이지만 mstatus.MIE=0이므로 irq_pending=0
      check_bit(irq_pending, 1'b0, "irq_pend MIE=0");

      // mie.MTIE[7] 세트 (타이머 인터럽트 활성화)
      csr_write(MIE, CSR_OP_RS, 32'h80);

      // 여전히 mstatus.MIE=0이므로 irq_pending=0
      csr_read(MIP, read_val);   // mip 읽기 확인
      check(read_val, 32'h80, "mip MTIP reflect");
      check_bit(irq_pending, 1'b0, "irq_pend mie=1 MIE=0");

      // mstatus.MIE[3] 세트 → 모든 조건 충족 → irq_pending=1
      csr_write(MSTATUS, CSR_OP_RS, 32'h8);   // MIE 비트[3] 세트
      #1;   // 조합 논리 안정화

      check_bit(irq_pending, 1'b1, "irq_pending asserted");

      // 타이머 인터럽트 해제 → irq_pending=0
      timer_irq = 1'b0;
      #1;
      check_bit(irq_pending, 1'b0, "irq_pend timer off");

      // 외부 인터럽트 확인 (ext_irq → mip.MEIP[11])
      ext_irq = 1'b1;
      // mie.MEIE[11] 아직 미세트 → irq_pending=0
      check_bit(irq_pending, 1'b0, "irq_pend MEIE=0");

      // mie.MEIE[11] 세트 → irq_pending=1
      csr_write(MIE, CSR_OP_RS, 32'h800);   // MEIE = bit[11]
      #1;
      check_bit(irq_pending, 1'b1, "irq_pend ext_irq");

      // mip은 소프트웨어 쓰기 무시 확인 (쓰기해도 하드웨어 값 유지)
      csr_write(MIP, CSR_OP_RW, 32'h0);    // mip 쓰기 시도 (무시되어야 함)
      csr_read(MIP, read_val);
      check(read_val, 32'h800, "mip write ignored");   // ext_irq=1이므로 0x800

      // 외부 인터럽트 해제
      ext_irq = 1'b0;
      #1;

      // =================================================================
      // 4단계: mepc/mcause 쓰기 확인 (Ch19 트랩 처리 예비)
      // =================================================================
      $display("");
      $display("--- 4단계: mepc/mcause 쓰기 확인 ---");

      // mepc 설정: 하위 1비트 강제 0 확인
      // 0x0000_1003 → 하위 비트 강제 0 → 0x0000_1002
      csr_write(MEPC, CSR_OP_RW, 32'h0000_1003);
      csr_read(MEPC, read_val);
      check(read_val, 32'h0000_1002, "mepc lsb forced 0");
      check(mepc_out, 32'h0000_1002, "mepc_out port");

      // mcause 설정: 타이머 인터럽트 (INT=1, code=7)
      // mcause = 0x8000_0007
      csr_write(MCAUSE, CSR_OP_RW, 32'h8000_0007);
      csr_read(MCAUSE, read_val);
      check(read_val, 32'h8000_0007, "mcause timer irq");

      // =================================================================
      // 5단계: 트랩 진입/복귀 하드웨어 자동 CSR 업데이트
      // =================================================================
      $display("");
      $display("--- 5단계: 트랩 진입/복귀 하드웨어 자동 업데이트 ---");

      // 사전 준비: mstatus.MIE=1 세트 (트랩 진입 시 0으로 변경되어야 함)
      csr_write(MSTATUS, CSR_OP_RW, 32'h8);   // MIE=1

      // 트랩 진입 시뮬레이션: trap_en=1, trap_pc, trap_cause 설정
      trap_pc    = 32'h0000_2000;   // 트랩 발생 PC
      trap_cause = 32'h8000_0007;   // 타이머 인터럽트
      trap_en    = 1'b1;
      @(posedge clk); #1;
      trap_en    = 1'b0;

      // mepc 확인: trap_pc 저장
      check(mepc_out, 32'h0000_2000, "trap mepc saved");

      // mcause 확인: trap_cause 저장
      csr_read(MCAUSE, read_val);
      check(read_val, 32'h8000_0007, "trap mcause saved");

      // mstatus 확인: MIE=0, MPIE=1 (이전 MIE 보존), MPP=2'b11
      // 0x1888 & ~WPRI = ? → MIE=0, MPIE=1(0x80), MPP=2'b11(0x1800)
      // 기대값: MPIE=1(0x80) + MPP=11(0x1800) = 0x1880
      csr_read(MSTATUS, read_val);
      check(read_val, 32'h1880, "trap mstatus update");

      // MRET 복귀 시뮬레이션
      mret_en = 1'b1;
      @(posedge clk); #1;
      mret_en = 1'b0;

      // mstatus 복원 확인: MIE=1(MPIE에서 복원), MPIE=1, MPP=2'b11(M-mode 유지)
      // Priv Spec 3.3.2: U-mode 미구현 시 MRET 후 MPP는 최소 지원 권한(M-mode)으로 설정
      // 기대값: MIE=1(0x8) + MPIE=1(0x80) + MPP=11(0x1800) = 0x1888
      csr_read(MSTATUS, read_val);
      check(read_val, 32'h1888, "mret mstatus restore (M-mode only)");

      // =================================================================
      // 최종 결과 출력
      // =================================================================
      $display("");
      $display("================================================");
      $display(" 테스트 결과: PASS=%0d  FAIL=%0d  TOTAL=%0d",
               pass_cnt, fail_cnt, pass_cnt + fail_cnt);
      if (fail_cnt == 0)
         $display(" 모든 테스트 통과 — CSR 유닛 정상 동작");
      else
         $display(" 실패한 테스트가 있습니다. 위 로그를 확인하세요.");
      $display("================================================");
      $display("");

      $finish;
   end

   // =========================================================================
   // 타임아웃 감시 (무한 루프 방지)
   // =========================================================================
   initial begin
      #10000;
      $display("[ERROR] 시뮬레이션 타임아웃 — 10us 초과");
      $finish;
   end

   // =========================================================================
   // 파형 덤프 (선택적 — VCD 파일 생성)
   // =========================================================================
   initial begin
      $dumpfile("ch18_csr_tb.vcd");
      $dumpvars(0, ch18_csr_tb);
   end

endmodule
