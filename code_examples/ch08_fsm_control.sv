// ============================================================================
// FSM 기반 제어 유닛 (FSM Control Unit)
// Chapter 08 — FSM 기반 제어 유닛
// RISC-V 프로세서 설계 완전정복
// ============================================================================
// 멀티사이클 프로세서의 핵심 제어기
// Moore FSM: always_ff (상태 레지스터) + always_comb (다음 상태 + 출력 로직)
// 5단계 상태: IF → ID → EX → MEM → WB
// ============================================================================

`timescale 1ns / 1ps

// --------------------------------------------------------------------------
// FSM 상태 정의
// --------------------------------------------------------------------------
typedef enum logic [3:0] {
   S_IF   = 4'b0000,   // 명령어 인출 (Instruction Fetch)
   S_ID   = 4'b0001,   // 명령어 해독 (Instruction Decode)
   S_EX_R = 4'b0010,   // 실행: R/I 타입 ALU 연산
   S_EX_M = 4'b0011,   // 실행: Load/Store 주소 계산
   S_EX_B = 4'b0100,   // 실행: Branch 조건 판정
   S_EX_U = 4'b0101,   // 실행: U/J 타입 처리
   S_MEM  = 4'b0110,   // 메모리 접근 (Load/Store)
   S_WB_R = 4'b0111,   // 쓰기 복귀: ALU 결과 → 레지스터
   S_WB_M = 4'b1000,   // 쓰기 복귀: 메모리 데이터 → 레지스터
   S_WB_U = 4'b1001    // 쓰기 복귀: U/J 타입 결과 → 레지스터
} fsm_state_t;

// --------------------------------------------------------------------------
// ALU 소스 선택 (ALUSrcA, ALUSrcB)
// --------------------------------------------------------------------------
typedef enum logic [1:0] {
   ALUSRC_A_RS1  = 2'b00,  // 레지스터 A (rs1)
   ALUSRC_A_PC   = 2'b01,  // 프로그램 카운터
   ALUSRC_A_ZERO = 2'b10   // 0 (LUI용)
} alu_src_a_t;

typedef enum logic [1:0] {
   ALUSRC_B_RS2  = 2'b00,  // 레지스터 B (rs2)
   ALUSRC_B_IMM  = 2'b01,  // 즉치수 (Immediate)
   ALUSRC_B_4    = 2'b10   // 상수 4 (PC+4 계산용)
} alu_src_b_t;

// --------------------------------------------------------------------------
// FSM 제어 유닛 모듈
// --------------------------------------------------------------------------
module fsm_control_unit (
   // --- 클럭 및 리셋 ---
   input  logic        clk,
   input  logic        rst_n,       // 비동기 액티브 로우 리셋

   // --- 명령어 필드 입력 ---
   input  logic [6:0]  opcode,      // 명령어 opcode 필드
   input  logic [2:0]  funct3,      // funct3 필드
   input  logic [6:0]  funct7,      // funct7 필드

   // --- 분기 비교 결과 ---
   input  logic        branch_taken, // 분기 조건 성립 여부

   // --- 데이터패스 제어 신호 출력 ---
   output logic        pc_write,     // PC 갱신 인에이블
   output logic        ir_write,     // 명령어 레지스터(IR) 갱신 인에이블
   output logic        reg_write,    // 레지스터 파일 쓰기 인에이블
   output logic        mem_read,     // 메모리 읽기 인에이블
   output logic        mem_write,    // 메모리 쓰기 인에이블
   output logic        i_or_d,       // 메모리 주소 선택: 0=PC(명령어), 1=ALUOut(데이터)
   output alu_src_a_t  alu_src_a,    // ALU A 입력 선택
   output alu_src_b_t  alu_src_b,    // ALU B 입력 선택
   output logic [3:0]  alu_op,       // ALU 연산 코드
   output logic [1:0]  reg_src,      // 레지스터 쓰기 데이터 소스
                                     // 00: ALUOut, 01: MDR, 10: PC
   output logic [1:0]  pc_src,       // PC 소스: 00: ALU결과, 01: ALUOut, 10: Jump주소

   // --- 상태 출력 (디버깅/관찰용) ---
   output fsm_state_t  current_state
);

   // =======================================================================
   // 상태 레지스터 (Sequential Logic)
   // =======================================================================
   // always_ff 블록: 클럭 상승 에지에서 상태 전이 수행
   // 리셋 시 S_IF 상태로 초기화
   // =======================================================================
   fsm_state_t state_reg, state_next;

   always_ff @(posedge clk or negedge rst_n) begin
      if (!rst_n)
         state_reg <= S_IF;
      else
         state_reg <= state_next;
   end

   assign current_state = state_reg;

   // =======================================================================
   // opcode 상수 정의 (Ch06 디코더와 동일)
   // =======================================================================
   localparam logic [6:0] OP_R_TYPE = 7'b0110011;
   localparam logic [6:0] OP_I_TYPE = 7'b0010011;
   localparam logic [6:0] OP_LOAD   = 7'b0000011;
   localparam logic [6:0] OP_STORE  = 7'b0100011;
   localparam logic [6:0] OP_BRANCH = 7'b1100011;
   localparam logic [6:0] OP_JAL    = 7'b1101111;
   localparam logic [6:0] OP_JALR   = 7'b1100111;
   localparam logic [6:0] OP_LUI    = 7'b0110111;
   localparam logic [6:0] OP_AUIPC  = 7'b0010111;

   // =======================================================================
   // 다음 상태 로직 (Combinational Logic)
   // =======================================================================
   // 현재 상태와 opcode에 따라 다음 상태를 결정
   // FSM의 "분기"는 ID 상태에서 발생 — 명령어 타입별로 다른 EX 상태로 전이
   // =======================================================================
   always_comb begin
      // 기본값: 안전한 기본 상태 (래치 방지)
      state_next = S_IF;

      case (state_reg)
         // ---------------------------------------------------------------
         // IF: 명령어 인출 → 항상 ID로 전이
         // ---------------------------------------------------------------
         S_IF: begin
            state_next = S_ID;
         end

         // ---------------------------------------------------------------
         // ID: 명령어 해독 → opcode에 따라 적절한 EX 상태로 분기
         // ---------------------------------------------------------------
         S_ID: begin
            case (opcode)
               OP_R_TYPE: state_next = S_EX_R;   // R 타입 → ALU 실행
               OP_I_TYPE: state_next = S_EX_R;   // I 타입 → ALU 실행 (동일 경로)
               OP_LOAD:   state_next = S_EX_M;   // Load → 주소 계산
               OP_STORE:  state_next = S_EX_M;   // Store → 주소 계산
               OP_BRANCH: state_next = S_EX_B;   // Branch → 조건 판정
               OP_JAL:    state_next = S_EX_U;   // JAL → U/J 처리
               OP_JALR:   state_next = S_EX_U;   // JALR → U/J 처리
               OP_LUI:    state_next = S_EX_U;   // LUI → U 처리
               OP_AUIPC:  state_next = S_EX_U;   // AUIPC → U 처리
               default:   state_next = S_IF;      // 미정의 → 리셋
            endcase
         end

         // ---------------------------------------------------------------
         // EX_R: R/I 타입 ALU 실행 → WB로 전이
         // ---------------------------------------------------------------
         S_EX_R: begin
            state_next = S_WB_R;
         end

         // ---------------------------------------------------------------
         // EX_M: Load/Store 주소 계산 → MEM으로 전이
         // ---------------------------------------------------------------
         S_EX_M: begin
            state_next = S_MEM;
         end

         // ---------------------------------------------------------------
         // EX_B: Branch 조건 판정 → IF로 복귀 (3사이클 완료)
         // ---------------------------------------------------------------
         S_EX_B: begin
            state_next = S_IF;
         end

         // ---------------------------------------------------------------
         // EX_U: U/J 타입 실행 → WB로 전이
         // ---------------------------------------------------------------
         S_EX_U: begin
            state_next = S_WB_U;
         end

         // ---------------------------------------------------------------
         // MEM: 메모리 접근
         //   - Load → WB_M (메모리 데이터 기록)
         //   - Store → IF (4사이클 완료)
         // ---------------------------------------------------------------
         S_MEM: begin
            if (opcode == OP_LOAD)
               state_next = S_WB_M;
            else
               state_next = S_IF;   // Store 완료
         end

         // ---------------------------------------------------------------
         // WB_R: R/I 타입 결과 레지스터 기록 → IF (4사이클 완료)
         // ---------------------------------------------------------------
         S_WB_R: begin
            state_next = S_IF;
         end

         // ---------------------------------------------------------------
         // WB_M: Load 데이터 레지스터 기록 → IF (5사이클 완료)
         // ---------------------------------------------------------------
         S_WB_M: begin
            state_next = S_IF;
         end

         // ---------------------------------------------------------------
         // WB_U: U/J 타입 결과 레지스터 기록 → IF (4사이클 완료)
         // ---------------------------------------------------------------
         S_WB_U: begin
            state_next = S_IF;
         end

         default: begin
            state_next = S_IF;
         end
      endcase
   end

   // =======================================================================
   // 출력 로직 (Combinational Logic) — Moore 방식
   // =======================================================================
   // 현재 상태에 의해서만 출력이 결정됨 (입력 무관)
   // 각 상태마다 필요한 제어 신호를 활성화
   // =======================================================================
   always_comb begin
      // 모든 출력 기본값 = 비활성 (래치 방지)
      pc_write  = 1'b0;
      ir_write  = 1'b0;
      reg_write = 1'b0;
      mem_read  = 1'b0;
      mem_write = 1'b0;
      i_or_d    = 1'b0;
      alu_src_a = ALUSRC_A_RS1;
      alu_src_b = ALUSRC_B_RS2;
      alu_op    = 4'b0000;   // ADD
      reg_src   = 2'b00;     // ALUOut
      pc_src    = 2'b00;     // ALU 결과

      case (state_reg)
         // ---------------------------------------------------------------
         // S_IF: 명령어 인출
         //   - PC가 가리키는 메모리에서 명령어 읽기
         //   - IR에 명령어 저장
         //   - PC = PC + 4 (다음 명령어 준비)
         // ---------------------------------------------------------------
         S_IF: begin
            mem_read  = 1'b1;     // 메모리 읽기
            i_or_d    = 1'b0;     // 주소 = PC (명령어 메모리)
            ir_write  = 1'b1;     // IR에 명령어 저장
            alu_src_a = ALUSRC_A_PC;   // ALU A = PC
            alu_src_b = ALUSRC_B_4;    // ALU B = 4
            alu_op    = 4'b0000;  // ADD: PC + 4
            pc_write  = 1'b1;     // PC 갱신
            pc_src    = 2'b00;    // PC ← ALU 결과 (PC+4)
         end

         // ---------------------------------------------------------------
         // S_ID: 명령어 해독
         //   - 레지스터 파일에서 rs1, rs2 읽기 → A, B 레지스터에 저장
         //   - 즉치수 부호 확장 (자동)
         //   - 분기/점프 목표 주소 미리 계산: ALUOut = PC + Imm
         // ---------------------------------------------------------------
         S_ID: begin
            alu_src_a = ALUSRC_A_PC;   // ALU A = PC
            alu_src_b = ALUSRC_B_IMM;  // ALU B = 즉치수
            alu_op    = 4'b0000;       // ADD: PC + Imm (분기 목표)
         end

         // ---------------------------------------------------------------
         // S_EX_R: R/I 타입 ALU 실행
         //   - ALU A = rs1 (레지스터 A)
         //   - ALU B = rs2 (R 타입) 또는 Imm (I 타입)
         //   - ALU 연산 = funct3/funct7에 따라 결정
         // ---------------------------------------------------------------
         S_EX_R: begin
            alu_src_a = ALUSRC_A_RS1;
            // R 타입: rs2, I 타입: 즉치수
            alu_src_b = (opcode == OP_R_TYPE) ? ALUSRC_B_RS2 : ALUSRC_B_IMM;
            // ALU 연산 코드는 funct3/funct7에서 도출
            alu_op = alu_decode(opcode, funct3, funct7);
         end

         // ---------------------------------------------------------------
         // S_EX_M: Load/Store 주소 계산
         //   - ALU A = rs1 (베이스 주소)
         //   - ALU B = Imm (오프셋)
         //   - ALU 연산 = ADD (주소 = base + offset)
         // ---------------------------------------------------------------
         S_EX_M: begin
            alu_src_a = ALUSRC_A_RS1;
            alu_src_b = ALUSRC_B_IMM;
            alu_op    = 4'b0000;       // ADD
         end

         // ---------------------------------------------------------------
         // S_EX_B: Branch 조건 판정
         //   - ALU A = rs1, ALU B = rs2 (비교 연산)
         //   - 분기 성립 시 PC ← ALUOut (ID에서 계산한 PC+Imm)
         //   - 분기 불성립 시 PC 유지 (이미 PC+4)
         // ---------------------------------------------------------------
         S_EX_B: begin
            alu_src_a = ALUSRC_A_RS1;
            alu_src_b = ALUSRC_B_RS2;
            alu_op    = 4'b0001;       // SUB (비교용)
            if (branch_taken) begin
               pc_write = 1'b1;
               pc_src   = 2'b01;       // PC ← ALUOut (분기 목표)
            end
         end

         // ---------------------------------------------------------------
         // S_EX_U: U/J 타입 실행
         //   - LUI:   ALUOut = 0 + Imm (상위 20비트)
         //   - AUIPC: ALUOut = PC + Imm
         //   - JAL:   PC ← ALUOut (ID에서 계산), rd = PC+4
         //   - JALR:  PC ← rs1 + Imm, rd = PC+4
         // ---------------------------------------------------------------
         S_EX_U: begin
            case (opcode)
               OP_LUI: begin
                  alu_src_a = ALUSRC_A_ZERO;  // 0
                  alu_src_b = ALUSRC_B_IMM;   // 즉치수
                  alu_op    = 4'b0000;         // ADD: 0 + Imm
               end
               OP_AUIPC: begin
                  alu_src_a = ALUSRC_A_PC;
                  alu_src_b = ALUSRC_B_IMM;
                  alu_op    = 4'b0000;         // ADD: PC + Imm
               end
               OP_JAL: begin
                  pc_write = 1'b1;
                  pc_src   = 2'b01;            // PC ← ALUOut (ID 계산)
                  alu_src_a = ALUSRC_A_PC;
                  alu_src_b = ALUSRC_B_4;
                  alu_op    = 4'b0000;         // ALU: PC + 4 (복귀 주소)
               end
               OP_JALR: begin
                  pc_write = 1'b1;
                  alu_src_a = ALUSRC_A_RS1;
                  alu_src_b = ALUSRC_B_IMM;
                  alu_op    = 4'b0000;         // ALU: rs1 + Imm
                  pc_src   = 2'b00;            // PC ← ALU 결과
               end
               default: ;
            endcase
         end

         // ---------------------------------------------------------------
         // S_MEM: 메모리 접근
         //   - Load:  주소 = ALUOut, 메모리 읽기
         //   - Store: 주소 = ALUOut, 메모리 쓰기
         // ---------------------------------------------------------------
         S_MEM: begin
            i_or_d = 1'b1;   // 주소 = ALUOut (데이터 주소)
            if (opcode == OP_LOAD) begin
               mem_read = 1'b1;
            end else begin
               mem_write = 1'b1;
            end
         end

         // ---------------------------------------------------------------
         // S_WB_R: R/I 타입 결과를 레지스터에 기록
         // ---------------------------------------------------------------
         S_WB_R: begin
            reg_write = 1'b1;
            reg_src   = 2'b00;   // ALUOut → rd
         end

         // ---------------------------------------------------------------
         // S_WB_M: Load 데이터를 레지스터에 기록
         // ---------------------------------------------------------------
         S_WB_M: begin
            reg_write = 1'b1;
            reg_src   = 2'b01;   // MDR → rd
         end

         // ---------------------------------------------------------------
         // S_WB_U: U/J 타입 결과를 레지스터에 기록
         //   - LUI/AUIPC: ALUOut → rd
         //   - JAL/JALR:  PC+4 (이전 PC) → rd
         // ---------------------------------------------------------------
         S_WB_U: begin
            reg_write = 1'b1;
            if (opcode == OP_JAL || opcode == OP_JALR)
               reg_src = 2'b10;  // PC (복귀 주소) → rd
            else
               reg_src = 2'b00;  // ALUOut → rd
         end

         default: ;
      endcase
   end

   // =======================================================================
   // ALU 연산 디코딩 함수
   // =======================================================================
   // funct3, funct7을 기반으로 ALU 연산 코드를 결정
   // Ch06 디코더의 로직을 재사용
   // =======================================================================
   function automatic logic [3:0] alu_decode(
      input logic [6:0] op,
      input logic [2:0] f3,
      input logic [6:0] f7
   );
      case (f3)
         3'b000: begin
            if (op == OP_R_TYPE && f7[5])
               alu_decode = 4'b0001;  // SUB
            else
               alu_decode = 4'b0000;  // ADD / ADDI
         end
         3'b001: alu_decode = 4'b0101;  // SLL / SLLI
         3'b010: alu_decode = 4'b1000;  // SLT / SLTI
         3'b011: alu_decode = 4'b1001;  // SLTU / SLTIU
         3'b100: alu_decode = 4'b0100;  // XOR / XORI
         3'b101: begin
            if (f7[5])
               alu_decode = 4'b0111;  // SRA / SRAI
            else
               alu_decode = 4'b0110;  // SRL / SRLI
         end
         3'b110: alu_decode = 4'b0011;  // OR / ORI
         3'b111: alu_decode = 4'b0010;  // AND / ANDI
         default: alu_decode = 4'b0000;
      endcase
   endfunction

endmodule
