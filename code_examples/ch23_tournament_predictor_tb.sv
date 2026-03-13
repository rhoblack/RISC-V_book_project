// =============================================================================
// 토너먼트 분기 예측기 테스트벤치
// Chapter 23 — 성능 최적화 기법
// =============================================================================
// 다양한 분기 패턴에 대한 예측률을 측정하고,
// 지역/전역 예측기 각각의 강점을 확인하는 검증 환경
// =============================================================================

`timescale 1ns / 1ps

module tournament_predictor_tb;

   // =========================================================================
   // 신호 선언
   // =========================================================================
   logic        clk;
   logic        rst_n;
   logic [31:0] pc;
   logic        predict_en;
   logic        predict_taken;
   logic        update_en;
   logic [31:0] update_pc;
   logic        actual_taken;

   // 성능 측정 카운터
   int total_branches;
   int correct_predictions;
   int mispredictions;

   // =========================================================================
   // DUT 인스턴스
   // =========================================================================
   tournament_predictor #(
      .PC_WIDTH     (32),
      .LOCAL_DEPTH  (64),
      .GLOBAL_DEPTH (64),
      .GHR_WIDTH    (6),
      .LOCAL_HIST_W (6)
   ) dut (
      .clk             (clk),
      .rst_n           (rst_n),
      .pc_i            (pc),
      .predict_en_i    (predict_en),
      .predict_taken_o (predict_taken),
      .update_en_i     (update_en),
      .update_pc_i     (update_pc),
      .actual_taken_i  (actual_taken)
   );

   // =========================================================================
   // 클럭 생성 (10ns 주기, 100MHz)
   // =========================================================================
   initial clk = 0;
   always #5 clk = ~clk;

   // =========================================================================
   // 분기 예측 + 갱신 태스크
   // =========================================================================
   task automatic do_branch(
      input logic [31:0] branch_pc,
      input logic        taken
   );
      // 1. 예측 요청
      @(posedge clk);
      pc         = branch_pc;
      predict_en = 1'b1;
      update_en  = 1'b0;

      @(posedge clk);
      predict_en = 1'b0;

      // 예측 결과 기록
      total_branches++;
      if (predict_taken == taken)
         correct_predictions++;
      else
         mispredictions++;

      // 2. 실제 결과로 갱신
      @(posedge clk);
      update_en     = 1'b1;
      update_pc     = branch_pc;
      actual_taken  = taken;

      @(posedge clk);
      update_en = 1'b0;
   endtask

   // =========================================================================
   // 테스트 시나리오
   // =========================================================================
   initial begin
      // 초기화
      rst_n      = 1'b0;
      pc         = 32'h0;
      predict_en = 1'b0;
      update_en  = 1'b0;
      update_pc  = 32'h0;
      actual_taken = 1'b0;

      total_branches      = 0;
      correct_predictions = 0;
      mispredictions      = 0;

      repeat (5) @(posedge clk);
      rst_n = 1'b1;
      repeat (2) @(posedge clk);

      // =====================================================================
      // 테스트 1: 루프 분기 (항상 Taken, 10회 반복)
      // =====================================================================
      $display("\n=== 테스트 1: 루프 분기 (항상 Taken, 50회) ===");
      total_branches = 0; correct_predictions = 0; mispredictions = 0;

      for (int i = 0; i < 50; i++) begin
         do_branch(32'h0000_0100, 1'b1);  // 항상 Taken
      end

      $display("총 분기: %0d, 정확: %0d, 오예측: %0d, 예측률: %0.1f%%",
               total_branches, correct_predictions, mispredictions,
               100.0 * correct_predictions / total_branches);

      // =====================================================================
      // 테스트 2: 교대 패턴 (T, NT, T, NT, ...)
      // =====================================================================
      $display("\n=== 테스트 2: 교대 패턴 (T/NT 반복, 50회) ===");
      total_branches = 0; correct_predictions = 0; mispredictions = 0;

      for (int i = 0; i < 50; i++) begin
         do_branch(32'h0000_0200, (i % 2 == 0) ? 1'b1 : 1'b0);
      end

      $display("총 분기: %0d, 정확: %0d, 오예측: %0d, 예측률: %0.1f%%",
               total_branches, correct_predictions, mispredictions,
               100.0 * correct_predictions / total_branches);

      // =====================================================================
      // 테스트 3: 중첩 루프 (외부 10회 × 내부 5회 Taken + 1회 Not-Taken)
      // =====================================================================
      $display("\n=== 테스트 3: 중첩 루프 패턴 ===");
      total_branches = 0; correct_predictions = 0; mispredictions = 0;

      for (int outer = 0; outer < 10; outer++) begin
         for (int inner = 0; inner < 5; inner++) begin
            do_branch(32'h0000_0300, 1'b1);  // 내부 루프: Taken
         end
         do_branch(32'h0000_0300, 1'b0);     // 내부 루프 탈출: Not-Taken
      end

      $display("총 분기: %0d, 정확: %0d, 오예측: %0d, 예측률: %0.1f%%",
               total_branches, correct_predictions, mispredictions,
               100.0 * correct_predictions / total_branches);

      // =====================================================================
      // 테스트 4: 상관 분기 (조건부 분기 2개가 서로 영향)
      // =====================================================================
      $display("\n=== 테스트 4: 상관 분기 패턴 ===");
      total_branches = 0; correct_predictions = 0; mispredictions = 0;

      for (int i = 0; i < 40; i++) begin
         logic first_taken;
         first_taken = (i % 3 != 0);  // 패턴: T, T, NT, T, T, NT, ...

         do_branch(32'h0000_0400, first_taken);
         // 두 번째 분기는 첫 번째와 반대
         do_branch(32'h0000_0404, ~first_taken);
      end

      $display("총 분기: %0d, 정확: %0d, 오예측: %0d, 예측률: %0.1f%%",
               total_branches, correct_predictions, mispredictions,
               100.0 * correct_predictions / total_branches);

      // =====================================================================
      // 테스트 완료
      // =====================================================================
      $display("\n=== 모든 테스트 완료 ===\n");
      $finish;
   end

   // 파형 덤프
   initial begin
      $dumpfile("tournament_predictor.vcd");
      $dumpvars(0, tournament_predictor_tb);
   end

endmodule
