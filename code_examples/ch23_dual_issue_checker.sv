// ============================================================
// Ch23: 2-이슈 발급 검사기 (Dual-Issue Checker)
// 명령어 A(첫 번째)와 B(두 번째)의 동시 발급 가능 여부 판정
// 합성 가능 (Synthesizable)
// ============================================================
module dual_issue_checker (
   input  logic [4:0] a_rd,        // 명령어 A의 목적 레지스터
   input  logic       a_reg_wen,   // 명령어 A의 레지스터 쓰기 여부
   input  logic       a_is_branch, // 명령어 A가 분기/점프인가
   input  logic       a_is_mem,    // 명령어 A가 메모리 접근인가
   input  logic [4:0] b_rs1,       // 명령어 B의 소스 레지스터 1
   input  logic [4:0] b_rs2,       // 명령어 B의 소스 레지스터 2
   input  logic       b_use_rs1,   // 명령어 B가 rs1을 사용하는가
   input  logic       b_use_rs2,   // 명령어 B가 rs2를 사용하는가
   input  logic       b_is_mem,    // 명령어 B가 메모리 접근인가
   output logic       can_dual     // 동시 발급 가능 여부
);

   logic raw_hazard;   // RAW 의존성 존재
   logic res_conflict; // 자원 충돌 존재
   logic ctrl_dep;     // 제어 의존성 존재

   // ── 조건 1: RAW 의존성 검사 ──
   // A의 목적 레지스터(rd)가 B의 소스 레지스터(rs1/rs2)와 일치하면 의존성
   // x0는 항상 0이므로 제외 (x0에 대한 포워딩은 불필요)
   assign raw_hazard = a_reg_wen && (a_rd != 5'd0) &&
                       ((b_use_rs1 && (a_rd == b_rs1)) ||
                        (b_use_rs2 && (a_rd == b_rs2)));

   // ── 조건 2: 자원 충돌 검사 ──
   // 두 명령어 모두 메모리 접근이면 DMEM 포트 충돌
   // (DMEM은 단일 포트로 가정)
   assign res_conflict = a_is_mem && b_is_mem;

   // ── 조건 3: 제어 의존성 검사 ──
   // A가 분기/점프이면 B의 유효성이 불확실하므로 동시 발급 차단
   assign ctrl_dep = a_is_branch;

   // ── 최종 판정 ──
   // 세 조건 모두 만족해야 동시 발급 가능
   assign can_dual = ~raw_hazard && ~res_conflict && ~ctrl_dep;

endmodule
