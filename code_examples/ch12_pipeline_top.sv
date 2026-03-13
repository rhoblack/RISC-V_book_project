///////////////////////////////////////////////////////////////////////////////
// Module: rv32i_pipeline_top
// Description: RV32I 5단계 파이프라인 프로세서 최상위 모듈
//              구조적/데이터/제어 해저드를 모두 처리하는 완성된 설계
//
// Features:
//   - IF/ID/EX/MEM/WB 5단계 파이프라인
//   - EX-EX, MEM-EX 데이터 포워딩 (Ch10)
//   - Load-Use 스톨 감지 (Ch10)
//   - 분기 예측 Predict-Not-Taken + Flush (Ch11)
//   - WB-ID 레지스터 파일 포워딩 (Ch12)
//   - 하버드 구조 IMEM/DMEM 분리 (Ch12)
//
// Author: RISC-V 프로세서 설계 완전정복, Chapter 12
// Standard: IEEE 1800-2017 (SystemVerilog)
// Target: Xilinx Basys 3 (XC7A35T)
///////////////////////////////////////////////////////////////////////////////

module rv32i_pipeline_top #(
   parameter int IMEM_DEPTH   = 1024,  // 명령어 메모리 깊이 (워드 단위)
   parameter int DMEM_DEPTH   = 1024,  // 데이터 메모리 깊이 (워드 단위)
   parameter int RESET_VECTOR = 32'h0000_0000  // 리셋 벡터 주소
)(
   input  logic        clk,       // 시스템 클록
   input  logic        rst_n      // 비동기 리셋 (액티브 로우)
);

   // =========================================================================
   // 내부 신호 선언
   // =========================================================================

   // --- IF 스테이지 ---
   logic [31:0] pc_current;       // 현재 PC
   logic [31:0] pc_next;          // 다음 PC
   logic [31:0] pc_plus4_if;      // PC + 4
   logic [31:0] instruction_if;   // IMEM에서 인출한 명령어

   // --- IF/ID 파이프라인 레지스터 ---
   logic [31:0] pc_id;            // ID 스테이지의 PC
   logic [31:0] pc_plus4_id;      // ID 스테이지의 PC+4
   logic [31:0] instruction_id;   // ID 스테이지의 명령어

   // --- ID 스테이지 ---
   logic [4:0]  rs1_addr_id;      // 소스 레지스터 1 주소
   logic [4:0]  rs2_addr_id;      // 소스 레지스터 2 주소
   logic [4:0]  rd_addr_id;       // 목적 레지스터 주소
   logic [31:0] rs1_data_id;      // 소스 레지스터 1 데이터
   logic [31:0] rs2_data_id;      // 소스 레지스터 2 데이터
   logic [31:0] imm_id;           // 즉치수
   logic [3:0]  alu_sel_id;       // ALU 연산 선택
   logic        reg_wen_id;       // 레지스터 쓰기 인에이블
   logic        mem_wen_id;       // 메모리 쓰기 인에이블
   logic        mem_ren_id;       // 메모리 읽기 인에이블
   logic [1:0]  wb_sel_id;        // WB 소스 선택
   logic        alu_src_id;       // ALU 소스 B 선택 (0: rs2, 1: imm)
   logic        branch_id;        // 분기 명령어 여부
   logic        jump_id;          // 점프 명령어 여부
   logic        branch_taken_id;  // 분기 성립 여부

   // --- ID/EX 파이프라인 레지스터 ---
   logic [31:0] pc_ex;
   logic [31:0] pc_plus4_ex;
   logic [31:0] rs1_data_ex;
   logic [31:0] rs2_data_ex;
   logic [31:0] imm_ex;
   logic [4:0]  rs1_addr_ex;
   logic [4:0]  rs2_addr_ex;
   logic [4:0]  rd_addr_ex;
   logic [3:0]  alu_sel_ex;
   logic        reg_wen_ex;
   logic        mem_wen_ex;
   logic        mem_ren_ex;
   logic [1:0]  wb_sel_ex;
   logic        alu_src_ex;

   // --- EX 스테이지 ---
   logic [31:0] alu_operand_a;    // ALU 입력 A (포워딩 적용)
   logic [31:0] alu_operand_b;    // ALU 입력 B (포워딩 적용)
   logic [31:0] alu_result_ex;    // ALU 출력
   logic [31:0] rs2_fwd_ex;       // 포워딩된 rs2 (스토어용)
   logic [1:0]  fwd_sel_a;        // 포워딩 MUX 선택 A
   logic [1:0]  fwd_sel_b;        // 포워딩 MUX 선택 B

   // --- EX/MEM 파이프라인 레지스터 ---
   logic [31:0] alu_result_mem;
   logic [31:0] rs2_data_mem;
   logic [31:0] pc_plus4_mem;
   logic [4:0]  rd_addr_mem;
   logic        reg_wen_mem;
   logic        mem_wen_mem;
   logic        mem_ren_mem;
   logic [1:0]  wb_sel_mem;

   // --- MEM 스테이지 ---
   logic [31:0] mem_rdata_mem;    // DMEM 읽기 데이터

   // --- MEM/WB 파이프라인 레지스터 ---
   logic [31:0] alu_result_wb;
   logic [31:0] mem_rdata_wb;
   logic [31:0] pc_plus4_wb;
   logic [4:0]  rd_addr_wb;
   logic        reg_wen_wb;
   logic [1:0]  wb_sel_wb;

   // --- WB 스테이지 ---
   logic [31:0] wb_data;          // 레지스터 파일에 쓸 데이터

   // --- 해저드 제어 신호 ---
   logic        pc_en;            // PC 갱신 인에이블
   logic        if_id_en;         // IF/ID 레지스터 인에이블
   logic        id_ex_flush;      // ID/EX 레지스터 플러시 (버블 삽입)
   logic        if_id_flush;      // IF/ID 레지스터 플러시
   logic        stall;            // Load-Use 스톨 신호

   // =========================================================================
   // [IF 스테이지] 명령어 인출
   // 하버드 구조: IMEM은 IF 스테이지 전용
   // =========================================================================

   // PC 레지스터
   always_ff @(posedge clk or negedge rst_n) begin
      if (!rst_n)
         pc_current <= RESET_VECTOR;
      else if (pc_en)
         pc_current <= pc_next;
   end

   assign pc_plus4_if = pc_current + 32'd4;

   // 다음 PC 선택 (우선순위: 분기/점프 > PC+4)
   always_comb begin
      if (branch_taken_id || jump_id)
         pc_next = alu_result_ex;  // 분기/점프 목적지
      else
         pc_next = pc_plus4_if;    // 순차 실행
   end

   // 명령어 메모리 (IMEM) — 하버드 구조로 IF 전용
   instruction_memory #(
      .DEPTH(IMEM_DEPTH)
   ) u_imem (
      .clk     (clk),
      .addr    (pc_current),
      .rdata   (instruction_if)
   );

   // =========================================================================
   // [IF/ID 파이프라인 레지스터]
   // =========================================================================
   always_ff @(posedge clk or negedge rst_n) begin
      if (!rst_n) begin
         pc_id          <= '0;
         pc_plus4_id    <= '0;
         instruction_id <= 32'h0000_0013; // NOP (ADDI x0, x0, 0)
      end else if (if_id_flush) begin
         // 분기/점프 시 플러시 — NOP 삽입
         pc_id          <= '0;
         pc_plus4_id    <= '0;
         instruction_id <= 32'h0000_0013;
      end else if (if_id_en) begin
         pc_id          <= pc_current;
         pc_plus4_id    <= pc_plus4_if;
         instruction_id <= instruction_if;
      end
      // if_id_en == 0이면 홀드 (Load-Use 스톨)
   end

   // =========================================================================
   // [ID 스테이지] 명령어 해독 및 레지스터 읽기
   // =========================================================================

   // 명령어 필드 추출
   assign rs1_addr_id = instruction_id[19:15];
   assign rs2_addr_id = instruction_id[24:20];
   assign rd_addr_id  = instruction_id[11:7];

   // 디코더 및 제어 유닛
   control_unit u_control (
      .instruction (instruction_id),
      .alu_sel     (alu_sel_id),
      .reg_wen     (reg_wen_id),
      .mem_wen     (mem_wen_id),
      .mem_ren     (mem_ren_id),
      .wb_sel      (wb_sel_id),
      .alu_src     (alu_src_id),
      .branch      (branch_id),
      .jump        (jump_id)
   );

   // 즉치수 생성기
   immediate_generator u_imm_gen (
      .instruction (instruction_id),
      .immediate   (imm_id)
   );

   // 레지스터 파일 (WB-ID 포워딩 내장)
   register_file_with_forwarding u_regfile (
      .clk        (clk),
      .rst_n      (rst_n),
      .wb_reg_wen (reg_wen_wb),
      .wb_rd      (rd_addr_wb),
      .wb_data    (wb_data),
      .id_rs1     (rs1_addr_id),
      .id_rs2     (rs2_addr_id),
      .id_rd1     (rs1_data_id),
      .id_rd2     (rs2_data_id)
   );

   // =========================================================================
   // [해저드 감지 유닛] — Load-Use 스톨
   // =========================================================================
   hazard_detection_unit u_hazard (
      .id_rs1         (rs1_addr_id),
      .id_rs2         (rs2_addr_id),
      .ex_rd          (rd_addr_ex),
      .ex_mem_ren     (mem_ren_ex),
      .branch_taken   (branch_taken_id),
      .jump           (jump_id),
      .stall          (stall),
      .pc_en          (pc_en),
      .if_id_en       (if_id_en),
      .id_ex_flush    (id_ex_flush),
      .if_id_flush    (if_id_flush)
   );

   // =========================================================================
   // [ID/EX 파이프라인 레지스터]
   // =========================================================================
   always_ff @(posedge clk or negedge rst_n) begin
      if (!rst_n || id_ex_flush) begin
         pc_ex        <= '0;
         pc_plus4_ex  <= '0;
         rs1_data_ex  <= '0;
         rs2_data_ex  <= '0;
         imm_ex       <= '0;
         rs1_addr_ex  <= '0;
         rs2_addr_ex  <= '0;
         rd_addr_ex   <= '0;
         alu_sel_ex   <= '0;
         reg_wen_ex   <= '0;
         mem_wen_ex   <= '0;
         mem_ren_ex   <= '0;
         wb_sel_ex    <= '0;
         alu_src_ex   <= '0;
      end else begin
         pc_ex        <= pc_id;
         pc_plus4_ex  <= pc_plus4_id;
         rs1_data_ex  <= rs1_data_id;
         rs2_data_ex  <= rs2_data_id;
         imm_ex       <= imm_id;
         rs1_addr_ex  <= rs1_addr_id;
         rs2_addr_ex  <= rs2_addr_id;
         rd_addr_ex   <= rd_addr_id;
         alu_sel_ex   <= alu_sel_id;
         reg_wen_ex   <= reg_wen_id;
         mem_wen_ex   <= mem_wen_id;
         mem_ren_ex   <= mem_ren_id;
         wb_sel_ex    <= wb_sel_id;
         alu_src_ex   <= alu_src_id;
      end
   end

   // =========================================================================
   // [EX 스테이지] ALU 연산 및 포워딩
   // =========================================================================

   // 포워딩 유닛 (Ch10에서 설계)
   forwarding_unit u_forwarding (
      .ex_rs1      (rs1_addr_ex),
      .ex_rs2      (rs2_addr_ex),
      .mem_rd      (rd_addr_mem),
      .mem_reg_wen (reg_wen_mem),
      .wb_rd       (rd_addr_wb),
      .wb_reg_wen  (reg_wen_wb),
      .fwd_sel_a   (fwd_sel_a),
      .fwd_sel_b   (fwd_sel_b)
   );

   // 포워딩 MUX — ALU 입력 A
   always_comb begin
      case (fwd_sel_a)
         2'b00:   alu_operand_a = rs1_data_ex;      // 포워딩 없음
         2'b01:   alu_operand_a = wb_data;           // MEM-EX 포워딩
         2'b10:   alu_operand_a = alu_result_mem;    // EX-EX 포워딩
         default: alu_operand_a = rs1_data_ex;
      endcase
   end

   // 포워딩 MUX — ALU 입력 B (포워딩 후 imm 선택)
   always_comb begin
      case (fwd_sel_b)
         2'b00:   rs2_fwd_ex = rs2_data_ex;
         2'b01:   rs2_fwd_ex = wb_data;
         2'b10:   rs2_fwd_ex = alu_result_mem;
         default: rs2_fwd_ex = rs2_data_ex;
      endcase
   end

   assign alu_operand_b = alu_src_ex ? imm_ex : rs2_fwd_ex;

   // ALU (Ch04에서 설계)
   alu u_alu (
      .operand_a (alu_operand_a),
      .operand_b (alu_operand_b),
      .alu_sel   (alu_sel_ex),
      .result    (alu_result_ex)
   );

   // =========================================================================
   // [EX/MEM 파이프라인 레지스터]
   // =========================================================================
   always_ff @(posedge clk or negedge rst_n) begin
      if (!rst_n) begin
         alu_result_mem <= '0;
         rs2_data_mem   <= '0;
         pc_plus4_mem   <= '0;
         rd_addr_mem    <= '0;
         reg_wen_mem    <= '0;
         mem_wen_mem    <= '0;
         mem_ren_mem    <= '0;
         wb_sel_mem     <= '0;
      end else begin
         alu_result_mem <= alu_result_ex;
         rs2_data_mem   <= rs2_fwd_ex;   // 포워딩된 값 전달 (스토어용)
         pc_plus4_mem   <= pc_plus4_ex;
         rd_addr_mem    <= rd_addr_ex;
         reg_wen_mem    <= reg_wen_ex;
         mem_wen_mem    <= mem_wen_ex;
         mem_ren_mem    <= mem_ren_ex;
         wb_sel_mem     <= wb_sel_ex;
      end
   end

   // =========================================================================
   // [MEM 스테이지] 데이터 메모리 접근
   // 하버드 구조: DMEM은 MEM 스테이지 전용
   // =========================================================================
   data_memory #(
      .DEPTH(DMEM_DEPTH)
   ) u_dmem (
      .clk    (clk),
      .wen    (mem_wen_mem),
      .ren    (mem_ren_mem),
      .addr   (alu_result_mem),
      .wdata  (rs2_data_mem),
      .rdata  (mem_rdata_mem)
   );

   // =========================================================================
   // [MEM/WB 파이프라인 레지스터]
   // =========================================================================
   always_ff @(posedge clk or negedge rst_n) begin
      if (!rst_n) begin
         alu_result_wb <= '0;
         mem_rdata_wb  <= '0;
         pc_plus4_wb   <= '0;
         rd_addr_wb    <= '0;
         reg_wen_wb    <= '0;
         wb_sel_wb     <= '0;
      end else begin
         alu_result_wb <= alu_result_mem;
         mem_rdata_wb  <= mem_rdata_mem;
         pc_plus4_wb   <= pc_plus4_mem;
         rd_addr_wb    <= rd_addr_mem;
         reg_wen_wb    <= reg_wen_mem;
         wb_sel_wb     <= wb_sel_mem;
      end
   end

   // =========================================================================
   // [WB 스테이지] 쓰기 복귀
   // =========================================================================
   always_comb begin
      case (wb_sel_wb)
         2'b00:   wb_data = alu_result_wb;   // ALU 결과 (R/I 타입)
         2'b01:   wb_data = mem_rdata_wb;     // 메모리 데이터 (Load)
         2'b10:   wb_data = pc_plus4_wb;      // PC+4 (JAL/JALR)
         default: wb_data = alu_result_wb;
      endcase
   end

endmodule
