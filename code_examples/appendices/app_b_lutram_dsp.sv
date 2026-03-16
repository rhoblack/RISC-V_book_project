// Appendix B: LUTRAM & DSP48E1 추론 패턴
// SystemVerilog - Vivado 합성 가능 코드

// ============================================================
// 패턴 1: LUTRAM (SRL - Shift Register LUT)
// ============================================================
module lutram_srl #(
    parameter int DEPTH = 32,
    parameter int DATA_WIDTH = 32
) (
    input  logic clk,
    input  logic [4:0] addr,          // SRL은 최대 32단계
    input  logic [DATA_WIDTH-1:0] din,
    output logic [DATA_WIDTH-1:0] dout
);

    logic [DATA_WIDTH-1:0] shift_reg [DEPTH];

    // SRL 추론: 레지스터 체인
    always_ff @(posedge clk) begin
        shift_reg[0] <= din;
        for (int i = 1; i < DEPTH; i++) begin
            shift_reg[i] <= shift_reg[i-1];
        end
    end

    assign dout = shift_reg[addr];

endmodule

// ============================================================
// 패턴 2: DSP48E1 곱셈 추론
// Xilinx Basys 3: DSP48E1 90개
// ============================================================
module dsp48e1_multiplier #(
    parameter int A_WIDTH = 18,
    parameter int B_WIDTH = 25
) (
    input  logic clk,
    input  logic [A_WIDTH-1:0] a,
    input  logic [B_WIDTH-1:0] b,
    output logic [A_WIDTH+B_WIDTH-1:0] p
);

    logic [A_WIDTH-1:0] a_reg;
    logic [B_WIDTH-1:0] b_reg;
    logic [A_WIDTH+B_WIDTH-1:0] p_temp;

    // 입력 파이프라인 (DSP 내부)
    always_ff @(posedge clk) begin
        a_reg <= a;
        b_reg <= b;
    end

    // 곱셈 (DSP 핵심)
    always_ff @(posedge clk) begin
        p_temp <= a_reg * b_reg;
    end

    // 출력
    assign p = p_temp;

endmodule

// ============================================================
// 패턴 3: DSP48E1 누적 곱셈 (MAC - Multiply-Accumulate)
// ============================================================
module dsp48e1_mac #(
    parameter int A_WIDTH = 18,
    parameter int B_WIDTH = 25
) (
    input  logic clk,
    input  logic rst_n,
    input  logic [A_WIDTH-1:0] a,
    input  logic [B_WIDTH-1:0] b,
    output logic [A_WIDTH+B_WIDTH+10-1:0] acc  // 더 큰 결과
);

    logic [A_WIDTH-1:0] a_reg;
    logic [B_WIDTH-1:0] b_reg;
    logic [A_WIDTH+B_WIDTH+10-1:0] acc_reg;

    // 입력 파이프라인
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            a_reg <= '0;
            b_reg <= '0;
        end else begin
            a_reg <= a;
            b_reg <= b;
        end
    end

    // MAC 연산
    always_ff @(posedge clk) begin
        if (!rst_n)
            acc_reg <= '0;
        else
            acc_reg <= acc_reg + (a_reg * b_reg);
    end

    assign acc = acc_reg;

endmodule

// ============================================================
// 패턴 4: DSP48E1 광범위 곱셈 (Wide Multiplier)
// 32-bit × 32-bit = 64-bit 곱셈
// ============================================================
module dsp48e1_wide_mult #(
    parameter int AW = 32,
    parameter int BW = 32
) (
    input  logic clk,
    input  logic [AW-1:0] a,
    input  logic [BW-1:0] b,
    output logic [AW+BW-1:0] p
);

    // Vivado는 32×32 곱셈을 자동으로 DSP 여러 개 사용
    logic [AW+BW-1:0] p_reg;

    always_ff @(posedge clk) begin
        p_reg <= a * b;
    end

    assign p = p_reg;

endmodule

// ============================================================
// 주의: Vivado DSP 추론 규칙
// ============================================================

/*
DSP48E1 추론 조건:
1. 곱셈 연산자 (*) 사용
   ✓ p = a * b;
   ✓ p = a * b + c;
   ✗ 비트 단위 곱셈 (논리 게이트만 사용)

2. 레지스터 (always_ff)
   ✓ DSP 내부 파이프라인 활용
   ✗ 조합 곱셈 (조합 논리만 사용하면 LUT)

3. 데이터폭 제한
   - A: 최대 18비트
   - B: 최대 25비트
   - P: 최대 48비트 (A×B)
   - 더 큰 곱셈은 DSP 여러 개 자동 연결

4. 누적 (MAC)
   ✓ p = p + (a * b);  // DSP 내부 가산기 사용
   ✗ p = a * b; p = p + c;  // 별도 가산기

5. Basys 3 제약
   - DSP48E1: 90개 한정
   - 32×32 곱셈: ~4개 DSP 사용
   - 성능 우선이면 DSP 활용, 면적 우선이면 LUT 사용
*/

// ============================================================
// 비교: LUT 기반 곱셈 vs DSP 기반 곱셈
// ============================================================

// ❌ 느림: LUT 기반 (조합)
module mult_lut #(
    parameter int A_WIDTH = 16,
    parameter int B_WIDTH = 16
) (
    input  logic [A_WIDTH-1:0] a,
    input  logic [B_WIDTH-1:0] b,
    output logic [A_WIDTH+B_WIDTH-1:0] p
);
    // 조합 곱셈 → LUT 사용 → 느림
    assign p = a * b;
endmodule

// ✓ 빠름: DSP 기반 (동기)
module mult_dsp #(
    parameter int A_WIDTH = 16,
    parameter int B_WIDTH = 16
) (
    input  logic clk,
    input  logic [A_WIDTH-1:0] a,
    input  logic [B_WIDTH-1:0] b,
    output logic [A_WIDTH+B_WIDTH-1:0] p
);
    logic [A_WIDTH-1:0] a_reg;
    logic [B_WIDTH-1:0] b_reg;
    logic [A_WIDTH+B_WIDTH-1:0] p_reg;

    always_ff @(posedge clk) begin
        a_reg <= a;
        b_reg <= b;
        p_reg <= a_reg * b_reg;
    end

    assign p = p_reg;
endmodule

// ============================================================
// Vivado 합성 지시 (Pragma)
// ============================================================

/*
Vivado 합성 시 다음 pragma로 세부 제어 가능:

1. 메모리 타입 강제:
   (* ram_style = "block" *)     // BRAM 강제
   (* ram_style = "distributed" *) // LUTRAM 강제

2. DSP 추론 제어:
   (* use_dsp = "yes" *)         // DSP 강제 사용
   (* use_dsp = "no" *)          // DSP 금지 (LUT만)

3. 병렬화:
   (* parallel_case *)           // case 병렬 처리
   (* full_case *)               // 모든 경우 명시적 처리

4. 인라인:
   (* inline *)                  // 모듈 인라인
   (* noinline *)                // 인라인 금지

예시:
    (* use_dsp = "yes" *)
    logic [31:0] mult_result;
    always_ff @(posedge clk) begin
        mult_result <= a[15:0] * b[15:0];
    end
*/
