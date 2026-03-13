// ============================================================================
// 포워딩 파이프라인 프로세서 Top-Level
// Chapter 10 — 데이터 해저드와 포워딩
// RISC-V 프로세서 설계 완전정복
// ============================================================================
// Ch09 기본 파이프라인에 포워딩 유닛과 해저드 감지 유닛을 추가
// EX-EX/MEM-EX 포워딩, Load-Use 스톨 처리 포함
// 참고: 제어 해저드(분기)는 Ch11에서 처리 예정
// ============================================================================

`timescale 1ns / 1ps

module rv32i_pipeline_forwarding #(
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

   // --- 해저드/스톨 제어 ---
   logic        pc_en;            // PC 인에이블
   logic        if_id_en;         // IF/ID 레지스터 인에이블
   logic        id_ex_flush;      // ID/EX 버블 삽입

   // --- 포워딩 제어 ---
   logic [1:0]  fwd_a;            // ALU 오퍼랜드 A 포워딩 선택
   logic [1:0]  fwd_b;            // ALU 오퍼랜드 B 포워딩 선택

   // --- 포워딩된 ALU 입력 ---
   logic [31:0] alu_src_a;        // 포워딩 MUX 출력 → ALU A
   logic [31:0] alu_src_b;        // 포워딩 MUX 출력 → ALU B

   // =====================================================================
   // IF/ID 파이프라인 레지스터
   // =====================================================================
   logic [31:0] if_id_pc;
   logic [31:0] if_id_pc_plus4;
   logic [31:0] if_id_instr;

   // =====================================================================
   // ID/EX 파이프라인 레지스터
   // =====================================================================
   logic [31:0] id_ex_pc;
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
   // PC 레지스터 (Enable 제어 포함)
   // =====================================================================
   always_ff @(posedge clk or negedge rst_n) begin
      if (!rst_n)
         pc <= 32'h0000_0000;
      else if (pc_en)               // 스톨 시 pc_en=0 → PC 홀드
         pc <= pc_next;
   end

   assign pc_plus4 = pc + 32'd4;
   assign pc_next  = pc_plus4;      // 분기 처리는 Ch11에서 추가

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
   // IF/ID 파이프라인 레지스터 (Enable 제어 포함)
   // =====================================================================
   always_ff @(posedge clk or negedge rst_n) begin
      if (!rst_n) begin
         if_id_pc       <= 32'b0;
         if_id_pc_plus4 <= 32'b0;
         if_id_instr    <= 32'h0000_0013; // NOP (addi x0, x0, 0)
      end
      else if (if_id_en) begin          // 스톨 시 if_id_en=0 → 홀드
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

   assign rs1_addr = if_id_instr[19:15];
   assign rs2_addr = if_id_instr[24:20];
   assign rd_addr  = if_id_instr[11:7];

   // 레지스터 파일 인스턴스 (Ch04에서 설계)
   register_file u_rf (
      .clk      (clk),
      .rst_n    (rst_n),
      .rs1_addr (rs1_addr),
      .rs2_addr (rs2_addr),
      .rd_addr  (mem_wb_rd),         // WB 스테이지에서 쓰기
      .rd_data  (wb_data),
      .reg_w_en (mem_wb_reg_w_en),
      .rs1_data (rs1_data),
      .rs2_data (rs2_data)
   );

   // 즉치수 생성기 인스턴스 (Ch04에서 설계)
   // imm_gen u_imm_gen ( ... );

   // 제어 유닛 인스턴스 (Ch06에서 설계)
   // control_unit u_ctrl ( ... );

   // =====================================================================
   // ID/EX 파이프라인 레지스터 (Flush 제어 포함)
   // =====================================================================
   always_ff @(posedge clk or negedge rst_n) begin
      if (!rst_n || id_ex_flush) begin
         // 리셋 또는 플러시 → 버블(NOP) 삽입
         id_ex_pc        <= 32'b0;
         id_ex_rs1_data  <= 32'b0;
         id_ex_rs2_data  <= 32'b0;
         id_ex_imm       <= 32'b0;
         id_ex_rs1       <= 5'b0;
         id_ex_rs2       <= 5'b0;
         id_ex_rd        <= 5'b0;
         id_ex_reg_w_en  <= 1'b0;    // 레지스터 쓰기 비활성화
         id_ex_mem_read  <= 1'b0;    // 메모리 읽기 비활성화
         id_ex_mem_write <= 1'b0;    // 메모리 쓰기 비활성화
         id_ex_a_sel     <= 1'b0;
         id_ex_b_sel     <= 1'b0;
         id_ex_alu_sel   <= 4'b0;
         id_ex_wb_sel    <= 2'b0;
      end
      else begin
         id_ex_pc        <= if_id_pc;
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
      end
   end

   // =====================================================================
   // EX 스테이지: 포워딩 MUX + ALU 연산
   // =====================================================================

   // --- 포워딩 MUX A: ALU 오퍼랜드 A 소스 선택 ---
   always_comb begin
      case (fwd_a)
         2'b00:   alu_src_a = id_ex_rs1_data;       // 레지스터 파일
         2'b10:   alu_src_a = ex_mem_alu_result;     // EX-EX 포워딩
         2'b01:   alu_src_a = wb_data;               // MEM-EX 포워딩
         default: alu_src_a = id_ex_rs1_data;
      endcase
   end

   // --- 포워딩 MUX B: ALU 오퍼랜드 B 소스 선택 ---
   logic [31:0] fwd_b_data;  // 포워딩된 rs2 데이터

   always_comb begin
      case (fwd_b)
         2'b00:   fwd_b_data = id_ex_rs2_data;      // 레지스터 파일
         2'b10:   fwd_b_data = ex_mem_alu_result;    // EX-EX 포워딩
         2'b01:   fwd_b_data = wb_data;              // MEM-EX 포워딩
         default: fwd_b_data = id_ex_rs2_data;
      endcase
   end

   // ALU 입력 최종 선택 (즉치수 vs 레지스터)
   logic [31:0] alu_a, alu_b;
   assign alu_a = id_ex_a_sel ? id_ex_pc     : alu_src_a;
   assign alu_b = id_ex_b_sel ? id_ex_imm    : fwd_b_data;

   // ALU 인스턴스 (Ch04에서 설계)
   logic [31:0] alu_result;
   alu u_alu (
      .a      (alu_a),
      .b      (alu_b),
      .alu_sel(id_ex_alu_sel),
      .result (alu_result)
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
      end
   end

   // =====================================================================
   // WB 스테이지: 쓰기 데이터 선택
   // =====================================================================
   always_comb begin
      case (mem_wb_wb_sel)
         2'b00:   wb_data = mem_wb_alu_result;    // ALU 결과
         2'b01:   wb_data = mem_wb_mem_data;       // 메모리 읽기 데이터
         2'b10:   wb_data = mem_wb_pc_plus4;       // PC+4 (JAL/JALR)
         default: wb_data = mem_wb_alu_result;
      endcase
   end

   // =====================================================================
   // 포워딩 유닛 인스턴스
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
   // 해저드 감지 유닛 인스턴스
   // =====================================================================
   hazard_detection_unit u_hazard (
      .id_ex_mem_read (id_ex_mem_read),
      .id_ex_rd       (id_ex_rd),
      .if_id_rs1      (rs1_addr),
      .if_id_rs2      (rs2_addr),
      .pc_en          (pc_en),
      .if_id_en       (if_id_en),
      .id_ex_flush    (id_ex_flush)
   );

endmodule
