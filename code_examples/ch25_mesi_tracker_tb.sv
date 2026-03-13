// ============================================================================
// MESI 캐시 라인 상태 추적기 테스트벤치
// - 4가지 상태 전이 시나리오를 검증
// - 시뮬레이션 전용 (합성 불가)
// ============================================================================
`timescale 1ns / 1ps

module mesi_tracker_tb;

   logic       clk;
   logic       rst_n;
   logic       pr_rd, pr_wr;
   logic       bus_rd, bus_rdx;
   logic       mem_shared;
   logic [1:0] state;
   logic       do_flush, do_bus_rd, do_bus_rdx, do_invalidate;

   // DUT 인스턴스
   mesi_tracker dut (
      .clk          (clk),
      .rst_n        (rst_n),
      .pr_rd        (pr_rd),
      .pr_wr        (pr_wr),
      .bus_rd       (bus_rd),
      .bus_rdx      (bus_rdx),
      .mem_shared   (mem_shared),
      .state        (state),
      .do_flush     (do_flush),
      .do_bus_rd    (do_bus_rd),
      .do_bus_rdx   (do_bus_rdx),
      .do_invalidate(do_invalidate)
   );

   // 상태 이름 출력용
   function string state_name(input logic [1:0] s);
      case (s)
         2'b00:   return "Modified";
         2'b01:   return "Exclusive";
         2'b10:   return "Shared";
         2'b11:   return "Invalid";
         default: return "Unknown";
      endcase
   endfunction

   // 클록 생성 (10ns 주기)
   initial clk = 0;
   always #5 clk = ~clk;

   // 입력 초기화 태스크
   task clear_inputs();
      pr_rd      = 0;
      pr_wr      = 0;
      bus_rd     = 0;
      bus_rdx    = 0;
      mem_shared = 0;
   endtask

   // 테스트 시퀀스
   initial begin
      $display("========================================");
      $display("MESI 상태 추적기 테스트벤치 시작");
      $display("========================================");

      clear_inputs();
      rst_n = 0;
      #20;
      rst_n = 1;
      #10;

      // ----- 시나리오 1: Invalid → Exclusive (단독 Read) -----
      $display("\n[시나리오 1] Invalid → Exclusive (단독 Read)");
      assert(state == 2'b11) else $error("초기 상태가 Invalid가 아님!");
      pr_rd      = 1;
      mem_shared = 0;  // 다른 캐시에 없음
      @(posedge clk); #1;
      clear_inputs();
      @(posedge clk); #1;
      $display("  상태: %s", state_name(state));
      assert(state == 2'b01) else $error("Exclusive 전이 실패!");

      // ----- 시나리오 2: Exclusive → Modified (로컬 Write) -----
      $display("\n[시나리오 2] Exclusive → Modified (로컬 Write)");
      pr_wr = 1;
      @(posedge clk); #1;
      clear_inputs();
      @(posedge clk); #1;
      $display("  상태: %s", state_name(state));
      assert(state == 2'b00) else $error("Modified 전이 실패!");

      // ----- 시나리오 3: Modified → Shared (다른 코어 Read) -----
      $display("\n[시나리오 3] Modified → Shared (BusRd)");
      bus_rd = 1;
      @(posedge clk); #1;
      clear_inputs();
      @(posedge clk); #1;
      $display("  상태: %s, do_flush: %b", state_name(state), do_flush);
      assert(state == 2'b10) else $error("Shared 전이 실패!");

      // ----- 시나리오 4: Shared → Invalid (다른 코어 Write) -----
      $display("\n[시나리오 4] Shared → Invalid (BusRdX)");
      bus_rdx = 1;
      @(posedge clk); #1;
      clear_inputs();
      @(posedge clk); #1;
      $display("  상태: %s", state_name(state));
      assert(state == 2'b11) else $error("Invalid 전이 실패!");

      // ----- 시나리오 5: Invalid → Shared (공유 Read) -----
      $display("\n[시나리오 5] Invalid → Shared (공유 Read)");
      pr_rd      = 1;
      mem_shared = 1;  // 다른 캐시에도 있음
      @(posedge clk); #1;
      clear_inputs();
      @(posedge clk); #1;
      $display("  상태: %s", state_name(state));
      assert(state == 2'b10) else $error("Shared 전이 실패!");

      // ----- 시나리오 6: Shared → Modified (로컬 Write + BusRdX) -----
      $display("\n[시나리오 6] Shared → Modified (로컬 Write)");
      pr_wr = 1;
      @(posedge clk); #1;
      clear_inputs();
      @(posedge clk); #1;
      $display("  상태: %s, do_bus_rdx: %b", state_name(state), do_bus_rdx);
      assert(state == 2'b00) else $error("Modified 전이 실패!");

      $display("\n========================================");
      $display("모든 시나리오 통과!");
      $display("========================================");
      #20;
      $finish;
   end

   // VCD 파형 저장
   initial begin
      $dumpfile("mesi_tracker_tb.vcd");
      $dumpvars(0, mesi_tracker_tb);
   end

endmodule
