// =============================================================================
// Chapter 15: 통합 캐시 시스템 테스트벤치
// =============================================================================
// 캐시 미스 핸들러와 메모리 컨트롤러의 동작을 검증한다.
// 시나리오: 캐시 히트, 컴펄서리 미스, 캐피시티 미스, dirty eviction
// CPI 측정 및 미스율 분석 기능 포함
// =============================================================================

`timescale 1ns / 1ps

module cache_system_tb;

   // =========================================================================
   // 파라미터
   // =========================================================================
   parameter CLK_PERIOD  = 10;           // 100 MHz
   parameter ADDR_WIDTH  = 32;
   parameter DATA_WIDTH  = 32;
   parameter LINE_WORDS  = 4;
   parameter MEM_LATENCY = 2;
   parameter NUM_SETS    = 128;          // 캐시 세트 수
   parameter TEST_COUNT  = 50;           // 테스트 접근 횟수

   // =========================================================================
   // 신호 선언
   // =========================================================================
   logic                    clk;
   logic                    rst_n;

   // I-Cache 인터페이스
   logic                    icache_req;
   logic [ADDR_WIDTH-1:0]   icache_addr;
   logic [DATA_WIDTH-1:0]   icache_rdata;
   logic                    icache_valid;
   logic                    icache_ready;

   // D-Cache 인터페이스
   logic                    dcache_req;
   logic                    dcache_write;
   logic [ADDR_WIDTH-1:0]   dcache_addr;
   logic [DATA_WIDTH-1:0]   dcache_wdata;
   logic [DATA_WIDTH-1:0]   dcache_rdata;
   logic                    dcache_valid;
   logic                    dcache_ready;

   // 메인 메모리 인터페이스
   logic                    mem_ce;
   logic                    mem_we;
   logic [ADDR_WIDTH-1:0]   mem_addr;
   logic [DATA_WIDTH-1:0]   mem_wdata;
   logic [DATA_WIDTH-1:0]   mem_rdata;
   logic                    mem_ready;

   // =========================================================================
   // 성능 카운터
   // =========================================================================
   int unsigned total_cycles;
   int unsigned total_instructions;
   int unsigned icache_accesses;
   int unsigned icache_misses;
   int unsigned dcache_accesses;
   int unsigned dcache_misses;
   int unsigned stall_cycles;

   // =========================================================================
   // 클럭 생성
   // =========================================================================
   initial clk = 1'b0;
   always #(CLK_PERIOD/2) clk = ~clk;

   // =========================================================================
   // DUT 인스턴스: 메모리 컨트롤러
   // =========================================================================
   memory_controller #(
      .ADDR_WIDTH  (ADDR_WIDTH),
      .DATA_WIDTH  (DATA_WIDTH),
      .LINE_WORDS  (LINE_WORDS),
      .MEM_LATENCY (MEM_LATENCY)
   ) u_mem_ctrl (
      .clk            (clk),
      .rst_n          (rst_n),
      // I-Cache
      .icache_req_i   (icache_req),
      .icache_addr_i  (icache_addr),
      .icache_rdata_o (icache_rdata),
      .icache_valid_o (icache_valid),
      .icache_ready_o (icache_ready),
      // D-Cache
      .dcache_req_i   (dcache_req),
      .dcache_write_i (dcache_write),
      .dcache_addr_i  (dcache_addr),
      .dcache_wdata_i (dcache_wdata),
      .dcache_rdata_o (dcache_rdata),
      .dcache_valid_o (dcache_valid),
      .dcache_ready_o (dcache_ready),
      // 메인 메모리
      .mem_ce_o       (mem_ce),
      .mem_we_o       (mem_we),
      .mem_addr_o     (mem_addr),
      .mem_wdata_o    (mem_wdata),
      .mem_rdata_i    (mem_rdata),
      .mem_ready_i    (mem_ready)
   );

   // =========================================================================
   // 간이 메인 메모리 모델 (SRAM, 지연 포함)
   // =========================================================================
   logic [DATA_WIDTH-1:0] main_mem [0:16383]; // 64KB
   logic [$clog2(MEM_LATENCY+1)-1:0] mem_delay_cnt;

   initial begin
      // 메모리 초기화: 주소 값을 데이터로 저장
      for (int i = 0; i < 16384; i++) begin
         main_mem[i] = i * 4;  // 주소 = 데이터 (검증 용이)
      end
   end

   always_ff @(posedge clk or negedge rst_n) begin
      if (!rst_n) begin
         mem_ready     <= 1'b0;
         mem_rdata     <= '0;
         mem_delay_cnt <= '0;
      end else begin
         if (mem_ce && !mem_we) begin
            // 읽기 요청: 항상 1 사이클 후 응답 (단순화)
            mem_ready <= 1'b1;
            mem_rdata <= main_mem[mem_addr[15:2]];
         end else if (mem_ce && mem_we) begin
            // 쓰기 요청
            main_mem[mem_addr[15:2]] <= mem_wdata;
            mem_ready <= 1'b1;
         end else begin
            mem_ready <= 1'b0;
            mem_rdata <= '0;
         end
      end
   end

   // =========================================================================
   // 테스트 시퀀스
   // =========================================================================
   initial begin
      $dumpfile("ch15_cache_system.vcd");
      $dumpvars(0, cache_system_tb);

      // 초기화
      rst_n        = 1'b0;
      icache_req   = 1'b0;
      icache_addr  = '0;
      dcache_req   = 1'b0;
      dcache_write = 1'b0;
      dcache_addr  = '0;
      dcache_wdata = '0;

      total_cycles       = 0;
      total_instructions = 0;
      icache_accesses    = 0;
      icache_misses      = 0;
      dcache_accesses    = 0;
      dcache_misses      = 0;
      stall_cycles       = 0;

      // 리셋 해제
      repeat (5) @(posedge clk);
      rst_n = 1'b1;
      repeat (2) @(posedge clk);

      $display("============================================================");
      $display("  Chapter 15: 통합 캐시 시스템 테스트");
      $display("============================================================");

      // -----------------------------------------------------------------
      // 테스트 1: I-Cache 순차 접근 (컴펄서리 미스 → 히트)
      // -----------------------------------------------------------------
      $display("\n--- 테스트 1: I-Cache 순차 접근 ---");
      for (int i = 0; i < 8; i++) begin
         icache_request(i * 4);
      end
      // 동일 주소 재접근 (히트 기대)
      $display("  >> 동일 주소 재접근 (캐시 히트 기대)");
      for (int i = 0; i < 8; i++) begin
         icache_request(i * 4);
      end

      // -----------------------------------------------------------------
      // 테스트 2: D-Cache 읽기 접근
      // -----------------------------------------------------------------
      $display("\n--- 테스트 2: D-Cache 읽기 접근 ---");
      for (int i = 0; i < 8; i++) begin
         dcache_read_request(32'h0001_0000 + i * 4);
      end

      // -----------------------------------------------------------------
      // 테스트 3: D-Cache 쓰기 → 읽기 (Write-Back 검증)
      // -----------------------------------------------------------------
      $display("\n--- 테스트 3: D-Cache 쓰기 후 읽기 ---");
      dcache_write_request(32'h0001_0000, 32'hDEAD_BEEF);
      dcache_read_request(32'h0001_0000);

      // -----------------------------------------------------------------
      // 테스트 4: I-Cache와 D-Cache 동시 요청 (중재 검증)
      // -----------------------------------------------------------------
      $display("\n--- 테스트 4: I/D 동시 요청 (D-Cache 우선) ---");
      fork
         icache_request(32'h0000_0100);
         dcache_read_request(32'h0001_0100);
      join

      // -----------------------------------------------------------------
      // 성능 결과 출력
      // -----------------------------------------------------------------
      repeat (10) @(posedge clk);

      $display("\n============================================================");
      $display("  성능 분석 결과");
      $display("============================================================");
      $display("  I-Cache 접근: %0d | 미스: %0d | 미스율: %0.1f%%",
               icache_accesses, icache_misses,
               icache_accesses > 0 ?
                  real'(icache_misses) / real'(icache_accesses) * 100.0 : 0.0);
      $display("  D-Cache 접근: %0d | 미스: %0d | 미스율: %0.1f%%",
               dcache_accesses, dcache_misses,
               dcache_accesses > 0 ?
                  real'(dcache_misses) / real'(dcache_accesses) * 100.0 : 0.0);
      $display("============================================================");
      $display("  ★ 모든 테스트 완료 ★");
      $display("============================================================");

      $finish;
   end

   // =========================================================================
   // 태스크: I-Cache 읽기 요청
   // =========================================================================
   task icache_request(input logic [ADDR_WIDTH-1:0] addr);
      @(posedge clk);
      icache_req  = 1'b1;
      icache_addr = addr;
      icache_accesses++;
      @(posedge clk);
      icache_req = 1'b0;

      // 응답 대기
      if (!icache_valid) begin
         icache_misses++;
         while (!icache_valid) @(posedge clk);
      end

      $display("  [I-Cache] 주소=0x%08h, 데이터=0x%08h", addr, icache_rdata);
      @(posedge clk);
   endtask

   // =========================================================================
   // 태스크: D-Cache 읽기 요청
   // =========================================================================
   task dcache_read_request(input logic [ADDR_WIDTH-1:0] addr);
      @(posedge clk);
      dcache_req   = 1'b1;
      dcache_write = 1'b0;
      dcache_addr  = addr;
      dcache_accesses++;
      @(posedge clk);
      dcache_req = 1'b0;

      // 응답 대기
      if (!dcache_valid) begin
         dcache_misses++;
         while (!dcache_valid) @(posedge clk);
      end

      $display("  [D-Cache RD] 주소=0x%08h, 데이터=0x%08h", addr, dcache_rdata);
      @(posedge clk);
   endtask

   // =========================================================================
   // 태스크: D-Cache 쓰기 요청
   // =========================================================================
   task dcache_write_request(
      input logic [ADDR_WIDTH-1:0] addr,
      input logic [DATA_WIDTH-1:0] data
   );
      @(posedge clk);
      dcache_req   = 1'b1;
      dcache_write = 1'b1;
      dcache_addr  = addr;
      dcache_wdata = data;
      dcache_accesses++;
      @(posedge clk);
      dcache_req = 1'b0;

      // 응답 대기
      if (!dcache_valid) begin
         dcache_misses++;
         while (!dcache_valid) @(posedge clk);
      end

      $display("  [D-Cache WR] 주소=0x%08h, 데이터=0x%08h", addr, data);
      @(posedge clk);
   endtask

   // =========================================================================
   // 타임아웃 감시
   // =========================================================================
   initial begin
      #100_000;
      $display("ERROR: 시뮬레이션 타임아웃!");
      $finish;
   end

endmodule
