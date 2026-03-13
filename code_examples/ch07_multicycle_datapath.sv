// ============================================================================
// 멀티사이클 데이터패스 (Multicycle Datapath)
// Chapter 07 — 멀티사이클 데이터패스
// RISC-V 프로세서 설계 완전정복
// ============================================================================
// RV32I 멀티사이클 프로세서의 데이터패스 모듈
// 핵심 구성: 통합 메모리, 공유 ALU, 중간 레지스터 (IR, MDR, A, B, ALUOut)
// 제어 유닛(FSM)은 Ch08에서 별도 설계
// ============================================================================

`timescale 1ns / 1ps

module multicycle_datapath (
   // --- 클럭 및 리셋 ---
   input  logic        clk,           // 시스템 클럭
   input  logic        rst_n,         // 비동기 리셋 (액티브 로우)

   // --- 제어 신호 입력 (FSM 제어 유닛에서 공급) ---
   input  logic        pc_write,      // PC 레지스터 쓰기 인에이블
   input  logic        pc_write_cond, // 조건부 PC 쓰기 (분기 시)
   input  logic        i_or_d,        // 메모리 주소 선택 (0: PC, 1: ALUOut)
   input  logic        mem_read,      // 메모리 읽기 인에이블
   input  logic        mem_write,     // 메모리 쓰기 인에이블
   input  logic        ir_write,      // 명령어 레지스터 쓰기 인에이블
   input  logic        reg_write,     // 레지스터 파일 쓰기 인에이블
   input  logic [1:0]  reg_dst,       // 쓰기 레지스터 선택 (rd)
   input  logic [1:0]  mem_to_reg,    // Write-Back 데이터 선택
   input  logic        alu_src_a,     // ALU A 입력 선택 (0: PC, 1: A 레지스터)
   input  logic [1:0]  alu_src_b,     // ALU B 입력 선택
   input  logic [3:0]  alu_op,        // ALU 연산 코드
   input  logic [1:0]  pc_src,        // PC 소스 선택

   // --- 상태 출력 (제어 유닛으로 전달) ---
   output logic [6:0]  opcode,        // 명령어 opcode 필드
   output logic [2:0]  funct3,        // 명령어 funct3 필드
   output logic [6:0]  funct7,        // 명령어 funct7 필드
   output logic        alu_zero       // ALU Zero 플래그
);

   // =====================================================================
   // 내부 신호 선언
   // =====================================================================

   // --- PC 관련 ---
   logic [31:0] pc_reg;          // 프로그램 카운터 레지스터
   logic [31:0] pc_next;         // 다음 PC 값
   logic        pc_en;           // PC 실제 인에이블 (pc_write OR 조건부)

   // --- 메모리 관련 ---
   logic [31:0] mem_addr;        // 메모리 주소 (IorD MUX 출력)
   logic [31:0] mem_data_out;    // 메모리 읽기 데이터

   // --- 중간 레지스터 ---
   logic [31:0] ir_reg;          // 명령어 레지스터 (Instruction Register)
   logic [31:0] mdr_reg;         // 메모리 데이터 레지스터 (Memory Data Register)
   logic [31:0] a_reg;           // A 레지스터 (rs1 데이터 임시 저장)
   logic [31:0] b_reg;           // B 레지스터 (rs2 데이터 임시 저장)
   logic [31:0] alu_out_reg;     // ALU 결과 레지스터

   // --- 레지스터 파일 관련 ---
   logic [4:0]  rs1_addr;        // rs1 주소
   logic [4:0]  rs2_addr;        // rs2 주소
   logic [4:0]  rd_addr;         // rd 주소
   logic [31:0] rs1_data;        // rs1 읽기 데이터
   logic [31:0] rs2_data;        // rs2 읽기 데이터
   logic [31:0] reg_write_data;  // 레지스터 파일 쓰기 데이터

   // --- ALU 관련 ---
   logic [31:0] alu_a;           // ALU A 입력
   logic [31:0] alu_b;           // ALU B 입력
   logic [31:0] alu_result;      // ALU 연산 결과

   // --- 즉치수 생성기 ---
   logic [31:0] imm_ext;         // 부호 확장된 즉치수

   // =====================================================================
   // 명령어 필드 추출
   // =====================================================================
   assign opcode   = ir_reg[6:0];
   assign funct3   = ir_reg[14:12];
   assign funct7   = ir_reg[31:25];
   assign rs1_addr = ir_reg[19:15];
   assign rs2_addr = ir_reg[24:20];
   assign rd_addr  = ir_reg[11:7];

   // =====================================================================
   // 1. 프로그램 카운터 (PC)
   // =====================================================================
   // PC 인에이블: 무조건 쓰기 OR (조건부 쓰기 AND ALU Zero)
   assign pc_en = pc_write | (pc_write_cond & alu_zero);

   always_ff @(posedge clk or negedge rst_n) begin
      if (!rst_n)
         pc_reg <= 32'h0000_0000;  // 리셋 시 PC = 0
      else if (pc_en)
         pc_reg <= pc_next;
   end

   // PC 소스 MUX (PCSrc)
   always_comb begin
      case (pc_src)
         2'b00:   pc_next = alu_result;     // ALU 직접 출력 (PC+4)
         2'b01:   pc_next = alu_out_reg;    // ALUOut (분기 목표 주소)
         2'b10:   pc_next = {alu_out_reg[31:28], ir_reg[25:0], 2'b00}; // 점프 주소
         default: pc_next = alu_result;
      endcase
   end

   // =====================================================================
   // 2. 메모리 주소 MUX (IorD)
   // =====================================================================
   // i_or_d = 0: PC (명령어 인출)
   // i_or_d = 1: ALUOut (데이터 접근)
   assign mem_addr = i_or_d ? alu_out_reg : pc_reg;

   // =====================================================================
   // 3. 통합 메모리 (Unified Memory)
   // =====================================================================
   // 명령어와 데이터를 하나의 메모리에서 처리 (Princeton 구조)
   // 실제 FPGA 구현 시에는 BRAM으로 추론
   logic [31:0] memory [0:4095]; // 16KB 메모리 (4K 워드)

   // 메모리 읽기 (동기)
   always_ff @(posedge clk) begin
      if (mem_read)
         mem_data_out <= memory[mem_addr[13:2]]; // 워드 정렬 주소
   end

   // 메모리 쓰기 (동기)
   always_ff @(posedge clk) begin
      if (mem_write)
         memory[mem_addr[13:2]] <= b_reg; // B 레지스터 데이터를 저장
   end

   // =====================================================================
   // 4. 명령어 레지스터 (IR) — 인출된 명령어를 유지
   // =====================================================================
   always_ff @(posedge clk or negedge rst_n) begin
      if (!rst_n)
         ir_reg <= 32'h0000_0013;  // 리셋 시 NOP (ADDI x0, x0, 0)
      else if (ir_write)
         ir_reg <= mem_data_out;    // 메모리에서 읽은 명령어 저장
   end

   // =====================================================================
   // 5. 메모리 데이터 레지스터 (MDR) — 로드 데이터를 한 사이클 유지
   // =====================================================================
   always_ff @(posedge clk) begin
      mdr_reg <= mem_data_out;      // 매 사이클 갱신 (인에이블 불필요)
   end

   // =====================================================================
   // 6. 레지스터 파일 (Register File)
   // =====================================================================
   logic [31:0] reg_file [0:31];

   // 비동기 읽기 (조합 논리)
   assign rs1_data = (rs1_addr == 5'd0) ? 32'd0 : reg_file[rs1_addr];
   assign rs2_data = (rs2_addr == 5'd0) ? 32'd0 : reg_file[rs2_addr];

   // 동기 쓰기
   always_ff @(posedge clk) begin
      if (reg_write && (rd_addr != 5'd0))
         reg_file[rd_addr] <= reg_write_data;
   end

   // Write-Back 데이터 선택 MUX (MemtoReg)
   always_comb begin
      case (mem_to_reg)
         2'b00:   reg_write_data = alu_out_reg;   // ALU 결과
         2'b01:   reg_write_data = mdr_reg;        // 메모리 로드 데이터
         2'b10:   reg_write_data = pc_reg;         // PC (JAL/JALR 복귀 주소)
         default: reg_write_data = alu_out_reg;
      endcase
   end

   // =====================================================================
   // 7. A/B 레지스터 — 레지스터 파일 출력을 한 사이클 보존
   // =====================================================================
   always_ff @(posedge clk) begin
      a_reg <= rs1_data;   // rs1 데이터 래치
      b_reg <= rs2_data;   // rs2 데이터 래치
   end

   // =====================================================================
   // 8. 즉치수 생성기 (Immediate Generator)
   // =====================================================================
   // IR에서 직접 즉치수를 추출하고 부호 확장
   always_comb begin
      case (opcode)
         // I-타입: ADDI, LW, JALR 등
         7'b0010011, 7'b0000011, 7'b1100111:
            imm_ext = {{20{ir_reg[31]}}, ir_reg[31:20]};

         // S-타입: SW 등
         7'b0100011:
            imm_ext = {{20{ir_reg[31]}}, ir_reg[31:25], ir_reg[11:7]};

         // B-타입: BEQ 등
         7'b1100011:
            imm_ext = {{19{ir_reg[31]}}, ir_reg[31], ir_reg[7],
                        ir_reg[30:25], ir_reg[11:8], 1'b0};

         // U-타입: LUI, AUIPC
         7'b0110111, 7'b0010111:
            imm_ext = {ir_reg[31:12], 12'd0};

         // J-타입: JAL
         7'b1101111:
            imm_ext = {{11{ir_reg[31]}}, ir_reg[31], ir_reg[19:12],
                        ir_reg[20], ir_reg[30:21], 1'b0};

         default:
            imm_ext = 32'd0;
      endcase
   end

   // =====================================================================
   // 9. ALU 입력 MUX
   // =====================================================================

   // ALU A 입력 선택 (ALUSrcA)
   // alu_src_a = 0: PC (PC+4 계산 또는 분기 주소 계산)
   // alu_src_a = 1: A 레지스터 (레지스터 연산)
   assign alu_a = alu_src_a ? a_reg : pc_reg;

   // ALU B 입력 선택 (ALUSrcB)
   always_comb begin
      case (alu_src_b)
         2'b00:   alu_b = b_reg;     // B 레지스터 (R-타입 연산)
         2'b01:   alu_b = 32'd4;     // 상수 4 (PC+4 계산)
         2'b10:   alu_b = imm_ext;   // 즉치수 (I-타입, S-타입, 분기 주소)
         2'b11:   alu_b = imm_ext;   // 즉치수 (예비)
         default: alu_b = b_reg;
      endcase
   end

   // =====================================================================
   // 10. ALU (공유 — 모든 단계에서 재사용)
   // =====================================================================
   always_comb begin
      alu_zero = 1'b0;
      case (alu_op)
         4'b0000: alu_result = alu_a + alu_b;                          // ADD
         4'b0001: alu_result = alu_a - alu_b;                          // SUB
         4'b0010: alu_result = alu_a & alu_b;                          // AND
         4'b0011: alu_result = alu_a | alu_b;                          // OR
         4'b0100: alu_result = alu_a ^ alu_b;                          // XOR
         4'b0101: alu_result = {31'd0, $signed(alu_a) < $signed(alu_b)}; // SLT
         4'b0110: alu_result = {31'd0, alu_a < alu_b};                 // SLTU
         4'b0111: alu_result = alu_a << alu_b[4:0];                    // SLL
         4'b1000: alu_result = alu_a >> alu_b[4:0];                    // SRL
         4'b1001: alu_result = $signed(alu_a) >>> alu_b[4:0];          // SRA
         default: alu_result = alu_a + alu_b;                          // 기본: ADD
      endcase
      alu_zero = (alu_result == 32'd0);
   end

   // =====================================================================
   // 11. ALUOut 레지스터 — ALU 결과를 다음 사이클까지 보존
   // =====================================================================
   always_ff @(posedge clk) begin
      alu_out_reg <= alu_result;
   end

endmodule