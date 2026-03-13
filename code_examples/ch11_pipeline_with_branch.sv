// ============================================================================
// ch11_pipeline_with_branch.sv
// Chapter 11 — 제어 해저드와 분기 처리
// RISC-V 프로세서 설계 완전정복
// ============================================================================
// Ch10 rv32i_pipeline_forwarding 기반에 제어 해저드 처리 추가:
//   - branch_unit (EX 단계 분기 판정)
//   - if_id_flush / id_ex_flush 확장 (분기/JAL/JALR 포함)
//   - pc_next 4-way MUX (PC+4 / branch_target / jal_target / jalr_target)
//   - JAL: ID 단계 처리 (1사이클 버블)
//   - JALR: EX 단계 처리 (2사이클 버블)
//   - Load-JALR: hazard_detection_unit이 rs1 포함 → 자동 스톨
// ============================================================================

`timescale 1ns / 1ps

module rv32i_pipeline_branch #(
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
   logic [31:0] pc;
   logic [31:0] pc_plus4;
   logic [31:0] pc_next;

   // --- 해저드/스톨 제어 (Ch10에서 계속) ---
   logic        load_use_stall;   // Load-Use 해저드 스톨
   logic        pc_en;            // PC 인에이블 (스톨 시 0)
   logic        if_id_en;         // IF/ID 레지스터 인에이블

   // --- 제어 해저드 신호 (Ch11 신규) ---
   logic        branch_taken_ex;  // EX 단계에서 분기 taken 판정
   logic        jal_id;           // ID 단계에서 JAL 감지
   logic        jalr_taken_ex;    // EX 단계에서 JALR 감지 (항상 taken)
   logic        if_id_flush;      // IF/ID 플러시 신호
   logic        id_ex_flush;      // ID/EX 플러시 신호 (스톨+분기 통합)

   // --- 포워딩 제어 (Ch10에서 계속) ---
   logic [1:0]  fwd_a;            // ALU 오퍼랜드 A 포워딩 선택
   logic [1:0]  fwd_b;            // ALU 오퍼랜드 B 포워딩 선택

   // --- 포워딩된 ALU 입력 ---
   logic [31:0] alu_src_a;        // 포워딩 MUX 출력 → ALU A
   logic [31:0] alu_src_b;        // ALU B 최종 입력
   logic [31:0] fwd_b_data;       // 포워딩된 rs2 데이터

   // =====================================================================
   // IF/ID 파이프라인 레지스터
   // =====================================================================
   logic [31:0] if_id_pc;
   logic [31:0] if_id_pc_plus4;
   logic [31:0] if_id_instr;

   // =====================================================================
   // ID/EX 파이프라인 레지스터 (Ch11: funct3/branch/jalr/pc_plus4 추가)
   // =====================================================================
   logic [31:0] id_ex_pc;
   logic [31:0] id_ex_pc_plus4;   // JAL/JALR 링크 주소 (WB에서 rd에 저장)
   logic [31:0] id_ex_rs1_data;
   logic [31:0] id_ex_rs2_data;
   logic [31:0] id_ex_imm;
   logic [4:0]  id_ex_rs1;
   logic [4:0]  id_ex_rs2;
   logic [4:0]  id_ex_rd;
   logic        id_ex_reg_w_en;
   logic        id_ex_mem_read;
   logic        id_ex_mem_write;
   logic        id_ex_a_sel;
   logic        id_ex_b_sel;
   logic [3:0]  id_ex_alu_sel;
   logic [1:0]  id_ex_wb_sel;
   logic [2:0]  id_ex_funct3;     // 분기 조건 판별 (Ch11 신규)
   logic        id_ex_branch;     // 분기 명령어 여부 (Ch11 신규)
   logic        id_ex_jalr;       // JALR 명령어 여부 (Ch11 신규)

   // =====================================================================
   // EX/MEM 파이프라인 레지스터
   // =====================================================================
   logic [31:0] ex_mem_alu_result;
   logic [31:0] ex_mem_rs2_data;
   logic [4:0]  ex_mem_rd;
   logic        ex_mem_reg_w_en;
   logic        ex_mem_mem_read;
   logic        ex_mem_mem_write;
   logic [1:0]  ex_mem_wb_sel;
   logic [31:0] ex_mem_pc_plus4;

   // =====================================================================
   // MEM/WB 파이프라인 레지스터
   // =====================================================================
   logic [31:0] mem_wb_alu_result;
   logic [31:0] mem_wb_mem_data;
   logic [4:0]  mem_wb_rd;
   logic        mem_wb_reg_w_en;
   logic [1:0]  mem_wb_wb_sel;
   logic [31:0] mem_wb_pc_plus4;

   // --- WB 스테이지 최종 데이터 ---
   logic [31:0] wb_data;

   // =====================================================================
   // PC 레지스터 (비동기 리셋 + Enable 제어)
   // =====================================================================
   always_ff @(posedge clk or negedge rst_n) begin
      if (!rst_n)
         pc <= 32'h0000_0000;
      else if (pc_en)            // 스톨 시 pc_en=0 → PC 홀드
         pc <= pc_next;
   end

   assign pc_plus4 = pc + 32'd4;

   // =====================================================================
   // pc_next 4-way MUX
   // =====================================================================
   // 우선순위: 분기/JAL/JALR > PC+4
   // branch_taken_ex와 jalr_taken_ex는 동시에 성립하지 않음 (JALR은 branch=0)
   // jal_id는 ID 단계에서 즉시 감지
   logic [31:0] branch_target;
   logic [31:0] jal_target;
   logic [31:0] jalr_target;
   logic [31:0] imm_J;

   // JAL J-type 즉치수 추출: {instr[31], instr[19:12], instr[20], instr[30:21], 1'b0}
   assign imm_J = {{12{if_id_instr[31]}},
                   if_id_instr[19:12],
                   if_id_instr[20],
                   if_id_instr[30:21],
                   1'b0};

   assign jal_id       = (if_id_instr[6:0] == 7'b1101111);  // JAL opcode
   assign jal_target   = if_id_pc + imm_J;

   assign branch_target = id_ex_pc + id_ex_imm;             // B-type: PC + imm_B
   assign jalr_taken_ex = id_ex_jalr;                        // JALR은 항상 taken
   assign jalr_target   = (alu_src_a + id_ex_imm) & ~32'h1; // JALR: (rs1+imm)&~1

   always_comb begin
      priority if (branch_taken_ex)  pc_next = branch_target;
      else if (jalr_taken_ex)        pc_next = jalr_target;
      else if (jal_id)               pc_next = jal_target;
      else                           pc_next = pc_plus4;
   end

   // =====================================================================
   // Flush / Stall 통합 제어 신호
   // =====================================================================
   // 규칙: Flush > Stall (분기 flush 발생 시 스톨보다 우선)
   assign if_id_flush  = branch_taken_ex | jal_id | jalr_taken_ex;
   assign id_ex_flush  = load_use_stall  | branch_taken_ex | jalr_taken_ex;

   // pc_en: 스톨 시 0, flush 시에도 PC는 새 주소로 갱신해야 하므로 1
   // (hazard_detection_unit이 stall=1이면 pc_en=0 출력하지만,
   //  flush 발생 시 flush > stall 원칙으로 pc_en=1 유지)
   // → hazard_detection_unit 출력 pc_en을 flush 신호로 오버라이드
   logic hdu_pc_en;
   assign pc_en = if_id_flush ? 1'b1 : hdu_pc_en;

   // =====================================================================
   // IF 스테이지: 명령어 인출
   // =====================================================================
   logic [31:0] instr;

   instruction_memory #(
      .DEPTH    (IMEM_DEPTH),
      .INIT_FILE(IMEM_INIT)
   ) u_imem (
      .addr  (pc),
      .rdata (instr)
   );

   // =====================================================================
   // IF/ID 파이프라인 레지스터 (flush > en 우선순위)
   // =====================================================================
   always_ff @(posedge clk or negedge rst_n) begin
      if (!rst_n || if_id_flush) begin
         // 리셋 또는 플러시 → NOP 삽입
         if_id_pc       <= 32'b0;
         if_id_pc_plus4 <= 32'b0;
         if_id_instr    <= 32'h0000_0013; // NOP (addi x0, x0, 0)
      end
      else if (if_id_en) begin             // 스톨 시 if_id_en=0 → 홀드
         if_id_pc       <= pc;
         if_id_pc_plus4 <= pc_plus4;
         if_id_instr    <= instr;
      end
   end

   // =====================================================================
   // ID 스테이지: 해독 및 레지스터 읽기
   // =====================================================================
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

   // 레지스터 파일 인스턴스 (Ch04에서 설계)
   register_file u_rf (
      .clk      (clk),
      .rst_n    (rst_n),
      .rs1_addr (rs1_addr),
      .rs2_addr (rs2_addr),
      .rd_addr  (mem_wb_rd),
      .rd_data  (wb_data),
      .reg_w_en (mem_wb_reg_w_en),
      .rs1_data (rs1_data),
      .rs2_data (rs2_data)
   );

   // 즉치수 생성기 (Ch04에서 설계)
   // imm_gen u_imm_gen (
   //    .instr  (if_id_instr),
   //    .imm    (imm)
   // );

   // 제어 유닛 (Ch06에서 설계)
   // control_unit u_ctrl (
   //    .opcode    (if_id_instr[6:0]),
   //    .funct3    (funct3_id),
   //    .funct7    (if_id_instr[31:25]),
   //    .reg_w_en  (reg_w_en),
   //    .mem_read  (mem_read),
   //    .mem_write (mem_write),
   //    .branch    (branch_id),
   //    .a_sel     (a_sel),
   //    .b_sel     (b_sel),
   //    .alu_sel   (alu_sel),
   //    .wb_sel    (wb_sel)
   // );

   // =====================================================================
   // ID/EX 파이프라인 레지스터 (Ch11: funct3/branch/jalr/pc_plus4 추가)
   // =====================================================================
   always_ff @(posedge clk or negedge rst_n) begin
      if (!rst_n || id_ex_flush) begin
         // 리셋 또는 플러시 → 버블(NOP) 삽입
         id_ex_pc        <= 32'b0;
         id_ex_pc_plus4  <= 32'b0;
         id_ex_rs1_data  <= 32'b0;
         id_ex_rs2_data  <= 32'b0;
         id_ex_imm       <= 32'b0;
         id_ex_rs1       <= 5'b0;
         id_ex_rs2       <= 5'b0;
         id_ex_rd        <= 5'b0;
         id_ex_reg_w_en  <= 1'b0;    // 레지스터 쓰기 비활성화
         id_ex_mem_read  <= 1'b0;    // 메모리 읽기 비활성화 (무한 스톨 방지)
         id_ex_mem_write <= 1'b0;
         id_ex_a_sel     <= 1'b0;
         id_ex_b_sel     <= 1'b0;
         id_ex_alu_sel   <= 4'b0;
         id_ex_wb_sel    <= 2'b0;
         id_ex_funct3    <= 3'b0;    // (Ch11 신규)
         id_ex_branch    <= 1'b0;    // (Ch11 신규)
         id_ex_jalr      <= 1'b0;    // (Ch11 신규)
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
         id_ex_funct3    <= funct3_id;  // (Ch11 신규)
         id_ex_branch    <= branch_id;  // (Ch11 신규)
         id_ex_jalr      <= jalr_id;    // (Ch11 신규)
      end
   end

   // =====================================================================
   // EX 스테이지: 포워딩 MUX + ALU 연산
   // =====================================================================

   // --- 포워딩 MUX A ---
   always_comb begin
      case (fwd_a)
         2'b00:   alu_src_a = id_ex_rs1_data;      // 레지스터 파일
         2'b10:   alu_src_a = ex_mem_alu_result;    // EX-EX 포워딩
         2'b01:   alu_src_a = wb_data;              // MEM-EX 포워딩
         default: alu_src_a = id_ex_rs1_data;
      endcase
   end

   // --- 포워딩 MUX B ---
   always_comb begin
      case (fwd_b)
         2'b00:   fwd_b_data = id_ex_rs2_data;     // 레지스터 파일
         2'b10:   fwd_b_data = ex_mem_alu_result;   // EX-EX 포워딩
         2'b01:   fwd_b_data = wb_data;             // MEM-EX 포워딩
         default: fwd_b_data = id_ex_rs2_data;
      endcase
   end

   // ALU 입력 최종 선택
   logic [31:0] alu_a, alu_b;
   assign alu_a = id_ex_a_sel ? id_ex_pc     : alu_src_a; // AUIPC/JAL은 PC 사용
   assign alu_b = id_ex_b_sel ? id_ex_imm    : fwd_b_data;

   // ALU 인스턴스 (Ch04에서 설계)
   logic [31:0] alu_result;
   alu u_alu (
      .a      (alu_a),
      .b      (alu_b),
      .alu_sel(id_ex_alu_sel),
      .result (alu_result)
   );

   // branch_unit 인스턴스 (Ch11 신규)
   branch_unit u_branch (
      .rs1_data    (alu_src_a),      // 포워딩된 rs1
      .rs2_data    (fwd_b_data),     // 포워딩된 rs2
      .funct3      (id_ex_funct3),
      .branch      (id_ex_branch),
      .branch_taken(branch_taken_ex)
   );

   // =====================================================================
   // EX/MEM 파이프라인 레지스터
   // =====================================================================
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
         ex_mem_rs2_data   <= fwd_b_data;  // 스토어 시 포워딩된 값 사용
         ex_mem_rd         <= id_ex_rd;
         ex_mem_reg_w_en   <= id_ex_reg_w_en;
         ex_mem_mem_read   <= id_ex_mem_read;
         ex_mem_mem_write  <= id_ex_mem_write;
         ex_mem_wb_sel     <= id_ex_wb_sel;
         ex_mem_pc_plus4   <= id_ex_pc_plus4;
      end
   end

   // =====================================================================
   // MEM 스테이지: 데이터 메모리 접근
   // =====================================================================
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

   // =====================================================================
   // MEM/WB 파이프라인 레지스터
   // =====================================================================
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

   // =====================================================================
   // WB 스테이지: 쓰기 데이터 선택
   // =====================================================================
   always_comb begin
      case (mem_wb_wb_sel)
         2'b00:   wb_data = mem_wb_alu_result;  // ALU 결과 (R/I 타입)
         2'b01:   wb_data = mem_wb_mem_data;    // 메모리 읽기 (LW 등)
         2'b10:   wb_data = mem_wb_pc_plus4;    // PC+4 (JAL/JALR 링크)
         default: wb_data = mem_wb_alu_result;
      endcase
   end

   // =====================================================================
   // 포워딩 유닛 인스턴스 (Ch10에서 설계)
   // =====================================================================
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

   // =====================================================================
   // 해저드 감지 유닛 인스턴스 (Ch10에서 설계, load_use_stall 출력)
   // =====================================================================
   hazard_detection_unit u_hazard (
      .id_ex_mem_read (id_ex_mem_read),
      .id_ex_rd       (id_ex_rd),
      .if_id_rs1      (rs1_addr),
      .if_id_rs2      (rs2_addr),
      .pc_en          (hdu_pc_en),    // flush가 오버라이드 (위 assign 참조)
      .if_id_en       (if_id_en),
      .id_ex_flush    (load_use_stall) // Ch11: load_use만 별도 분리
   );

endmodule
