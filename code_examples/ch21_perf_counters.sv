// ============================================================
// Chapter 21 — 성능 카운터 (mcycle / minstret)
// RISC-V 프로세서 설계 완전정복
// ============================================================
// RISC-V Zicntr 확장의 핵심 카운터를 구현합니다.
// mcycle:   매 클럭 사이클 +1
// minstret: WB 스테이지에서 유효 명령어 커밋 시 +1
// IPC = minstret / mcycle
// ============================================================

module perf_counters (
   input  logic        clk,
   input  logic        rst_n,

   // === 파이프라인 제어 신호 ===
   input  logic        wb_valid,      // WB 스테이지 유효 커밋
   input  logic        count_inhibit, // 카운터 정지 (mcountinhibit CSR)

   // === CSR 읽기/쓰기 인터페이스 ===
   input  logic        csr_wen,       // CSR 쓰기 인에이블
   input  logic [11:0] csr_addr,      // CSR 주소
   input  logic [31:0] csr_wdata,     // CSR 쓰기 데이터
   output logic [31:0] csr_rdata,     // CSR 읽기 데이터
   output logic        csr_valid      // 유효 CSR 접근 (주소 일치)
);

   // ---------------------------------------------------------
   // CSR 주소 정의 (RISC-V 특권 사양)
   // ---------------------------------------------------------
   localparam CSR_MCYCLE       = 12'hB00;  // 하위 32비트
   localparam CSR_MCYCLEH      = 12'hB80;  // 상위 32비트
   localparam CSR_MINSTRET     = 12'hB02;  // 하위 32비트
   localparam CSR_MINSTRETH    = 12'hB82;  // 상위 32비트
   localparam CSR_MCOUNTINHIBIT = 12'h320; // 카운터 억제

   // ---------------------------------------------------------
   // 64비트 카운터 레지스터
   // ---------------------------------------------------------
   logic [63:0] mcycle;
   logic [63:0] minstret;
   logic [31:0] mcountinhibit;

   wire cycle_inhibit   = mcountinhibit[0];  // CY 비트
   wire instret_inhibit = mcountinhibit[2];  // IR 비트

   // ---------------------------------------------------------
   // mcycle 카운터 — 매 클럭 +1
   // ---------------------------------------------------------
   always_ff @(posedge clk or negedge rst_n) begin
      if (!rst_n) begin
         mcycle <= 64'h0;
      end else if (csr_wen && csr_addr == CSR_MCYCLE) begin
         // 소프트웨어 직접 쓰기 (하위 32비트)
         mcycle[31:0] <= csr_wdata;
      end else if (csr_wen && csr_addr == CSR_MCYCLEH) begin
         // 소프트웨어 직접 쓰기 (상위 32비트)
         mcycle[63:32] <= csr_wdata;
      end else if (!cycle_inhibit && !count_inhibit) begin
         mcycle <= mcycle + 64'h1;
      end
   end

   // ---------------------------------------------------------
   // minstret 카운터 — 유효 명령어 커밋 시 +1
   // ---------------------------------------------------------
   // wb_valid 조건:
   //   - WB 스테이지에 유효 명령어가 존재
   //   - NOP(버블), 플러시된 명령어, 스톨 중 명령어 제외
   //   - 예외 발생 명령어도 리타이어로 카운트
   // ---------------------------------------------------------
   always_ff @(posedge clk or negedge rst_n) begin
      if (!rst_n) begin
         minstret <= 64'h0;
      end else if (csr_wen && csr_addr == CSR_MINSTRET) begin
         minstret[31:0] <= csr_wdata;
      end else if (csr_wen && csr_addr == CSR_MINSTRETH) begin
         minstret[63:32] <= csr_wdata;
      end else if (wb_valid && !instret_inhibit && !count_inhibit) begin
         minstret <= minstret + 64'h1;
      end
   end

   // ---------------------------------------------------------
   // mcountinhibit 레지스터
   // ---------------------------------------------------------
   // [0] CY: mcycle 억제
   // [2] IR: minstret 억제
   // 다른 비트는 WARL(Write Any, Read Legal) = 0으로 처리
   always_ff @(posedge clk or negedge rst_n) begin
      if (!rst_n) begin
         mcountinhibit <= 32'h0;
      end else if (csr_wen && csr_addr == CSR_MCOUNTINHIBIT) begin
         mcountinhibit <= {29'b0, csr_wdata[2], 1'b0, csr_wdata[0]};
      end
   end

   // ---------------------------------------------------------
   // CSR 읽기 멀티플렉서
   // ---------------------------------------------------------
   always_comb begin
      csr_valid = 1'b1;
      case (csr_addr)
         CSR_MCYCLE:        csr_rdata = mcycle[31:0];
         CSR_MCYCLEH:       csr_rdata = mcycle[63:32];
         CSR_MINSTRET:      csr_rdata = minstret[31:0];
         CSR_MINSTRETH:     csr_rdata = minstret[63:32];
         CSR_MCOUNTINHIBIT: csr_rdata = mcountinhibit;
         default: begin
            csr_rdata = 32'h0;
            csr_valid = 1'b0;
         end
      endcase
   end

   // ---------------------------------------------------------
   // IPC 계산 보조 — 소프트웨어에서 사용하는 읽기 순서
   // ---------------------------------------------------------
   // RISC-V 권장 64비트 카운터 읽기 절차 (32비트 CPU):
   //
   //   retry:
   //     csrr  a2, mcycleh      // 상위 읽기
   //     csrr  a0, mcycle       // 하위 읽기
   //     csrr  a1, mcycleh      // 상위 재읽기
   //     bne   a2, a1, retry    // 상위 변경 시 재시도
   //
   // 이 절차로 읽기 중 오버플로 발생 시의 불일치를 방지합니다.
   // ---------------------------------------------------------

endmodule
