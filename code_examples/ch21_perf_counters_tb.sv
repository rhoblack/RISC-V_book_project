// ============================================================
// Chapter 21 — 성능 카운터 테스트벤치
// RISC-V 프로세서 설계 완전정복
// ============================================================
// mcycle, minstret 카운터와 IPC 계산을 검증합니다.
// ============================================================

`timescale 1ns / 1ps

module perf_counters_tb;

   // ---------------------------------------------------------
   // 신호 선언
   // ---------------------------------------------------------
   logic        clk;
   logic        rst_n;
   logic        wb_valid;
   logic        count_inhibit;
   logic        csr_wen;
   logic [11:0] csr_addr;
   logic [31:0] csr_wdata;
   logic [31:0] csr_rdata;
   logic        csr_valid;

   // ---------------------------------------------------------
   // DUT 인스턴스
   // ---------------------------------------------------------
   perf_counters u_dut (
      .clk            (clk),
      .rst_n          (rst_n),
      .wb_valid       (wb_valid),
      .count_inhibit  (count_inhibit),
      .csr_wen        (csr_wen),
      .csr_addr       (csr_addr),
      .csr_wdata      (csr_wdata),
      .csr_rdata      (csr_rdata),
      .csr_valid      (csr_valid)
   );

   // ---------------------------------------------------------
   // 클럭 생성 (50 MHz = 20ns 주기)
   // ---------------------------------------------------------
   initial clk = 1'b0;
   always #10 clk = ~clk;

   // ---------------------------------------------------------
   // CSR 읽기/쓰기 태스크
   // ---------------------------------------------------------
   task automatic csr_write(input logic [11:0] addr, input logic [31:0] data);
      @(posedge clk);
      csr_wen   <= 1'b1;
      csr_addr  <= addr;
      csr_wdata <= data;
      @(posedge clk);
      csr_wen   <= 1'b0;
   endtask

   task automatic csr_read(input logic [11:0] addr, output logic [31:0] data);
      @(posedge clk);
      csr_addr <= addr;
      csr_wen  <= 1'b0;
      @(posedge clk);
      data = csr_rdata;
   endtask

   // ---------------------------------------------------------
   // 테스트 시나리오
   // ---------------------------------------------------------
   logic [31:0] read_val;
   integer cycle_count;
   integer instr_count;
   real    ipc;

   initial begin
      // 초기화
      rst_n          = 1'b0;
      wb_valid       = 1'b0;
      count_inhibit  = 1'b0;
      csr_wen        = 1'b0;
      csr_addr       = 12'h0;
      csr_wdata      = 32'h0;

      // 리셋 해제
      repeat (5) @(posedge clk);
      rst_n = 1'b1;
      repeat (2) @(posedge clk);

      // =====================================================
      // 테스트 1: mcycle이 매 클럭 증가하는지 확인
      // =====================================================
      $display("\n[테스트 1] mcycle 자동 증가 확인");

      csr_read(12'hB00, read_val);  // mcycle 읽기
      $display("  리셋 후 mcycle = %0d", read_val);

      repeat (100) @(posedge clk);  // 100 사이클 대기

      csr_read(12'hB00, read_val);
      $display("  100 사이클 후 mcycle = %0d", read_val);
      assert(read_val > 100)
         $display("  [PASS] mcycle이 정상 증가");
      else
         $error("  [FAIL] mcycle 증가 실패");

      // =====================================================
      // 테스트 2: minstret이 wb_valid에만 증가
      // =====================================================
      $display("\n[테스트 2] minstret은 wb_valid일 때만 증가");

      // minstret 초기값 읽기
      csr_read(12'hB02, read_val);
      instr_count = read_val;

      // 50 사이클 중 30회 wb_valid 어서트
      for (int i = 0; i < 50; i++) begin
         @(posedge clk);
         wb_valid <= (i < 30) ? 1'b1 : 1'b0;
      end
      wb_valid <= 1'b0;

      @(posedge clk);
      csr_read(12'hB02, read_val);
      $display("  minstret 변화: %0d → %0d (차이: %0d)",
               instr_count, read_val, read_val - instr_count);
      assert(read_val - instr_count == 30)
         $display("  [PASS] minstret = wb_valid 횟수");
      else
         $error("  [FAIL] minstret 불일치 (예상: 30)");

      // =====================================================
      // 테스트 3: IPC 계산
      // =====================================================
      $display("\n[테스트 3] IPC 측정 시뮬레이션");

      // 카운터 리셋 (직접 쓰기)
      csr_write(12'hB00, 32'h0);  // mcycle = 0
      csr_write(12'hB02, 32'h0);  // minstret = 0

      // 200 사이클 중 150회 유효 명령어 (IPC ≈ 0.75)
      for (int i = 0; i < 200; i++) begin
         @(posedge clk);
         // 4사이클 중 3사이클 유효 (스톨 1사이클 시뮬레이션)
         wb_valid <= (i % 4 != 3) ? 1'b1 : 1'b0;
      end
      wb_valid <= 1'b0;

      @(posedge clk);
      csr_read(12'hB00, read_val);
      cycle_count = read_val;

      csr_read(12'hB02, read_val);
      instr_count = read_val;

      ipc = real'(instr_count) / real'(cycle_count);
      $display("  mcycle   = %0d", cycle_count);
      $display("  minstret = %0d", instr_count);
      $display("  IPC      = %0.3f", ipc);
      assert(ipc > 0.7 && ipc < 0.8)
         $display("  [PASS] IPC ≈ 0.75 (예상 범위)");
      else
         $error("  [FAIL] IPC 범위 이탈");

      // =====================================================
      // 테스트 4: mcountinhibit 동작 확인
      // =====================================================
      $display("\n[테스트 4] mcountinhibit CY 비트 테스트");

      // CY 비트 설정 → mcycle 정지
      csr_write(12'h320, 32'h1);   // mcountinhibit[0] = 1

      csr_read(12'hB00, read_val);
      cycle_count = read_val;

      repeat (50) @(posedge clk);

      csr_read(12'hB00, read_val);
      $display("  억제 상태 50사이클 후 mcycle 변화: %0d",
               read_val - cycle_count);
      assert(read_val == cycle_count)
         $display("  [PASS] mcycle 정지 확인");
      else
         $error("  [FAIL] mcycle이 정지되지 않음");

      // CY 비트 해제
      csr_write(12'h320, 32'h0);

      // =====================================================
      // 테스트 완료
      // =====================================================
      $display("\n========================================");
      $display("  모든 성능 카운터 테스트 완료");
      $display("========================================\n");
      $finish;
   end

   // ---------------------------------------------------------
   // 파형 덤프 (VCD)
   // ---------------------------------------------------------
   initial begin
      $dumpfile("perf_counters_tb.vcd");
      $dumpvars(0, perf_counters_tb);
   end

endmodule
