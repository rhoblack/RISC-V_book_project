// Appendix B: BRAM 추론 패턴
// SystemVerilog - Vivado 합성 가능 코드

// ============================================================
// 패턴 1: Simple Dual Port BRAM (읽기/쓰기 독립 포트)
// ============================================================
module bram_sdp #(
    parameter int DATA_WIDTH = 32,
    parameter int ADDR_WIDTH = 10,
    parameter int DEPTH = 1 << ADDR_WIDTH
) (
    input  logic clk,

    // 읽기 포트 (비동기)
    input  logic [ADDR_WIDTH-1:0] rd_addr,
    output logic [DATA_WIDTH-1:0] rd_data,

    // 쓰기 포트 (동기)
    input  logic [ADDR_WIDTH-1:0] wr_addr,
    input  logic [DATA_WIDTH-1:0] wr_data,
    input  logic wr_en
);

    logic [DATA_WIDTH-1:0] mem [DEPTH];

    // 동기 쓰기 (BRAM 기본)
    always_ff @(posedge clk) begin
        if (wr_en)
            mem[wr_addr] <= wr_data;
    end

    // 비동기 읽기 (조합 논리)
    assign rd_data = mem[rd_addr];

endmodule

// ============================================================
// 패턴 2: True Dual Port BRAM (동일 클럭, 동기 읽기)
// ============================================================
module bram_tdp #(
    parameter int DATA_WIDTH = 32,
    parameter int ADDR_WIDTH = 10,
    parameter int DEPTH = 1 << ADDR_WIDTH
) (
    input  logic clk,

    // 포트 A
    input  logic [ADDR_WIDTH-1:0] a_addr,
    input  logic a_wr_en,
    input  logic [DATA_WIDTH-1:0] a_wr_data,
    output logic [DATA_WIDTH-1:0] a_rd_data,

    // 포트 B
    input  logic [ADDR_WIDTH-1:0] b_addr,
    input  logic b_wr_en,
    input  logic [DATA_WIDTH-1:0] b_wr_data,
    output logic [DATA_WIDTH-1:0] b_rd_data
);

    logic [DATA_WIDTH-1:0] mem [DEPTH];

    // 포트 A: 동기 읽기/쓰기
    always_ff @(posedge clk) begin
        if (a_wr_en)
            mem[a_addr] <= a_wr_data;
        else
            a_rd_data <= mem[a_addr];
    end

    // 포트 B: 동기 읽기/쓰기
    always_ff @(posedge clk) begin
        if (b_wr_en)
            mem[b_addr] <= b_wr_data;
        else
            b_rd_data <= mem[b_addr];
    end

endmodule

// ============================================================
// 패턴 3: BRAM with Write-First (쓰기 우선, 읽기 포함)
// Vivado 권장: "write_first"
// ============================================================
module bram_write_first #(
    parameter int DATA_WIDTH = 32,
    parameter int ADDR_WIDTH = 10,
    parameter int DEPTH = 1 << ADDR_WIDTH
) (
    input  logic clk,
    input  logic [ADDR_WIDTH-1:0] addr,
    input  logic [DATA_WIDTH-1:0] wr_data,
    output logic [DATA_WIDTH-1:0] rd_data,
    input  logic wr_en
);

    logic [DATA_WIDTH-1:0] mem [DEPTH];

    always_ff @(posedge clk) begin
        if (wr_en) begin
            mem[addr] <= wr_data;
            rd_data <= wr_data;  // 쓰기와 동시에 쓴 데이터 반환
        end else begin
            rd_data <= mem[addr];
        end
    end

endmodule

// ============================================================
// 패턴 4: LUTRAM 직접 구현 (분산 RAM, 조합 읽기)
// Vivado 합성 옵션: (* ram_style = "distributed" *)
// ============================================================
module lutram_distributed #(
    parameter int DATA_WIDTH = 32,
    parameter int ADDR_WIDTH = 5,  // LUTRAM은 작은 주소폭
    parameter int DEPTH = 1 << ADDR_WIDTH
) (
    input  logic clk,
    input  logic [ADDR_WIDTH-1:0] rd_addr,
    input  logic [ADDR_WIDTH-1:0] wr_addr,
    input  logic [DATA_WIDTH-1:0] wr_data,
    input  logic wr_en,
    output logic [DATA_WIDTH-1:0] rd_data
);

    (* ram_style = "distributed" *)
    logic [DATA_WIDTH-1:0] mem [DEPTH];

    // 동기 쓰기
    always_ff @(posedge clk) begin
        if (wr_en)
            mem[wr_addr] <= wr_data;
    end

    // 비동기 읽기 (조합 논리)
    assign rd_data = mem[rd_addr];

endmodule

// ============================================================
// 주의: 피해야 할 패턴
// ============================================================

// ❌ 틀린 예: 조합 루프 (X)
// always_comb begin
//     mem[addr] <= data;  // 비동기 쓰기는 합성 불가
// end

// ❌ 틀린 예: 초기화 블록의 반복 사용 (X)
// always @(*) begin
//     if (reset)
//         for (int i = 0; i < DEPTH; i++)
//             mem[i] = 0;  // 합성 불가
// end

// ============================================================
// Vivado 합성 팁
// ============================================================
/*
1. BRAM vs LUTRAM 선택:
   - BRAM: 큰 메모리 (>1KB), 높은 성능
   - LUTRAM: 작은 메모리 (<1KB), 빠른 접근

2. (* ram_style = "distributed" *)
   - LUTRAM 강제 추론
   - 기본값 없이 Vivado는 자동 최적화

3. (* ram_style = "block" *)
   - BRAM 강제 추론
   - DEPTH가 자동으로 2^N으로 조정될 수 있음

4. 제약: Basys 3 XC7A35T
   - BRAM: 50개 × 36Kb (최대 1.8MB)
   - LUT: 20,800개
   - 메모리 설계 시 BRAM/LUTRAM 혼합 전략 권장
*/
