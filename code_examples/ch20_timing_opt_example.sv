// ============================================================================
// 모듈: timing_optimization_examples
// 설명: 타이밍 클로저를 위한 RTL 수준 최적화 기법 예제
// Chapter 20: FPGA 합성 최적화와 타이밍 클로저
// ============================================================================

// ============================================================================
// 예제 1: 레지스터 삽입(Register Insertion)을 통한 임계 경로 분할
//
// [최적화 전] 긴 조합 로직 체인 → Setup Violation 발생 가능
// [최적화 후] 중간에 레지스터를 삽입하여 경로를 2사이클로 분할
// ============================================================================

// --- 최적화 전: 긴 조합 로직 체인 ---
module alu_no_pipeline (
   input  logic        clk,
   input  logic        rst_n,
   input  logic [31:0] operand_a,
   input  logic [31:0] operand_b,
   input  logic [3:0]  alu_op,
   output logic [31:0] result
);

   logic [31:0] alu_out;

   // 조합 로직: 연산 + 비교 + 멀티플렉서가 한 경로에 연결
   always_comb begin
      case (alu_op)
         4'b0000: alu_out = operand_a + operand_b;   // ADD
         4'b0001: alu_out = operand_a - operand_b;   // SUB
         4'b0010: alu_out = operand_a & operand_b;   // AND
         4'b0011: alu_out = operand_a | operand_b;   // OR
         4'b0100: alu_out = operand_a ^ operand_b;   // XOR
         4'b0101: alu_out = operand_a << operand_b[4:0]; // SLL
         4'b0110: alu_out = operand_a >> operand_b[4:0]; // SRL
         4'b0111: alu_out = $signed(operand_a) >>> operand_b[4:0]; // SRA
         4'b1000: alu_out = {31'b0, $signed(operand_a) < $signed(operand_b)}; // SLT
         4'b1001: alu_out = {31'b0, operand_a < operand_b}; // SLTU
         default: alu_out = 32'b0;
      endcase
   end

   always_ff @(posedge clk or negedge rst_n) begin
      if (!rst_n)
         result <= 32'b0;
      else
         result <= alu_out;
   end

endmodule

// --- 최적화 후: 출력 레지스터 분리 + 리타이밍 힌트 ---
// Vivado의 retiming 옵션이 활성화되면, 합성 도구가 자동으로
// 조합 로직을 레지스터 경계 사이에서 재배분(rebalancing)함
module alu_retiming_friendly (
   input  logic        clk,
   input  logic        rst_n,
   input  logic [31:0] operand_a,
   input  logic [31:0] operand_b,
   input  logic [3:0]  alu_op,
   output logic [31:0] result
);

   // 입력 레지스터 (리타이밍 대상)
   logic [31:0] op_a_reg, op_b_reg;
   logic [3:0]  alu_op_reg;

   always_ff @(posedge clk or negedge rst_n) begin
      if (!rst_n) begin
         op_a_reg   <= 32'b0;
         op_b_reg   <= 32'b0;
         alu_op_reg <= 4'b0;
      end else begin
         op_a_reg   <= operand_a;
         op_b_reg   <= operand_b;
         alu_op_reg <= alu_op;
      end
   end

   // 조합 로직 (리타이밍 도구가 레지스터를 이동시킬 수 있음)
   logic [31:0] alu_out;

   always_comb begin
      case (alu_op_reg)
         4'b0000: alu_out = op_a_reg + op_b_reg;
         4'b0001: alu_out = op_a_reg - op_b_reg;
         4'b0010: alu_out = op_a_reg & op_b_reg;
         4'b0011: alu_out = op_a_reg | op_b_reg;
         4'b0100: alu_out = op_a_reg ^ op_b_reg;
         4'b0101: alu_out = op_a_reg << op_b_reg[4:0];
         4'b0110: alu_out = op_a_reg >> op_b_reg[4:0];
         4'b0111: alu_out = $signed(op_a_reg) >>> op_b_reg[4:0];
         4'b1000: alu_out = {31'b0, $signed(op_a_reg) < $signed(op_b_reg)};
         4'b1001: alu_out = {31'b0, op_a_reg < op_b_reg};
         default: alu_out = 32'b0;
      endcase
   end

   // 출력 레지스터
   always_ff @(posedge clk or negedge rst_n) begin
      if (!rst_n)
         result <= 32'b0;
      else
         result <= alu_out;
   end

endmodule

// ============================================================================
// 예제 2: 리소스 공유(Resource Sharing)
//
// 서로 다른 시점에 사용되는 연산기를 하나로 공유하여 LUT 절감
// 트레이드오프: LUT↓, MUX 추가, 임계 경로 가능성↑
// ============================================================================

// --- 공유 없음: 별도 가산기 2개 ---
module no_sharing (
   input  logic        clk,
   input  logic        rst_n,
   input  logic [31:0] a, b, c, d,
   input  logic        sel,
   output logic [31:0] result
);

   logic [31:0] sum1, sum2;

   assign sum1 = a + b;  // 가산기 #1
   assign sum2 = c + d;  // 가산기 #2

   always_ff @(posedge clk or negedge rst_n) begin
      if (!rst_n)
         result <= 32'b0;
      else
         result <= sel ? sum2 : sum1;
   end

endmodule

// --- 공유: 가산기 1개 + MUX ---
module with_sharing (
   input  logic        clk,
   input  logic        rst_n,
   input  logic [31:0] a, b, c, d,
   input  logic        sel,
   output logic [31:0] result
);

   logic [31:0] add_op1, add_op2;
   logic [31:0] add_result;

   // 입력 멀티플렉서로 피연산자 선택
   assign add_op1 = sel ? c : a;
   assign add_op2 = sel ? d : b;

   // 공유 가산기 1개
   assign add_result = add_op1 + add_op2;

   always_ff @(posedge clk or negedge rst_n) begin
      if (!rst_n)
         result <= 32'b0;
      else
         result <= add_result;
   end

endmodule

// ============================================================================
// 예제 3: BRAM 추론을 위한 코딩 패턴
//
// Vivado가 코드를 BRAM으로 자동 추론하려면 특정 패턴을 따라야 함.
// 잘못된 패턴은 LUTRAM(분산 RAM)으로 합성되어 LUT 소모량 급증.
// ============================================================================

// --- BRAM 추론 가능한 패턴: 동기 읽기 + 동기 쓰기 ---
module bram_inferred #(
   parameter ADDR_WIDTH = 10,   // 1024 워드
   parameter DATA_WIDTH = 32
) (
   input  logic                    clk,
   input  logic                    we,       // 쓰기 인에이블
   input  logic [ADDR_WIDTH-1:0]   addr,     // 주소
   input  logic [DATA_WIDTH-1:0]   din,      // 쓰기 데이터
   output logic [DATA_WIDTH-1:0]   dout      // 읽기 데이터
);

   // 메모리 배열 선언
   logic [DATA_WIDTH-1:0] mem [0:2**ADDR_WIDTH-1];

   // 동기 읽기/쓰기 — 이 패턴이 BRAM으로 추론됨
   always_ff @(posedge clk) begin
      if (we)
         mem[addr] <= din;
      dout <= mem[addr];  // Read-First 모드
   end

endmodule

// --- BRAM 추론 불가한 패턴: 비동기 읽기 ---
// 이 패턴은 LUTRAM(분산 RAM)으로 합성됨
// 레지스터 파일처럼 비동기 읽기가 필요한 경우에만 사용
module lutram_pattern #(
   parameter ADDR_WIDTH = 5,   // 32 워드 (레지스터 파일용)
   parameter DATA_WIDTH = 32
) (
   input  logic                    clk,
   input  logic                    we,
   input  logic [ADDR_WIDTH-1:0]   waddr,
   input  logic [ADDR_WIDTH-1:0]   raddr1,
   input  logic [ADDR_WIDTH-1:0]   raddr2,
   input  logic [DATA_WIDTH-1:0]   wdata,
   output logic [DATA_WIDTH-1:0]   rdata1,
   output logic [DATA_WIDTH-1:0]   rdata2
);

   logic [DATA_WIDTH-1:0] mem [0:2**ADDR_WIDTH-1];

   // 동기 쓰기
   always_ff @(posedge clk) begin
      if (we)
         mem[waddr] <= wdata;
   end

   // 비동기 읽기 — LUTRAM으로 합성됨 (BRAM 불가)
   assign rdata1 = mem[raddr1];
   assign rdata2 = mem[raddr2];

endmodule
