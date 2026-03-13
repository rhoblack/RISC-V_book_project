///////////////////////////////////////////////////////////////////////////////
// 모듈명 : divider_iterative
// 설  명 : 반복(iterative) 방식의 32비트 나눗셈기
//          비복원 나눗셈(non-restoring division) 알고리즘을 사용한다.
//          32사이클에 걸쳐 1비트씩 몫을 산출하며, 완료 시 valid를 어서트한다.
// 표  준 : IEEE 1800-2017 (SystemVerilog)
// 대상 보드 : Basys 3 (XC7A35T)
// 참  고 : RISC-V 스펙에 따라 0으로 나누기(division by zero)와
//          오버플로(signed overflow) 예외를 정의한다.
///////////////////////////////////////////////////////////////////////////////

module divider_iterative (
   input  logic        clk,        // 시스템 클럭
   input  logic        rst_n,      // 비동기 리셋 (액티브 로우)
   input  logic        start,      // 나눗셈 시작
   input  logic        is_signed,  // 1: 부호 있는 나눗셈, 0: 부호 없는 나눗셈
   input  logic        is_rem,     // 1: 나머지(REM/REMU), 0: 몫(DIV/DIVU)
   input  logic [31:0] dividend,   // 피제수 (rs1)
   input  logic [31:0] divisor,    // 제수 (rs2)
   output logic [31:0] result,     // 나눗셈 결과
   output logic        valid,      // 결과 유효 신호
   output logic        busy        // 연산 진행 중
);

   // ---------------------------------------------------------------
   // 상태 정의
   // ---------------------------------------------------------------
   typedef enum logic [1:0] {
      S_IDLE  = 2'b00,   // 대기 상태
      S_CALC  = 2'b01,   // 반복 연산 중
      S_DONE  = 2'b10    // 완료
   } state_t;

   state_t state, next_state;

   // ---------------------------------------------------------------
   // 내부 레지스터
   // ---------------------------------------------------------------
   logic [63:0] remainder;    // {나머지, 부분 몫}
   logic [31:0] div_abs;      // 제수 절대값
   logic [5:0]  count;        // 반복 카운터 (0~31)
   logic        sign_quot;    // 몫 부호
   logic        sign_rem;     // 나머지 부호
   logic        div_by_zero;  // 0으로 나누기 플래그
   logic        overflow;     // 오버플로 플래그

   // ---------------------------------------------------------------
   // 절대값 계산 (부호 있는 나눗셈 지원)
   // ---------------------------------------------------------------
   logic [31:0] dvd_abs;  // 피제수 절대값
   logic [31:0] dvs_abs;  // 제수 절대값

   always_comb begin
      if (is_signed) begin
         dvd_abs = dividend[31] ? (~dividend + 1'b1) : dividend;
         dvs_abs = divisor[31]  ? (~divisor  + 1'b1) : divisor;
      end else begin
         dvd_abs = dividend;
         dvs_abs = divisor;
      end
   end

   // ---------------------------------------------------------------
   // 상태 전이
   // ---------------------------------------------------------------
   always_ff @(posedge clk or negedge rst_n) begin
      if (!rst_n)
         state <= S_IDLE;
      else
         state <= next_state;
   end

   always_comb begin
      next_state = state;
      case (state)
         S_IDLE: begin
            if (start)
               next_state = S_CALC;
         end
         S_CALC: begin
            if (count == 6'd32 || div_by_zero || overflow)
               next_state = S_DONE;
         end
         S_DONE: begin
            next_state = S_IDLE;
         end
         default: next_state = S_IDLE;
      endcase
   end

   // ---------------------------------------------------------------
   // 비복원 나눗셈 데이터패스
   // ---------------------------------------------------------------
   always_ff @(posedge clk or negedge rst_n) begin
      if (!rst_n) begin
         remainder   <= '0;
         div_abs     <= '0;
         count       <= '0;
         sign_quot   <= 1'b0;
         sign_rem    <= 1'b0;
         div_by_zero <= 1'b0;
         overflow    <= 1'b0;
      end else begin
         case (state)
            S_IDLE: begin
               if (start) begin
                  // RISC-V 스펙: 0으로 나누기 특수 처리
                  div_by_zero <= (divisor == 32'd0);

                  // RISC-V 스펙: signed overflow (-2^31 / -1 = 2^31, 표현 불가)
                  overflow <= is_signed &&
                              (dividend == 32'h8000_0000) &&
                              (divisor  == 32'hFFFF_FFFF);

                  // 초기화
                  remainder <= {32'd0, dvd_abs};
                  div_abs   <= dvs_abs;
                  count     <= 6'd0;
                  sign_quot <= is_signed & (dividend[31] ^ divisor[31]);
                  sign_rem  <= is_signed & dividend[31];
               end
            end

            S_CALC: begin
               if (!div_by_zero && !overflow) begin
                  // 1비트 시프트 후 뺄셈 시도
                  if (remainder[63:31] >= {1'b0, div_abs}) begin
                     remainder <= {remainder[63:31] - {1'b0, div_abs},
                                   remainder[30:0], 1'b1};
                  end else begin
                     remainder <= {remainder[62:0], 1'b0};
                  end
                  count <= count + 6'd1;
               end
            end

            S_DONE: begin
               // 아무 동작 없음 — 결과는 조합 논리로 출력
            end

            default: ;
         endcase
      end
   end

   // ---------------------------------------------------------------
   // 결과 선택 (조합 논리)
   // RISC-V 스펙 준수:
   //   div_by_zero → 몫 = -1 (all 1s), 나머지 = 피제수
   //   overflow    → 몫 = -2^31,       나머지 = 0
   // ---------------------------------------------------------------
   logic [31:0] quotient_raw;
   logic [31:0] remainder_raw;

   assign quotient_raw  = sign_quot ? (~remainder[31:0] + 1'b1) : remainder[31:0];
   assign remainder_raw = sign_rem  ? (~remainder[63:32] + 1'b1) : remainder[63:32];

   always_comb begin
      if (div_by_zero) begin
         result = is_rem ? dividend : 32'hFFFF_FFFF;
      end else if (overflow) begin
         result = is_rem ? 32'd0 : 32'h8000_0000;
      end else begin
         result = is_rem ? remainder_raw : quotient_raw;
      end
   end

   // 제어 출력
   assign valid = (state == S_DONE);
   assign busy  = (state == S_CALC);

endmodule
