// ============================================================================
// 제어 해저드 테스트벤치
// Chapter 11: 제어 해저드와 분기 처리 — 11.7절
// ============================================================================
// 테스트 시나리오:
//   1. BEQ 분기 성공 (Taken) → flush 확인
//   2. BEQ 분기 실패 (Not-Taken) → 정상 진행 확인
//   3. BNE 분기 성공
//   4. JAL 무조건 점프
//   5. JALR 간접 점프
//   6. Load-Use + Branch 중첩 해저드 (flush 우선 확인)
// ============================================================================

`timescale 1ns / 1ps

module control_hazard_tb;

   // ---------------------------------------------------------------
   // 신호 선언
   // ---------------------------------------------------------------
   logic        clk;
   logic        rst_n;

   // branch_control 입력
   logic [31:0] ex_pc;
   logic [31:0] ex_imm;
   logic [31:0] ex_rs1_data;
   logic [31:0] ex_rs2_data;
   logic [2:0]  ex_funct3;
   logic        ex_branch;
   logic        ex_jal;
   logic        ex_jalr;

   // branch_control 출력
   logic        branch_taken;
   logic [31:0] branch_target;
   logic        flush_if_id;
   logic        flush_id_ex;

   // hazard_control_unit 입력
   logic        id_ex_mem_read;
   logic [4:0]  id_ex_rd;
   logic [4:0]  if_id_rs1;
   logic [4:0]  if_id_rs2;

   // hazard_control_unit 출력
   logic        pc_write;
   logic        if_id_write;
   logic        if_id_flush;
   logic        id_ex_flush;

   // ---------------------------------------------------------------
   // DUT 인스턴스
   // ---------------------------------------------------------------
   branch_control u_branch_ctrl (
      .ex_pc         (ex_pc),
      .ex_imm        (ex_imm),
      .ex_rs1_data   (ex_rs1_data),
      .ex_rs2_data   (ex_rs2_data),
      .ex_funct3     (ex_funct3),
      .ex_branch     (ex_branch),
      .ex_jal        (ex_jal),
      .ex_jalr       (ex_jalr),
      .branch_taken  (branch_taken),
      .branch_target (branch_target),
      .flush_if_id   (flush_if_id),
      .flush_id_ex   (flush_id_ex)
   );

   hazard_control_unit u_hazard_ctrl (
      .id_ex_mem_read (id_ex_mem_read),
      .id_ex_rd       (id_ex_rd),
      .if_id_rs1      (if_id_rs1),
      .if_id_rs2      (if_id_rs2),
      .branch_taken   (branch_taken),
      .pc_write       (pc_write),
      .if_id_write    (if_id_write),
      .if_id_flush    (if_id_flush),
      .id_ex_flush    (id_ex_flush)
   );

   // ---------------------------------------------------------------
   // 클록 생성 (10ns 주기 = 100MHz)
   // ---------------------------------------------------------------
   initial clk = 1'b0;
   always #5 clk = ~clk;

   // ---------------------------------------------------------------
   // 테스트 시나리오 실행
   // ---------------------------------------------------------------
   integer pass_count;
   integer fail_count;

   task automatic init_signals();
      ex_pc         = 32'h0;
      ex_imm        = 32'h0;
      ex_rs1_data   = 32'h0;
      ex_rs2_data   = 32'h0;
      ex_funct3     = 3'b000;
      ex_branch     = 1'b0;
      ex_jal        = 1'b0;
      ex_jalr       = 1'b0;
      id_ex_mem_read = 1'b0;
      id_ex_rd      = 5'b0;
      if_id_rs1     = 5'b0;
      if_id_rs2     = 5'b0;
   endtask

   task automatic check(input string test_name,
                         input logic expected_taken,
                         input logic [31:0] expected_target);
      #1;  // 조합 논리 안정화 대기
      if (branch_taken !== expected_taken) begin
         $display("[FAIL] %s: branch_taken=%b, expected=%b",
                  test_name, branch_taken, expected_taken);
         fail_count++;
      end
      else if (expected_taken && (branch_target !== expected_target)) begin
         $display("[FAIL] %s: branch_target=%h, expected=%h",
                  test_name, branch_target, expected_target);
         fail_count++;
      end
      else begin
         $display("[PASS] %s", test_name);
         pass_count++;
      end
   endtask

   initial begin
      pass_count = 0;
      fail_count = 0;
      init_signals();

      // 리셋
      rst_n = 1'b0;
      #20;
      rst_n = 1'b1;
      #10;

      // ===== 테스트 1: BEQ Taken (x1 == x2) =====
      $display("\n--- 테스트 1: BEQ Taken ---");
      init_signals();
      ex_pc       = 32'h0000_1000;
      ex_imm      = 32'h0000_0020;  // offset = +32
      ex_rs1_data = 32'h0000_000A;
      ex_rs2_data = 32'h0000_000A;  // 같은 값
      ex_funct3   = 3'b000;         // BEQ
      ex_branch   = 1'b1;
      check("BEQ Taken", 1'b1, 32'h0000_1020);
      @(posedge clk);

      // ===== 테스트 2: BEQ Not-Taken (x1 != x2) =====
      $display("\n--- 테스트 2: BEQ Not-Taken ---");
      init_signals();
      ex_pc       = 32'h0000_1000;
      ex_imm      = 32'h0000_0020;
      ex_rs1_data = 32'h0000_000A;
      ex_rs2_data = 32'h0000_000B;  // 다른 값
      ex_funct3   = 3'b000;         // BEQ
      ex_branch   = 1'b1;
      check("BEQ Not-Taken", 1'b0, 32'h0);
      @(posedge clk);

      // ===== 테스트 3: BNE Taken (x1 != x2) =====
      $display("\n--- 테스트 3: BNE Taken ---");
      init_signals();
      ex_pc       = 32'h0000_2000;
      ex_imm      = 32'hFFFF_FFF0;  // offset = -16
      ex_rs1_data = 32'h0000_0001;
      ex_rs2_data = 32'h0000_0002;  // 다른 값
      ex_funct3   = 3'b001;         // BNE
      ex_branch   = 1'b1;
      check("BNE Taken", 1'b1, 32'h0000_1FF0);
      @(posedge clk);

      // ===== 테스트 4: JAL =====
      $display("\n--- 테스트 4: JAL ---");
      init_signals();
      ex_pc  = 32'h0000_3000;
      ex_imm = 32'h0000_0100;  // offset = +256
      ex_jal = 1'b1;
      check("JAL", 1'b1, 32'h0000_3100);
      @(posedge clk);

      // ===== 테스트 5: JALR =====
      $display("\n--- 테스트 5: JALR ---");
      init_signals();
      ex_pc       = 32'h0000_4000;
      ex_imm      = 32'h0000_0004;
      ex_rs1_data = 32'h0000_5000;  // rs1 = 0x5000
      ex_jalr     = 1'b1;
      // 대상 = (0x5000 + 0x4) & 0xFFFFFFFE = 0x5004
      check("JALR", 1'b1, 32'h0000_5004);
      @(posedge clk);

      // ===== 테스트 6: JALR LSB 클리어 확인 =====
      $display("\n--- 테스트 6: JALR LSB 클리어 ---");
      init_signals();
      ex_pc       = 32'h0000_4000;
      ex_imm      = 32'h0000_0001;
      ex_rs1_data = 32'h0000_5000;
      ex_jalr     = 1'b1;
      // 대상 = (0x5000 + 0x1) & 0xFFFFFFFE = 0x5000
      check("JALR LSB clear", 1'b1, 32'h0000_5000);
      @(posedge clk);

      // ===== 테스트 7: Load-Use + Branch Taken (Flush 우선) =====
      $display("\n--- 테스트 7: Load-Use + Branch (Flush 우선) ---");
      init_signals();
      // Load-Use 조건 설정
      id_ex_mem_read = 1'b1;
      id_ex_rd       = 5'd5;
      if_id_rs1      = 5'd5;        // 의존성 존재
      // 동시에 분기 성공
      ex_pc       = 32'h0000_6000;
      ex_imm      = 32'h0000_0010;
      ex_rs1_data = 32'h0000_0007;
      ex_rs2_data = 32'h0000_0007;
      ex_funct3   = 3'b000;
      ex_branch   = 1'b1;
      #1;
      // Flush 우선: pc_write=1, if_id_flush=1
      if (pc_write && if_id_flush && id_ex_flush) begin
         $display("[PASS] Flush 우선순위 확인: pc_write=%b, if_id_flush=%b",
                  pc_write, if_id_flush);
         pass_count++;
      end else begin
         $display("[FAIL] Flush 우선순위 위반: pc_write=%b, if_id_flush=%b",
                  pc_write, if_id_flush);
         fail_count++;
      end
      @(posedge clk);

      // ===== 결과 요약 =====
      $display("\n========================================");
      $display("  테스트 완료: PASS=%0d, FAIL=%0d", pass_count, fail_count);
      $display("========================================\n");

      if (fail_count == 0)
         $display("*** 모든 테스트 통과! ***");
      else
         $display("*** %0d개 테스트 실패 ***", fail_count);

      #20;
      $finish;
   end

endmodule
