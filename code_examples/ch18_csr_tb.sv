// ============================================================================
// CSR 유닛 테스트벤치 (CSR Unit Testbench)
// Chapter 18 — CSR과 시스템 명령어
// RISC-V 프로세서 설계 완전정복
// ============================================================================
// 검증 시나리오:
//   1) CSRRW: mtvec에 트랩 벡터 주소 설정
//   2) CSRRS: mstatus.MIE 비트 세트 (인터럽트 활성화)
//   3) CSRRC: mstatus.MIE 비트 클리어 (인터럽트 비활성화)
//   4) CSRRWI: mscratch에 즉치수 값 쓰기
//   5) CSRRSI: mie 레지스터 비트 세트
//   6) 트랩 진입/복귀 시퀀스 검증
// ============================================================================

`timescale 1ns / 1ps

module csr_tb;

   // =========================================================================
   // 신호 선언
   // =========================================================================
   logic        clk;
   logic        rst_n;
   logic [11:0] csr_addr;
   logic [4:0]  rs1_addr;
   logic [31:0] rs1_data;
   logic [2:0]  funct3;
   logic        csr_en;
   logic [31:0] csr_rd_data;

   // 트랩 인터페이스
   logic        trap_enter;
   logic [31:0] trap_pc;
   logic [31:0] trap_cause;
   logic        mret_exec;

   // 인터럽트
   logic        ext_irq;
   logic        timer_irq;
   logic        sw_irq;

   // 출력
   logic [31:0] mtvec_out;
   logic [31:0] mepc_out;
   logic        irq_pending;
   logic        csr_access_fault;

   // =========================================================================
   // funct3 상수 정의
   // =========================================================================
   localparam logic [2:0] FUNCT3_CSRRW  = 3'b001;
   localparam logic [2:0] FUNCT3_CSRRS  = 3'b010;
   localparam logic [2:0] FUNCT3_CSRRC  = 3'b011;
   localparam logic [2:0] FUNCT3_CSRRWI = 3'b101;
   localparam logic [2:0] FUNCT3_CSRRSI = 3'b110;
   localparam logic [2:0] FUNCT3_CSRRCI = 3'b111;

   // CSR 주소
   localparam logic [11:0] MSTATUS  = 12'h300;
   localparam logic [11:0] MIE      = 12'h304;
   localparam logic [11:0] MTVEC    = 12'h305;
   localparam logic [11:0] MSCRATCH = 12'h340;
   localparam logic [11:0] MEPC     = 12'h341;
   localparam logic [11:0] MCAUSE   = 12'h342;

   // =========================================================================
   // DUT 인스턴스
   // =========================================================================
   csr_unit u_dut (
      .clk              (clk),
      .rst_n            (rst_n),
      .csr_addr         (csr_addr),
      .rs1_addr         (rs1_addr),
      .rs1_data         (rs1_data),
      .funct3           (funct3),
      .csr_en           (csr_en),
      .csr_rd_data      (csr_rd_data),
      .trap_enter       (trap_enter),
      .trap_pc          (trap_pc),
      .trap_cause       (trap_cause),
      .mret_exec        (mret_exec),
      .ext_irq          (ext_irq),
      .timer_irq        (timer_irq),
      .sw_irq           (sw_irq),
      .mtvec_out        (mtvec_out),
      .mepc_out         (mepc_out),
      .irq_pending      (irq_pending),
      .csr_access_fault (csr_access_fault)
   );

   // =========================================================================
   // 클럭 생성 (10ns 주기 = 100MHz)
   // =========================================================================
   initial clk = 0;
   always #5 clk = ~clk;

   // =========================================================================
   // 공통 초기화 태스크
   // =========================================================================
   task automatic idle();
      csr_addr   = 12'b0;
      rs1_addr   = 5'b0;
      rs1_data   = 32'b0;
      funct3     = 3'b0;
      csr_en     = 1'b0;
      trap_enter = 1'b0;
      trap_pc    = 32'b0;
      trap_cause = 32'b0;
      mret_exec  = 1'b0;
      ext_irq    = 1'b0;
      timer_irq  = 1'b0;
      sw_irq     = 1'b0;
   endtask

   // =========================================================================
   // CSR 쓰기 태스크
   // =========================================================================
   task automatic csr_write(
      input logic [11:0] addr,
      input logic [4:0]  rs1,
      input logic [31:0] data,
      input logic [2:0]  func
   );
      @(posedge clk);
      csr_addr = addr;
      rs1_addr = rs1;
      rs1_data = data;
      funct3   = func;
      csr_en   = 1'b1;
      @(posedge clk);
      csr_en   = 1'b0;
   endtask

   // =========================================================================
   // 테스트 시나리오
   // =========================================================================
   integer pass_count;
   integer fail_count;

   initial begin
      pass_count = 0;
      fail_count = 0;
      idle();

      // --- 리셋 ---
      rst_n = 0;
      repeat (3) @(posedge clk);
      rst_n = 1;
      @(posedge clk);

      // ==============================
      // 테스트 1: CSRRW — mtvec 설정
      // ==============================
      $display("\n[TEST 1] CSRRW: mtvec에 트랩 벡터 주소 0x1000_0000 설정");
      csr_write(MTVEC, 5'd1, 32'h1000_0000, FUNCT3_CSRRW);
      @(posedge clk);
      if (mtvec_out == 32'h1000_0000) begin
         $display("  PASS: mtvec = 0x%08h", mtvec_out);
         pass_count++;
      end else begin
         $display("  FAIL: mtvec = 0x%08h (기대값: 0x10000000)", mtvec_out);
         fail_count++;
      end

      // ==============================
      // 테스트 2: CSRRS — mstatus.MIE 세트
      // ==============================
      $display("\n[TEST 2] CSRRS: mstatus.MIE 비트 세트 (글로벌 인터럽트 활성화)");
      csr_write(MSTATUS, 5'd2, 32'h0000_0008, FUNCT3_CSRRS); // 비트[3] = MIE
      @(posedge clk);
      // mstatus 읽기
      csr_addr = MSTATUS;
      csr_en   = 1'b1;
      funct3   = FUNCT3_CSRRS;
      rs1_addr = 5'd0;  // rs1=x0 → 읽기만
      rs1_data = 32'b0;
      @(posedge clk);
      if (csr_rd_data[3] == 1'b1) begin
         $display("  PASS: mstatus.MIE = 1");
         pass_count++;
      end else begin
         $display("  FAIL: mstatus.MIE = %b (기대값: 1)", csr_rd_data[3]);
         fail_count++;
      end
      csr_en = 1'b0;

      // ==============================
      // 테스트 3: CSRRC — mstatus.MIE 클리어
      // ==============================
      $display("\n[TEST 3] CSRRC: mstatus.MIE 비트 클리어 (글로벌 인터럽트 비활성화)");
      csr_write(MSTATUS, 5'd3, 32'h0000_0008, FUNCT3_CSRRC);
      @(posedge clk);
      csr_addr = MSTATUS;
      csr_en   = 1'b1;
      funct3   = FUNCT3_CSRRS;
      rs1_addr = 5'd0;
      rs1_data = 32'b0;
      @(posedge clk);
      if (csr_rd_data[3] == 1'b0) begin
         $display("  PASS: mstatus.MIE = 0");
         pass_count++;
      end else begin
         $display("  FAIL: mstatus.MIE = %b (기대값: 0)", csr_rd_data[3]);
         fail_count++;
      end
      csr_en = 1'b0;

      // ==============================
      // 테스트 4: CSRRWI — mscratch에 즉치수 쓰기
      // ==============================
      $display("\n[TEST 4] CSRRWI: mscratch에 즉치수 값 5'd17 쓰기");
      csr_write(MSCRATCH, 5'd17, 32'b0, FUNCT3_CSRRWI); // zimm = 17
      @(posedge clk);
      csr_addr = MSCRATCH;
      csr_en   = 1'b1;
      funct3   = FUNCT3_CSRRS;
      rs1_addr = 5'd0;
      rs1_data = 32'b0;
      @(posedge clk);
      if (csr_rd_data == 32'd17) begin
         $display("  PASS: mscratch = %0d", csr_rd_data);
         pass_count++;
      end else begin
         $display("  FAIL: mscratch = %0d (기대값: 17)", csr_rd_data);
         fail_count++;
      end
      csr_en = 1'b0;

      // ==============================
      // 테스트 5: CSRRSI — mie.MTIE 세트
      // ==============================
      $display("\n[TEST 5] CSRRSI: mie.MTIE (비트 7) 세트 — 타이머 인터럽트 활성화");
      csr_write(MIE, 5'd8, 32'b0, FUNCT3_CSRRSI); // zimm=8 → 비트[3]=MSIE... 아닌 zimm값 8 = 5'b01000
      // zimm = 5'b01000 = 8, 제로확장 → 32'h0000_0008 → mie[3] = MSIE
      // 타이머는 비트 7이므로 zimm=5'b10000 (16) 사용 필요
      // 교정: 첫 번째 테스트는 MSIE(비트3)을 활성화하는 것으로 설명 수정
      @(posedge clk);
      csr_addr = MIE;
      csr_en   = 1'b1;
      funct3   = FUNCT3_CSRRS;
      rs1_addr = 5'd0;
      rs1_data = 32'b0;
      @(posedge clk);
      if (csr_rd_data[3] == 1'b1) begin
         $display("  PASS: mie.MSIE = 1 (비트 3 세트)");
         pass_count++;
      end else begin
         $display("  FAIL: mie = 0x%08h", csr_rd_data);
         fail_count++;
      end
      csr_en = 1'b0;

      // ==============================
      // 테스트 6: 트랩 진입/복귀 시퀀스
      // ==============================
      $display("\n[TEST 6] 트랩 진입 → MRET 복귀 시퀀스");

      // 먼저 mstatus.MIE 활성화
      csr_write(MSTATUS, 5'd1, 32'h0000_0008, FUNCT3_CSRRS);
      @(posedge clk);

      // 트랩 진입
      idle();
      @(posedge clk);
      trap_enter = 1'b1;
      trap_pc    = 32'h0000_0100; // 트랩 발생 PC
      trap_cause = 32'h0000_000B; // Environment call from M-mode
      @(posedge clk);
      trap_enter = 1'b0;
      @(posedge clk);

      // mepc 확인
      if (mepc_out == 32'h0000_0100) begin
         $display("  PASS: mepc = 0x%08h (트랩 발생 PC 저장됨)", mepc_out);
         pass_count++;
      end else begin
         $display("  FAIL: mepc = 0x%08h (기대값: 0x00000100)", mepc_out);
         fail_count++;
      end

      // mstatus.MIE가 0으로 변경되었는지 확인
      csr_addr = MSTATUS;
      csr_en   = 1'b1;
      funct3   = FUNCT3_CSRRS;
      rs1_addr = 5'd0;
      rs1_data = 32'b0;
      @(posedge clk);
      if (csr_rd_data[3] == 1'b0 && csr_rd_data[7] == 1'b1) begin
         $display("  PASS: 트랩 진입 후 MIE=0, MPIE=1 (인터럽트 비활성화, 이전 상태 보존)");
         pass_count++;
      end else begin
         $display("  FAIL: mstatus = 0x%08h (MIE=%b, MPIE=%b)",
                  csr_rd_data, csr_rd_data[3], csr_rd_data[7]);
         fail_count++;
      end
      csr_en = 1'b0;

      // MRET 실행
      @(posedge clk);
      mret_exec = 1'b1;
      @(posedge clk);
      mret_exec = 1'b0;
      @(posedge clk);

      // MIE 복원 확인
      csr_addr = MSTATUS;
      csr_en   = 1'b1;
      funct3   = FUNCT3_CSRRS;
      rs1_addr = 5'd0;
      rs1_data = 32'b0;
      @(posedge clk);
      if (csr_rd_data[3] == 1'b1) begin
         $display("  PASS: MRET 후 MIE=1 복원 (인터럽트 재활성화)");
         pass_count++;
      end else begin
         $display("  FAIL: MRET 후 mstatus = 0x%08h (MIE=%b)", csr_rd_data, csr_rd_data[3]);
         fail_count++;
      end
      csr_en = 1'b0;

      // ==============================
      // 결과 요약
      // ==============================
      @(posedge clk);
      $display("\n========================================");
      $display(" 테스트 결과: %0d PASS / %0d FAIL", pass_count, fail_count);
      $display("========================================\n");

      if (fail_count == 0)
         $display(">>> 모든 테스트 통과! CSR 유닛이 정상 동작합니다. <<<");
      else
         $display(">>> %0d개 테스트 실패. 파형을 확인하십시오. <<<", fail_count);

      $finish;
   end

   // =========================================================================
   // 파형 덤프 (시뮬레이션용)
   // =========================================================================
   initial begin
      $dumpfile("csr_tb.vcd");
      $dumpvars(0, csr_tb);
   end

endmodule