// ============================================================================
// CSR 연산 유닛 (CSR ALU)
// Chapter 18 — CSR과 시스템 명령어
// RISC-V 프로세서 설계 완전정복
// ============================================================================
// CSR 명령어의 원자적 읽기-수정-쓰기 연산을 수행
// CSRRW/CSRRS/CSRRC (및 즉치수 변형)의 "수정" 단계 담당
// ============================================================================

`timescale 1ns / 1ps

module csr_alu (
   // --- 입력 ---
   input  logic [31:0] csr_rdata,    // CSR 현재 값 (읽기)
   input  logic [31:0] src_data,     // rs1 데이터 또는 zimm (제로 확장된 5비트)
   input  logic [1:0]  csr_op,       // CSR 연산 선택

   // --- 출력 ---
   output logic [31:0] csr_wdata     // CSR에 쓸 새 값
);

   // =========================================================================
   // CSR 연산 타입 정의
   // =========================================================================
   // funct3 인코딩에서 하위 2비트를 사용
   // 01 → Write (CSRRW/CSRRWI)
   // 10 → Set   (CSRRS/CSRRSI)
   // 11 → Clear (CSRRC/CSRRCI)
   localparam logic [1:0] CSR_WRITE = 2'b01;
   localparam logic [1:0] CSR_SET   = 2'b10;
   localparam logic [1:0] CSR_CLEAR = 2'b11;

   // =========================================================================
   // 연산 수행 (조합 논리)
   // =========================================================================
   always_comb begin
      case (csr_op)
         CSR_WRITE: csr_wdata = src_data;                    // 덮어쓰기
         CSR_SET:   csr_wdata = csr_rdata | src_data;        // 비트 세트
         CSR_CLEAR: csr_wdata = csr_rdata & (~src_data);     // 비트 클리어
         default:   csr_wdata = csr_rdata;                   // 변경 없음
      endcase
   end

endmodule