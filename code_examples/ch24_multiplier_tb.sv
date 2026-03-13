///////////////////////////////////////////////////////////////////////////////
// 모듈명 : multiplier_tb
// 설  명 : M 확장 곱셈기 통합 테스트벤치
//          MUL/MULH/MULHSU/MULHU 4종 명령어에 대해 경계값 검증을 수행한다.
// 표  준 : IEEE 1800-2017 (SystemVerilog)
// 용  도 : 시뮬레이션 전용 (합성 불가)
///////////////////////////////////////////////////////////////////////////////

`timescale 1ns / 1ps

module multiplier_tb;

   // ---------------------------------------------------------------
   // 신호 선언
   // ---------------------------------------------------------------
   logic        clk;
   logic        rst_n;
   logic        start;
   logic [1:0]  mul_op;
   logic [31:0] operand_a;
   logic [31:0] operand_b;
   logic [31:0] result;
   logic        valid;

   // 테스트 결과 추적
   int pass_count = 0;
   int fail_count = 0;

   // ---------------------------------------------------------------
   // DUT 인스턴스
   // ---------------------------------------------------------------
   multiplier_dsp48e1 u_dut (
      .clk       (clk),
      .rst_n     (rst_n),
      .start     (start),
      .mul_op    (mul_op),
      .operand_a (operand_a),
      .operand_b (operand_b),
      .result    (result),
      .valid     (valid)
   );

   // ---------------------------------------------------------------
   // 클럭 생성: 10ns 주기 (100MHz)
   // ---------------------------------------------------------------
   initial clk = 1'b0;
   always #5 clk = ~clk;

   // ---------------------------------------------------------------
   // 검증 태스크
   // ---------------------------------------------------------------
   task automatic check_mul(
      input string   test_name,
      input [1:0]    op,
      input [31:0]   a,
      input [31:0]   b,
      input [31:0]   expected
   );
      @(posedge clk);
      mul_op    = op;
      operand_a = a;
      operand_b = b;
      start     = 1'b1;
      @(posedge clk);
      start = 1'b0;

      // 3사이클 파이프라인 대기
      repeat (3) @(posedge clk);

      if (result === expected) begin
         $display("[PASS] %s: 0x%08h * 0x%08h = 0x%08h",
                  test_name, a, b, result);
         pass_count++;
      end else begin
         $display("[FAIL] %s: 0x%08h * 0x%08h = 0x%08h (expected: 0x%08h)",
                  test_name, a, b, result, expected);
         fail_count++;
      end
   endtask

   // ---------------------------------------------------------------
   // 테스트 시나리오
   // ---------------------------------------------------------------
   initial begin
      // 초기화
      rst_n     = 1'b0;
      start     = 1'b0;
      mul_op    = 2'b00;
      operand_a = 32'd0;
      operand_b = 32'd0;

      repeat (5) @(posedge clk);
      rst_n = 1'b1;
      repeat (2) @(posedge clk);

      $display("========================================");
      $display(" M 확장 곱셈기 테스트 시작");
      $display("========================================");

      // --- MUL (하위 32비트) 테스트 ---
      $display("\n--- MUL (funct3=000) 테스트 ---");
      check_mul("MUL 기본",       2'b00, 32'd7,          32'd6,          32'd42);
      check_mul("MUL 0 곱셈",     2'b00, 32'd0,          32'd12345,      32'd0);
      check_mul("MUL 1 곱셈",     2'b00, 32'd1,          32'hDEAD_BEEF,  32'hDEAD_BEEF);
      check_mul("MUL 음수x양수",  2'b00, 32'hFFFF_FFFF,  32'd3,          32'hFFFF_FFFD);
      check_mul("MUL 음수x음수",  2'b00, 32'hFFFF_FFFF,  32'hFFFF_FFFF,  32'h0000_0001);
      check_mul("MUL 큰수",       2'b00, 32'h0001_0000,  32'h0001_0000,  32'h0000_0000);

      // --- MULH (상위 32비트, signed x signed) 테스트 ---
      $display("\n--- MULH (funct3=001) 테스트 ---");
      check_mul("MULH 양수x양수", 2'b01, 32'd7,          32'd6,          32'd0);
      check_mul("MULH 큰양수",    2'b01, 32'h7FFF_FFFF,  32'h7FFF_FFFF,  32'h3FFF_FFFF);
      check_mul("MULH -1x-1",     2'b01, 32'hFFFF_FFFF,  32'hFFFF_FFFF,  32'h0000_0000);
      check_mul("MULH -1x1",      2'b01, 32'hFFFF_FFFF,  32'h0000_0001,  32'hFFFF_FFFF);

      // --- MULHU (상위 32비트, unsigned x unsigned) 테스트 ---
      $display("\n--- MULHU (funct3=011) 테스트 ---");
      check_mul("MULHU 기본",     2'b11, 32'hFFFF_FFFF,  32'hFFFF_FFFF,  32'hFFFF_FFFE);
      check_mul("MULHU 소수",     2'b11, 32'd7,          32'd6,          32'd0);

      // --- 결과 요약 ---
      $display("\n========================================");
      $display(" 테스트 완료: PASS=%0d, FAIL=%0d", pass_count, fail_count);
      $display("========================================");

      if (fail_count == 0)
         $display("모든 테스트 통과!");
      else
         $display("실패한 테스트가 있습니다. 파형을 확인하십시오.");

      #100;
      $finish;
   end

   // 파형 덤프 (VCS/Verdi용)
   initial begin
      $dumpfile("ch24_multiplier_tb.vcd");
      $dumpvars(0, multiplier_tb);
   end

endmodule
