///////////////////////////////////////////////////////////////////////////////
// Module: hazard_detection_unit
// Description: 해저드 감지 유닛 — 스톨 및 플러시 제어
//              Load-Use 해저드 감지 + 제어 해저드 플러시 통합
//
// Author: RISC-V 프로세서 설계 완전정복, Chapter 12
// Standard: IEEE 1800-2017 (SystemVerilog)
// Target: Xilinx Basys 3 (XC7A35T)
///////////////////////////////////////////////////////////////////////////////

module hazard_detection_unit (
   // ID 스테이지 소스 레지스터
   input  logic [4:0] id_rs1,          // ID 스테이지 rs1
   input  logic [4:0] id_rs2,          // ID 스테이지 rs2

   // EX 스테이지 목적 레지스터 (Load-Use 감지용)
   input  logic [4:0] ex_rd,           // EX 스테이지 rd
   input  logic       ex_mem_ren,      // EX 스테이지 메모리 읽기 (Load 명령어)

   // 분기/점프 제어
   input  logic       branch_taken,    // 분기 성립 (ID 또는 EX 스테이지)
   input  logic       jump,            // 점프 명령어

   // 출력: 파이프라인 제어 신호
   output logic       stall,           // 스톨 발생 표시
   output logic       pc_en,           // PC 갱신 인에이블
   output logic       if_id_en,        // IF/ID 레지스터 인에이블
   output logic       id_ex_flush,     // ID/EX 레지스터 플러시
   output logic       if_id_flush      // IF/ID 레지스터 플러시
);

   // =========================================================================
   // Load-Use 해저드 감지
   // EX 스테이지에 Load 명령어가 있고, 그 rd가 ID 스테이지의
   // rs1 또는 rs2와 동일하면 1사이클 스톨 필요
   // =========================================================================
   logic load_use_hazard;

   always_comb begin
      load_use_hazard = ex_mem_ren
                        && (ex_rd != 5'b0)
                        && ((ex_rd == id_rs1) || (ex_rd == id_rs2));
   end

   // =========================================================================
   // 제어 해저드 감지
   // 분기 성립 또는 점프 시 이미 인출된 명령어를 플러시
   // =========================================================================
   logic control_hazard;

   assign control_hazard = branch_taken || jump;

   // =========================================================================
   // 제어 신호 생성
   // 우선순위: 제어 해저드(플러시) > Load-Use 해저드(스톨)
   //
   // [핵심 규칙]
   // - 스톨 시: PC 홀드, IF/ID 홀드, ID/EX 플러시(버블)
   // - 플러시 시: IF/ID 플러시, ID/EX 플러시, PC 갱신 허용
   // =========================================================================
   always_comb begin
      // 기본값: 정상 동작
      stall       = 1'b0;
      pc_en       = 1'b1;
      if_id_en    = 1'b1;
      id_ex_flush = 1'b0;
      if_id_flush = 1'b0;

      if (control_hazard) begin
         // 제어 해저드: 플러시 우선
         // PC는 분기/점프 목적지로 갱신됨 (pc_en = 1)
         if_id_flush = 1'b1;  // IF/ID에 들어있는 잘못된 명령어 제거
         id_ex_flush = 1'b1;  // ID/EX에 들어있는 잘못된 명령어 제거
      end else if (load_use_hazard) begin
         // Load-Use 해저드: 1사이클 스톨
         stall       = 1'b1;
         pc_en       = 1'b0;  // PC 홀드 (같은 명령어 재인출)
         if_id_en    = 1'b0;  // IF/ID 홀드 (같은 명령어 유지)
         id_ex_flush = 1'b1;  // ID/EX에 버블(NOP) 삽입
      end
   end

endmodule
