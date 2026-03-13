///////////////////////////////////////////////////////////////////////////////
// 모듈명 : zicntr_counters
// 설  명 : Zicntr 확장 성능 카운터 구현
//          mcycle/mcycleh   (64비트 사이클 카운터)
//          minstret/minstreth (64비트 은퇴 명령어 카운터)
//          CSR 읽기/쓰기 인터페이스를 포함한다.
// 표  준 : IEEE 1800-2017 (SystemVerilog)
// 대상 보드 : Basys 3 (XC7A35T)
///////////////////////////////////////////////////////////////////////////////

module zicntr_counters (
   input  logic        clk,           // 시스템 클럭
   input  logic        rst_n,         // 비동기 리셋 (액티브 로우)

   // 카운터 증가 조건
   input  logic        instr_retire,  // 명령어 은퇴(retire) 신호

   // CSR 읽기/쓰기 인터페이스
   input  logic [11:0] csr_addr,      // CSR 주소
   input  logic        csr_wen,       // CSR 쓰기 인에이블
   input  logic [31:0] csr_wdata,     // CSR 쓰기 데이터
   output logic [31:0] csr_rdata,     // CSR 읽기 데이터
   output logic        csr_valid      // 유효한 CSR 주소 여부
);

   // ---------------------------------------------------------------
   // CSR 주소 정의 (RISC-V Privileged Spec)
   // ---------------------------------------------------------------
   localparam logic [11:0] CSR_MCYCLE    = 12'hB00;  // 사이클 카운터 하위
   localparam logic [11:0] CSR_MCYCLEH   = 12'hB80;  // 사이클 카운터 상위
   localparam logic [11:0] CSR_MINSTRET  = 12'hB02;  // 은퇴 명령어 카운터 하위
   localparam logic [11:0] CSR_MINSTRETH = 12'hB82;  // 은퇴 명령어 카운터 상위

   // 사용자 모드 읽기 전용 미러
   localparam logic [11:0] CSR_CYCLE     = 12'hC00;
   localparam logic [11:0] CSR_CYCLEH    = 12'hC80;
   localparam logic [11:0] CSR_INSTRET   = 12'hC02;
   localparam logic [11:0] CSR_INSTRETH  = 12'hC82;

   // ---------------------------------------------------------------
   // 64비트 카운터 레지스터
   // ---------------------------------------------------------------
   logic [63:0] mcycle_reg;
   logic [63:0] minstret_reg;

   // ---------------------------------------------------------------
   // mcycle: 매 클럭 사이클마다 +1
   // CSR 쓰기 시 값을 직접 설정할 수 있다.
   // ---------------------------------------------------------------
   always_ff @(posedge clk or negedge rst_n) begin
      if (!rst_n) begin
         mcycle_reg <= 64'd0;
      end else begin
         if (csr_wen && csr_addr == CSR_MCYCLE)
            mcycle_reg[31:0] <= csr_wdata;
         else if (csr_wen && csr_addr == CSR_MCYCLEH)
            mcycle_reg[63:32] <= csr_wdata;
         else
            mcycle_reg <= mcycle_reg + 64'd1;
      end
   end

   // ---------------------------------------------------------------
   // minstret: 명령어 은퇴(retire) 시 +1
   // WB 스테이지에서 instr_retire가 어서트될 때 증가한다.
   // ---------------------------------------------------------------
   always_ff @(posedge clk or negedge rst_n) begin
      if (!rst_n) begin
         minstret_reg <= 64'd0;
      end else begin
         if (csr_wen && csr_addr == CSR_MINSTRET)
            minstret_reg[31:0] <= csr_wdata;
         else if (csr_wen && csr_addr == CSR_MINSTRETH)
            minstret_reg[63:32] <= csr_wdata;
         else if (instr_retire)
            minstret_reg <= minstret_reg + 64'd1;
      end
   end

   // ---------------------------------------------------------------
   // CSR 읽기 다중화
   // 머신 모드 레지스터와 사용자 모드 미러 양쪽 모두 지원
   // ---------------------------------------------------------------
   always_comb begin
      csr_rdata = 32'd0;
      csr_valid = 1'b0;

      case (csr_addr)
         CSR_MCYCLE,  CSR_CYCLE:    begin csr_rdata = mcycle_reg[31:0];    csr_valid = 1'b1; end
         CSR_MCYCLEH, CSR_CYCLEH:   begin csr_rdata = mcycle_reg[63:32];   csr_valid = 1'b1; end
         CSR_MINSTRET, CSR_INSTRET: begin csr_rdata = minstret_reg[31:0];  csr_valid = 1'b1; end
         CSR_MINSTRETH, CSR_INSTRETH: begin csr_rdata = minstret_reg[63:32]; csr_valid = 1'b1; end
         default: begin
            csr_rdata = 32'd0;
            csr_valid = 1'b0;
         end
      endcase
   end

endmodule
