// ============================================================================
// ch12_rv32i_pipeline_complete.sv
// Chapter 12 — 구조적 해저드와 파이프라인 완성
// RISC-V 프로세서 설계 완전정복
// ============================================================================
// ch11_pipeline_with_branch.sv 기반으로 최종 완성
//
// 변경 사항 (Ch11 → Ch12):
//   1. 모듈명: rv32i_pipeline_branch → rv32i_pipeline_complete
//   2. 파라미터 추가: DATA_WIDTH=32, ADDR_WIDTH=32, RF_DEPTH=32
//   3. register_file에 WB-ID 포워딩 추가 (ch12_register_file_with_forwarding)
//   4. imm_gen 인스턴스화 (이전 주석 해제 + 포트 확인)
//   5. control_unit 인스턴스화 (이전 주석 해제 + 포트 확인)
//   6. 모든 구조적 해저드 처리 완료 (Harvard 구조 유지)
//
// 해저드 처리 완성:
//   - RAW 해저드: EX-EX(2'b10), MEM-EX(2'b01) 포워딩 (Ch10)
//   - Load-Use 스톨: hazard_detection_unit (Ch10)
//   - 분기/JAL/JALR 플러시: branch_unit + flush 제어 (Ch11)
//   - WB-ID 포워딩: register_file 내부 처리 (Ch12)
//   - 구조적 해저드: Harvard 구조 (Ch09에서 이미 해결)
//
// 제어 신호 우선순위:
//   if_id_flush = branch_taken_ex | jal_id | jalr_taken_ex
//   id_ex_flush = load_use_stall  | branch_taken_ex | jalr_taken_ex
//   pc_en       = if_id_flush ? 1'b1 : hdu_pc_en   (Flush > Stall)
// ============================================================================

`timescale 1ns / 1ps

module rv32i_pipeline_complete #(
   parameter int DATA_WIDTH  = 32,    // 데이터 버스 폭 (RV32I: 32비트)
   parameter int ADDR_WIDTH  = 32,    // 주소 버스 폭
   parameter int RF_DEPTH    = 32,    // 레지스터 파일 깊이 (x0~x31)
   parameter int IMEM_DEPTH  = 1024,  // 명령어 메모리 깊이 (워드 단위)
   parameter int DMEM_DEPTH  = 1024,  // 데이터 메모리 깊이 (워드 단위)
   parameter     IMEM_INIT   = ""     // 명령어 메모리 초기화 파일 (.hex)
)(
   input  logic        clk,           // 시스템 클록
   input  logic        rst_n          // 비동기 리셋 (액티브 로우)
);

   // ==========================================================================
   // 내부 신호 선언
   // ==========================================================================

   // --- PC 관련 ---
   logic [31:0] pc;
   logic [31:0] pc_plus4;
   logic [31:0] pc_next;

   // --- 해저드/스톨 제어 ---
   logic        load_use_stall;      // Load-Use 해저드 스톨
   logic        pc_en;               // PC 인에이블 (스톨 시 0)
   logic        if_id_en;            // IF/ID 레지스터 인에이블
   logic        hdu_pc_en;           // 해저드 유닛 pc_en 출력 (flush로 오버라이드)

   // --- 제어 해저드 신호 ---
   logic        branch_taken_ex;     // EX 단계에서 분기 taken 판정
   logic        jal_id;              // ID 단계에서 JAL 감지
   logic        jalr_taken_ex;       // EX 단계에서 JALR 감지 (항상 taken)
   logic        if_id_flush;         // IF/ID 플러시 신호
   logic        id_ex_flush;         // ID/EX 플러시 신호 (스톨+분기 통합)

   // --- 포워딩 제어 ---
   logic [1:0]  fwd_a;               // ALU 오퍼랜드 A 포워딩 선택
   logic [1:0]  fwd_b;               // ALU 오퍼랜드 B 포워딩 선택

   // --- 포워딩된 ALU 입력 ---
   logic [31:0] alu_src_a;           // 포워딩 MUX 출력 → ALU A (a_sel MUX 전단)
   // logic [31:0] alu_src_b;        // 삭제: 실제 ALU B 입력은 alu_b (line ~333) 사용
   logic [31:0] fwd_b_data;          // 포워딩된 rs2 데이터 (b_sel MUX 전단)

   // ==========================================================================
   // IF/ID 파이프라인 레지스터
   // ==========================================================================
   logic [31:0] if_id_pc;
   logic [31:0] if_id_pc_plus4;
   logic [31:0] if_id_instr;

   // ==========================================================================
   // ID/EX 파이프라인 레지스터
   // ==========================================================================
   logic [31:0] id_ex_pc;
   logic [31:0] id_ex_pc_plus4;
   logic [31:0] id_ex_rs1_data;
   logic [31:0] id_ex_rs2_data;
   logic [31:0] id_ex_imm;
   logic [4:0]  id_ex_rs1;
   logic [4:0]  id_ex_rs2;
   logic [4:0]  id_ex_rd;
   logic        id_ex_reg_w_en;
   logic        id_ex_mem_read;
   logic        id_ex_mem_write;
   logic        id_ex_a_sel;         // ALU 입력 A 선택 (0: rs1, 1: pc)
   logic        id_ex_b_sel;         // ALU 입력 B 선택 (0: rs2, 1: imm)
   logic [3:0]  id_ex_alu_sel;
   logic [1:0]  id_ex_wb_sel;
   logic [2:0]  id_ex_funct3;        // 분기 조건 판별
   logic        id_ex_branch;        // 분기 명령어 여부
   logic        id_ex_jalr;          // JALR 명령어 여부

   // ==========================================================================
   // EX/MEM 파이프라인 레지스터
   // ==========================================================================
   logic [31:0] ex_mem_alu_result;
   logic [31:0] ex_mem_rs2_data;
   logic [4:0]  ex_mem_rd;
   logic        ex_mem_reg_w_en;
   logic        ex_mem_mem_read;
   logic        ex_mem_mem_write;
   logic [1:0]  ex_mem_wb_sel;
   logic [31:0] ex_mem_pc_plus4;

   // ==========================================================================
   // MEM/WB 파이프라인 레지스터
   // ==========================================================================
   logic [31:0] mem_wb_alu_result;
   logic [31:0] mem_wb_mem_data;
   logic [4:0]  mem_wb_rd;
   logic        mem_wb_reg_w_en;
   logic [1:0]  mem_wb_wb_sel;
   logic [31:0] mem_wb_pc_plus4;

   // --- WB 스테이지 최종 데이터 ---
   logic [31:0] wb_data;

   // ==========================================================================
   // PC 레지스터 (비동기 리셋 + Enable 제어)
   // ==========================================================================
   always_ff @(posedge clk or negedge rst_n) begin
      if (!rst_n)
         pc <= 32'h0000_0000;
      else if (pc_en)
         pc <= pc_next;
   end

   assign pc_plus4 = pc + 32'd4;

   // ==========================================================================
   // pc_next 4-way MUX
   // 우선순위: 분기 > JALR > JAL > PC+4
   // ==========================================================================
   logic [31:0] branch_target;
   logic [31:0] jal_target;
   logic [31:0] jalr_target;
   logic [31:0] imm_J;

   // JAL J-type 즉치수 추출
   assign imm_J = {{12{if_id_instr[31]}},
                   if_id_instr[19:12],
                   if_id_instr[20],
                   if_id_instr[30:21],
                   1'b0};

   assign jal_id       = (if_id_instr[6:0] == 7'b1101111);   // JAL opcode
   assign jal_target   = if_id_pc + imm_J;
   assign branch_target = id_ex_pc + id_ex_imm;              // B-type: PC + imm_B
   assign jalr_taken_ex = id_ex_jalr;                         // JALR은 항상 taken
   assign jalr_target   = (alu_src_a + id_ex_imm) & ~32'h1;  // JALR: (rs1+imm)&~1

   always_comb begin
      priority if (branch_taken_ex) pc_next = branch_target;
      else if (jalr_taken_ex)       pc_next = jalr_target;
      else if (jal_id)              pc_next = jal_target;
      else                          pc_next = pc_plus4;
   end

   // ==========================================================================
   // Flush / Stall 통합 제어 신호
   // ==========================================================================
   assign if_id_flush = branch_taken_ex | jal_id | jalr_taken_ex;
   assign id_ex_flush = load_use_stall  | branch_taken_ex | jalr_taken_ex;
   // Flush > Stall: flush 발생 시 PC는 새 주소로 갱신해야 하므로 pc_en = 1
   assign pc_en = if_id_flush ? 1'b1 : hdu_pc_en;

   // ==========================================================================
   // IF 스테이지: 명령어 인출 (Harvard 구조 — IMEM 전용)
   // ==========================================================================
   logic [31:0] instr;

   instruction_memory #(
      .DEPTH    (IMEM_DEPTH),
      .INIT_FILE(IMEM_INIT)
   ) u_imem (
      .addr  (pc),
      .rdata (instr)
   );

   // ==========================================================================
   // IF/ID 파이프라인 레지스터 (flush > en 우선순위)
   // ==========================================================================
   always_ff @(posedge clk or negedge rst_n) begin
      if (!rst_n || if_id_flush) begin
         if_id_pc       <= 32'b0;
         if_id_pc_plus4 <= 32'b0;
         if_id_instr    <= 32'h0000_0013;   // NOP (ADDI x0, x0, 0)
      end
      else if (if_id_en) begin              // 스톨 시 if_id_en=0 → 홀드
         if_id_pc       <= pc;
         if_id_pc_plus4 <= pc_plus4;
         if_id_instr    <= instr;
      end
   end

   // ==========================================================================
   // ID 스테이지: 해독 및 레지스터 읽기
   // ==========================================================================
   logic [4:0]  rs1_addr, rs2_addr, rd_addr;
   logic [31:0] rs1_data, rs2_data, imm;
   logic        reg_w_en, mem_read, mem_write;
   logic        a_sel, b_sel;
   logic [3:0]  alu_sel;
   logic [1:0]  wb_sel;
   logic [2:0]  funct3_id;
   logic        branch_id, jalr_id;

   assign rs1_addr  = if_id_instr[19:15];
   assign rs2_addr  = if_id_instr[24:20];
   assign rd_addr   = if_id_instr[11:7];
   assign funct3_id = if_id_instr[14:12];

   // JALR 감지 (opcode = 7'b1100111)
   assign jalr_id = (if_id_instr[6:0] == 7'b1100111);

   // 레지스터 파일 (Ch12: WB-ID 포워딩 내장)
   register_file u_rf (
      .clk      (clk),
      .rst_n    (rst_n),
      .rs1_addr (rs1_addr),
      .rs2_addr (rs2_addr),
      .rd_addr  (mem_wb_rd),           // WB 스테이지 rd
      .rd_data  (wb_data),             // WB 스테이지 쓰기 데이터
      .reg_w_en (mem_wb_reg_w_en),     // WB 스테이지 쓰기 인에이블
      .rs1_data (rs1_data),
      .rs2_data (rs2_data)
   );

   // 즉치수 생성기 (파이프라인 전용 — opcode 기반 자동 타입 감지)
   // Ch04 imm_gen(inst/imm_sel/imm_out 인터페이스)과 구별됨:
   //   파이프라인에서는 제어 유닛 없이 opcode만으로 즉치수 타입을 자동 판별
   pipeline_imm_gen u_imm_gen (
      .instr (if_id_instr),
      .imm   (imm)
   );

   // 제어 유닛 (파이프라인 전용 — opcode/funct3/funct7 분리 입력)
   // Ch06 control_unit(instr[31:0]/rs1_data/rs2_data 인터페이스)과 구별됨:
   //   파이프라인에서는 분기 비교를 EX 단계 branch_unit이 담당하므로
   //   제어 유닛은 opcode/funct3/funct7만으로 모든 제어 신호를 생성
   pipeline_control_unit u_ctrl (
      .opcode    (if_id_instr[6:0]),
      .funct3    (funct3_id),
      .funct7    (if_id_instr[31:25]),
      .reg_w_en  (reg_w_en),
      .mem_read  (mem_read),
      .mem_write (mem_write),
      .branch    (branch_id),
      .a_sel     (a_sel),
      .b_sel     (b_sel),
      .alu_sel   (alu_sel),
      .wb_sel    (wb_sel)
   );

   // ==========================================================================
   // ID/EX 파이프라인 레지스터
   // ==========================================================================
   always_ff @(posedge clk or negedge rst_n) begin
      if (!rst_n || id_ex_flush) begin
         id_ex_pc        <= 32'b0;
         id_ex_pc_plus4  <= 32'b0;
         id_ex_rs1_data  <= 32'b0;
         id_ex_rs2_data  <= 32'b0;
         id_ex_imm       <= 32'b0;
         id_ex_rs1       <= 5'b0;
         id_ex_rs2       <= 5'b0;
         id_ex_rd        <= 5'b0;
         id_ex_reg_w_en  <= 1'b0;
         id_ex_mem_read  <= 1'b0;   // 무한 스톨 방지
         id_ex_mem_write <= 1'b0;
         id_ex_a_sel     <= 1'b0;
         id_ex_b_sel     <= 1'b0;
         id_ex_alu_sel   <= 4'b0;
         id_ex_wb_sel    <= 2'b0;
         id_ex_funct3    <= 3'b0;
         id_ex_branch    <= 1'b0;
         id_ex_jalr      <= 1'b0;
      end
      else begin
         id_ex_pc        <= if_id_pc;
         id_ex_pc_plus4  <= if_id_pc_plus4;
         id_ex_rs1_data  <= rs1_data;
         id_ex_rs2_data  <= rs2_data;
         id_ex_imm       <= imm;
         id_ex_rs1       <= rs1_addr;
         id_ex_rs2       <= rs2_addr;
         id_ex_rd        <= rd_addr;
         id_ex_reg_w_en  <= reg_w_en;
         id_ex_mem_read  <= mem_read;
         id_ex_mem_write <= mem_write;
         id_ex_a_sel     <= a_sel;
         id_ex_b_sel     <= b_sel;
         id_ex_alu_sel   <= alu_sel;
         id_ex_wb_sel    <= wb_sel;
         id_ex_funct3    <= funct3_id;
         id_ex_branch    <= branch_id;
         id_ex_jalr      <= jalr_id;
      end
   end

   // ==========================================================================
   // EX 스테이지: 포워딩 MUX + ALU 연산
   // ==========================================================================

   // 포워딩 MUX A
   always_comb begin
      case (fwd_a)
         2'b00:   alu_src_a = id_ex_rs1_data;     // 레지스터 파일
         2'b10:   alu_src_a = ex_mem_alu_result;   // EX-EX 포워딩
         2'b01:   alu_src_a = wb_data;             // MEM-EX 포워딩
         default: alu_src_a = id_ex_rs1_data;
      endcase
   end

   // 포워딩 MUX B
   always_comb begin
      case (fwd_b)
         2'b00:   fwd_b_data = id_ex_rs2_data;    // 레지스터 파일
         2'b10:   fwd_b_data = ex_mem_alu_result;  // EX-EX 포워딩
         2'b01:   fwd_b_data = wb_data;            // MEM-EX 포워딩
         default: fwd_b_data = id_ex_rs2_data;
      endcase
   end

   // ALU 입력 최종 선택
   logic [31:0] alu_a, alu_b;
   assign alu_a = id_ex_a_sel ? id_ex_pc    : alu_src_a;   // AUIPC: PC 사용
   assign alu_b = id_ex_b_sel ? id_ex_imm   : fwd_b_data;  // I/S/B/U/J 타입: imm

   // ALU 인스턴스 (Ch09 파이프라인용 포트명 — Ch04 원본에서 변경됨)
   // Ch04: operand_a / operand_b / alu_ctrl / alu_result / alu_zero
   // Ch09+: a / b / alu_sel / result  (포트명 단순화, alu_zero는 branch_unit 담당)
   // alu_zero 포트: 분기 판정은 branch_unit에서 funct3 기반으로 처리하므로 미연결
   logic [31:0] alu_result;
   alu u_alu (
      .a      (alu_a),
      .b      (alu_b),
      .alu_sel(id_ex_alu_sel),
      .result (alu_result)
   );

   // 분기 유닛 인스턴스 (Ch11에서 설계)
   branch_unit u_branch (
      .rs1_data    (alu_src_a),       // 포워딩된 rs1
      .rs2_data    (fwd_b_data),      // 포워딩된 rs2
      .funct3      (id_ex_funct3),
      .branch      (id_ex_branch),
      .branch_taken(branch_taken_ex)
   );

   // ==========================================================================
   // EX/MEM 파이프라인 레지스터
   // ==========================================================================
   always_ff @(posedge clk or negedge rst_n) begin
      if (!rst_n) begin
         ex_mem_alu_result <= 32'b0;
         ex_mem_rs2_data   <= 32'b0;
         ex_mem_rd         <= 5'b0;
         ex_mem_reg_w_en   <= 1'b0;
         ex_mem_mem_read   <= 1'b0;
         ex_mem_mem_write  <= 1'b0;
         ex_mem_wb_sel     <= 2'b0;
         ex_mem_pc_plus4   <= 32'b0;
      end
      else begin
         ex_mem_alu_result <= alu_result;
         ex_mem_rs2_data   <= fwd_b_data;   // 스토어 시 포워딩된 값 사용
         ex_mem_rd         <= id_ex_rd;
         ex_mem_reg_w_en   <= id_ex_reg_w_en;
         ex_mem_mem_read   <= id_ex_mem_read;
         ex_mem_mem_write  <= id_ex_mem_write;
         ex_mem_wb_sel     <= id_ex_wb_sel;
         ex_mem_pc_plus4   <= id_ex_pc_plus4;
      end
   end

   // ==========================================================================
   // MEM 스테이지: 데이터 메모리 접근 (Harvard 구조 — DMEM 전용)
   // ==========================================================================
   logic [31:0] mem_rdata;

   data_memory #(
      .DEPTH(DMEM_DEPTH)
   ) u_dmem (
      .clk   (clk),
      .addr  (ex_mem_alu_result),
      .wdata (ex_mem_rs2_data),
      .we    (ex_mem_mem_write),
      .re    (ex_mem_mem_read),
      .rdata (mem_rdata)
   );

   // ==========================================================================
   // MEM/WB 파이프라인 레지스터
   // ==========================================================================
   always_ff @(posedge clk or negedge rst_n) begin
      if (!rst_n) begin
         mem_wb_alu_result <= 32'b0;
         mem_wb_mem_data   <= 32'b0;
         mem_wb_rd         <= 5'b0;
         mem_wb_reg_w_en   <= 1'b0;
         mem_wb_wb_sel     <= 2'b0;
         mem_wb_pc_plus4   <= 32'b0;
      end
      else begin
         mem_wb_alu_result <= ex_mem_alu_result;
         mem_wb_mem_data   <= mem_rdata;
         mem_wb_rd         <= ex_mem_rd;
         mem_wb_reg_w_en   <= ex_mem_reg_w_en;
         mem_wb_wb_sel     <= ex_mem_wb_sel;
         mem_wb_pc_plus4   <= ex_mem_pc_plus4;
      end
   end

   // ==========================================================================
   // WB 스테이지: 쓰기 데이터 선택
   // 2'b00 = ALU 결과 (R/I 타입)
   // 2'b01 = 메모리 읽기 (LW 등)
   // 2'b10 = PC+4 (JAL/JALR 링크 주소)
   // ==========================================================================
   always_comb begin
      case (mem_wb_wb_sel)
         2'b00:   wb_data = mem_wb_alu_result;  // ALU 결과
         2'b01:   wb_data = mem_wb_mem_data;    // 메모리 읽기
         2'b10:   wb_data = mem_wb_pc_plus4;    // PC+4 링크
         default: wb_data = mem_wb_alu_result;
      endcase
   end

   // ==========================================================================
   // 포워딩 유닛 인스턴스 (Ch10에서 설계 — 수정 없음)
   // WB-ID 포워딩은 register_file 내부에서 처리하므로 이 유닛은 변경 불필요
   // ==========================================================================
   forwarding_unit u_fwd (
      .id_ex_rs1       (id_ex_rs1),
      .id_ex_rs2       (id_ex_rs2),
      .ex_mem_reg_w_en (ex_mem_reg_w_en),
      .ex_mem_rd       (ex_mem_rd),
      .mem_wb_reg_w_en (mem_wb_reg_w_en),
      .mem_wb_rd       (mem_wb_rd),
      .fwd_a           (fwd_a),
      .fwd_b           (fwd_b)
   );

   // ==========================================================================
   // 해저드 감지 유닛 인스턴스 (Ch10에서 설계 — 수정 없음)
   // ==========================================================================
   hazard_detection_unit u_hazard (
      .id_ex_mem_read (id_ex_mem_read),
      .id_ex_rd       (id_ex_rd),
      .if_id_rs1      (rs1_addr),
      .if_id_rs2      (rs2_addr),
      .pc_en          (hdu_pc_en),       // flush가 오버라이드 (위 assign 참조)
      .if_id_en       (if_id_en),
      .id_ex_flush    (load_use_stall)   // load_use만 별도 분리 (Ch11 패턴 유지)
   );

endmodule

// ============================================================================
// pipeline_imm_gen
// 파이프라인 전용 즉치수 생성기 — opcode 기반 자동 타입 감지
// ============================================================================
// Ch04 imm_gen과의 차이점:
//   Ch04: imm_sel[2:0] 입력을 제어 유닛에서 받아 타입 선택
//   Ch12: opcode[6:0]만으로 타입 자동 감지 (파이프라인 ID 단계에 최적화)
// ============================================================================
module pipeline_imm_gen (
   input  logic [31:0] instr,    // 32비트 명령어
   output logic [31:0] imm       // 부호 확장된 즉치수
);
   logic [6:0] opcode;
   assign opcode = instr[6:0];

   always_comb begin
      case (opcode)
         // I 타입: ADDI, ANDI, ORI, XORI, SLTI, SLTIU, LW, LH, LB, LHU, LBU
         7'b0010011,   // OP-IMM (ADDI 등)
         7'b0000011,   // LOAD   (LW 등)
         7'b1100111:   // JALR
            imm = {{20{instr[31]}}, instr[31:20]};

         // S 타입: SW, SH, SB
         7'b0100011:
            imm = {{20{instr[31]}}, instr[31:25], instr[11:7]};

         // B 타입: BEQ, BNE, BLT, BGE, BLTU, BGEU
         7'b1100011:
            imm = {{19{instr[31]}}, instr[31], instr[7],
                   instr[30:25], instr[11:8], 1'b0};

         // U 타입: LUI, AUIPC
         7'b0110111,   // LUI
         7'b0010111:   // AUIPC
            imm = {instr[31:12], 12'b0};

         // J 타입: JAL
         7'b1101111:
            imm = {{11{instr[31]}}, instr[31], instr[19:12],
                   instr[20], instr[30:21], 1'b0};

         // R 타입 등: 즉치수 없음
         default:
            imm = 32'b0;
      endcase
   end
endmodule

// ============================================================================
// pipeline_control_unit
// 파이프라인 전용 제어 유닛 — opcode/funct3/funct7 분리 입력
// ============================================================================
// Ch06 control_unit과의 차이점:
//   Ch06: instr[31:0] 전체 + rs1_data/rs2_data 입력 (단일사이클 분기 비교 내장)
//   Ch12: opcode/funct3/funct7 분리 입력, 분기 비교는 EX 단계 branch_unit 담당
// ============================================================================
// ALU 선택 코드 (alu_sel[3:0]) — Ch04 alu와 동일:
//   0000=ADD, 0001=SUB, 0010=AND, 0011=OR, 0100=XOR
//   0101=SLL, 0110=SRL, 0111=SRA, 1000=SLT, 1001=SLTU
// WB 선택 (wb_sel[1:0]):
//   2'b00=ALU 결과 (R/I 타입), 2'b01=메모리 읽기 (LW), 2'b10=PC+4 (JAL/JALR)
// ============================================================================
module pipeline_control_unit (
   input  logic [6:0] opcode,     // 명령어 opcode
   input  logic [2:0] funct3,     // funct3 필드
   input  logic [6:0] funct7,     // funct7 필드 (R 타입 구별용)
   output logic       reg_w_en,   // 레지스터 쓰기 인에이블
   output logic       mem_read,   // 메모리 읽기
   output logic       mem_write,  // 메모리 쓰기
   output logic       branch,     // 분기 명령어 (branch_unit 활성화)
   output logic       a_sel,      // ALU A 입력 선택 (0: rs1, 1: pc — AUIPC용)
   output logic       b_sel,      // ALU B 입력 선택 (0: rs2, 1: imm)
   output logic [3:0] alu_sel,    // ALU 연산 선택
   output logic [1:0] wb_sel      // Write-Back 소스 선택
);
   always_comb begin
      // 기본값 (NOP 동작)
      reg_w_en  = 1'b0;
      mem_read  = 1'b0;
      mem_write = 1'b0;
      branch    = 1'b0;
      a_sel     = 1'b0;   // rs1
      b_sel     = 1'b0;   // rs2
      alu_sel   = 4'b0000; // ADD
      wb_sel    = 2'b00;  // ALU 결과

      case (opcode)
         // R 타입: ADD, SUB, AND, OR, XOR, SLL, SRL, SRA, SLT, SLTU
         7'b0110011: begin
            reg_w_en = 1'b1;
            b_sel    = 1'b0;   // rs2
            wb_sel   = 2'b00;
            case ({funct7[5], funct3})
               4'b0_000: alu_sel = 4'b0000; // ADD
               4'b1_000: alu_sel = 4'b0001; // SUB
               4'b0_111: alu_sel = 4'b0010; // AND
               4'b0_110: alu_sel = 4'b0011; // OR
               4'b0_100: alu_sel = 4'b0100; // XOR
               4'b0_001: alu_sel = 4'b0101; // SLL
               4'b0_101: alu_sel = 4'b0110; // SRL
               4'b1_101: alu_sel = 4'b0111; // SRA
               4'b0_010: alu_sel = 4'b1000; // SLT
               4'b0_011: alu_sel = 4'b1001; // SLTU
               default:  alu_sel = 4'b0000;
            endcase
         end

         // I 타입 연산: ADDI, ANDI, ORI, XORI, SLTI, SLTIU, SLLI, SRLI, SRAI
         7'b0010011: begin
            reg_w_en = 1'b1;
            b_sel    = 1'b1;   // imm
            wb_sel   = 2'b00;
            case (funct3)
               3'b000: alu_sel = 4'b0000; // ADDI
               3'b111: alu_sel = 4'b0010; // ANDI
               3'b110: alu_sel = 4'b0011; // ORI
               3'b100: alu_sel = 4'b0100; // XORI
               3'b001: alu_sel = 4'b0101; // SLLI
               3'b101: alu_sel = funct7[5] ? 4'b0111 : 4'b0110; // SRAI:SRLI
               3'b010: alu_sel = 4'b1000; // SLTI
               3'b011: alu_sel = 4'b1001; // SLTIU
               default: alu_sel = 4'b0000;
            endcase
         end

         // LW, LH, LB, LHU, LBU (로드 명령어)
         7'b0000011: begin
            reg_w_en = 1'b1;
            mem_read = 1'b1;
            b_sel    = 1'b1;   // imm
            alu_sel  = 4'b0000; // ADD (주소 계산)
            wb_sel   = 2'b01;  // 메모리 읽기
         end

         // SW, SH, SB (스토어 명령어)
         7'b0100011: begin
            mem_write = 1'b1;
            b_sel     = 1'b1;   // imm
            alu_sel   = 4'b0000; // ADD (주소 계산)
         end

         // B 타입: BEQ, BNE, BLT, BGE, BLTU, BGEU
         7'b1100011: begin
            branch   = 1'b1;
            b_sel    = 1'b0;   // rs2 (ALU는 EX에서 branch_unit이 처리)
            alu_sel  = 4'b0001; // SUB (비교용, branch_unit이 funct3으로 판정)
         end

         // LUI
         7'b0110111: begin
            reg_w_en = 1'b1;
            b_sel    = 1'b1;   // imm (U 타입)
            a_sel    = 1'b0;   // rs1 (x0 강제, 어셈블러가 rs1=x0 설정)
            alu_sel  = 4'b0011; // OR (0 | imm_U = imm_U, a_sel로 0 선택)
            wb_sel   = 2'b00;
            // 구현 참고: LUI는 레지스터 파일에서 rs1=x0이 읽히므로
            //           ALU에 0 | imm_U = imm_U 결과 저장
         end

         // AUIPC
         7'b0010111: begin
            reg_w_en = 1'b1;
            a_sel    = 1'b1;   // pc (PC + imm_U)
            b_sel    = 1'b1;   // imm
            alu_sel  = 4'b0000; // ADD
            wb_sel   = 2'b00;
         end

         // JAL
         7'b1101111: begin
            reg_w_en = 1'b1;
            wb_sel   = 2'b10;  // PC+4 (링크 주소 저장)
            // 분기 주소 계산은 최상위 모듈에서 imm_J 사용 (별도 처리)
         end

         // JALR
         7'b1100111: begin
            reg_w_en = 1'b1;
            b_sel    = 1'b1;   // imm (rs1 + imm_I 계산용)
            alu_sel  = 4'b0000; // ADD
            wb_sel   = 2'b10;  // PC+4 (링크 주소 저장)
         end

         default: begin
            // NOP 또는 미정의 명령어 — 모든 출력 기본값(0) 유지
         end
      endcase
   end
endmodule
