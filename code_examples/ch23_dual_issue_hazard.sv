// =============================================================================
// 2-이슈 인오더 파이프라인 — 이슈 간 의존성 검사 유닛
// Chapter 23 — 성능 최적화 기법 (23.4절 미니 설계 과제)
// =============================================================================
// Way A(슬롯 0)와 Way B(슬롯 1)의 명령어 간 데이터 의존성을 검사하여
// 동시 발행 가능 여부를 판단하는 유닛
// =============================================================================

module dual_issue_hazard_unit (
   // Way A 명령어 정보 (슬롯 0, 항상 발행)
   input  logic [4:0]  way_a_rd_i,       // Way A 목적 레지스터
   input  logic        way_a_reg_wen_i,   // Way A 레지스터 쓰기 여부
   input  logic        way_a_mem_read_i,  // Way A 로드 명령어 여부
   input  logic        way_a_branch_i,    // Way A 분기 명령어 여부

   // Way B 명령어 정보 (슬롯 1, 조건부 발행)
   input  logic [4:0]  way_b_rs1_i,      // Way B 소스 레지스터 1
   input  logic [4:0]  way_b_rs2_i,      // Way B 소스 레지스터 2
   input  logic        way_b_use_rs1_i,   // Way B가 rs1을 사용하는가
   input  logic        way_b_use_rs2_i,   // Way B가 rs2를 사용하는가
   input  logic        way_b_mem_access_i,// Way B 메모리 접근 여부
   input  logic        way_b_branch_i,    // Way B 분기 명령어 여부

   // 출력
   output logic        way_b_stall_o,     // Way B 발행 차단 (NOP 삽입)
   output logic [2:0]  stall_reason_o     // 스톨 원인 (디버깅용)
);

   // 스톨 원인 인코딩 (디버깅 및 성능 카운터용)
   localparam REASON_NONE       = 3'b000;  // 스톨 없음
   localparam REASON_RAW_RS1    = 3'b001;  // RAW 해저드 (rs1)
   localparam REASON_RAW_RS2    = 3'b010;  // RAW 해저드 (rs2)
   localparam REASON_STRUCT_MEM = 3'b011;  // 구조적 해저드 (메모리 포트)
   localparam REASON_CONTROL    = 3'b100;  // 제어 해저드 (분기)
   localparam REASON_RAW_BOTH   = 3'b101;  // RAW 해저드 (rs1 + rs2)

   // =========================================================================
   // 의존성 검사 로직
   // =========================================================================

   // 1. RAW 해저드: Way A의 rd가 Way B의 rs1 또는 rs2와 일치
   //    단, x0에 대한 의존성은 무시 (x0는 항상 0)
   logic raw_hazard_rs1;
   logic raw_hazard_rs2;
   logic raw_hazard;

   assign raw_hazard_rs1 = way_a_reg_wen_i
                         & way_b_use_rs1_i
                         & (way_a_rd_i == way_b_rs1_i)
                         & (way_a_rd_i != 5'b0);      // x0 제외

   assign raw_hazard_rs2 = way_a_reg_wen_i
                         & way_b_use_rs2_i
                         & (way_a_rd_i == way_b_rs2_i)
                         & (way_a_rd_i != 5'b0);

   assign raw_hazard = raw_hazard_rs1 | raw_hazard_rs2;

   // 2. 구조적 해저드: 메모리 포트 경합
   //    Way A가 메모리 접근 명령어이고, Way B도 메모리 접근이면 동시 발행 불가
   //    (DMEM 포트가 1개이므로)
   logic structural_hazard;
   assign structural_hazard = way_a_mem_read_i & way_b_mem_access_i;

   // 3. 제어 해저드: 분기 명령어는 동시 발행 불가
   //    Way A가 분기이면 Way B 결과가 불확실
   logic control_hazard;
   assign control_hazard = way_a_branch_i | way_b_branch_i;

   // =========================================================================
   // 스톨 결정 및 원인 출력
   // =========================================================================
   always_comb begin
      way_b_stall_o  = 1'b0;
      stall_reason_o = REASON_NONE;

      if (control_hazard) begin
         way_b_stall_o  = 1'b1;
         stall_reason_o = REASON_CONTROL;
      end else if (structural_hazard) begin
         way_b_stall_o  = 1'b1;
         stall_reason_o = REASON_STRUCT_MEM;
      end else if (raw_hazard_rs1 & raw_hazard_rs2) begin
         way_b_stall_o  = 1'b1;
         stall_reason_o = REASON_RAW_BOTH;
      end else if (raw_hazard_rs1) begin
         way_b_stall_o  = 1'b1;
         stall_reason_o = REASON_RAW_RS1;
      end else if (raw_hazard_rs2) begin
         way_b_stall_o  = 1'b1;
         stall_reason_o = REASON_RAW_RS2;
      end
   end

endmodule
