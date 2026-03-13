///////////////////////////////////////////////////////////////////////////////
// Module: register_file_with_forwarding
// Description: WB-ID 포워딩을 포함한 레지스터 파일
//              동일 사이클에서 WB 쓰기와 ID 읽기가 충돌할 때
//              최신 데이터를 포워딩하여 구조적 해저드를 해결
//
// Author: RISC-V 프로세서 설계 완전정복, Chapter 12
// Standard: IEEE 1800-2017 (SystemVerilog)
// Target: Xilinx Basys 3 (XC7A35T) — LUTRAM 추론
///////////////////////////////////////////////////////////////////////////////

module register_file_with_forwarding #(
   parameter int DATA_WIDTH = 32,   // 데이터 폭
   parameter int ADDR_WIDTH = 5,    // 주소 폭 (32개 레지스터)
   parameter int NUM_REGS   = 32    // 레지스터 개수
)(
   input  logic                  clk,        // 시스템 클록
   input  logic                  rst_n,      // 비동기 리셋 (액티브 로우)

   // WB 스테이지 쓰기 포트
   input  logic                  wb_reg_wen, // 쓰기 인에이블
   input  logic [ADDR_WIDTH-1:0] wb_rd,      // 목적 레지스터 주소
   input  logic [DATA_WIDTH-1:0] wb_data,    // 쓰기 데이터

   // ID 스테이지 읽기 포트
   input  logic [ADDR_WIDTH-1:0] id_rs1,     // 소스 레지스터 1 주소
   input  logic [ADDR_WIDTH-1:0] id_rs2,     // 소스 레지스터 2 주소
   output logic [DATA_WIDTH-1:0] id_rd1,     // 소스 레지스터 1 데이터
   output logic [DATA_WIDTH-1:0] id_rd2      // 소스 레지스터 2 데이터
);

   // =========================================================================
   // 레지스터 배열 선언 — LUTRAM으로 추론됨 (Basys 3)
   // =========================================================================
   logic [DATA_WIDTH-1:0] regs [NUM_REGS];

   // =========================================================================
   // 동기 쓰기: 클록 상승 에지에서 WB 데이터 기록
   // x0는 항상 0이므로 쓰기 방지
   // =========================================================================
   always_ff @(posedge clk or negedge rst_n) begin
      if (!rst_n) begin
         for (int i = 0; i < NUM_REGS; i++) begin
            regs[i] <= '0;
         end
      end else if (wb_reg_wen && (wb_rd != '0)) begin
         regs[wb_rd] <= wb_data;
      end
   end

   // =========================================================================
   // 비동기 읽기 + WB-ID 포워딩
   // 핵심 로직: WB가 쓰려는 레지스터를 ID가 동시에 읽으면
   //            레지스터 파일의 (아직 갱신되지 않은) 값 대신
   //            WB의 최신 데이터를 직접 전달
   // =========================================================================

   // rs1 포워딩 조건:
   //   1) WB 스테이지가 쓰기를 수행 중 (wb_reg_wen == 1)
   //   2) 목적 레지스터가 x0가 아님 (wb_rd != 0)
   //   3) WB의 목적 레지스터와 ID의 소스 레지스터가 동일 (wb_rd == id_rs1)
   always_comb begin
      if (id_rs1 == '0) begin
         // x0는 항상 0
         id_rd1 = '0;
      end else if (wb_reg_wen && (wb_rd != '0) && (wb_rd == id_rs1)) begin
         // WB-ID 포워딩: 최신 데이터 바이패스
         id_rd1 = wb_data;
      end else begin
         // 일반 읽기: 레지스터 파일에서 직접 읽기
         id_rd1 = regs[id_rs1];
      end
   end

   // rs2 포워딩 — rs1과 동일한 논리
   always_comb begin
      if (id_rs2 == '0) begin
         id_rd2 = '0;
      end else if (wb_reg_wen && (wb_rd != '0) && (wb_rd == id_rs2)) begin
         id_rd2 = wb_data;
      end else begin
         id_rd2 = regs[id_rs2];
      end
   end

endmodule
