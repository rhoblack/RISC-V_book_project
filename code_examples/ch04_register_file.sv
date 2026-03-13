// =============================================================================
// 모듈명: register_file
// 설  명: RV32I 레지스터 파일 — 32개 x 32비트, 2 Read / 1 Write 포트
// 파  일: ch04_register_file.sv
// 표  준: IEEE 1800-2017 (SystemVerilog)
// 저  자: RISC-V 프로세서 설계 완전정복 — Chapter 04
// =============================================================================
// 설계 결정:
//   - 비동기 읽기 (Asynchronous Read)  → FPGA에서 LUTRAM으로 추론
//   - 동기 쓰기   (Synchronous Write)  → posedge clk에서 기록
//   - x0 레지스터: 쓰기 무시, 항상 0 반환
// 이유:
//   단일 사이클 프로세서에서 레지스터 파일의 읽기 값은 같은 클럭 사이클 내에
//   ALU로 전달되어야 합니다. BRAM은 동기 읽기이므로 1사이클 지연이 발생하여
//   단일 사이클 동작이 불가합니다. 따라서 비동기 읽기를 사용합니다.
// =============================================================================

module register_file (
   input  logic        clk,          // 시스템 클록
   input  logic        rst_n,        // 비동기 리셋 (액티브 로우)

   // 읽기 포트 1 (비동기)
   input  logic [4:0]  rs1_addr,     // 소스 레지스터 1 주소 (inst[19:15])
   output logic [31:0] rs1_data,     // 소스 레지스터 1 데이터

   // 읽기 포트 2 (비동기)
   input  logic [4:0]  rs2_addr,     // 소스 레지스터 2 주소 (inst[24:20])
   output logic [31:0] rs2_data,     // 소스 레지스터 2 데이터

   // 쓰기 포트 (동기)
   input  logic [4:0]  rd_addr,      // 목적지 레지스터 주소 (inst[11:7])
   input  logic [31:0] rd_data,      // 기록할 데이터
   input  logic        reg_wr_en     // 쓰기 인에이블 (제어 유닛에서 생성)
);

   // 32개 x 32비트 레지스터 배열
   logic [31:0] registers [0:31];

   // --- 동기 쓰기 로직 ---
   // x0 레지스터는 항상 0이므로 쓰기를 무시합니다.
   // 리셋 시 모든 레지스터를 0으로 초기화합니다.
   always_ff @(posedge clk or negedge rst_n) begin
      if (!rst_n) begin
         // 비동기 리셋: 모든 레지스터를 0으로 초기화
         for (int i = 0; i < 32; i++) begin
            registers[i] <= 32'b0;
         end
      end else if (reg_wr_en && (rd_addr != 5'b0)) begin
         // x0이 아닌 레지스터에만 쓰기 수행
         registers[rd_addr] <= rd_data;
      end
   end

   // --- 비동기 읽기 로직 ---
   // x0 레지스터는 항상 0을 반환합니다.
   // 조합 논리로 구현되어 LUTRAM으로 합성됩니다.
   assign rs1_data = (rs1_addr == 5'b0) ? 32'b0 : registers[rs1_addr];
   assign rs2_data = (rs2_addr == 5'b0) ? 32'b0 : registers[rs2_addr];

endmodule
