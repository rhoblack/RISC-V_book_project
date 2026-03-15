// ============================================================
// Ch23: 예약 스테이션 Behavioral 시뮬레이션 모델
// Tomasulo 알고리즘 교육용 — 합성 불가 (Simulation Only)
//
// 이 모듈은 개념 이해를 위한 behavioral 모델입니다.
// 실제 합성 가능한 OOO 프로세서를 만드는 것이 아니라,
// 예약 스테이션과 CDB 브로드캐스트의 동작을 관찰하는 것이 목적입니다.
// ============================================================
module reservation_station_sim #(
   parameter RS_ENTRIES = 4,   // 예약 스테이션 엔트리 수
   parameter TAG_BITS   = 3    // 태그 비트 수 (생산자 식별)
)(
   input  logic              clk,
   input  logic              rst_n,
   // ── 이슈 인터페이스 ──
   input  logic              issue_valid,     // 명령어 이슈 요청
   input  logic [2:0]        issue_op,        // 연산 종류
   input  logic [31:0]       issue_val1,      // 소스 1 값 (준비된 경우)
   input  logic [31:0]       issue_val2,      // 소스 2 값 (준비된 경우)
   input  logic [TAG_BITS-1:0] issue_tag1,    // 소스 1 태그 (대기 중인 경우)
   input  logic [TAG_BITS-1:0] issue_tag2,    // 소스 2 태그
   input  logic              issue_rdy1,      // 소스 1 준비 여부
   input  logic              issue_rdy2,      // 소스 2 준비 여부
   input  logic [TAG_BITS-1:0] issue_dest_tag,// 이 명령어의 결과 태그
   output logic              issue_accepted,  // 이슈 수락됨
   // ── CDB 입력 (브로드캐스트 수신) ──
   input  logic              cdb_valid,       // CDB에 결과가 있는가
   input  logic [TAG_BITS-1:0] cdb_tag,       // CDB 태그
   input  logic [31:0]       cdb_value,       // CDB 값
   // ── 실행 출력 ──
   output logic              exec_valid,      // 실행 시작
   output logic [2:0]        exec_op,         // 연산
   output logic [31:0]       exec_val1,       // 오퍼랜드 1
   output logic [31:0]       exec_val2,       // 오퍼랜드 2
   output logic [TAG_BITS-1:0] exec_dest_tag  // 결과 태그
);

   // ── 예약 스테이션 엔트리 구조 ──
   typedef struct packed {
      logic              busy;
      logic [2:0]        op;
      logic [31:0]       val1;
      logic [31:0]       val2;
      logic [TAG_BITS-1:0] tag1;
      logic [TAG_BITS-1:0] tag2;
      logic              rdy1;
      logic              rdy2;
      logic [TAG_BITS-1:0] dest_tag;
   } rs_entry_t;

   rs_entry_t rs [0:RS_ENTRIES-1];

   // ── 빈 엔트리 검색 ──
   logic [$clog2(RS_ENTRIES)-1:0] free_idx;
   logic has_free;

   always_comb begin
      has_free = 1'b0;
      free_idx = '0;
      for (int j = 0; j < RS_ENTRIES; j++) begin
         if (!rs[j].busy && !has_free) begin
            has_free = 1'b1;
            free_idx = j[$clog2(RS_ENTRIES)-1:0];
         end
      end
   end

   assign issue_accepted = issue_valid && has_free;

   // ── 실행 가능한 엔트리 검색 (오퍼랜드 모두 준비됨) ──
   logic [$clog2(RS_ENTRIES)-1:0] exec_idx;
   logic has_ready;

   always_comb begin
      has_ready = 1'b0;
      exec_idx = '0;
      for (int j = 0; j < RS_ENTRIES; j++) begin
         if (rs[j].busy && rs[j].rdy1 && rs[j].rdy2 && !has_ready) begin
            has_ready = 1'b1;
            exec_idx = j[$clog2(RS_ENTRIES)-1:0];
         end
      end
   end

   assign exec_valid    = has_ready;
   assign exec_op       = rs[exec_idx].op;
   assign exec_val1     = rs[exec_idx].val1;
   assign exec_val2     = rs[exec_idx].val2;
   assign exec_dest_tag = rs[exec_idx].dest_tag;

   // ── 순차 로직: 이슈, CDB 스누핑, 실행 완료 ──
   always_ff @(posedge clk or negedge rst_n) begin
      if (!rst_n) begin
         for (int j = 0; j < RS_ENTRIES; j++) begin
            rs[j].busy <= 1'b0;
         end
      end else begin
         // 1. CDB 브로드캐스트 수신 — 대기 중인 오퍼랜드 갱신
         if (cdb_valid) begin
            for (int j = 0; j < RS_ENTRIES; j++) begin
               if (rs[j].busy) begin
                  if (!rs[j].rdy1 && rs[j].tag1 == cdb_tag) begin
                     rs[j].val1 <= cdb_value;
                     rs[j].rdy1 <= 1'b1;
                     // synthesis translate_off
                     $display("[RS %0d] 소스1 수신: tag=%0d, val=0x%08h", j, cdb_tag, cdb_value);
                     // synthesis translate_on
                  end
                  if (!rs[j].rdy2 && rs[j].tag2 == cdb_tag) begin
                     rs[j].val2 <= cdb_value;
                     rs[j].rdy2 <= 1'b1;
                     // synthesis translate_off
                     $display("[RS %0d] 소스2 수신: tag=%0d, val=0x%08h", j, cdb_tag, cdb_value);
                     // synthesis translate_on
                  end
               end
            end
         end

         // 2. 새 명령어 이슈
         if (issue_accepted) begin
            rs[free_idx].busy     <= 1'b1;
            rs[free_idx].op       <= issue_op;
            rs[free_idx].val1     <= issue_val1;
            rs[free_idx].val2     <= issue_val2;
            rs[free_idx].tag1     <= issue_tag1;
            rs[free_idx].tag2     <= issue_tag2;
            rs[free_idx].rdy1     <= issue_rdy1;
            rs[free_idx].rdy2     <= issue_rdy2;
            rs[free_idx].dest_tag <= issue_dest_tag;
            // synthesis translate_off
            $display("[RS %0d] 이슈: op=%0d, rdy1=%b, rdy2=%b, dest_tag=%0d",
                     free_idx, issue_op, issue_rdy1, issue_rdy2, issue_dest_tag);
            // synthesis translate_on
         end

         // 3. 실행 시작 → 엔트리 해제
         if (has_ready) begin
            rs[exec_idx].busy <= 1'b0;
            // synthesis translate_off
            $display("[RS %0d] 실행 시작: op=%0d, val1=0x%08h, val2=0x%08h",
                     exec_idx, rs[exec_idx].op, rs[exec_idx].val1, rs[exec_idx].val2);
            // synthesis translate_on
         end
      end
   end

endmodule
