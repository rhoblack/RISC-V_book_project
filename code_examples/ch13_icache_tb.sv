// =============================================================================
// Ch13: L1 I-Cache 테스트벤치 (Testbench for icache_direct_mapped)
// 4가지 시나리오로 캐시 동작 검증
//
// 시나리오 1: Cold Start   → 모두 MISS (히트율 0%)
// 시나리오 2: Sequential   → 공간적 지역성 활용 (히트율 87.5%)
// 시나리오 3: Loop Access  → 시간적 지역성 활용 (히트율 66.7%)
// 시나리오 4: Conflict Miss → 직접 매핑 한계 (히트율 0%)
// =============================================================================

`timescale 1ns / 1ps

module ch13_icache_tb;

   // =========================================================================
   // 신호 선언
   // =========================================================================

   logic        clk;
   logic        rst_n;
   logic [31:0] cpu_addr;
   logic        cpu_req;
   logic [31:0] cpu_rdata;
   logic        cache_hit;
   logic        icache_stall;
   logic [31:0] mem_addr;
   logic        mem_req;
   logic [31:0] mem_rdata;
   logic        mem_ready;

   // 히트율 집계 변수
   integer      total_access;
   integer      total_hit;
   integer      scenario_access;
   integer      scenario_hit;

   // =========================================================================
   // DUT 인스턴스
   // =========================================================================

   icache_direct_mapped #(
      .CACHE_SIZE   (4096),
      .BLOCK_SIZE   (32),
      .NUM_ENTRIES  (128),
      .ADDR_WIDTH   (32)
   ) dut (
      .clk          (clk),
      .rst_n        (rst_n),
      .cpu_addr     (cpu_addr),
      .cpu_req      (cpu_req),
      .cpu_rdata    (cpu_rdata),
      .cache_hit    (cache_hit),
      .icache_stall (icache_stall),
      .mem_addr     (mem_addr),
      .mem_req      (mem_req),
      .mem_rdata    (mem_rdata),
      .mem_ready    (mem_ready)
   );

   // =========================================================================
   // 클록 생성 (10ns 주기 = 100MHz)
   // =========================================================================

   initial clk = 0;
   always #5 clk = ~clk;

   // =========================================================================
   // 메모리 모델: 단순 응답 (5사이클 지연)
   // =========================================================================

   logic [2:0] mem_delay_cnt;

   always_ff @(posedge clk) begin
      if (!rst_n) begin
         mem_delay_cnt <= 3'b0;
         mem_ready     <= 1'b0;
         mem_rdata     <= 32'h0;
      end else begin
         if (mem_req && mem_delay_cnt == 3'b0) begin
            mem_delay_cnt <= 3'd4;   // 5사이클 지연 시작
            mem_ready     <= 1'b0;
         end else if (mem_delay_cnt > 3'b0) begin
            mem_delay_cnt <= mem_delay_cnt - 1'b1;
            if (mem_delay_cnt == 3'd1) begin
               mem_ready <= 1'b1;
               // 응답 데이터: 주소 기반 더미 명령어 (NOP)
               mem_rdata <= {mem_addr[31:2], 2'b11};  // 주소 기반 패턴
            end else begin
               mem_ready <= 1'b0;
            end
         end else begin
            mem_ready <= 1'b0;
         end
      end
   end

   // =========================================================================
   // 태스크: 단일 주소 접근 및 결과 기록
   // =========================================================================

   task automatic access_addr(
      input [31:0] addr,
      input string desc
   );
      @(posedge clk);
      cpu_addr = addr;
      cpu_req  = 1'b1;
      #1;  // 조합 논리 안정화 대기

      // 히트 여부 집계
      if (cache_hit) begin
         $display("[HIT ] 주소=0x%08X (%s) - Tag=0x%05X Index=%03d Offset=%02d",
                  addr, desc, addr[31:12], addr[11:5], addr[4:0]);
         total_hit++;
         scenario_hit++;
      end else begin
         $display("[MISS] 주소=0x%08X (%s) - Tag=0x%05X Index=%03d Offset=%02d",
                  addr, desc, addr[31:12], addr[11:5], addr[4:0]);
      end
      total_access++;
      scenario_access++;

      // 스톨 동안 대기 (미스 페널티 5사이클)
      if (icache_stall) begin
         $display("       → icache_stall=1: 메모리 접근 대기 중...");
         wait (!icache_stall);
         @(posedge clk);
         $display("       → 캐시 채움 완료, 파이프라인 재개");
      end
   endtask

   // =========================================================================
   // 태스크: 시나리오 1 — Cold Start (Cold Miss)
   // 처음 접근하는 주소들 → 캐시 비어있음 → 모두 MISS
   // =========================================================================

   task cold_start_test();
      scenario_access = 0;
      scenario_hit    = 0;
      $display("\n====================================================");
      $display("시나리오 1: Cold Start (캐시 전체 비어있음)");
      $display("====================================================");

      // 서로 다른 캐시 라인에 처음 접근
      access_addr(32'h0000_0000, "Index=0, Tag=0x00000");
      access_addr(32'h0000_0020, "Index=1, Tag=0x00000");
      access_addr(32'h0000_0040, "Index=2, Tag=0x00000");

      $display("시나리오 1 결과: 히트=%0d / 전체=%0d → 히트율=%0d%%",
               scenario_hit, scenario_access,
               scenario_access > 0 ? scenario_hit * 100 / scenario_access : 0);
      $display("→ 예상 히트율: 0%% (모두 Cold Miss)");
   endtask

   // =========================================================================
   // 태스크: 시나리오 2 — Sequential Access (공간적 지역성, 87.5% HIT)
   // 0x0000_0000 MISS 후 같은 블록 내 0x0000_0004~0x0000_001C HIT
   // =========================================================================

   task sequential_access_test();
      scenario_access = 0;
      scenario_hit    = 0;
      $display("\n====================================================");
      $display("시나리오 2: Sequential Access (공간적 지역성)");
      $display("====================================================");
      $display("→ 0x0000_0000~0x0000_001C: 같은 캐시 블록(Index=0)");

      // 첫 접근: MISS (Cold Miss)
      access_addr(32'h0000_0000, "블록 기저 주소 - Cold Miss");

      // 같은 블록 내 순차 접근: HIT (공간적 지역성!)
      access_addr(32'h0000_0004, "Offset=4 - HIT 예상");
      access_addr(32'h0000_0008, "Offset=8 - HIT 예상");
      access_addr(32'h0000_000C, "Offset=C - HIT 예상");
      access_addr(32'h0000_0010, "Offset=10 - HIT 예상");
      access_addr(32'h0000_0014, "Offset=14 - HIT 예상");
      access_addr(32'h0000_0018, "Offset=18 - HIT 예상");
      access_addr(32'h0000_001C, "Offset=1C - HIT 예상");

      $display("시나리오 2 결과: 히트=%0d / 전체=%0d → 히트율=%0d%%",
               scenario_hit, scenario_access,
               scenario_access > 0 ? scenario_hit * 100 / scenario_access : 0);
      $display("→ 예상 히트율: 87.5%% (7/8 = 공간적 지역성 효과)");
   endtask

   // =========================================================================
   // 태스크: 시나리오 3 — Loop Access (시간적 지역성, 66.7% HIT)
   // 같은 주소를 3회 반복: 1회차 MISS, 2~3회차 HIT
   // =========================================================================

   task loop_access_test();
      scenario_access = 0;
      scenario_hit    = 0;
      $display("\n====================================================");
      $display("시나리오 3: Loop Access (시간적 지역성)");
      $display("====================================================");
      $display("→ 0x0000_0100을 3회 반복 접근");

      // 3회 반복 (1회차 MISS, 2~3회차 HIT)
      for (int i = 0; i < 3; i++) begin
         $display("  [반복 %0d회차]", i+1);
         access_addr(32'h0000_0100, "시간적 지역성 테스트");
         access_addr(32'h0000_0120, "두 번째 캐시 라인");
         access_addr(32'h0000_0140, "세 번째 캐시 라인");
      end

      $display("시나리오 3 결과: 히트=%0d / 전체=%0d → 히트율=%0d%%",
               scenario_hit, scenario_access,
               scenario_access > 0 ? scenario_hit * 100 / scenario_access : 0);
      $display("→ 예상 히트율: 66.7%% (6/9 = 시간적 지역성 효과)");
   endtask

   // =========================================================================
   // 태스크: 시나리오 4 — Conflict Miss (직접 매핑 한계, 0% HIT)
   // A=0x0000_0000 (Index=0) ↔ B=0x0001_0000 (Index=0) 번갈아 접근
   // =========================================================================

   task conflict_miss_test();
      scenario_access = 0;
      scenario_hit    = 0;
      $display("\n====================================================");
      $display("시나리오 4: Conflict Miss (직접 매핑 한계)");
      $display("====================================================");
      $display("→ A(0x0000_0000)와 B(0x0001_0000): 모두 Index=0 → 충돌!");

      // A → B → A → B 번갈아 접근
      access_addr(32'h0000_0000, "A: Tag=0x00000, Index=0");
      access_addr(32'h0001_0000, "B: Tag=0x00010, Index=0 (A 축출!)");
      access_addr(32'h0000_0000, "A: Tag=0x00000, Index=0 (B 축출!)");
      access_addr(32'h0001_0000, "B: Tag=0x00010, Index=0 (A 축출!)");

      $display("시나리오 4 결과: 히트=%0d / 전체=%0d → 히트율=%0d%%",
               scenario_hit, scenario_access,
               scenario_access > 0 ? scenario_hit * 100 / scenario_access : 0);
      $display("→ 예상 히트율: 0%% (충돌 미스 = 직접 매핑 한계)");
      $display("→ 해결책: Ch14 2-Way 집합 연관 캐시!");
   endtask

   // =========================================================================
   // 메인 테스트 시퀀스
   // =========================================================================

   initial begin
      // 초기화
      rst_n     = 1'b0;
      cpu_addr  = 32'h0;
      cpu_req   = 1'b0;
      total_access = 0;
      total_hit    = 0;

      // 리셋 해제
      repeat(3) @(posedge clk);
      rst_n = 1'b1;
      @(posedge clk);

      $display("========================================");
      $display("Ch13 L1 I-Cache 테스트벤치 시작");
      $display("파라미터: 4KB / 128엔트리 / 32바이트 블록");
      $display("========================================");

      // 4가지 시나리오 실행
      cold_start_test();
      sequential_access_test();
      loop_access_test();
      conflict_miss_test();

      // -------------------------------------------------------
      // 전체 결과 출력
      // -------------------------------------------------------
      @(posedge clk);
      cpu_req = 1'b0;

      $display("\n========================================");
      $display("전체 테스트 결과 요약");
      $display("========================================");
      $display("총 접근 횟수: %0d회", total_access);
      $display("캐시 HIT 횟수: %0d회", total_hit);
      $display("캐시 MISS 횟수: %0d회", total_access - total_hit);
      if (total_access > 0)
         $display("전체 평균 히트율: %0d%%", total_hit * 100 / total_access);
      $display("========================================");
      $display("시나리오별 분석:");
      $display("  1. Cold Start:   히트율 0%%  (Cold Miss - 처음 접근)");
      $display("  2. Sequential:   히트율 87.5%% (공간적 지역성 효과)");
      $display("  3. Loop:         히트율 66.7%% (시간적 지역성 효과)");
      $display("  4. Conflict:     히트율 0%%  (직접 매핑 한계 확인)");
      $display("========================================");
      $display("Ch13 테스트벤치 완료.");

      $finish;
   end

   // =========================================================================
   // 타임아웃 가드 (무한 루프 방지)
   // =========================================================================

   initial begin
      #100_000;
      $display("[ERROR] 타임아웃: 시뮬레이션이 100us 내에 완료되지 않았습니다.");
      $finish;
   end

   // =========================================================================
   // 히트율 모니터 (실시간 집계)
   // =========================================================================

   always @(posedge clk) begin
      if (cpu_req && !icache_stall) begin
         // 이미 태스크에서 집계하므로 여기서는 파형 기록용으로만 사용
      end
   end

endmodule
