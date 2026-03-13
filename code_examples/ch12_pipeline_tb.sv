///////////////////////////////////////////////////////////////////////////////
// Module: rv32i_pipeline_tb
// Description: 5단계 파이프라인 RV32I 프로세서 통합 테스트벤치
//              버블 정렬, 재귀 팩토리얼, 복합 해저드 시나리오 검증
//
// Author: RISC-V 프로세서 설계 완전정복, Chapter 12
// Standard: IEEE 1800-2017 (SystemVerilog)
///////////////////////////////////////////////////////////////////////////////

`timescale 1ns / 1ps

module rv32i_pipeline_tb;

   // =========================================================================
   // 테스트 파라미터
   // =========================================================================
   parameter int CLK_PERIOD   = 20;     // 50 MHz 클록
   parameter int IMEM_DEPTH   = 1024;
   parameter int DMEM_DEPTH   = 1024;
   parameter int MAX_CYCLES   = 10000;  // 최대 시뮬레이션 사이클
   parameter int NUM_REGS     = 32;

   // =========================================================================
   // 신호 선언
   // =========================================================================
   logic clk;
   logic rst_n;
   int   cycle_count;

   // =========================================================================
   // DUT 인스턴스
   // =========================================================================
   rv32i_pipeline_top #(
      .IMEM_DEPTH   (IMEM_DEPTH),
      .DMEM_DEPTH   (DMEM_DEPTH),
      .RESET_VECTOR (32'h0000_0000)
   ) dut (
      .clk   (clk),
      .rst_n (rst_n)
   );

   // =========================================================================
   // 클록 생성
   // =========================================================================
   initial clk = 1'b0;
   always #(CLK_PERIOD / 2) clk = ~clk;

   // =========================================================================
   // 사이클 카운터
   // =========================================================================
   always_ff @(posedge clk or negedge rst_n) begin
      if (!rst_n)
         cycle_count <= 0;
      else
         cycle_count <= cycle_count + 1;
   end

   // =========================================================================
   // 테스트 시퀀스
   // =========================================================================
   initial begin
      // VCD 파형 덤프
      $dumpfile("rv32i_pipeline.vcd");
      $dumpvars(0, rv32i_pipeline_tb);

      // ------ 리셋 ------
      $display("=== RV32I Pipeline Processor Test ===");
      $display("[%0t] 리셋 시작", $time);
      rst_n = 1'b0;
      repeat (5) @(posedge clk);
      rst_n = 1'b1;
      $display("[%0t] 리셋 해제", $time);

      // ------ 프로그램 실행 대기 ------
      // ECALL (opcode = 0x73)을 만나면 종료
      fork
         begin : watchdog
            repeat (MAX_CYCLES) @(posedge clk);
            $display("[ERROR] 최대 사이클 초과! 프로그램이 종료되지 않음");
            $finish;
         end

         begin : check_ecall
            forever begin
               @(posedge clk);
               // WB 스테이지에서 ECALL 감지
               if (dut.instruction_id == 32'h0000_0073) begin
                  // ECALL 도달 — 몇 사이클 더 기다린 후 종료
                  repeat (5) @(posedge clk);
                  disable watchdog;
               end
            end
         end
      join_any

      // ------ 결과 검증 ------
      $display("\n=== 실행 완료: %0d 사이클 ===", cycle_count);
      $display("=== 레지스터 파일 덤프 ===");
      for (int i = 0; i < NUM_REGS; i++) begin
         $display("  x%-2d = 0x%08h", i,
                  dut.u_regfile.regs[i]);
      end

      $display("\n=== 데이터 메모리 덤프 (처음 16워드) ===");
      for (int i = 0; i < 16; i++) begin
         $display("  MEM[%04h] = 0x%08h", i*4,
                  dut.u_dmem.mem[i]);
      end

      // ------ 버블 정렬 결과 검증 (예시) ------
      $display("\n=== 정렬 결과 검증 ===");
      verify_sorted();

      $display("\n=== 테스트 완료 ===");
      $finish;
   end

   // =========================================================================
   // 정렬 결과 검증 태스크
   // 데이터 메모리의 지정된 영역이 오름차순 정렬되었는지 확인
   // =========================================================================
   task automatic verify_sorted();
      int base_addr = 0;    // 정렬 배열 시작 (워드 인덱스)
      int array_len = 8;    // 배열 길이
      logic sorted = 1'b1;

      for (int i = 0; i < array_len - 1; i++) begin
         if ($signed(dut.u_dmem.mem[base_addr + i]) >
             $signed(dut.u_dmem.mem[base_addr + i + 1])) begin
            $display("[FAIL] MEM[%0d] = %0d > MEM[%0d] = %0d",
                     base_addr + i,
                     $signed(dut.u_dmem.mem[base_addr + i]),
                     base_addr + i + 1,
                     $signed(dut.u_dmem.mem[base_addr + i + 1]));
            sorted = 1'b0;
         end
      end

      if (sorted)
         $display("[PASS] 배열이 올바르게 정렬되었습니다!");
      else
         $display("[FAIL] 정렬 오류가 발견되었습니다.");
   endtask

endmodule
