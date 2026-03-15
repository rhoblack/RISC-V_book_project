// =============================================================
// M 확장 곱셈/나눗셈 유닛 (RV32M)
// - 곱셈: 조합 논리 (DSP 슬라이스 자동 매핑)
// - 나눗셈: Restoring Division FSM (최대 36사이클: 초기화1+반복32+부호보정2+종료1)
//
// Chapter 24 — RV32I 확장: M & F 표준 확장
// =============================================================
module mul_div_unit #(
   parameter DATA_WIDTH = 32
)(
   input  logic                  clk,
   input  logic                  rst_n,
   input  logic                  start,       // 연산 시작
   input  logic                  flush,       // 파이프라인 flush
   input  logic [2:0]            funct3,      // 연산 종류
   input  logic [DATA_WIDTH-1:0] operand_a,   // rs1
   input  logic [DATA_WIDTH-1:0] operand_b,   // rs2
   output logic [DATA_WIDTH-1:0] result,      // 결과
   output logic                  ready,       // 결과 유효
   output logic                  busy         // 연산 진행 중
);

   // funct3 인코딩
   localparam MUL    = 3'b000;
   localparam MULH   = 3'b001;
   localparam MULHSU = 3'b010;
   localparam MULHU  = 3'b011;
   localparam DIV_OP = 3'b100;
   localparam DIVU   = 3'b101;
   localparam REM_OP = 3'b110;
   localparam REMU   = 3'b111;

   // -------------------------------------------------------
   // 곱셈: 조합 논리 (1사이클, DSP48E1 매핑)
   // -------------------------------------------------------
   logic signed [63:0] mul_ss;  // signed × signed
   logic signed [63:0] mul_su;  // signed × unsigned
   logic        [63:0] mul_uu;  // unsigned × unsigned

   assign mul_ss = $signed(operand_a) * $signed(operand_b);
   assign mul_su = $signed(operand_a) * $signed({1'b0, operand_b});
   assign mul_uu = {32'b0, operand_a} * {32'b0, operand_b};

   logic [DATA_WIDTH-1:0] mul_result;
   always_comb begin
      case (funct3)
         MUL:    mul_result = mul_ss[31:0];    // 하위 32비트
         MULH:   mul_result = mul_ss[63:32];   // 상위 (signed×signed)
         MULHSU: mul_result = mul_su[63:32];   // 상위 (signed×unsigned)
         MULHU:  mul_result = mul_uu[63:32];   // 상위 (unsigned×unsigned)
         default: mul_result = '0;
      endcase
   end

   // -------------------------------------------------------
   // 나눗셈: Restoring Division FSM
   // -------------------------------------------------------
   typedef enum logic [2:0] {
      IDLE,
      INIT,       // 부호 처리 및 절대값 변환
      COMPUTE,    // 반복 나눗셈 (32회)
      SIGN_ADJ,   // 결과 부호 보정
      DONE
   } div_state_t;

   div_state_t state, state_next;
   logic [5:0]            count;       // 반복 카운터 (0~31)
   logic [DATA_WIDTH-1:0] quotient;    // 몫
   logic [DATA_WIDTH:0]   remainder;   // 나머지 (33비트, 부호 비트 포함)
   logic [DATA_WIDTH-1:0] divisor_abs; // 제수 절대값
   logic [DATA_WIDTH-1:0] dividend_abs;// 피제수 절대값
   logic                  quot_sign;   // 몫 부호
   logic                  rem_sign;    // 나머지 부호
   logic                  div_by_zero; // 0으로 나누기
   logic                  is_signed;   // signed 연산 여부
   logic                  is_div;      // 나눗셈(DIV) vs 나머지(REM)

   assign is_signed  = (funct3 == DIV_OP) || (funct3 == REM_OP);
   assign is_div     = (funct3 == DIV_OP) || (funct3 == DIVU);
   assign div_by_zero = (operand_b == '0);

   // FSM: 상태 전이
   always_ff @(posedge clk or negedge rst_n) begin
      if (!rst_n)
         state <= IDLE;
      else if (flush)
         state <= IDLE;
      else
         state <= state_next;
   end

   always_comb begin
      state_next = state;
      case (state)
         IDLE:     if (start && (funct3 >= DIV_OP))
                      state_next = div_by_zero ? DONE : INIT;
         INIT:     state_next = COMPUTE;
         COMPUTE:  if (count == 6'd31)
                      state_next = is_signed ? SIGN_ADJ : DONE;
         SIGN_ADJ: state_next = DONE;
         DONE:     state_next = IDLE;
         default:  state_next = IDLE;
      endcase
   end

   // FSM: 데이터패스
   always_ff @(posedge clk or negedge rst_n) begin
      if (!rst_n) begin
         count        <= '0;
         quotient     <= '0;
         remainder    <= '0;
         divisor_abs  <= '0;
         dividend_abs <= '0;
         quot_sign    <= 1'b0;
         rem_sign     <= 1'b0;
      end else if (flush) begin
         count        <= '0;
         quotient     <= '0;
         remainder    <= '0;
      end else begin
         case (state)
            IDLE: begin
               count <= '0;
               if (start && div_by_zero) begin
                  // 0으로 나누기: 즉시 결과
                  if (is_div)
                     quotient <= 32'hFFFFFFFF;  // -1 (signed) 또는 max (unsigned)
                  else
                     quotient <= operand_a;     // REM 결과 = 피제수
               end
            end
            INIT: begin
               // 절대값 변환
               dividend_abs <= (is_signed && operand_a[31]) ?
                               (~operand_a + 1'b1) : operand_a;
               divisor_abs  <= (is_signed && operand_b[31]) ?
                               (~operand_b + 1'b1) : operand_b;
               quot_sign    <= is_signed &&
                               (operand_a[31] ^ operand_b[31]);
               rem_sign     <= is_signed && operand_a[31];
               remainder    <= '0;
               quotient     <= '0;
               count        <= '0;
            end
            COMPUTE: begin
               // Restoring Division 핵심 루프
               count <= count + 1'b1;
               begin
                  logic [DATA_WIDTH:0] shifted_rem;
                  logic [DATA_WIDTH:0] trial_sub;
                  shifted_rem = {remainder[DATA_WIDTH-1:0],
                                 dividend_abs[DATA_WIDTH-1-count[4:0]]};
                  trial_sub   = shifted_rem - {1'b0, divisor_abs};

                  if (!trial_sub[DATA_WIDTH]) begin
                     // 양수: 몫 비트 = 1
                     remainder <= trial_sub;
                     quotient[DATA_WIDTH-1-count[4:0]] <= 1'b1;
                  end else begin
                     // 음수: 몫 비트 = 0, 복원
                     remainder <= shifted_rem;
                     quotient[DATA_WIDTH-1-count[4:0]] <= 1'b0;
                  end
               end
            end
            SIGN_ADJ: begin
               if (quot_sign) quotient  <= ~quotient + 1'b1;
               if (rem_sign)  remainder <= ~remainder + 1'b1;
            end
            default: ;
         endcase
      end
   end

   // -------------------------------------------------------
   // 출력 선택
   // -------------------------------------------------------
   logic [DATA_WIDTH-1:0] div_result;
   assign div_result = is_div ? quotient : remainder[DATA_WIDTH-1:0];

   logic is_mul_op;
   assign is_mul_op = (funct3 <= MULHU);

   // 곱셈: start 후 1사이클에 ready
   logic mul_ready_r;
   always_ff @(posedge clk or negedge rst_n) begin
      if (!rst_n)     mul_ready_r <= 1'b0;
      else if (flush) mul_ready_r <= 1'b0;
      else            mul_ready_r <= start && is_mul_op;
   end

   assign result = is_mul_op ? mul_result : div_result;
   assign ready  = is_mul_op ? mul_ready_r : (state == DONE);
   assign busy   = is_mul_op ? 1'b0 :
                   (state != IDLE) && (state != DONE);

endmodule
