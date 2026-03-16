// ============================================================================
// app_e_vivado_sim_testbench.sv
// Vivado Simulator 검증용 간단 테스트벤치
// ============================================================================
// 목적: Vivado Simulator (xsim) 설치 확인 및 기본 파형 분석 체험
//
// 시뮬레이션 실행 (Vivado Tcl Console):
//   1. Vivado 프로젝트에 이 파일을 Simulation Sources로 추가
//   2. Flow → Run Simulation → Run Behavioral Simulation
//   3. 파형 창에서 clk, rst_n, counter, led_out 신호 관찰
// ============================================================================

`timescale 1ns / 1ps

module tb_led_blink;

   // -------------------------------------------------------
   // 신호 선언
   // -------------------------------------------------------
   logic        clk;
   logic        rst_n;
   logic        led_out;

   // -------------------------------------------------------
   // DUT (Device Under Test) 인스턴스
   // -------------------------------------------------------
   // led_blink 모듈: 100MHz 클록 → 1Hz LED 토글
   led_blink dut (
      .clk     (clk),
      .rst_n   (rst_n),
      .led_out (led_out)
   );

   // -------------------------------------------------------
   // 클록 생성: 100 MHz (주기 10ns)
   // -------------------------------------------------------
   initial begin
      clk = 1'b0;
   end

   always #5 clk = ~clk;  // 5ns ON + 5ns OFF = 10ns 주기

   // -------------------------------------------------------
   // 리셋 및 테스트 시나리오
   // -------------------------------------------------------
   initial begin
      // --- 리셋 인가 (처음 100ns) ---
      rst_n = 1'b0;               // 리셋 활성화 (능동 저전압)
      #100;
      rst_n = 1'b1;               // 리셋 해제
      $display("[%0t ns] 리셋 해제 완료", $time);

      // --- 카운터 동작 관찰 (500us = 500,000ns) ---
      // 참고: 실제 LED 토글은 ~1.34초 (134,000,000ns)이므로
      //       시뮬레이션에서는 카운터 증가만 확인
      #500_000;
      $display("[%0t ns] 시뮬레이션 종료", $time);
      $display("  led_out = %b", led_out);

      // --- 검증 ---
      // 리셋 해제 후 카운터가 0이 아니면 정상 동작
      if (dut.counter != 27'd0) begin
         $display("  테스트 통과: 카운터 정상 동작 (counter = %0d)", dut.counter);
      end else begin
         $display("  테스트 실패: 카운터가 0입니다. 클록 또는 리셋을 확인하세요.");
      end

      $finish;
   end

   // -------------------------------------------------------
   // 파형 덤프 (Vivado Simulator용)
   // -------------------------------------------------------
   // Vivado xsim은 자동으로 .wdb 파일 생성
   // VCS 사용 시: $fsdbDumpfile / $fsdbDumpvars 로 대체
   initial begin
      $dumpfile("tb_led_blink.vcd");
      $dumpvars(0, tb_led_blink);
   end

endmodule
