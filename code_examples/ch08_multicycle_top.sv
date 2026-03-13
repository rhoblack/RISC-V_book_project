// ============================================================================
// 멀티사이클 CPU Top-Level 모듈
// Chapter 08 — FSM 기반 제어 유닛
// RISC-V 프로세서 설계 완전정복
// ============================================================================
// Ch07 멀티사이클 데이터패스 + Ch08 FSM 제어 유닛 통합
// RV32I 명령어 세트 지원: R/I/S/B/U/J 타입
// ============================================================================

`timescale 1ns / 1ps

module multicycle_cpu_top (
   input  logic        clk,
   input  logic        rst_n,

   // --- 외부 메모리 인터페이스 ---
   output logic [31:0] mem_addr,     // 메모리 주소
   output logic [31:0] mem_wdata,    // 메모리 쓰기 데이터
   input  logic [31:0] mem_rdata,    // 메모리 읽기 데이터
   output logic        mem_read,     // 메모리 읽기 인에이블
   output logic        mem_write,    // 메모리 쓰기 인에이블

   // --- 디버깅용 출력 ---
   output logic [31:0] debug_pc,     // 현재 PC
   output logic [3:0]  debug_state   // 현재 FSM 상태
);

   // =======================================================================
   // 내부 신호 선언
   // =======================================================================

   // --- 프로그램 카운터 ---
   logic [31:0] pc_reg;        // 프로그램 카운터 레지스터
   logic [31:0] pc_next;       // 다음 PC 값

   // --- 명령어 레지스터 ---
   logic [31:0] ir_reg;        // 명령어 레지스터 (Instruction Register)

   // --- 중간 결과 레지스터 (멀티사이클 핵심) ---
   logic [31:0] a_reg;         // rs1 데이터 래치
   logic [31:0] b_reg;         // rs2 데이터 래치
   logic [31:0] alu_out_reg;   // ALU 결과 래치
   logic [31:0] mdr_reg;       // 메모리 데이터 레지스터 (Memory Data Register)

   // --- 레지스터 파일 ---
   logic [31:0] reg_file [0:31];   // 32개 레지스터 (x0~x31)
   logic [31:0] rs1_data, rs2_data;
   logic [31:0] rd_data;

   // --- 명령어 필드 ---
   logic [6:0]  opcode;
   logic [4:0]  rs1_addr, rs2_addr, rd_addr;
   logic [2:0]  funct3;
   logic [6:0]  funct7;

   // --- 즉치수 (Immediate) ---
   logic [31:0] imm_ext;       // 부호 확장된 즉치수

   // --- ALU ---
   logic [31:0] alu_a, alu_b;  // ALU 입력
   logic [31:0] alu_result;    // ALU 출력

   // --- 분기 비교 ---
   logic        branch_taken;

   // --- 제어 신호 ---
   logic        pc_write;
   logic        ir_write;
   logic        reg_write_en;
   logic        ctrl_mem_read;
   logic        ctrl_mem_write;
   logic        i_or_d;
   alu_src_a_t  alu_src_a;
   alu_src_b_t  alu_src_b;
   logic [3:0]  alu_op;
   logic [1:0]  reg_src;
   logic [1:0]  pc_src;
   fsm_state_t  current_state;

   // =======================================================================
   // 명령어 필드 추출
   // =======================================================================
   assign opcode   = ir_reg[6:0];
   assign rd_addr  = ir_reg[11:7];
   assign funct3   = ir_reg[14:12];
   assign rs1_addr = ir_reg[19:15];
   assign rs2_addr = ir_reg[24:20];
   assign funct7   = ir_reg[31:25];

   // =======================================================================
   // FSM 제어 유닛 인스턴스
   // =======================================================================
   fsm_control_unit u_fsm_ctrl (
      .clk           (clk),
      .rst_n         (rst_n),
      .opcode        (opcode),
      .funct3        (funct3),
      .funct7        (funct7),
      .branch_taken  (branch_taken),
      .pc_write      (pc_write),
      .ir_write      (ir_write),
      .reg_write     (reg_write_en),
      .mem_read      (ctrl_mem_read),
      .mem_write     (ctrl_mem_write),
      .i_or_d        (i_or_d),
      .alu_src_a     (alu_src_a),
      .alu_src_b     (alu_src_b),
      .alu_op        (alu_op),
      .reg_src       (reg_src),
      .pc_src        (pc_src),
      .current_state (current_state)
   );

   // =======================================================================
   // 프로그램 카운터 (PC)
   // =======================================================================
   always_ff @(posedge clk or negedge rst_n) begin
      if (!rst_n)
         pc_reg <= 32'h0000_0000;
      else if (pc_write)
         pc_reg <= pc_next;
   end

   // PC 소스 멀티플렉서
   always_comb begin
      case (pc_src)
         2'b00:   pc_next = alu_result;   // ALU 결과 (PC+4 또는 JALR)
         2'b01:   pc_next = alu_out_reg;  // ALUOut (분기/JAL 목표)
         2'b10:   pc_next = alu_result;   // 점프 주소
         default: pc_next = alu_result;
      endcase
   end

   // =======================================================================
   // 명령어 레지스터 (IR)
   // =======================================================================
   always_ff @(posedge clk or negedge rst_n) begin
      if (!rst_n)
         ir_reg <= 32'h0000_0013;   // NOP (ADDI x0, x0, 0)
      else if (ir_write)
         ir_reg <= mem_rdata;
   end

   // =======================================================================
   // 메모리 인터페이스
   // =======================================================================
   // IorD 멀티플렉서: 명령어 주소(PC) 또는 데이터 주소(ALUOut)
   assign mem_addr  = i_or_d ? alu_out_reg : pc_reg;
   assign mem_wdata = b_reg;
   assign mem_read  = ctrl_mem_read;
   assign mem_write = ctrl_mem_write;

   // =======================================================================
   // 메모리 데이터 레지스터 (MDR)
   // =======================================================================
   always_ff @(posedge clk) begin
      mdr_reg <= mem_rdata;
   end

   // =======================================================================
   // 레지스터 파일
   // =======================================================================
   // 비동기 읽기 (조합 로직)
   assign rs1_data = (rs1_addr == 5'd0) ? 32'd0 : reg_file[rs1_addr];
   assign rs2_data = (rs2_addr == 5'd0) ? 32'd0 : reg_file[rs2_addr];

   // 동기 쓰기
   always_ff @(posedge clk or negedge rst_n) begin
      if (!rst_n) begin
         for (int i = 0; i < 32; i++)
            reg_file[i] <= 32'd0;
      end else if (reg_write_en && rd_addr != 5'd0) begin
         reg_file[rd_addr] <= rd_data;
      end
   end

   // 레지스터 쓰기 데이터 소스 멀티플렉서
   always_comb begin
      case (reg_src)
         2'b00:   rd_data = alu_out_reg;  // ALU 결과
         2'b01:   rd_data = mdr_reg;      // 메모리 데이터 (Load)
         2'b10:   rd_data = pc_reg;       // PC (JAL/JALR 복귀 주소)
         default: rd_data = alu_out_reg;
      endcase
   end

   // =======================================================================
   // A, B 레지스터 (중간 결과 래치)
   // =======================================================================
   always_ff @(posedge clk) begin
      a_reg <= rs1_data;
      b_reg <= rs2_data;
   end

   // =======================================================================
   // 즉치수 생성기 (Immediate Generator)
   // =======================================================================
   // Ch04에서 설계한 즉치수 생성기와 동일한 로직
   always_comb begin
      case (opcode)
         // I 타입: ADDI, SLTI, Load, JALR 등
         7'b0010011, 7'b0000011, 7'b1100111:
            imm_ext = {{20{ir_reg[31]}}, ir_reg[31:20]};

         // S 타입: Store
         7'b0100011:
            imm_ext = {{20{ir_reg[31]}}, ir_reg[31:25], ir_reg[11:7]};

         // B 타입: Branch
         7'b1100011:
            imm_ext = {{19{ir_reg[31]}}, ir_reg[31], ir_reg[7],
                        ir_reg[30:25], ir_reg[11:8], 1'b0};

         // U 타입: LUI, AUIPC
         7'b0110111, 7'b0010111:
            imm_ext = {ir_reg[31:12], 12'd0};

         // J 타입: JAL
         7'b1101111:
            imm_ext = {{11{ir_reg[31]}}, ir_reg[31], ir_reg[19:12],
                        ir_reg[20], ir_reg[30:21], 1'b0};

         default:
            imm_ext = 32'd0;
      endcase
   end

   // =======================================================================
   // ALU 입력 멀티플렉서
   // =======================================================================
   always_comb begin
      // ALU A 입력
      case (alu_src_a)
         ALUSRC_A_RS1:  alu_a = a_reg;     // 레지스터 A
         ALUSRC_A_PC:   alu_a = pc_reg;    // PC
         ALUSRC_A_ZERO: alu_a = 32'd0;     // 0 (LUI용)
         default:       alu_a = a_reg;
      endcase

      // ALU B 입력
      case (alu_src_b)
         ALUSRC_B_RS2:  alu_b = b_reg;     // 레지스터 B
         ALUSRC_B_IMM:  alu_b = imm_ext;   // 즉치수
         ALUSRC_B_4:    alu_b = 32'd4;     // 상수 4
         default:       alu_b = b_reg;
      endcase
   end

   // =======================================================================
   // ALU (Ch04에서 설계한 모듈 재사용)
   // =======================================================================
   always_comb begin
      case (alu_op)
         4'b0000: alu_result = alu_a + alu_b;                          // ADD
         4'b0001: alu_result = alu_a - alu_b;                          // SUB
         4'b0010: alu_result = alu_a & alu_b;                          // AND
         4'b0011: alu_result = alu_a | alu_b;                          // OR
         4'b0100: alu_result = alu_a ^ alu_b;                          // XOR
         4'b0101: alu_result = alu_a << alu_b[4:0];                    // SLL
         4'b0110: alu_result = alu_a >> alu_b[4:0];                    // SRL
         4'b0111: alu_result = $signed(alu_a) >>> alu_b[4:0];          // SRA
         4'b1000: alu_result = {31'd0, $signed(alu_a) < $signed(alu_b)}; // SLT
         4'b1001: alu_result = {31'd0, alu_a < alu_b};                 // SLTU
         default: alu_result = alu_a + alu_b;
      endcase
   end

   // =======================================================================
   // ALUOut 레지스터
   // =======================================================================
   always_ff @(posedge clk) begin
      alu_out_reg <= alu_result;
   end

   // =======================================================================
   // 분기 비교기
   // =======================================================================
   always_comb begin
      branch_taken = 1'b0;
      if (opcode == 7'b1100011) begin
         case (funct3)
            3'b000: branch_taken = (a_reg == b_reg);                     // BEQ
            3'b001: branch_taken = (a_reg != b_reg);                     // BNE
            3'b100: branch_taken = ($signed(a_reg) < $signed(b_reg));    // BLT
            3'b101: branch_taken = ($signed(a_reg) >= $signed(b_reg));   // BGE
            3'b110: branch_taken = (a_reg < b_reg);                      // BLTU
            3'b111: branch_taken = (a_reg >= b_reg);                     // BGEU
            default: branch_taken = 1'b0;
         endcase
      end
   end

   // =======================================================================
   // 디버깅 출력
   // =======================================================================
   assign debug_pc    = pc_reg;
   assign debug_state = current_state;

endmodule
