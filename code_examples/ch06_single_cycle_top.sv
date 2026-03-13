// ============================================================================
// RV32I 단일 사이클 프로세서 Top-Level
// Chapter 06 — 제어 유닛과 단일 사이클 통합
// RISC-V 프로세서 설계 완전정복
// ============================================================================
// Ch04 (ALU, RF, ImmGen) + Ch05 (IMEM, DMEM) + Ch06 (Control Unit) 통합
// 37개 RV32I 명령어 지원, 단일 사이클 실행
// ============================================================================

`timescale 1ns / 1ps

module rv32i_single_cycle_top #(
   parameter IMEM_DEPTH = 1024,   // 명령어 메모리 깊이 (워드 단위)
   parameter DMEM_DEPTH = 1024,   // 데이터 메모리 깊이 (워드 단위)
   parameter IMEM_INIT  = ""      // 명령어 메모리 초기화 파일 (.hex)
)(
   input  logic        clk,       // 시스템 클록
   input  logic        rst_n      // 비동기 리셋 (액티브 로우)
);

   // =======================================================================
   // 내부 신호 선언
   // =======================================================================

   // --- PC 관련 ---
   logic [31:0] pc;               // 현재 프로그램 카운터
   logic [31:0] pc_plus4;         // PC + 4
   logic [31:0] pc_next;          // 다음 PC 값

   // --- 명령어 ---
   logic [31:0] instr;            // 현재 명령어

   // --- 레지스터 파일 ---
   logic [31:0] rs1_data;         // rs1 읽기 데이터
   logic [31:0] rs2_data;         // rs2 읽기 데이터
   logic [31:0] rd_data;          // rd 쓰기 데이터

   // --- 즉치수 ---
   logic [31:0] imm;              // 부호 확장된 즉치수

   // --- ALU ---
   logic [31:0] alu_a;            // ALU A 입력
   logic [31:0] alu_b;            // ALU B 입력
   logic [31:0] alu_result;       // ALU 출력

   // --- 메모리 ---
   logic [31:0] dmem_rdata;       // DMEM 읽기 데이터
   logic [31:0] dmem_rdata_ext;   // 부호/무부호 확장된 DMEM 데이터

   // --- 제어 신호 ---
   alu_op_t     alu_sel;
   imm_sel_t    imm_sel;
   logic        reg_w_en;
   mem_rw_t     mem_rw;
   pc_sel_t     pc_sel;
   wb_sel_t     wb_sel;
   logic        a_sel;
   logic        b_sel;
   logic        br_un;
   logic        illegal_instr;

   // --- 명령어 필드 ---
   logic [4:0]  rs1_addr;
   logic [4:0]  rs2_addr;
   logic [4:0]  rd_addr;
   logic [2:0]  funct3;

   // =======================================================================
   // 1. 프로그램 카운터 (PC)
   // =======================================================================
   assign pc_plus4 = pc + 32'd4;

   always_ff @(posedge clk or negedge rst_n) begin
      if (!rst_n)
         pc <= 32'h0000_0000;
      else
         pc <= pc_next;
   end

   // PC 다음 값 선택 (MUX)
   always_comb begin
      case (pc_sel)
         PC_PLUS4:  pc_next = pc_plus4;
         PC_BRANCH: pc_next = alu_result;         // 분기/JAL 목표 주소
         PC_JALR:   pc_next = alu_result & 32'hFFFF_FFFE; // JALR: LSB=0 강제
         default:   pc_next = pc_plus4;
      endcase
   end

   // =======================================================================
   // 2. 명령어 메모리 (IMEM) — 비동기 읽기 ROM
   // =======================================================================
   instruction_memory #(
      .DEPTH     (IMEM_DEPTH),
      .INIT_FILE (IMEM_INIT)
   ) u_imem (
      .addr  (pc),
      .instr (instr)
   );

   // =======================================================================
   // 3. 제어 유닛
   // =======================================================================
   control_unit u_control (
      .instr         (instr),
      .rs1_data      (rs1_data),
      .rs2_data      (rs2_data),
      .alu_sel       (alu_sel),
      .imm_sel       (imm_sel),
      .reg_w_en      (reg_w_en),
      .mem_rw        (mem_rw),
      .pc_sel        (pc_sel),
      .wb_sel        (wb_sel),
      .a_sel         (a_sel),
      .b_sel         (b_sel),
      .br_un         (br_un),
      .illegal_instr (illegal_instr),
      .rs1_addr      (rs1_addr),
      .rs2_addr      (rs2_addr),
      .rd_addr       (rd_addr),
      .funct3_out    (funct3)
   );

   // =======================================================================
   // 4. 레지스터 파일 (32x32-bit, 비동기 읽기, 동기 쓰기)
   // =======================================================================
   register_file u_rf (
      .clk      (clk),
      .rst_n    (rst_n),
      .rs1_addr (rs1_addr),
      .rs2_addr (rs2_addr),
      .rd_addr  (rd_addr),
      .rd_data  (rd_data),
      .reg_w_en (reg_w_en),
      .rs1_data (rs1_data),
      .rs2_data (rs2_data)
   );

   // =======================================================================
   // 5. 즉치수 생성기 (Immediate Generator)
   // =======================================================================
   immediate_generator u_immgen (
      .instr   (instr),
      .imm_sel (imm_sel),
      .imm     (imm)
   );

   // =======================================================================
   // 6. ALU 입력 멀티플렉서
   // =======================================================================
   // A 입력: rs1 또는 PC
   assign alu_a = a_sel ? pc : rs1_data;

   // B 입력: rs2 또는 즉치수
   assign alu_b = b_sel ? imm : rs2_data;

   // =======================================================================
   // 7. ALU
   // =======================================================================
   alu u_alu (
      .a      (alu_a),
      .b      (alu_b),
      .alu_op (alu_sel),
      .result (alu_result)
   );

   // =======================================================================
   // 8. 데이터 메모리 (DMEM)
   // =======================================================================
   data_memory #(
      .DEPTH (DMEM_DEPTH)
   ) u_dmem (
      .clk    (clk),
      .addr   (alu_result),
      .wdata  (rs2_data),
      .mem_rw (mem_rw),
      .funct3 (funct3),
      .rdata  (dmem_rdata)
   );

   // --- 로드 데이터 부호/무부호 확장 ---
   always_comb begin
      case (funct3)
         3'b000: // LB (부호 확장)
            dmem_rdata_ext = {{24{dmem_rdata[7]}}, dmem_rdata[7:0]};
         3'b001: // LH (부호 확장)
            dmem_rdata_ext = {{16{dmem_rdata[15]}}, dmem_rdata[15:0]};
         3'b010: // LW (전체 워드)
            dmem_rdata_ext = dmem_rdata;
         3'b100: // LBU (무부호 확장)
            dmem_rdata_ext = {24'b0, dmem_rdata[7:0]};
         3'b101: // LHU (무부호 확장)
            dmem_rdata_ext = {16'b0, dmem_rdata[15:0]};
         default:
            dmem_rdata_ext = dmem_rdata;
      endcase
   end

   // =======================================================================
   // 9. Write-Back 멀티플렉서
   // =======================================================================
   always_comb begin
      case (wb_sel)
         WB_ALU: rd_data = alu_result;
         WB_MEM: rd_data = dmem_rdata_ext;
         WB_PC4: rd_data = pc_plus4;
         default: rd_data = alu_result;
      endcase
   end

endmodule

// ============================================================================
// 명령어 메모리 (Instruction Memory)
// ============================================================================
// 비동기 읽기 ROM — $readmemh로 .hex 파일 초기화
// ============================================================================
module instruction_memory #(
   parameter DEPTH     = 1024,
   parameter INIT_FILE = ""
)(
   input  logic [31:0] addr,
   output logic [31:0] instr
);

   logic [31:0] mem [0:DEPTH-1];

   // 초기화
   initial begin
      // 메모리를 NOP(ADDI x0, x0, 0 = 0x00000013)으로 초기화
      for (int i = 0; i < DEPTH; i++)
         mem[i] = 32'h0000_0013;

      if (INIT_FILE != "")
         $readmemh(INIT_FILE, mem);
   end

   // 비동기 읽기 (워드 정렬 주소)
   assign instr = mem[addr[31:2]];

endmodule

// ============================================================================
// 데이터 메모리 (Data Memory)
// ============================================================================
// 동기 쓰기, 비동기 읽기
// 바이트/하프워드/워드 접근 지원
// ============================================================================
module data_memory #(
   parameter DEPTH = 1024
)(
   input  logic        clk,
   input  logic [31:0] addr,
   input  logic [31:0] wdata,
   input  mem_rw_t     mem_rw,
   input  logic [2:0]  funct3,
   output logic [31:0] rdata
);

   logic [7:0] mem [0:DEPTH*4-1];   // 바이트 주소 지정 메모리

   // --- 메모리 초기화 ---
   initial begin
      for (int i = 0; i < DEPTH*4; i++)
         mem[i] = 8'h00;
   end

   // --- 동기 쓰기 ---
   always_ff @(posedge clk) begin
      if (mem_rw == MEM_WRITE) begin
         case (funct3)
            3'b000: begin // SB
               mem[addr[31:0]] <= wdata[7:0];
            end
            3'b001: begin // SH
               mem[addr[31:0]]     <= wdata[7:0];
               mem[addr[31:0] + 1] <= wdata[15:8];
            end
            3'b010: begin // SW
               mem[addr[31:0]]     <= wdata[7:0];
               mem[addr[31:0] + 1] <= wdata[15:8];
               mem[addr[31:0] + 2] <= wdata[23:16];
               mem[addr[31:0] + 3] <= wdata[31:24];
            end
            default: ; // 미정의
         endcase
      end
   end

   // --- 비동기 읽기 (리틀 엔디언) ---
   assign rdata = {mem[{addr[31:2], 2'b00} + 3],
                   mem[{addr[31:2], 2'b00} + 2],
                   mem[{addr[31:2], 2'b00} + 1],
                   mem[{addr[31:2], 2'b00}]};

endmodule

// ============================================================================
// 레지스터 파일 (Register File)
// ============================================================================
// 32개 x 32비트 레지스터, x0 = 하드와이어드 0
// 비동기 읽기, 동기 쓰기
// ============================================================================
module register_file (
   input  logic        clk,
   input  logic        rst_n,
   input  logic [4:0]  rs1_addr,
   input  logic [4:0]  rs2_addr,
   input  logic [4:0]  rd_addr,
   input  logic [31:0] rd_data,
   input  logic        reg_w_en,
   output logic [31:0] rs1_data,
   output logic [31:0] rs2_data
);

   logic [31:0] regs [0:31];

   // --- 레지스터 초기화 ---
   initial begin
      for (int i = 0; i < 32; i++)
         regs[i] = 32'h0;
   end

   // --- 비동기 읽기 (x0은 항상 0) ---
   assign rs1_data = (rs1_addr == 5'd0) ? 32'h0 : regs[rs1_addr];
   assign rs2_data = (rs2_addr == 5'd0) ? 32'h0 : regs[rs2_addr];

   // --- 동기 쓰기 (x0 쓰기 방지) ---
   always_ff @(posedge clk or negedge rst_n) begin
      if (!rst_n) begin
         for (int i = 0; i < 32; i++)
            regs[i] <= 32'h0;
      end else if (reg_w_en && rd_addr != 5'd0) begin
         regs[rd_addr] <= rd_data;
      end
   end

endmodule

// ============================================================================
// 즉치수 생성기 (Immediate Generator)
// ============================================================================
// 명령어에서 즉치수를 추출하고 32비트로 부호 확장
// ============================================================================
module immediate_generator (
   input  logic [31:0]  instr,
   input  imm_sel_t     imm_sel,
   output logic [31:0]  imm
);

   always_comb begin
      case (imm_sel)
         // I 타입: instr[31:20]
         IMM_I: imm = {{20{instr[31]}}, instr[31:20]};

         // S 타입: {instr[31:25], instr[11:7]}
         IMM_S: imm = {{20{instr[31]}}, instr[31:25], instr[11:7]};

         // B 타입: {instr[12], instr[10:5], instr[4:1], instr[11], 1'b0}
         IMM_B: imm = {{19{instr[31]}}, instr[31], instr[7],
                        instr[30:25], instr[11:8], 1'b0};

         // U 타입: {instr[31:12], 12'b0}
         IMM_U: imm = {instr[31:12], 12'b0};

         // J 타입: {instr[20], instr[10:1], instr[11], instr[19:12], 12'b0} → 부호확장
         IMM_J: imm = {{11{instr[31]}}, instr[31], instr[19:12],
                        instr[20], instr[30:21], 1'b0};

         default: imm = 32'h0;
      endcase
   end

endmodule

// ============================================================================
// ALU (Arithmetic Logic Unit)
// ============================================================================
// 10가지 연산 지원: ADD, SUB, AND, OR, XOR, SLL, SRL, SRA, SLT, SLTU
// ============================================================================
module alu (
   input  logic [31:0] a,
   input  logic [31:0] b,
   input  alu_op_t     alu_op,
   output logic [31:0] result
);

   always_comb begin
      case (alu_op)
         ALU_ADD:  result = a + b;
         ALU_SUB:  result = a - b;
         ALU_AND:  result = a & b;
         ALU_OR:   result = a | b;
         ALU_XOR:  result = a ^ b;
         ALU_SLL:  result = a << b[4:0];
         ALU_SRL:  result = a >> b[4:0];
         ALU_SRA:  result = $signed(a) >>> b[4:0];
         ALU_SLT:  result = {31'b0, $signed(a) < $signed(b)};
         ALU_SLTU: result = {31'b0, a < b};
         default:  result = 32'h0;
      endcase
   end

endmodule