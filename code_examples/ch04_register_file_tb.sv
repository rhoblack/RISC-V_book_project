// =============================================================================
// 모듈명: register_file_tb
// 설  명: 레지스터 파일 단위 테스트벤치 — 읽기/쓰기, x0 보호, 동시 접근 검증
// 파  일: ch04_register_file_tb.sv
// 표  준: IEEE 1800-2017 (SystemVerilog)
// 저  자: RISC-V 프로세서 설계 완전정복 — Chapter 04
// =============================================================================

`timescale 1ns / 1ps

module register_file_tb;

   // === 신호 선언 ===
   logic        clk;
   logic        rst_n;
   logic [4:0]  rs1_addr;
   logic [31:0] rs1_data;
   logic [4:0]  rs2_addr;
   logic [31:0] rs2_data;
   logic [4:0]  rd_addr;
   logic [31:0] rd_data;
   logic        reg_wr_en;

   // === DUT 인스턴스 ===
   register_file u_rf (
      .clk       (clk),
      .rst_n     (rst_n),
      .rs1_addr  (rs1_addr),
      .rs1_data  (rs1_data),
      .rs2_addr  (rs2_addr),
      .rs2_data  (rs2_data),
      .rd_addr   (rd_addr),
      .rd_data   (rd_data),
      .reg_wr_en (reg_wr_en)
   );

   // === 클록 생성: 10ns 주기 (100MHz) ===
   initial clk = 1'b0;
   always #5 clk = ~clk;

   // === 테스트 통계 ===
   int pass_count = 0;
   int fail_count = 0;
   int test_count = 0;

   // === 검증 태스크 ===
   task automatic check_read(
      input string   test_name,
      input [31:0]   actual,
      input [31:0]   expected
   );
      test_count++;
      if (actual !== expected) begin
         $display("[FAIL] %s: got=0x%08h, expected=0x%08h", test_name, actual, expected);
         fail_count++;
      end else begin
         $display("[PASS] %s: data=0x%08h", test_name, actual);
         pass_count++;
      end
   endtask

   // === 쓰기 태스크: 한 클럭 사이클 동안 쓰기 수행 ===
   task automatic write_reg(
      input [4:0]  addr,
      input [31:0] data
   );
      @(posedge clk);
      rd_addr   = addr;
      rd_data   = data;
      reg_wr_en = 1'b1;
      @(posedge clk);
      reg_wr_en = 1'b0;
   endtask

   // === 메인 테스트 시퀀스 ===
   initial begin
      $display("==========================================================");
      $display(" 레지스터 파일 단위 테스트벤치 시작");
      $display("==========================================================");

      // 초기화
      rst_n     = 1'b0;
      rs1_addr  = 5'b0;
      rs2_addr  = 5'b0;
      rd_addr   = 5'b0;
      rd_data   = 32'b0;
      reg_wr_en = 1'b0;

      // 리셋 해제
      repeat (3) @(posedge clk);
      rst_n = 1'b1;
      @(posedge clk);

      // -------------------------------------------------------
      // 테스트 1: 리셋 후 x0 읽기 — 항상 0
      // -------------------------------------------------------
      $display("\n--- 테스트 1: 리셋 후 x0 읽기 ---");
      rs1_addr = 5'd0;
      #1;
      check_read("x0 읽기 (리셋 후)", rs1_data, 32'd0);

      // -------------------------------------------------------
      // 테스트 2: x1에 쓰기 후 읽기
      // -------------------------------------------------------
      $display("\n--- 테스트 2: x1에 쓰기 후 읽기 ---");
      write_reg(5'd1, 32'hDEAD_BEEF);
      rs1_addr = 5'd1;
      #1;
      check_read("x1 읽기", rs1_data, 32'hDEAD_BEEF);

      // -------------------------------------------------------
      // 테스트 3: x0에 쓰기 시도 — 무시되어야 함
      // -------------------------------------------------------
      $display("\n--- 테스트 3: x0 쓰기 무시 검증 ---");
      write_reg(5'd0, 32'h1234_5678);
      rs1_addr = 5'd0;
      #1;
      check_read("x0 쓰기 시도 후 읽기 (0 유지)", rs1_data, 32'd0);

      // -------------------------------------------------------
      // 테스트 4: 두 포트 동시 읽기
      // -------------------------------------------------------
      $display("\n--- 테스트 4: 두 포트 동시 읽기 ---");
      write_reg(5'd2, 32'hAAAA_AAAA);
      write_reg(5'd3, 32'h5555_5555);
      rs1_addr = 5'd2;
      rs2_addr = 5'd3;
      #1;
      check_read("포트1: x2 읽기", rs1_data, 32'hAAAA_AAAA);
      check_read("포트2: x3 읽기", rs2_data, 32'h5555_5555);

      // -------------------------------------------------------
      // 테스트 5: 같은 레지스터를 두 포트에서 동시 읽기
      // -------------------------------------------------------
      $display("\n--- 테스트 5: 동일 레지스터 동시 읽기 ---");
      rs1_addr = 5'd1;
      rs2_addr = 5'd1;
      #1;
      check_read("포트1: x1 읽기", rs1_data, 32'hDEAD_BEEF);
      check_read("포트2: x1 읽기", rs2_data, 32'hDEAD_BEEF);

      // -------------------------------------------------------
      // 테스트 6: reg_wr_en = 0일 때 쓰기 무시
      // -------------------------------------------------------
      $display("\n--- 테스트 6: 쓰기 인에이블 비활성화 ---");
      @(posedge clk);
      rd_addr   = 5'd1;
      rd_data   = 32'hFFFF_FFFF;
      reg_wr_en = 1'b0;  // 쓰기 비활성
      @(posedge clk);
      rs1_addr = 5'd1;
      #1;
      check_read("x1 쓰기 비활성 후 읽기 (이전 값 유지)", rs1_data, 32'hDEAD_BEEF);

      // -------------------------------------------------------
      // 테스트 7: 여러 레지스터 순차 쓰기/읽기 (x10~x15)
      // -------------------------------------------------------
      $display("\n--- 테스트 7: 연속 레지스터 쓰기/읽기 ---");
      for (int i = 10; i <= 15; i++) begin
         write_reg(i[4:0], 32'(i * 100));
      end
      for (int i = 10; i <= 15; i++) begin
         rs1_addr = i[4:0];
         #1;
         check_read($sformatf("x%0d 읽기", i), rs1_data, 32'(i * 100));
      end

      // -------------------------------------------------------
      // 테스트 8: 비동기 읽기 확인 — 클록 없이 즉시 반영
      // -------------------------------------------------------
      $display("\n--- 테스트 8: 비동기 읽기 즉시성 ---");
      rs1_addr = 5'd10;
      #1;
      check_read("비동기 읽기 (클록 대기 없음)", rs1_data, 32'd1000);
      // 주소 변경 후 즉시 확인
      rs1_addr = 5'd11;
      #1;
      check_read("주소 변경 후 즉시 읽기", rs1_data, 32'd1100);

      // -------------------------------------------------------
      // 테스트 9: 리셋 재적용
      // -------------------------------------------------------
      $display("\n--- 테스트 9: 리셋 재적용 ---");
      rst_n = 1'b0;
      @(posedge clk);
      @(posedge clk);
      rst_n = 1'b1;
      @(posedge clk);
      rs1_addr = 5'd1;
      #1;
      check_read("리셋 후 x1 읽기 (0으로 초기화)", rs1_data, 32'd0);
      rs1_addr = 5'd10;
      #1;
      check_read("리셋 후 x10 읽기 (0으로 초기화)", rs1_data, 32'd0);

      // -------------------------------------------------------
      // 결과 요약
      // -------------------------------------------------------
      $display("\n==========================================================");
      $display(" 테스트 완료: 총 %0d개 | 통과 %0d개 | 실패 %0d개",
               test_count, pass_count, fail_count);
      if (fail_count == 0)
         $display(" *** 모든 테스트 통과! ***");
      else
         $display(" *** 실패한 테스트가 있습니다. 위의 [FAIL] 항목을 확인하십시오. ***");
      $display("==========================================================");
      $finish;
   end

   // 파형 덤프 (시뮬레이터 호환)
   initial begin
      $dumpfile("register_file_tb.vcd");
      $dumpvars(0, register_file_tb);
   end

endmodule
