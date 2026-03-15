// =============================================================
// M 확장 곱셈/나눗셈 유닛 테스트벤치
// Chapter 24 — RV32I 확장: M & F 표준 확장
// =============================================================
`timescale 1ns / 1ps

module mul_div_tb;

   logic        clk, rst_n, start, flush;
   logic [2:0]  funct3;
   logic [31:0] operand_a, operand_b;
   logic [31:0] result;
   logic        ready, busy;

   mul_div_unit #(.DATA_WIDTH(32)) dut (.*);

   // 클럭 생성 (10ns 주기, 100MHz)
   initial clk = 0;
   always #5 clk = ~clk;

   // 테스트 카운터
   int pass_cnt = 0;
   int fail_cnt = 0;

   // 곱셈 테스트 태스크
   task automatic test_mul(
      input  string      name,
      input  logic [2:0]  f3,
      input  logic [31:0] a, b,
      input  logic [31:0] expected
   );
      @(posedge clk);
      funct3    = f3;
      operand_a = a;
      operand_b = b;
      start     = 1'b1;
      @(posedge clk);
      start = 1'b0;
      // 곱셈: 1사이클 후 ready
      @(posedge clk);
      if (ready && result === expected) begin
         $display("[PASS] %s: 0x%08h op 0x%08h = 0x%08h",
                  name, a, b, result);
         pass_cnt++;
      end else begin
         $display("[FAIL] %s: expected 0x%08h, got 0x%08h (ready=%b)",
                  name, expected, result, ready);
         fail_cnt++;
      end
   endtask

   // 나눗셈 테스트 태스크
   task automatic test_div(
      input  string      name,
      input  logic [2:0]  f3,
      input  logic [31:0] a, b,
      input  logic [31:0] expected
   );
      @(posedge clk);
      funct3    = f3;
      operand_a = a;
      operand_b = b;
      start     = 1'b1;
      @(posedge clk);
      start = 1'b0;
      // 나눗셈: ready 대기
      wait(ready);
      @(posedge clk);
      if (result === expected) begin
         $display("[PASS] %s: 0x%08h op 0x%08h = 0x%08h",
                  name, a, b, result);
         pass_cnt++;
      end else begin
         $display("[FAIL] %s: expected 0x%08h, got 0x%08h",
                  name, expected, result);
         fail_cnt++;
      end
   endtask

   // 메인 테스트 시퀀스
   initial begin
      $display("=========================================");
      $display("  M Extension MUL/DIV Unit Test");
      $display("=========================================");
      rst_n = 0; start = 0; flush = 0;
      funct3 = 0; operand_a = 0; operand_b = 0;
      repeat(3) @(posedge clk);
      rst_n = 1;
      @(posedge clk);

      // ===== 곱셈 테스트 =====
      $display("\n--- Multiplication Tests ---");

      // MUL (funct3=000): 하위 32비트
      test_mul("MUL  7*3",      3'b000, 32'd7, 32'd3, 32'd21);
      test_mul("MUL -7*3",      3'b000, -32'sd7, 32'd3, -32'sd21);
      test_mul("MUL  0*x",      3'b000, 32'd0, 32'd12345, 32'd0);
      test_mul("MUL  1*x",      3'b000, 32'd1, 32'hDEAD_BEEF, 32'hDEAD_BEEF);
      test_mul("MUL -1*-1",     3'b000, 32'hFFFFFFFF, 32'hFFFFFFFF, 32'd1);

      // MULH (funct3=001): 상위 32비트 (signed × signed)
      test_mul("MULH  7*3",     3'b001, 32'd7, 32'd3, 32'd0);
      test_mul("MULH large",    3'b001, 32'h7FFF_FFFF, 32'd2, 32'h0000_0000);

      // MULHU (funct3=011): 상위 32비트 (unsigned × unsigned)
      test_mul("MULHU max*2",   3'b011, 32'hFFFF_FFFF, 32'd2, 32'h0000_0001);
      test_mul("MULHU max*max", 3'b011, 32'hFFFF_FFFF, 32'hFFFF_FFFF, 32'hFFFF_FFFE);

      // ===== 나눗셈 테스트 =====
      $display("\n--- Division Tests ---");

      // DIV (funct3=100): signed 나눗셈
      test_div("DIV  100/7",    3'b100, 32'd100, 32'd7, 32'd14);
      test_div("DIV -100/7",    3'b100, -32'sd100, 32'd7, -32'sd14);
      test_div("DIV  20/4",     3'b100, 32'd20, 32'd4, 32'd5);

      // DIVU (funct3=101): unsigned 나눗셈
      test_div("DIVU max/2",    3'b101, 32'hFFFF_FFFF, 32'd2, 32'h7FFF_FFFF);
      test_div("DIVU 256/16",   3'b101, 32'd256, 32'd16, 32'd16);

      // REM (funct3=110): signed 나머지
      test_div("REM  100%7",    3'b110, 32'd100, 32'd7, 32'd2);
      test_div("REM -100%7",    3'b110, -32'sd100, 32'd7, -32'sd2);

      // REMU (funct3=111): unsigned 나머지
      test_div("REMU 100%7",    3'b111, 32'd100, 32'd7, 32'd2);

      // ===== 특수 케이스 =====
      $display("\n--- Special Cases ---");

      // 0으로 나누기
      test_div("DIV  x/0",      3'b100, 32'd42, 32'd0, 32'hFFFF_FFFF);
      test_div("REM  x/0",      3'b110, 32'd42, 32'd0, 32'd42);
      test_div("DIVU x/0",      3'b101, 32'd42, 32'd0, 32'hFFFF_FFFF);
      test_div("REMU x/0",      3'b111, 32'd42, 32'd0, 32'd42);

      // -2^31 / -1 오버플로 (RISC-V 스펙: DIV=-2^31, REM=0)
      test_div("DIV -2^31/-1",  3'b100, 32'h8000_0000, 32'hFFFF_FFFF, 32'h8000_0000);
      test_div("REM -2^31/-1",  3'b110, 32'h8000_0000, 32'hFFFF_FFFF, 32'd0);

      // 결과 요약
      $display("\n=========================================");
      $display("  Results: %0d PASS, %0d FAIL", pass_cnt, fail_cnt);
      $display("=========================================");
      $finish;
   end

   // 타임아웃 가드
   initial begin
      #200000;
      $display("[TIMEOUT] Simulation exceeded time limit");
      $finish;
   end

endmodule
