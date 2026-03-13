// ============================================================================
// RV32I 기본 파이프라인 프로세서 Top-Level (해저드 미처리)
// Chapter 09 — 파이프라인 기초: 스테이지 분할
// RISC-V 프로세서 설계 완전정복
// ============================================================================
// 5단계 파이프라인: IF → ID → EX → MEM → WB
// 해저드 처리 없음 — NOP 삽입 방식으로 동작 확인
// Ch10(데이터 해저드), Ch11(제어 해저드)에서 해저드 처리 추가 예정
// ============================================================================

`timescale 1ns / 1ps

import pipeline_pkg::*;

module rv32i_pipeline_top #(
   parameter IMEM_DEPTH = 1024,   // 명령어 메모리 깊이 (워드 단위)
   parameter DMEM_DEPTH = 1024,   // 데이터 메모리 깊이 (워드 단위)
   parameter IMEM_INIT  = ""      // 명령어 메모리 초기화 파일 (.hex)
)(
   input  logic        clk,       // 시스템 클록
   input  logic        rst_n      // 비동기 리셋 (액티브 로우)
);

   // =======================================================================
   // 신호 선언 — 스테이지별 정리
   // =======================================================================

   // --- IF 스테이지 ---
   logic [31:0] if_pc;
   logic [31:0] if_pc_plus4;
   logic [31:0] if_pc_next;
   logic [31:0] if_instr;

   // --- ID 스테이지 (IF/ID 레지스터 출력) ---
   logic [31:0] id_instr;
   logic [31:0] id_pc;
   logic [31:0] id_pc_plus4;
   logic [31:0] id_rs1_data;
   logic [31:0] id_rs2_data;
   logic [31:0] id_imm;
   logic [4:0]  id_rs1_addr;
   logic [4:0]  id_rs2_addr;
   logic [4:0]  id_rd_addr;
   logic [2:0]  id_funct3;
   ctrl_ex_t    id_ctrl_ex;
   ctrl_mem_t   id_ctrl_mem;
   ctrl_wb_t    id_ctrl_wb;
   imm_sel_t    id_imm_sel;

   // --- EX 스테이지 (ID/EX 레지스터 출력) ---
   logic [31:0] ex_rs1_data;
   logic [31:0] ex_rs2_data;
   logic [31:0] ex_imm;
   logic [31:0] ex_pc;
   logic [31:0] ex_pc_plus4;
   logic [4:0]  ex_rs1_addr;
   logic [4:0]  ex_rs2_addr;
   logic [4:0]  ex_rd_addr;
   logic [2:0]  ex_funct3;
   ctrl_ex_t    ex_ctrl_ex;
   ctrl_mem_t   ex_ctrl_mem;
   ctrl_wb_t    ex_ctrl_wb;

   logic [31:0] ex_alu_a;
   logic [31:0] ex_alu_b;
   logic [31:0] ex_alu_result;

   // --- MEM 스테이지 (EX/MEM 레지스터 출력) ---
   logic [31:0] mem_alu_result;
   logic [31:0] mem_rs2_data;
   logic [31:0] mem_pc_plus4;
   logic [4:0]  mem_rd_addr;
   logic [2:0]  mem_funct3;
   ctrl_mem_t   mem_ctrl_mem;
   ctrl_wb_t    mem_ctrl_wb;
   logic [31:0] mem_dmem_rdata;
   logic [31:0] mem_dmem_rdata_ext;

   // --- WB 스테이지 (MEM/WB 레지스터 출력) ---
   logic [31:0] wb_alu_result;
   logic [31:0] wb_mem_rdata;
   logic [31:0] wb_pc_plus4;
   logic [4:0]  wb_rd_addr;
   ctrl_wb_t    wb_ctrl_wb;
   logic [31:0] wb_rd_data;

   // =======================================================================
   // ★ 스테이지 1: IF (Instruction Fetch)
   // =======================================================================

   // --- PC 레지스터 ---
   always_ff @(posedge clk or negedge rst_n) begin
      if (!rst_n)
         if_pc <= 32'h0000_0000;
      else
         if_pc <= if_pc_next;
   end

   assign if_pc_plus4 = if_pc + 32'd4;

   // --- 다음 PC 선택 ---
   // 해저드 미처리: 항상 PC+4 (분기/점프 무시)
   // Ch11에서 분기/점프 경로 추가 예정
   assign if_pc_next = if_pc_plus4;

   // --- 명령어 메모리 (비동기 읽기) ---
   logic [31:0] imem [0:IMEM_DEPTH-1];

   initial begin
      for (int i = 0; i < IMEM_DEPTH; i++)
         imem[i] = 32'h0000_0013;   // NOP (ADDI x0, x0, 0)
      if (IMEM_INIT != "")
         $readmemh(IMEM_INIT, imem);
   end

   assign if_instr = imem[if_pc[31:2]];

   // =======================================================================
   // 파이프라인 레지스터: IF/ID
   // =======================================================================
   pipe_reg_if_id u_pipe_if_id (
      .clk          (clk),
      .rst_n        (rst_n),
      .if_instr     (if_instr),
      .if_pc        (if_pc),
      .if_pc_plus4  (if_pc_plus4),
      .id_instr     (id_instr),
      .id_pc        (id_pc),
      .id_pc_plus4  (id_pc_plus4)
   );

   // =======================================================================
   // ★ 스테이지 2: ID (Instruction Decode)
   // =======================================================================

   // --- 명령어 필드 추출 ---
   assign id_rs1_addr = id_instr[19:15];
   assign id_rs2_addr = id_instr[24:20];
   assign id_rd_addr  = id_instr[11:7];
   assign id_funct3   = id_instr[14:12];

   // --- 레지스터 파일 (비동기 읽기, 동기 쓰기) ---
   logic [31:0] regfile [0:31];

   initial begin
      for (int i = 0; i < 32; i++)
         regfile[i] = 32'h0;
   end

   // 비동기 읽기 (x0은 항상 0)
   assign id_rs1_data = (id_rs1_addr == 5'd0) ? 32'h0 : regfile[id_rs1_addr];
   assign id_rs2_data = (id_rs2_addr == 5'd0) ? 32'h0 : regfile[id_rs2_addr];

   // 동기 쓰기 (WB 스테이지에서 구동)
   always_ff @(posedge clk or negedge rst_n) begin
      if (!rst_n) begin
         for (int i = 0; i < 32; i++)
            regfile[i] <= 32'h0;
      end else if (wb_ctrl_wb.reg_w_en && wb_rd_addr != 5'd0) begin
         regfile[wb_rd_addr] <= wb_rd_data;
      end
   end

   // --- 즉치수 생성기 ---
   // opcode 기반 즉치수 타입 결정
   logic [6:0] id_opcode;
   assign id_opcode = id_instr[6:0];

   always_comb begin
      case (id_opcode)
         7'b0010011,                    // I 타입 (ADDI, ANDI, ...)
         7'b0000011,                    // Load (LW, LB, ...)
         7'b1100111: id_imm_sel = IMM_I; // JALR
         7'b0100011: id_imm_sel = IMM_S; // Store (SW, SB, ...)
         7'b1100011: id_imm_sel = IMM_B; // Branch (BEQ, BNE, ...)
         7'b0110111,                    // LUI
         7'b0010111: id_imm_sel = IMM_U; // AUIPC
         7'b1101111: id_imm_sel = IMM_J; // JAL
         default:    id_imm_sel = IMM_I; // R 타입 등 (즉치수 미사용)
      endcase
   end

   // 즉치수 부호 확장
   always_comb begin
      case (id_imm_sel)
         IMM_I: id_imm = {{20{id_instr[31]}}, id_instr[31:20]};
         IMM_S: id_imm = {{20{id_instr[31]}}, id_instr[31:25], id_instr[11:7]};
         IMM_B: id_imm = {{19{id_instr[31]}}, id_instr[31], id_instr[7],
                           id_instr[30:25], id_instr[11:8], 1'b0};
         IMM_U: id_imm = {id_instr[31:12], 12'b0};
         IMM_J: id_imm = {{11{id_instr[31]}}, id_instr[31], id_instr[19:12],
                           id_instr[20], id_instr[30:21], 1'b0};
         default: id_imm = 32'h0;
      endcase
   end

   // --- 제어 신호 생성 (간소화 디코더) ---
   logic [6:0] id_funct7;
   assign id_funct7 = id_instr[31:25];

   always_comb begin
      // 기본값: NOP과 동일 (모든 쓰기 비활성)
      id_ctrl_ex  = '{alu_sel: ALU_ADD, a_sel: 1'b0, b_sel: 1'b0};
      id_ctrl_mem = '{mem_rw: MEM_NONE, br_taken: 1'b0};
      id_ctrl_wb  = '{wb_sel: WB_ALU, reg_w_en: 1'b0};

      case (id_opcode)
         // --- R 타입: 레지스터-레지스터 연산 ---
         7'b0110011: begin
            id_ctrl_ex.a_sel  = 1'b0;   // rs1
            id_ctrl_ex.b_sel  = 1'b0;   // rs2
            id_ctrl_wb.wb_sel = WB_ALU;
            id_ctrl_wb.reg_w_en = 1'b1;
            // ALU 연산 선택 (funct7[5]과 funct3 조합)
            case ({id_funct7[5], id_funct3})
               4'b0_000: id_ctrl_ex.alu_sel = ALU_ADD;   // ADD
               4'b1_000: id_ctrl_ex.alu_sel = ALU_SUB;   // SUB
               4'b0_001: id_ctrl_ex.alu_sel = ALU_SLL;   // SLL
               4'b0_010: id_ctrl_ex.alu_sel = ALU_SLT;   // SLT
               4'b0_011: id_ctrl_ex.alu_sel = ALU_SLTU;  // SLTU
               4'b0_100: id_ctrl_ex.alu_sel = ALU_XOR;   // XOR
               4'b0_101: id_ctrl_ex.alu_sel = ALU_SRL;   // SRL
               4'b1_101: id_ctrl_ex.alu_sel = ALU_SRA;   // SRA
               4'b0_110: id_ctrl_ex.alu_sel = ALU_OR;    // OR
               4'b0_111: id_ctrl_ex.alu_sel = ALU_AND;   // AND
               default:  id_ctrl_ex.alu_sel = ALU_ADD;
            endcase
         end

         // --- I 타입: 즉치수 연산 ---
         7'b0010011: begin
            id_ctrl_ex.a_sel  = 1'b0;   // rs1
            id_ctrl_ex.b_sel  = 1'b1;   // imm
            id_ctrl_wb.wb_sel = WB_ALU;
            id_ctrl_wb.reg_w_en = 1'b1;
            case (id_funct3)
               3'b000: id_ctrl_ex.alu_sel = ALU_ADD;   // ADDI
               3'b010: id_ctrl_ex.alu_sel = ALU_SLT;   // SLTI
               3'b011: id_ctrl_ex.alu_sel = ALU_SLTU;  // SLTIU
               3'b100: id_ctrl_ex.alu_sel = ALU_XOR;   // XORI
               3'b110: id_ctrl_ex.alu_sel = ALU_OR;    // ORI
               3'b111: id_ctrl_ex.alu_sel = ALU_AND;   // ANDI
               3'b001: id_ctrl_ex.alu_sel = ALU_SLL;   // SLLI
               3'b101: id_ctrl_ex.alu_sel = id_funct7[5] ? ALU_SRA : ALU_SRL;
               default: id_ctrl_ex.alu_sel = ALU_ADD;
            endcase
         end

         // --- Load 명령어 ---
         7'b0000011: begin
            id_ctrl_ex.a_sel    = 1'b0;      // rs1
            id_ctrl_ex.b_sel    = 1'b1;      // imm (오프셋)
            id_ctrl_ex.alu_sel  = ALU_ADD;   // 주소 계산
            id_ctrl_mem.mem_rw  = MEM_READ;
            id_ctrl_wb.wb_sel   = WB_MEM;
            id_ctrl_wb.reg_w_en = 1'b1;
         end

         // --- Store 명령어 ---
         7'b0100011: begin
            id_ctrl_ex.a_sel    = 1'b0;      // rs1
            id_ctrl_ex.b_sel    = 1'b1;      // imm (오프셋)
            id_ctrl_ex.alu_sel  = ALU_ADD;   // 주소 계산
            id_ctrl_mem.mem_rw  = MEM_WRITE;
            id_ctrl_wb.reg_w_en = 1'b0;      // 레지스터 쓰기 없음
         end

         // --- LUI ---
         7'b0110111: begin
            id_ctrl_ex.a_sel    = 1'b0;
            id_ctrl_ex.b_sel    = 1'b1;      // imm
            id_ctrl_ex.alu_sel  = ALU_ADD;   // 0 + imm (rs1=x0 취급)
            id_ctrl_wb.wb_sel   = WB_ALU;
            id_ctrl_wb.reg_w_en = 1'b1;
         end

         // --- AUIPC ---
         7'b0010111: begin
            id_ctrl_ex.a_sel    = 1'b1;      // PC
            id_ctrl_ex.b_sel    = 1'b1;      // imm
            id_ctrl_ex.alu_sel  = ALU_ADD;   // PC + imm
            id_ctrl_wb.wb_sel   = WB_ALU;
            id_ctrl_wb.reg_w_en = 1'b1;
         end

         // --- JAL ---
         7'b1101111: begin
            id_ctrl_wb.wb_sel   = WB_PC4;   // rd = PC+4
            id_ctrl_wb.reg_w_en = 1'b1;
            // 분기는 이 버전에서 미처리 (Ch11)
         end

         // --- JALR ---
         7'b1100111: begin
            id_ctrl_ex.a_sel    = 1'b0;      // rs1
            id_ctrl_ex.b_sel    = 1'b1;      // imm
            id_ctrl_ex.alu_sel  = ALU_ADD;
            id_ctrl_wb.wb_sel   = WB_PC4;   // rd = PC+4
            id_ctrl_wb.reg_w_en = 1'b1;
            // 점프는 이 버전에서 미처리 (Ch11)
         end

         // --- Branch ---
         7'b1100011: begin
            id_ctrl_ex.a_sel   = 1'b1;       // PC
            id_ctrl_ex.b_sel   = 1'b1;       // imm
            id_ctrl_ex.alu_sel = ALU_ADD;    // 분기 목표 주소 계산
            // 분기 판정은 이 버전에서 미처리 (Ch11)
         end

         default: begin
            // NOP 또는 미정의 명령어
         end
      endcase
   end

   // =======================================================================
   // 파이프라인 레지스터: ID/EX
   // =======================================================================
   pipe_reg_id_ex u_pipe_id_ex (
      .clk          (clk),
      .rst_n        (rst_n),
      // 데이터
      .id_rs1_data  (id_rs1_data),
      .id_rs2_data  (id_rs2_data),
      .id_imm       (id_imm),
      .id_pc        (id_pc),
      .id_pc_plus4  (id_pc_plus4),
      .id_rs1_addr  (id_rs1_addr),
      .id_rs2_addr  (id_rs2_addr),
      .id_rd_addr   (id_rd_addr),
      .id_funct3    (id_funct3),
      // 제어 신호
      .id_ctrl_ex   (id_ctrl_ex),
      .id_ctrl_mem  (id_ctrl_mem),
      .id_ctrl_wb   (id_ctrl_wb),
      // 출력
      .ex_rs1_data  (ex_rs1_data),
      .ex_rs2_data  (ex_rs2_data),
      .ex_imm       (ex_imm),
      .ex_pc        (ex_pc),
      .ex_pc_plus4  (ex_pc_plus4),
      .ex_rs1_addr  (ex_rs1_addr),
      .ex_rs2_addr  (ex_rs2_addr),
      .ex_rd_addr   (ex_rd_addr),
      .ex_funct3    (ex_funct3),
      .ex_ctrl_ex   (ex_ctrl_ex),
      .ex_ctrl_mem  (ex_ctrl_mem),
      .ex_ctrl_wb   (ex_ctrl_wb)
   );

   // =======================================================================
   // ★ 스테이지 3: EX (Execute)
   // =======================================================================

   // --- ALU 입력 멀티플렉서 ---
   assign ex_alu_a = ex_ctrl_ex.a_sel ? ex_pc : ex_rs1_data;
   assign ex_alu_b = ex_ctrl_ex.b_sel ? ex_imm : ex_rs2_data;

   // --- ALU ---
   always_comb begin
      case (ex_ctrl_ex.alu_sel)
         ALU_ADD:  ex_alu_result = ex_alu_a + ex_alu_b;
         ALU_SUB:  ex_alu_result = ex_alu_a - ex_alu_b;
         ALU_AND:  ex_alu_result = ex_alu_a & ex_alu_b;
         ALU_OR:   ex_alu_result = ex_alu_a | ex_alu_b;
         ALU_XOR:  ex_alu_result = ex_alu_a ^ ex_alu_b;
         ALU_SLL:  ex_alu_result = ex_alu_a << ex_alu_b[4:0];
         ALU_SRL:  ex_alu_result = ex_alu_a >> ex_alu_b[4:0];
         ALU_SRA:  ex_alu_result = $signed(ex_alu_a) >>> ex_alu_b[4:0];
         ALU_SLT:  ex_alu_result = {31'b0, $signed(ex_alu_a) < $signed(ex_alu_b)};
         ALU_SLTU: ex_alu_result = {31'b0, ex_alu_a < ex_alu_b};
         default:  ex_alu_result = 32'h0;
      endcase
   end

   // =======================================================================
   // 파이프라인 레지스터: EX/MEM
   // =======================================================================
   pipe_reg_ex_mem u_pipe_ex_mem (
      .clk            (clk),
      .rst_n          (rst_n),
      .ex_alu_result  (ex_alu_result),
      .ex_rs2_data    (ex_rs2_data),
      .ex_pc_plus4    (ex_pc_plus4),
      .ex_rd_addr     (ex_rd_addr),
      .ex_funct3      (ex_funct3),
      .ex_ctrl_mem    (ex_ctrl_mem),
      .ex_ctrl_wb     (ex_ctrl_wb),
      .mem_alu_result (mem_alu_result),
      .mem_rs2_data   (mem_rs2_data),
      .mem_pc_plus4   (mem_pc_plus4),
      .mem_rd_addr    (mem_rd_addr),
      .mem_funct3     (mem_funct3),
      .mem_ctrl_mem   (mem_ctrl_mem),
      .mem_ctrl_wb    (mem_ctrl_wb)
   );

   // =======================================================================
   // ★ 스테이지 4: MEM (Memory Access)
   // =======================================================================

   // --- 데이터 메모리 ---
   logic [7:0] dmem [0:DMEM_DEPTH*4-1];

   initial begin
      for (int i = 0; i < DMEM_DEPTH*4; i++)
         dmem[i] = 8'h00;
   end

   // 동기 쓰기
   always_ff @(posedge clk) begin
      if (mem_ctrl_mem.mem_rw == MEM_WRITE) begin
         case (mem_funct3)
            3'b000: begin // SB
               dmem[mem_alu_result[31:0]] <= mem_rs2_data[7:0];
            end
            3'b001: begin // SH
               dmem[mem_alu_result[31:0]]     <= mem_rs2_data[7:0];
               dmem[mem_alu_result[31:0] + 1] <= mem_rs2_data[15:8];
            end
            3'b010: begin // SW
               dmem[mem_alu_result[31:0]]     <= mem_rs2_data[7:0];
               dmem[mem_alu_result[31:0] + 1] <= mem_rs2_data[15:8];
               dmem[mem_alu_result[31:0] + 2] <= mem_rs2_data[23:16];
               dmem[mem_alu_result[31:0] + 3] <= mem_rs2_data[31:24];
            end
            default: ;
         endcase
      end
   end

   // 비동기 읽기 (리틀 엔디언)
   assign mem_dmem_rdata = {dmem[{mem_alu_result[31:2], 2'b00} + 3],
                            dmem[{mem_alu_result[31:2], 2'b00} + 2],
                            dmem[{mem_alu_result[31:2], 2'b00} + 1],
                            dmem[{mem_alu_result[31:2], 2'b00}]};

   // --- 로드 데이터 부호/무부호 확장 ---
   always_comb begin
      case (mem_funct3)
         3'b000:  mem_dmem_rdata_ext = {{24{mem_dmem_rdata[7]}},  mem_dmem_rdata[7:0]};   // LB
         3'b001:  mem_dmem_rdata_ext = {{16{mem_dmem_rdata[15]}}, mem_dmem_rdata[15:0]};  // LH
         3'b010:  mem_dmem_rdata_ext = mem_dmem_rdata;                                     // LW
         3'b100:  mem_dmem_rdata_ext = {24'b0, mem_dmem_rdata[7:0]};                       // LBU
         3'b101:  mem_dmem_rdata_ext = {16'b0, mem_dmem_rdata[15:0]};                      // LHU
         default: mem_dmem_rdata_ext = mem_dmem_rdata;
      endcase
   end

   // =======================================================================
   // 파이프라인 레지스터: MEM/WB
   // =======================================================================
   pipe_reg_mem_wb u_pipe_mem_wb (
      .clk            (clk),
      .rst_n          (rst_n),
      .mem_alu_result (mem_alu_result),
      .mem_rdata      (mem_dmem_rdata_ext),
      .mem_pc_plus4   (mem_pc_plus4),
      .mem_rd_addr    (mem_rd_addr),
      .mem_ctrl_wb    (mem_ctrl_wb),
      .wb_alu_result  (wb_alu_result),
      .wb_mem_rdata   (wb_mem_rdata),
      .wb_pc_plus4    (wb_pc_plus4),
      .wb_rd_addr     (wb_rd_addr),
      .wb_ctrl_wb     (wb_ctrl_wb)
   );

   // =======================================================================
   // ★ 스테이지 5: WB (Write Back)
   // =======================================================================

   // --- Write-Back 멀티플렉서 ---
   always_comb begin
      case (wb_ctrl_wb.wb_sel)
         WB_ALU:  wb_rd_data = wb_alu_result;
         WB_MEM:  wb_rd_data = wb_mem_rdata;
         WB_PC4:  wb_rd_data = wb_pc_plus4;
         default: wb_rd_data = wb_alu_result;
      endcase
   end

   // 레지스터 파일 쓰기는 위 ID 스테이지의 always_ff 블록에서 수행

   // =======================================================================
   // 디버그용 시뮬레이션 출력
   // =======================================================================
   // synthesis translate_off
   always_ff @(posedge clk) begin
      if (rst_n) begin
         $display("[%0t] IF:  PC=%h  Instr=%h", $time, if_pc, if_instr);
         $display("[%0t] ID:  PC=%h  Instr=%h  rs1=%0d  rs2=%0d  rd=%0d",
                  $time, id_pc, id_instr, id_rs1_addr, id_rs2_addr, id_rd_addr);
         $display("[%0t] EX:  ALU_A=%h  ALU_B=%h  Result=%h",
                  $time, ex_alu_a, ex_alu_b, ex_alu_result);
         $display("[%0t] MEM: Addr=%h  MemRW=%0b",
                  $time, mem_alu_result, mem_ctrl_mem.mem_rw);
         $display("[%0t] WB:  rd=%0d  Data=%h  WrEn=%b",
                  $time, wb_rd_addr, wb_rd_data, wb_ctrl_wb.reg_w_en);
         $display("---");
      end
   end
   // synthesis translate_on

endmodule
