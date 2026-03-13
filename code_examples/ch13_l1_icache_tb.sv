// =============================================================================
// L1 명령어 캐시 테스트벤치
// 히트/미스 시나리오 검증, 미스 페널티 측정
// =============================================================================

`timescale 1ns / 1ps

module l1_icache_tb;

   // =========================================================================
   // 파라미터 및 신호 선언
   // =========================================================================
   parameter ADDR_WIDTH  = 32;
   parameter DATA_WIDTH  = 32;
   parameter CLK_PERIOD  = 10;   // 10ns = 100MHz

   logic                    clk;
   logic                    rst_n;
   logic [ADDR_WIDTH-1:0]   proc_addr;
   logic                    proc_req;
   logic [DATA_WIDTH-1:0]   proc_rdata;
   logic                    icache_stall;
   logic [ADDR_WIDTH-1:0]   mem_addr;
   logic                    mem_req;
   logic [DATA_WIDTH-1:0]   mem_rdata;
   logic                    mem_ready;

   // 성능 카운터
   int total_accesses;
   int hit_count;
   int miss_count;
   int total_stall_cycles;

   // =========================================================================
   // DUT 인스턴스
   // =========================================================================
   l1_icache #(
      .ADDR_WIDTH  (ADDR_WIDTH),
      .DATA_WIDTH  (DATA_WIDTH),
      .CACHE_LINES (128),
      .BLOCK_WORDS (8)
   ) dut (
      .clk          (clk),
      .rst_n        (rst_n),
      .proc_addr    (proc_addr),
      .proc_req     (proc_req),
      .proc_rdata   (proc_rdata),
      .icache_stall (icache_stall),
      .mem_addr     (mem_addr),
      .mem_req      (mem_req),
      .mem_rdata    (mem_rdata),
      .mem_ready    (mem_ready)
   );

   // =========================================================================
   // 클럭 생성
   // =========================================================================
   initial clk = 1'b0;
   always #(CLK_PERIOD/2) clk = ~clk;

   // =========================================================================
   // 간이 메모리 모델 (8 사이클 지연)
   // 주소를 기반으로 고유한 명령어 패턴 생성
   // =========================================================================
   parameter MEM_LATENCY = 8;  // 메모리 응답 지연 (사이클)
   int mem_delay_cnt;

   always_ff @(posedge clk or negedge rst_n) begin
      if (!rst_n) begin
         mem_ready     <= 1'b0;
         mem_rdata     <= '0;
         mem_delay_cnt <= 0;
      end else begin
         if (mem_req && mem_delay_cnt == 0) begin
            mem_delay_cnt <= MEM_LATENCY;
         end

         if (mem_delay_cnt > 1) begin
            mem_delay_cnt <= mem_delay_cnt - 1;
            mem_ready     <= 1'b0;
         end else if (mem_delay_cnt == 1) begin
            mem_delay_cnt <= 0;
            mem_ready     <= 1'b1;
            // 주소 기반 테스트 데이터 생성
            mem_rdata     <= {16'hCAFE, mem_addr[15:0]};
         end else begin
            mem_ready <= 1'b0;
         end
      end
   end

   // =========================================================================
   // 스톨 사이클 카운터
   // =========================================================================
   always_ff @(posedge clk or negedge rst_n) begin
      if (!rst_n)
         total_stall_cycles <= 0;
      else if (icache_stall)
         total_stall_cycles <= total_stall_cycles + 1;
   end

   // =========================================================================
   // 캐시 접근 태스크
   // =========================================================================
   task automatic cache_read(input logic [31:0] addr);
      @(posedge clk);
      proc_addr <= addr;
      proc_req  <= 1'b1;
      total_accesses++;

      @(posedge clk);
      if (!icache_stall) begin
         hit_count++;
         $display("[%0t] HIT  addr=0x%08h data=0x%08h", $time, addr, proc_rdata);
      end else begin
         miss_count++;
         $display("[%0t] MISS addr=0x%08h — 블록 채움 시작", $time, addr);
         // 스톨이 해제될 때까지 대기
         while (icache_stall) @(posedge clk);
         $display("[%0t] FILL DONE addr=0x%08h data=0x%08h", $time, addr, proc_rdata);
      end

      proc_req <= 1'b0;
   endtask

   // =========================================================================
   // 테스트 시나리오
   // =========================================================================
   initial begin
      // 초기화
      rst_n     = 1'b0;
      proc_addr = '0;
      proc_req  = 1'b0;
      total_accesses = 0;
      hit_count      = 0;
      miss_count     = 0;

      repeat (5) @(posedge clk);
      rst_n = 1'b1;
      repeat (2) @(posedge clk);

      $display("=== 테스트 1: 순차 접근 (공간적 지역성 검증) ===");
      // 같은 캐시 블록 내 연속 주소 접근
      // 블록 크기 = 32바이트 → 0x00~0x1F는 같은 블록
      cache_read(32'h0000_0000);  // 미스: 첫 접근
      cache_read(32'h0000_0004);  // 히트: 같은 블록
      cache_read(32'h0000_0008);  // 히트: 같은 블록
      cache_read(32'h0000_000C);  // 히트: 같은 블록
      cache_read(32'h0000_0010);  // 히트: 같은 블록

      $display("");
      $display("=== 테스트 2: 시간적 지역성 검증 ===");
      // 같은 주소 반복 접근
      cache_read(32'h0000_0000);  // 히트: 이미 캐시에 있음
      cache_read(32'h0000_0004);  // 히트
      cache_read(32'h0000_0000);  // 히트

      $display("");
      $display("=== 테스트 3: 새로운 블록 미스 ===");
      // 다른 캐시 라인에 매핑되는 주소
      cache_read(32'h0000_0020);  // 미스: 새로운 블록 (인덱스 1)
      cache_read(32'h0000_0024);  // 히트: 같은 블록

      $display("");
      $display("=== 테스트 4: 충돌 미스 (Conflict Miss) ===");
      // 같은 인덱스, 다른 태그
      cache_read(32'h0001_0000);  // 미스: 인덱스 0, 태그 다름 → 충돌
      cache_read(32'h0000_0000);  // 미스: 원래 블록이 퇴출됨 → 재미스

      $display("");
      $display("============================================");
      $display("성능 통계:");
      $display("  총 접근 횟수   : %0d", total_accesses);
      $display("  히트 횟수      : %0d", hit_count);
      $display("  미스 횟수      : %0d", miss_count);
      $display("  히트율         : %0.1f%%",
               real'(hit_count) / real'(total_accesses) * 100.0);
      $display("  총 스톨 사이클 : %0d", total_stall_cycles);
      $display("============================================");

      repeat (5) @(posedge clk);
      $finish;
   end

   // 타임아웃 보호
   initial begin
      #100000;
      $display("ERROR: 시뮬레이션 타임아웃");
      $finish;
   end

endmodule
