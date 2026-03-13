// ============================================================================
// 명령어 디코더 (Instruction Decoder)
// Chapter 06 — 제어 유닛과 단일 사이클 통합
// RISC-V 프로세서 설계 완전정복
// ============================================================================
// RV32I 37개 명령어 완전 디코딩
// opcode → 명령어 유형 분류, funct3/funct7 → ALU 연산 선택
// ============================================================================

`timescale 1ns / 1ps

// --------------------------------------------------------------------------
// ALU 연산 코드 정의
// --------------------------------------------------------------------------
typedef enum logic [3:0] {
   ALU_ADD  = 4'b0000,   // 덧셈
   ALU_SUB  = 4'b0001,   // 뺄셈
   ALU_AND  = 4'b0010,   // 비트 AND
   ALU_OR   = 4'b0011,   // 비트 OR
   ALU_XOR  = 4'b0100,   // 비트 XOR
   ALU_SLL  = 4'b0101,   // 좌측 논리 시프트
   ALU_SRL  = 4'b0110,   // 우측 논리 시프트
   ALU_SRA  = 4'b0111,   // 우측 산술 시프트
   ALU_SLT  = 4'b1000,   // 부호 있는 비교 (Set Less Than)
   ALU_SLTU = 4'b1001    // 부호 없는 비교 (Set Less Than Unsigned)
} alu_op_t;

// --------------------------------------------------------------------------
// 즉치수 타입 정의
// --------------------------------------------------------------------------
typedef enum logic [2:0] {
   IMM_I = 3'b000,   // I 타입 즉치수
   IMM_S = 3'b001,   // S 타입 즉치수
   IMM_B = 3'b010,   // B 타입 즉치수
   IMM_U = 3'b011,   // U 타입 즉치수
   IMM_J = 3'b100    // J 타입 즉치수
} imm_sel_t;

// --------------------------------------------------------------------------
// Write-Back 소스 선택
// --------------------------------------------------------------------------
typedef enum logic [1:0] {
   WB_ALU  = 2'b00,  // ALU 결과
   WB_MEM  = 2'b01,  // 메모리 읽기 결과
   WB_PC4  = 2'b10   // PC + 4 (JAL/JALR용)
} wb_sel_t;

// --------------------------------------------------------------------------
// PC 소스 선택
// --------------------------------------------------------------------------
typedef enum logic [1:0] {
   PC_PLUS4  = 2'b00,  // PC + 4 (순차 실행)
   PC_BRANCH = 2'b01,  // 분기 목표 주소 (PC + imm)
   PC_JALR   = 2'b10   // JALR 목표 주소 (rs1 + imm)
} pc_sel_t;

// --------------------------------------------------------------------------
// 메모리 읽기/쓰기 제어
// --------------------------------------------------------------------------
typedef enum logic [1:0] {
   MEM_NONE  = 2'b00,  // 메모리 접근 없음
   MEM_READ  = 2'b01,  // 메모리 읽기 (Load)
   MEM_WRITE = 2'b10   // 메모리 쓰기 (Store)
} mem_rw_t;

// ============================================================================
// 명령어 디코더 모듈
// ============================================================================
module instruction_decoder (
   // --- 입력 ---
   input  logic [31:0] instr,       // 32비트 명령어
   input  logic        br_eq,       // 분기 비교 결과: 같음
   input  logic        br_lt,       // 분기 비교 결과: 미만

   // --- 제어 신호 출력 ---
   output alu_op_t     alu_sel,     // ALU 연산 선택
   output imm_sel_t    imm_sel,     // 즉치수 타입 선택
   output logic        reg_w_en,    // 레지스터 파일 쓰기 인에이블
   output mem_rw_t     mem_rw,      // 메모리 읽기/쓰기 제어
   output pc_sel_t     pc_sel,      // 다음 PC 선택
   output wb_sel_t     wb_sel,      // Write-Back 소스 선택
   output logic        a_sel,       // ALU A 입력: 0=rs1, 1=PC
   output logic        b_sel,       // ALU B 입력: 0=rs2, 1=imm
   output logic        br_un,       // 분기 비교: 무부호 비교 여부
   output logic        illegal_instr // 미정의 명령어 감지
);

   // --- 명령어 필드 분리 ---
   logic [6:0] opcode;
   logic [2:0] funct3;
   logic [6:0] funct7;

   assign opcode = instr[6:0];
   assign funct3 = instr[14:12];
   assign funct7 = instr[31:25];

   // --- opcode 상수 정의 ---
   localparam logic [6:0] OP_R_TYPE  = 7'b0110011;  // R 타입 연산
   localparam logic [6:0] OP_I_TYPE  = 7'b0010011;  // I 타입 ALU 연산
   localparam logic [6:0] OP_LOAD    = 7'b0000011;  // Load 명령어
   localparam logic [6:0] OP_STORE   = 7'b0100011;  // Store 명령어
   localparam logic [6:0] OP_BRANCH  = 7'b1100011;  // 분기 명령어
   localparam logic [6:0] OP_JAL     = 7'b1101111;  // JAL (J 타입)
   localparam logic [6:0] OP_JALR    = 7'b1100111;  // JALR (I 타입)
   localparam logic [6:0] OP_LUI     = 7'b0110111;  // LUI (U 타입)
   localparam logic [6:0] OP_AUIPC   = 7'b0010111;  // AUIPC (U 타입)
   localparam logic [6:0] OP_SYSTEM  = 7'b1110011;  // ECALL/EBREAK

   // --- 분기 조건 판정 ---
   logic branch_taken;

   always_comb begin
      branch_taken = 1'b0;
      if (opcode == OP_BRANCH) begin
         case (funct3)
            3'b000:  branch_taken = br_eq;            // BEQ
            3'b001:  branch_taken = ~br_eq;           // BNE
            3'b100:  branch_taken = br_lt;            // BLT
            3'b101:  branch_taken = ~br_lt;           // BGE
            3'b110:  branch_taken = br_lt;            // BLTU
            3'b111:  branch_taken = ~br_lt;           // BGEU
            default: branch_taken = 1'b0;
         endcase
      end
   end

   // --- 메인 디코더: opcode 기반 제어 신호 생성 ---
   always_comb begin
      // 기본값 (안전한 기본값으로 래치 방지)
      alu_sel       = ALU_ADD;
      imm_sel       = IMM_I;
      reg_w_en      = 1'b0;
      mem_rw        = MEM_NONE;
      pc_sel        = PC_PLUS4;
      wb_sel        = WB_ALU;
      a_sel         = 1'b0;   // rs1
      b_sel         = 1'b0;   // rs2
      br_un         = 1'b0;
      illegal_instr = 1'b0;

      case (opcode)
         // ============================================================
         // R 타입: register-register 연산
         // ============================================================
         OP_R_TYPE: begin
            reg_w_en = 1'b1;
            a_sel    = 1'b0;   // rs1
            b_sel    = 1'b0;   // rs2
            wb_sel   = WB_ALU;
            // ALU 연산은 funct3/funct7으로 결정
            case (funct3)
               3'b000: alu_sel = (funct7[5]) ? ALU_SUB : ALU_ADD;
               3'b001: alu_sel = ALU_SLL;
               3'b010: alu_sel = ALU_SLT;
               3'b011: alu_sel = ALU_SLTU;
               3'b100: alu_sel = ALU_XOR;
               3'b101: alu_sel = (funct7[5]) ? ALU_SRA : ALU_SRL;
               3'b110: alu_sel = ALU_OR;
               3'b111: alu_sel = ALU_AND;
            endcase
         end

         // ============================================================
         // I 타입: 즉치수 ALU 연산
         // ============================================================
         OP_I_TYPE: begin
            reg_w_en = 1'b1;
            a_sel    = 1'b0;   // rs1
            b_sel    = 1'b1;   // 즉치수
            imm_sel  = IMM_I;
            wb_sel   = WB_ALU;
            case (funct3)
               3'b000: alu_sel = ALU_ADD;  // ADDI
               3'b001: alu_sel = ALU_SLL;  // SLLI
               3'b010: alu_sel = ALU_SLT;  // SLTI
               3'b011: alu_sel = ALU_SLTU; // SLTIU
               3'b100: alu_sel = ALU_XOR;  // XORI
               3'b101: alu_sel = (funct7[5]) ? ALU_SRA : ALU_SRL; // SRAI / SRLI
               3'b110: alu_sel = ALU_OR;   // ORI
               3'b111: alu_sel = ALU_AND;  // ANDI
            endcase
         end

         // ============================================================
         // Load: 메모리에서 레지스터로 데이터 적재
         // ============================================================
         OP_LOAD: begin
            reg_w_en = 1'b1;
            a_sel    = 1'b0;       // rs1 (베이스 주소)
            b_sel    = 1'b1;       // 즉치수 (오프셋)
            imm_sel  = IMM_I;
            alu_sel  = ALU_ADD;    // 주소 = rs1 + imm
            mem_rw   = MEM_READ;
            wb_sel   = WB_MEM;     // 메모리 데이터를 레지스터에 기록
         end

         // ============================================================
         // Store: 레지스터에서 메모리로 데이터 저장
         // ============================================================
         OP_STORE: begin
            reg_w_en = 1'b0;       // 레지스터 쓰기 없음
            a_sel    = 1'b0;       // rs1 (베이스 주소)
            b_sel    = 1'b1;       // 즉치수 (오프셋)
            imm_sel  = IMM_S;
            alu_sel  = ALU_ADD;    // 주소 = rs1 + imm
            mem_rw   = MEM_WRITE;
         end

         // ============================================================
         // Branch: 조건부 분기
         // ============================================================
         OP_BRANCH: begin
            reg_w_en = 1'b0;
            a_sel    = 1'b1;       // PC (분기 목표 주소 계산)
            b_sel    = 1'b1;       // 즉치수
            imm_sel  = IMM_B;
            alu_sel  = ALU_ADD;    // 분기 목표 = PC + imm
            pc_sel   = branch_taken ? PC_BRANCH : PC_PLUS4;
            // 무부호 비교 여부 (BLTU, BGEU)
            br_un    = (funct3[1]) ? 1'b1 : 1'b0;
         end

         // ============================================================
         // JAL: Jump and Link (J 타입)
         // ============================================================
         OP_JAL: begin
            reg_w_en = 1'b1;
            a_sel    = 1'b1;       // PC
            b_sel    = 1'b1;       // 즉치수
            imm_sel  = IMM_J;
            alu_sel  = ALU_ADD;    // 점프 목표 = PC + imm
            pc_sel   = PC_BRANCH;  // 항상 점프
            wb_sel   = WB_PC4;     // rd = PC + 4 (복귀 주소)
         end

         // ============================================================
         // JALR: Jump and Link Register (I 타입)
         // ============================================================
         OP_JALR: begin
            reg_w_en = 1'b1;
            a_sel    = 1'b0;       // rs1
            b_sel    = 1'b1;       // 즉치수
            imm_sel  = IMM_I;
            alu_sel  = ALU_ADD;    // 점프 목표 = rs1 + imm
            pc_sel   = PC_JALR;
            wb_sel   = WB_PC4;     // rd = PC + 4 (복귀 주소)
         end

         // ============================================================
         // LUI: Load Upper Immediate (U 타입)
         // ============================================================
         OP_LUI: begin
            reg_w_en = 1'b1;
            a_sel    = 1'b0;       // 사용 안 함 (0으로 처리)
            b_sel    = 1'b1;       // 즉치수
            imm_sel  = IMM_U;
            alu_sel  = ALU_ADD;    // rd = 0 + imm (상위 20비트)
            wb_sel   = WB_ALU;
            // 참고: ALU A 입력을 0으로 설정하여 imm을 그대로 전달
            // 실제 구현에서는 별도 MUX 또는 x0 포워딩으로 처리
         end

         // ============================================================
         // AUIPC: Add Upper Immediate to PC (U 타입)
         // ============================================================
         OP_AUIPC: begin
            reg_w_en = 1'b1;
            a_sel    = 1'b1;       // PC
            b_sel    = 1'b1;       // 즉치수
            imm_sel  = IMM_U;
            alu_sel  = ALU_ADD;    // rd = PC + imm
            wb_sel   = WB_ALU;
         end

         // ============================================================
         // SYSTEM: ECALL, EBREAK (현재는 NOP 처리)
         // ============================================================
         OP_SYSTEM: begin
            // 최소 구현: 아무 동작 없음
            // 전체 구현은 Ch18 (CSR) 참조
            reg_w_en = 1'b0;
         end

         // ============================================================
         // 미정의 opcode → illegal instruction
         // ============================================================
         default: begin
            illegal_instr = 1'b1;
         end
      endcase
   end

endmodule