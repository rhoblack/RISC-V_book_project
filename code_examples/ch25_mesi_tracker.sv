// ============================================================================
// MESI 캐시 라인 상태 추적기 (Cache Line State Tracker)
// - 교육용 단순화 모델: 단일 캐시 라인의 MESI 상태 전이를 구현
// - 합성 가능, Basys 3 대상
// ============================================================================
module mesi_tracker (
   input  logic       clk,
   input  logic       rst_n,
   // 프로세서 요청 (로컬 코어)
   input  logic       pr_rd,        // 프로세서 Read 요청
   input  logic       pr_wr,        // 프로세서 Write 요청
   // 버스 스누핑 입력 (다른 코어의 버스 트랜잭션)
   input  logic       bus_rd,       // 다른 코어의 Read 관찰
   input  logic       bus_rdx,      // 다른 코어의 Read-Exclusive (Write 의도)
   // 메모리 응답
   input  logic       mem_shared,   // 메모리 응답 시 다른 캐시에도 복사본 존재 여부
   // 상태 출력
   output logic [1:0] state,        // 현재 MESI 상태
   // 버스 동작 출력
   output logic       do_flush,     // 수정된 데이터를 메모리에 기록
   output logic       do_bus_rd,    // 버스 Read 트랜잭션 발생
   output logic       do_bus_rdx,   // 버스 Read-Exclusive 트랜잭션 발생
   output logic       do_invalidate // 자신의 캐시 라인을 무효화
);

   // MESI 상태 인코딩
   localparam logic [1:0] MODIFIED  = 2'b00;
   localparam logic [1:0] EXCLUSIVE = 2'b01;
   localparam logic [1:0] SHARED    = 2'b10;
   localparam logic [1:0] INVALID   = 2'b11;

   logic [1:0] state_next;

   // 상태 레지스터
   always_ff @(posedge clk or negedge rst_n) begin
      if (!rst_n)
         state <= INVALID;
      else
         state <= state_next;
   end

   // 다음 상태 및 출력 결정 (조합 논리)
   always_comb begin
      // 기본값: 현재 상태 유지, 버스 동작 없음
      state_next    = state;
      do_flush      = 1'b0;
      do_bus_rd     = 1'b0;
      do_bus_rdx    = 1'b0;
      do_invalidate = 1'b0;

      case (state)
         // ---------------------------------------------------------------
         // Modified: 이 캐시만 유일한 최신 복사본 보유 (메모리는 오래됨)
         // ---------------------------------------------------------------
         MODIFIED: begin
            if (bus_rd) begin
               // 다른 코어가 읽기 요청 → 데이터 공급 후 Shared로 전이
               state_next = SHARED;
               do_flush   = 1'b1;  // 메모리에 기록 (Flush)
            end
            else if (bus_rdx) begin
               // 다른 코어가 쓰기 의도 → 데이터 공급 후 Invalid로 전이
               state_next    = INVALID;
               do_flush      = 1'b1;
               do_invalidate = 1'b1;
            end
            // pr_rd, pr_wr → 상태 변화 없음 (이미 Modified)
         end

         // ---------------------------------------------------------------
         // Exclusive: 이 캐시만 보유, 메모리와 동일한 값
         // ---------------------------------------------------------------
         EXCLUSIVE: begin
            if (pr_wr) begin
               // 로컬 쓰기 → 버스 트랜잭션 없이 Modified로 (Silent 전이)
               state_next = MODIFIED;
            end
            else if (bus_rd) begin
               // 다른 코어가 읽기 → Shared로 전이
               state_next = SHARED;
            end
            else if (bus_rdx) begin
               // 다른 코어가 쓰기 의도 → Invalid로 전이
               state_next    = INVALID;
               do_invalidate = 1'b1;
            end
            // pr_rd → 상태 변화 없음
         end

         // ---------------------------------------------------------------
         // Shared: 여러 캐시가 동일한 값 보유
         // ---------------------------------------------------------------
         SHARED: begin
            if (pr_wr) begin
               // 로컬 쓰기 → 다른 복사본 무효화 방송 후 Modified
               state_next = MODIFIED;
               do_bus_rdx = 1'b1;  // BusRdX (Invalidate 방송)
            end
            else if (bus_rdx) begin
               // 다른 코어가 쓰기 의도 → 자신을 Invalid로
               state_next    = INVALID;
               do_invalidate = 1'b1;
            end
            // pr_rd, bus_rd → 상태 변화 없음
         end

         // ---------------------------------------------------------------
         // Invalid: 유효한 데이터 없음
         // ---------------------------------------------------------------
         INVALID: begin
            if (pr_rd) begin
               // 로컬 읽기 미스 → 버스 Read
               do_bus_rd = 1'b1;
               if (mem_shared)
                  state_next = SHARED;     // 다른 캐시에도 있으면 Shared
               else
                  state_next = EXCLUSIVE;  // 단독이면 Exclusive
            end
            else if (pr_wr) begin
               // 로컬 쓰기 미스 → 버스 Read-Exclusive 후 Modified
               state_next = MODIFIED;
               do_bus_rdx = 1'b1;
            end
            // bus_rd, bus_rdx → 이미 Invalid, 변화 없음
         end

         default: state_next = INVALID;
      endcase
   end

endmodule
