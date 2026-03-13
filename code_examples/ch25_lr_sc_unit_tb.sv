// ============================================================================
// LR/SC 유닛 테스트벤치
// - LR.W → SC.W 성공/실패 시나리오 검증
// - 스누핑에 의한 예약 무효화 검증
// - 시뮬레이션 전용 (합성 불가)
// ============================================================================
`timescale 1ns / 1ps

module lr_sc_unit_tb;

   logic        clk, rst_n;
   logic        ex_lr_w, ex_sc_w;
   logic [31:0] ex_addr, ex_wdata;
   logic        snoop_valid, snoop_write;
   logic [31:0] snoop_addr;
   logic        mem_rd, mem_wr;
   logic [31:0] mem_addr, mem_wdata;
   logic        sc_success, sc_result_valid;

   // DUT 인스턴스
   lr_sc_unit dut (
      .clk            (clk),
      .rst_n          (rst_n),
      .ex_lr_w        (ex_lr_w),
      .ex_sc_w        (ex_sc_w),
      .ex_addr        (ex_addr),
      .ex_wdata       (ex_wdata),
      .snoop_valid    (snoop_valid),
      .snoop_addr     (snoop_addr),
      .snoop_write    (snoop_write),
      .mem_rd         (mem_rd),
      .mem_wr         (mem_wr),
      .mem_addr       (mem_addr),
      .mem_wdata      (mem_wdata),
      .sc_success     (sc_success),
      .sc_result_valid(sc_result_valid)
   );

   // 클록 생성
   initial clk = 0;
   always #5 clk = ~clk;

   // 입력 초기화
   task clear_inputs();
      ex_lr_w     = 0;
      ex_sc_w     = 0;
      ex_addr     = 32'h0;
      ex_wdata    = 32'h0;
      snoop_valid = 0;
      snoop_addr  = 32'h0;
      snoop_write = 0;
   endtask

   initial begin
      $display("========================================");
      $display("LR/SC 유닛 테스트벤치 시작");
      $display("========================================");

      clear_inputs();
      rst_n = 0;
      #20;
      rst_n = 1;
      #10;

      // ----- 시나리오 1: LR.W → SC.W 성공 -----
      $display("\n[시나리오 1] LR.W → SC.W 성공 (간섭 없음)");

      // LR.W: 주소 0x1000에서 읽기 + 예약 설정
      ex_lr_w = 1;
      ex_addr = 32'h0000_1000;
      @(posedge clk); #1;
      clear_inputs();
      assert(mem_rd == 1) else $error("LR.W 시 mem_rd가 1이 아님!");
      $display("  LR.W 실행: addr=0x%08h, mem_rd=%b", 32'h1000, mem_rd);

      @(posedge clk); #1;

      // SC.W: 같은 주소에 값 42 기록 시도
      ex_sc_w = 1;
      ex_addr = 32'h0000_1000;
      ex_wdata = 32'd42;
      @(posedge clk); #1;
      $display("  SC.W 실행: sc_success=%b, mem_wr=%b", sc_success, mem_wr);
      assert(sc_success == 1) else $error("SC.W 성공해야 함!");
      assert(mem_wr == 1) else $error("SC.W 성공 시 mem_wr=1이어야 함!");
      clear_inputs();
      @(posedge clk); #1;

      // ----- 시나리오 2: LR.W → 스누핑 무효화 → SC.W 실패 -----
      $display("\n[시나리오 2] LR.W → 스누핑 무효화 → SC.W 실패");

      // LR.W: 주소 0x2000 예약
      ex_lr_w = 1;
      ex_addr = 32'h0000_2000;
      @(posedge clk); #1;
      clear_inputs();

      @(posedge clk); #1;

      // 다른 코어가 같은 주소에 쓰기 → 예약 무효화
      snoop_valid = 1;
      snoop_addr  = 32'h0000_2000;
      snoop_write = 1;
      @(posedge clk); #1;
      clear_inputs();
      $display("  스누핑 무효화: addr=0x%08h", 32'h2000);

      @(posedge clk); #1;

      // SC.W: 예약이 무효화되었으므로 실패해야 함
      ex_sc_w  = 1;
      ex_addr  = 32'h0000_2000;
      ex_wdata = 32'd99;
      @(posedge clk); #1;
      $display("  SC.W 실행: sc_success=%b, mem_wr=%b", sc_success, mem_wr);
      assert(sc_success == 0) else $error("SC.W 실패해야 함!");
      assert(mem_wr == 0) else $error("SC.W 실패 시 mem_wr=0이어야 함!");
      clear_inputs();
      @(posedge clk); #1;

      // ----- 시나리오 3: LR.W → SC.W 주소 불일치 → 실패 -----
      $display("\n[시나리오 3] LR.W → SC.W 주소 불일치 → 실패");

      // LR.W: 주소 0x3000 예약
      ex_lr_w = 1;
      ex_addr = 32'h0000_3000;
      @(posedge clk); #1;
      clear_inputs();

      @(posedge clk); #1;

      // SC.W: 다른 주소 0x4000에 시도 → 실패
      ex_sc_w  = 1;
      ex_addr  = 32'h0000_4000;
      ex_wdata = 32'd77;
      @(posedge clk); #1;
      $display("  SC.W 실행 (주소 불일치): sc_success=%b", sc_success);
      assert(sc_success == 0) else $error("주소 불일치 시 SC.W 실패해야 함!");
      clear_inputs();
      @(posedge clk); #1;

      $display("\n========================================");
      $display("모든 시나리오 통과!");
      $display("========================================");
      #20;
      $finish;
   end

   // VCD 파형 저장
   initial begin
      $dumpfile("lr_sc_unit_tb.vcd");
      $dumpvars(0, lr_sc_unit_tb);
   end

endmodule
