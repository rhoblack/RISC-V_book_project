// ============================================================================
// 데이터 해저드 테스트벤치
// Chapter 10 — 데이터 해저드와 포워딩
// RISC-V 프로세서 설계 완전정복
// ============================================================================
// 시나리오:
//   1) EX-EX 포워딩 검증 (연속 RAW)
//   2) MEM-EX 포워딩 검증 (2사이클 간격 RAW)
//   3) Load-Use 스톨 + MEM-EX 포워딩 검증
//   4) 포워딩 우선순위 검증 (EX-EX vs MEM-EX 동시 발생)
//   5) x0 포워딩 방지 검증
//   6) 1~10 합산 프로그램 통합 검증
// ============================================================================

`timescale 1ns / 1ps

module data_hazard_tb;

   // ========================================================================
   // 신호 선언
   // ========================================================================
   logic        clk;
   logic        rst_n;

   // 클록 생성: 10ns 주기 (100 MHz)
   localparam CLK_PERIOD = 10;
   initial clk = 0;
   always #(CLK_PERIOD / 2) clk = ~clk;

   // ========================================================================
   // DUT 인스턴스 (포워딩 유닛 단독 테스트)
   // ========================================================================
   logic [4:0]  id_ex_rs1, id_ex_rs2;
   logic        ex_mem_reg_w_en;
   logic [4:0]  ex_mem_rd;
   logic        mem_wb_reg_w_en;
   logic [4:0]  mem_wb_rd;
   logic [1:0]  fwd_a, fwd_b;

   forwarding_unit u_fwd (
      .id_ex_rs1       (id_ex_rs1),
      .id_ex_rs2       (id_ex_rs2),
      .ex_mem_reg_w_en (ex_mem_reg_w_en),
      .ex_mem_rd       (ex_mem_rd),
      .mem_wb_reg_w_en (mem_wb_reg_w_en),
      .mem_wb_rd       (mem_wb_rd),
      .fwd_a           (fwd_a),
      .fwd_b           (fwd_b)
   );

   // ========================================================================
   // 해저드 감지 유닛 테스트
   // ========================================================================
   logic        id_ex_mem_read;
   logic [4:0]  id_ex_rd_haz;
   logic [4:0]  if_id_rs1_haz, if_id_rs2_haz;
   logic        pc_en, if_id_en, id_ex_flush;

   hazard_detection_unit u_hazard (
      .id_ex_mem_read (id_ex_mem_read),
      .id_ex_rd       (id_ex_rd_haz),
      .if_id_rs1      (if_id_rs1_haz),
      .if_id_rs2      (if_id_rs2_haz),
      .pc_en          (pc_en),
      .if_id_en       (if_id_en),
      .id_ex_flush    (id_ex_flush)
   );

   // ========================================================================
   // 테스트 시나리오
   // ========================================================================
   integer pass_count = 0;
   integer fail_count = 0;

   task check_fwd(
      input string test_name,
      input logic [1:0] exp_fwd_a,
      input logic [1:0] exp_fwd_b
   );
      #1; // 조합 로직 안정화 대기
      if (fwd_a !== exp_fwd_a || fwd_b !== exp_fwd_b) begin
         $display("[FAIL] %s: fwd_a=%b(exp=%b), fwd_b=%b(exp=%b)",
                  test_name, fwd_a, exp_fwd_a, fwd_b, exp_fwd_b);
         fail_count++;
      end
      else begin
         $display("[PASS] %s: fwd_a=%b, fwd_b=%b",
                  test_name, fwd_a, fwd_b);
         pass_count++;
      end
   endtask

   task check_stall(
      input string test_name,
      input logic exp_pc_en,
      input logic exp_if_id_en,
      input logic exp_id_ex_flush
   );
      #1;
      if (pc_en !== exp_pc_en ||
          if_id_en !== exp_if_id_en ||
          id_ex_flush !== exp_id_ex_flush) begin
         $display("[FAIL] %s: pc_en=%b(exp=%b), if_id_en=%b(exp=%b), flush=%b(exp=%b)",
                  test_name, pc_en, exp_pc_en,
                  if_id_en, exp_if_id_en,
                  id_ex_flush, exp_id_ex_flush);
         fail_count++;
      end
      else begin
         $display("[PASS] %s: pc_en=%b, if_id_en=%b, flush=%b",
                  test_name, pc_en, if_id_en, id_ex_flush);
         pass_count++;
      end
   endtask

   initial begin
      $display("========================================");
      $display(" 데이터 해저드 테스트벤치 시작");
      $display("========================================");

      // 초기화
      id_ex_rs1        = 5'b0;
      id_ex_rs2        = 5'b0;
      ex_mem_reg_w_en  = 1'b0;
      ex_mem_rd        = 5'b0;
      mem_wb_reg_w_en  = 1'b0;
      mem_wb_rd        = 5'b0;
      id_ex_mem_read   = 1'b0;
      id_ex_rd_haz     = 5'b0;
      if_id_rs1_haz    = 5'b0;
      if_id_rs2_haz    = 5'b0;

      // ====================================================================
      // 시나리오 1: EX-EX 포워딩 (rs1)
      // add x1, x2, x3  →  sub x4, x1, x5
      // ====================================================================
      $display("\n--- 시나리오 1: EX-EX 포워딩 (rs1) ---");
      id_ex_rs1        = 5'd1;     // 현재 명령어가 x1을 읽음
      id_ex_rs2        = 5'd5;
      ex_mem_reg_w_en  = 1'b1;     // 1사이클 전 명령어가 x1에 씀
      ex_mem_rd        = 5'd1;
      mem_wb_reg_w_en  = 1'b0;
      mem_wb_rd        = 5'd0;
      check_fwd("EX-EX fwd_a", 2'b10, 2'b00);

      // ====================================================================
      // 시나리오 2: MEM-EX 포워딩 (rs2)
      // add x1, x2, x3  →  nop  →  sub x4, x5, x1
      // ====================================================================
      $display("\n--- 시나리오 2: MEM-EX 포워딩 (rs2) ---");
      id_ex_rs1        = 5'd5;
      id_ex_rs2        = 5'd1;     // 현재 명령어가 x1을 읽음
      ex_mem_reg_w_en  = 1'b0;
      ex_mem_rd        = 5'd0;
      mem_wb_reg_w_en  = 1'b1;     // 2사이클 전 명령어가 x1에 씀
      mem_wb_rd        = 5'd1;
      check_fwd("MEM-EX fwd_b", 2'b00, 2'b01);

      // ====================================================================
      // 시나리오 3: 포워딩 우선순위 (EX-EX가 MEM-EX보다 우선)
      // add x1, ... → add x1, ... → sub x4, x1, x5
      // ====================================================================
      $display("\n--- 시나리오 3: 포워딩 우선순위 ---");
      id_ex_rs1        = 5'd1;
      id_ex_rs2        = 5'd5;
      ex_mem_reg_w_en  = 1'b1;     // EX/MEM: x1에 쓰기 (최신)
      ex_mem_rd        = 5'd1;
      mem_wb_reg_w_en  = 1'b1;     // MEM/WB: x1에 쓰기 (이전)
      mem_wb_rd        = 5'd1;
      check_fwd("Priority EX>MEM", 2'b10, 2'b00);

      // ====================================================================
      // 시나리오 4: x0 포워딩 방지
      // add x0, x2, x3  →  sub x4, x0, x5
      // x0은 항상 0이므로 포워딩하면 안 됨
      // ====================================================================
      $display("\n--- 시나리오 4: x0 포워딩 방지 ---");
      id_ex_rs1        = 5'd0;     // x0을 읽음
      id_ex_rs2        = 5'd5;
      ex_mem_reg_w_en  = 1'b1;
      ex_mem_rd        = 5'd0;     // x0에 쓰기 시도 (무효)
      mem_wb_reg_w_en  = 1'b0;
      mem_wb_rd        = 5'd0;
      check_fwd("x0 no forward", 2'b00, 2'b00);

      // ====================================================================
      // 시나리오 5: 포워딩 불필요 (의존성 없음)
      // ====================================================================
      $display("\n--- 시나리오 5: 포워딩 불필요 ---");
      id_ex_rs1        = 5'd3;
      id_ex_rs2        = 5'd4;
      ex_mem_reg_w_en  = 1'b1;
      ex_mem_rd        = 5'd1;     // x1에 쓰기 (rs1/rs2와 무관)
      mem_wb_reg_w_en  = 1'b1;
      mem_wb_rd        = 5'd2;     // x2에 쓰기 (rs1/rs2와 무관)
      check_fwd("No dependency", 2'b00, 2'b00);

      // ====================================================================
      // 시나리오 6: Load-Use 해저드 감지
      // lw x1, 0(x2)  →  add x3, x1, x4
      // ====================================================================
      $display("\n--- 시나리오 6: Load-Use 스톨 ---");
      id_ex_mem_read   = 1'b1;     // EX 스테이지에 Load 명령어
      id_ex_rd_haz     = 5'd1;     // Load 목적지 = x1
      if_id_rs1_haz    = 5'd1;     // 다음 명령어가 x1을 rs1으로 읽음
      if_id_rs2_haz    = 5'd4;
      check_stall("Load-Use rs1", 1'b0, 1'b0, 1'b1);

      // ====================================================================
      // 시나리오 7: Load-Use 해저드 (rs2)
      // lw x1, 0(x2)  →  add x3, x4, x1
      // ====================================================================
      $display("\n--- 시나리오 7: Load-Use 스톨 (rs2) ---");
      id_ex_mem_read   = 1'b1;
      id_ex_rd_haz     = 5'd1;
      if_id_rs1_haz    = 5'd4;
      if_id_rs2_haz    = 5'd1;     // 다음 명령어가 x1을 rs2로 읽음
      check_stall("Load-Use rs2", 1'b0, 1'b0, 1'b1);

      // ====================================================================
      // 시나리오 8: Load-Use x0 스톨 방지
      // lw x0, 0(x2)  →  add x3, x0, x4 (x0이므로 스톨 불필요)
      // ====================================================================
      $display("\n--- 시나리오 8: Load x0 스톨 방지 ---");
      id_ex_mem_read   = 1'b1;
      id_ex_rd_haz     = 5'd0;     // x0에 Load (무효)
      if_id_rs1_haz    = 5'd0;
      if_id_rs2_haz    = 5'd4;
      check_stall("Load x0 no stall", 1'b1, 1'b1, 1'b0);

      // ====================================================================
      // 시나리오 9: 스톨 불필요 (Load이지만 의존성 없음)
      // lw x1, 0(x2)  →  add x3, x4, x5 (x1 사용 안 함)
      // ====================================================================
      $display("\n--- 시나리오 9: Load 무의존 ---");
      id_ex_mem_read   = 1'b1;
      id_ex_rd_haz     = 5'd1;
      if_id_rs1_haz    = 5'd4;     // x1과 무관
      if_id_rs2_haz    = 5'd5;     // x1과 무관
      check_stall("Load no dep", 1'b1, 1'b1, 1'b0);

      // ====================================================================
      // 결과 요약
      // ====================================================================
      $display("\n========================================");
      $display(" 테스트 결과: PASS=%0d, FAIL=%0d", pass_count, fail_count);
      $display("========================================");

      if (fail_count == 0)
         $display(" 모든 테스트 통과!");
      else
         $display(" %0d개 테스트 실패!", fail_count);

      $finish;
   end

endmodule
