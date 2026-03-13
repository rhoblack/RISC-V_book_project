// ============================================================================
// Chapter 14 — D-Cache 테스트벤치
// RISC-V 프로세서 설계 완전정복
// ============================================================================
// 설명: 2-Way Set-Associative Write-Back D-Cache 검증
//       시나리오: 히트, Clean 미스, Dirty 미스(Eviction), LRU 교체
// 시뮬레이션: VCS/Vivado Simulator
// ============================================================================

`timescale 1ns / 1ps

module dcache_tb;

   // -----------------------------------------------------------------------
   // 파라미터
   // -----------------------------------------------------------------------
   localparam ADDR_WIDTH  = 32;
   localparam NUM_SETS    = 64;
   localparam BLOCK_WORDS = 8;
   localparam CLK_PERIOD  = 10; // 100 MHz

   // 메모리 지연 시뮬레이션용 파라미터
   localparam MEM_LATENCY = 2;  // 메모리 응답 지연 (사이클)

   // -----------------------------------------------------------------------
   // 신호 선언
   // -----------------------------------------------------------------------
   logic                    clk;
   logic                    rst_n;

   // CPU 인터페이스
   logic                    cpu_req;
   logic                    cpu_write;
   logic [ADDR_WIDTH-1:0]   cpu_addr;
   logic [31:0]             cpu_wdata;
   logic [3:0]              cpu_byte_en;
   logic [31:0]             cpu_rdata;
   logic                    dcache_stall;

   // 메모리 인터페이스
   logic                    mem_req;
   logic                    mem_write;
   logic [ADDR_WIDTH-1:0]   mem_addr;
   logic [31:0]             mem_wdata;
   logic [31:0]             mem_rdata;
   logic                    mem_ready;

   // -----------------------------------------------------------------------
   // DUT 인스턴스
   // -----------------------------------------------------------------------
   dcache_2way_wb #(
      .ADDR_WIDTH  (ADDR_WIDTH),
      .NUM_SETS    (NUM_SETS),
      .BLOCK_WORDS (BLOCK_WORDS)
   ) u_dcache (
      .clk            (clk),
      .rst_n          (rst_n),
      .cpu_req_i      (cpu_req),
      .cpu_write_i    (cpu_write),
      .cpu_addr_i     (cpu_addr),
      .cpu_wdata_i    (cpu_wdata),
      .cpu_byte_en_i  (cpu_byte_en),
      .cpu_rdata_o    (cpu_rdata),
      .dcache_stall_o (dcache_stall),
      .mem_req_o      (mem_req),
      .mem_write_o    (mem_write),
      .mem_addr_o     (mem_addr),
      .mem_wdata_o    (mem_wdata),
      .mem_rdata_i    (mem_rdata),
      .mem_ready_i    (mem_ready)
   );

   // -----------------------------------------------------------------------
   // 클럭 생성
   // -----------------------------------------------------------------------
   initial clk = 1'b0;
   always #(CLK_PERIOD/2) clk = ~clk;

   // -----------------------------------------------------------------------
   // 간이 메모리 모델 (지연 포함)
   // -----------------------------------------------------------------------
   logic [31:0] main_memory [0:65535]; // 256KB 메인 메모리
   int          mem_delay_cnt;

   initial begin
      for (int i = 0; i < 65536; i++)
         main_memory[i] = i * 4; // 초기값: 주소 기반 패턴
   end

   always_ff @(posedge clk or negedge rst_n) begin
      if (!rst_n) begin
         mem_ready     <= 1'b0;
         mem_rdata     <= '0;
         mem_delay_cnt <= 0;
      end else begin
         if (mem_req) begin
            if (mem_delay_cnt < MEM_LATENCY - 1) begin
               mem_delay_cnt <= mem_delay_cnt + 1;
               mem_ready     <= 1'b0;
            end else begin
               mem_ready     <= 1'b1;
               mem_delay_cnt <= 0;
               if (mem_write)
                  main_memory[mem_addr[17:2]] <= mem_wdata;
               else
                  mem_rdata <= main_memory[mem_addr[17:2]];
            end
         end else begin
            mem_ready     <= 1'b0;
            mem_delay_cnt <= 0;
         end
      end
   end

   // -----------------------------------------------------------------------
   // 테스트 유틸리티 태스크
   // -----------------------------------------------------------------------
   int test_pass_cnt = 0;
   int test_fail_cnt = 0;

   task automatic cache_read(
      input  logic [31:0] addr,
      output logic [31:0] rdata
   );
      @(posedge clk);
      cpu_req     <= 1'b1;
      cpu_write   <= 1'b0;
      cpu_addr    <= addr;
      cpu_byte_en <= 4'hF;
      @(posedge clk);
      cpu_req <= 1'b0;
      // 스톨 대기
      while (dcache_stall) @(posedge clk);
      rdata = cpu_rdata;
   endtask

   task automatic cache_write(
      input logic [31:0] addr,
      input logic [31:0] wdata,
      input logic [3:0]  byte_en
   );
      @(posedge clk);
      cpu_req     <= 1'b1;
      cpu_write   <= 1'b1;
      cpu_addr    <= addr;
      cpu_wdata   <= wdata;
      cpu_byte_en <= byte_en;
      @(posedge clk);
      cpu_req <= 1'b0;
      // 스톨 대기
      while (dcache_stall) @(posedge clk);
   endtask

   task automatic check_result(
      input string test_name,
      input logic [31:0] actual,
      input logic [31:0] expected
   );
      if (actual === expected) begin
         $display("[PASS] %s: got 0x%08h", test_name, actual);
         test_pass_cnt++;
      end else begin
         $display("[FAIL] %s: expected 0x%08h, got 0x%08h",
                  test_name, expected, actual);
         test_fail_cnt++;
      end
   endtask

   // -----------------------------------------------------------------------
   // 테스트 시나리오
   // -----------------------------------------------------------------------
   logic [31:0] read_data;

   initial begin
      $display("============================================");
      $display(" D-Cache 2-Way Write-Back 테스트 시작");
      $display("============================================");

      // 초기화
      rst_n       = 1'b0;
      cpu_req     = 1'b0;
      cpu_write   = 1'b0;
      cpu_addr    = '0;
      cpu_wdata   = '0;
      cpu_byte_en = '0;

      repeat (5) @(posedge clk);
      rst_n = 1'b1;
      repeat (3) @(posedge clk);

      // ------------------------------------------------------------------
      // 시나리오 1: Cold Miss (첫 접근 - 캐시 비어있음)
      // ------------------------------------------------------------------
      $display("\n--- 시나리오 1: Cold Miss ---");
      cache_read(32'h0000_0100, read_data);
      check_result("Cold Miss Read @0x100", read_data,
                   main_memory[32'h100 >> 2]);

      // ------------------------------------------------------------------
      // 시나리오 2: Cache Hit (같은 주소 재접근)
      // ------------------------------------------------------------------
      $display("\n--- 시나리오 2: Cache Hit ---");
      cache_read(32'h0000_0100, read_data);
      check_result("Cache Hit Read @0x100", read_data,
                   main_memory[32'h100 >> 2]);

      // ------------------------------------------------------------------
      // 시나리오 3: Write Hit + Read Back
      // ------------------------------------------------------------------
      $display("\n--- 시나리오 3: Write Hit ---");
      cache_write(32'h0000_0100, 32'hDEAD_BEEF, 4'hF);
      cache_read(32'h0000_0100, read_data);
      check_result("Write Hit + Read Back @0x100",
                   read_data, 32'hDEAD_BEEF);

      // ------------------------------------------------------------------
      // 시나리오 4: 같은 Set, 다른 Tag (Way 1에 할당)
      // ------------------------------------------------------------------
      $display("\n--- 시나리오 4: Same Set, Way 1 Allocation ---");
      // Index가 같은 다른 태그 주소 접근
      cache_read(32'h0010_0100, read_data);
      check_result("Way 1 Alloc @0x100100", read_data,
                   main_memory[32'h100100 >> 2]);

      // ------------------------------------------------------------------
      // 시나리오 5: Dirty Eviction (3번째 충돌 → LRU Way 교체)
      // ------------------------------------------------------------------
      $display("\n--- 시나리오 5: Dirty Eviction ---");
      // 같은 Set의 3번째 태그 → LRU Way(Way0, Dirty)를 Evict
      cache_read(32'h0020_0100, read_data);
      check_result("Dirty Eviction + Refill @0x200100", read_data,
                   main_memory[32'h200100 >> 2]);

      // Eviction 후 메인 메모리에 Write-Back 되었는지 확인
      // (0x100 주소의 데이터가 0xDEAD_BEEF로 Write-Back 되었어야 함)
      check_result("Write-Back 검증 @0x100",
                   main_memory[32'h100 >> 2], 32'hDEAD_BEEF);

      // ------------------------------------------------------------------
      // 시나리오 6: 바이트 단위 쓰기 (SB 명령어 시뮬레이션)
      // ------------------------------------------------------------------
      $display("\n--- 시나리오 6: Byte Write ---");
      cache_write(32'h0010_0100, 32'h0000_00AB, 4'b0001); // 최하위 바이트만
      cache_read(32'h0010_0100, read_data);
      // 원본의 상위 3바이트 유지 + 최하위 바이트 0xAB
      $display("  Byte write result: 0x%08h", read_data);

      // ------------------------------------------------------------------
      // 결과 요약
      // ------------------------------------------------------------------
      repeat (5) @(posedge clk);
      $display("\n============================================");
      $display(" 테스트 결과: %0d PASS, %0d FAIL",
               test_pass_cnt, test_fail_cnt);
      $display("============================================");

      if (test_fail_cnt == 0)
         $display(" 모든 테스트를 통과하였습니다!");
      else
         $display(" %0d개의 테스트가 실패하였습니다.", test_fail_cnt);

      $finish;
   end

   // -----------------------------------------------------------------------
   // 파형 덤프 (VCS/Vivado 호환)
   // -----------------------------------------------------------------------
   initial begin
      $dumpfile("dcache_tb.vcd");
      $dumpvars(0, dcache_tb);
   end

   // 타임아웃 보호
   initial begin
      #1_000_000;
      $display("[TIMEOUT] 시뮬레이션 시간 초과!");
      $finish;
   end

endmodule
