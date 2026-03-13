// ============================================================
// Chapter 21 — HTIF (Host-Target Interface) 모니터
// RISC-V 프로세서 설계 완전정복
// ============================================================
// riscv-tests 공식 테스트의 PASS/FAIL 판정을 위한
// tohost 메모리 주소 감시 모듈입니다.
// 시뮬레이션과 FPGA 모두에서 사용 가능합니다.
// ============================================================

module htif_monitor #(
   parameter TOHOST_ADDR = 32'h8000_1000  // tohost 주소 (링커 스크립트와 일치)
)(
   input  logic        clk,
   input  logic        rst_n,

   // === 메모리 쓰기 관찰 인터페이스 ===
   input  logic        mem_wen,       // 메모리 쓰기 인에이블
   input  logic [31:0] mem_addr,      // 메모리 쓰기 주소
   input  logic [31:0] mem_wdata,     // 메모리 쓰기 데이터

   // === 테스트 결과 출력 ===
   output logic        test_done,     // 테스트 완료 신호
   output logic        test_pass,     // PASS (1) / FAIL (0)
   output logic [15:0] test_id,       // 실패 시 테스트 케이스 번호

   // === LED/UART 연결용 ===
   output logic        led_pass,      // 녹색 LED (PASS)
   output logic        led_fail       // 적색 LED (FAIL)
);

   // ---------------------------------------------------------
   // tohost 주소 감시
   // ---------------------------------------------------------
   // riscv-tests 프로토콜:
   //   tohost에 기록되는 값의 의미:
   //   - 값 == 1        → 모든 테스트 PASS
   //   - 값 != 1 (홀수) → FAIL, 테스트 번호 = 값 >> 1
   //   - 값 == 0        → 아직 완료되지 않음
   // ---------------------------------------------------------

   logic [31:0] tohost_value;

   always_ff @(posedge clk or negedge rst_n) begin
      if (!rst_n) begin
         tohost_value <= 32'h0;
         test_done    <= 1'b0;
         test_pass    <= 1'b0;
         test_id      <= 16'h0;
      end else begin
         // tohost 주소에 비-0 값이 기록되면 테스트 완료
         if (mem_wen && (mem_addr == TOHOST_ADDR) && (mem_wdata != 32'h0)) begin
            tohost_value <= mem_wdata;
            test_done    <= 1'b1;

            if (mem_wdata == 32'h1) begin
               // PASS: tohost == 1
               test_pass <= 1'b1;
               test_id   <= 16'h0;
            end else begin
               // FAIL: tohost != 1
               test_pass <= 1'b0;
               test_id   <= mem_wdata[16:1];  // 실패 테스트 번호
            end
         end
      end
   end

   // LED 출력 — Basys 3에서 결과 시각 확인
   assign led_pass = test_done & test_pass;
   assign led_fail = test_done & ~test_pass;

   // ---------------------------------------------------------
   // 시뮬레이션 전용: 결과 출력 및 종료
   // ---------------------------------------------------------
   // synthesis translate_off
   always_ff @(posedge clk) begin
      if (test_done) begin
         if (test_pass) begin
            $display("============================================");
            $display("  TEST PASSED");
            $display("============================================");
         end else begin
            $display("============================================");
            $display("  TEST FAILED — 테스트 케이스 #%0d", test_id);
            $display("  tohost = 0x%08h", tohost_value);
            $display("============================================");
         end
         $finish;
      end
   end

   // 타임아웃 보호 — 무한 루프 방지
   logic [31:0] timeout_cnt;

   always_ff @(posedge clk or negedge rst_n) begin
      if (!rst_n)
         timeout_cnt <= 32'h0;
      else if (!test_done)
         timeout_cnt <= timeout_cnt + 32'h1;
   end

   always_ff @(posedge clk) begin
      if (timeout_cnt > 32'd1_000_000 && !test_done) begin
         $display("============================================");
         $display("  TIMEOUT — 1,000,000 사이클 초과");
         $display("============================================");
         $finish;
      end
   end
   // synthesis translate_on

endmodule
