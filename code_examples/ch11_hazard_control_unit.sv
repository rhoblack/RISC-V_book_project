// ============================================================================
// 통합 해저드 제어 유닛 — Flush/Stall 우선순위 관리
// Chapter 11: 제어 해저드와 분기 처리
// ============================================================================
// - 데이터 해저드(Load-Use 스톨)와 제어 해저드(분기 flush) 통합
// - Flush 우선 규칙: branch_flush가 load_use_stall보다 우선
// ============================================================================

module hazard_control_unit (
   // ---- 데이터 해저드 감지 입력 (Ch10 확장) ----
   input  logic        id_ex_mem_read,    // ID/EX 스테이지의 메모리 읽기 여부
   input  logic [4:0]  id_ex_rd,          // ID/EX 스테이지의 목적 레지스터
   input  logic [4:0]  if_id_rs1,         // IF/ID 스테이지의 소스 레지스터 1
   input  logic [4:0]  if_id_rs2,         // IF/ID 스테이지의 소스 레지스터 2

   // ---- 제어 해저드 감지 입력 ----
   input  logic        branch_taken,      // 분기/점프 성공 여부 (EX에서)

   // ---- 파이프라인 제어 출력 ----
   output logic        pc_write,          // PC 레지스터 쓰기 인에이블
   output logic        if_id_write,       // IF/ID 레지스터 쓰기 인에이블
   output logic        if_id_flush,       // IF/ID 레지스터 flush
   output logic        id_ex_flush        // ID/EX 레지스터 flush (스톨 시 버블)
);

   // ---------------------------------------------------------------
   // Load-Use 해저드 감지
   // ID/EX에 Load 명령어가 있고, 그 rd가 IF/ID의 rs1 또는 rs2와 동일
   // ---------------------------------------------------------------
   logic load_use_stall;

   assign load_use_stall = id_ex_mem_read
                         & (id_ex_rd != 5'b0)         // x0 포워딩 방지
                         & ( (id_ex_rd == if_id_rs1)
                           | (id_ex_rd == if_id_rs2) );

   // ---------------------------------------------------------------
   // 우선순위 결정 로직
   // ★ 핵심 규칙: Flush는 Stall보다 항상 우선
   //
   // 이유: 분기가 성공하면, 스톨 대상 명령어(IF/ID에 있는)도
   //       어차피 flush되어야 하므로 스톨할 필요가 없음.
   // ---------------------------------------------------------------
   always_comb begin
      if (branch_taken) begin
         // ----- 제어 해저드: Flush 우선 -----
         pc_write     = 1'b1;    // PC에 branch_target 기록 허용
         if_id_write  = 1'b1;    // IF/ID 쓰기 허용 (flush 위해)
         if_id_flush  = 1'b1;    // IF/ID 레지스터 클리어
         id_ex_flush  = 1'b1;    // ID/EX 레지스터 클리어
      end
      else if (load_use_stall) begin
         // ----- 데이터 해저드: Stall (flush 미발생 시에만) -----
         pc_write     = 1'b0;    // PC 홀드 (같은 명령어 재fetch)
         if_id_write  = 1'b0;    // IF/ID 홀드 (같은 명령어 유지)
         if_id_flush  = 1'b0;    // flush 하지 않음
         id_ex_flush  = 1'b1;    // ID/EX에 버블(NOP) 삽입
      end
      else begin
         // ----- 정상 동작 -----
         pc_write     = 1'b1;    // PC 정상 갱신
         if_id_write  = 1'b1;    // IF/ID 정상 기록
         if_id_flush  = 1'b0;    // flush 없음
         id_ex_flush  = 1'b0;    // flush 없음
      end
   end

endmodule
