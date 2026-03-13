// ============================================================
// Chapter 21 — UART 디버그 모니터
// RISC-V 프로세서 설계 완전정복
// ============================================================
// 파이프라인 WB 스테이지의 PC, 명령어, 레지스터 변경을
// UART로 출력하는 간이 디버그 모니터입니다.
// MMIO 주소 0x4000_0100에 매핑하여 소프트웨어 제어 가능.
// ============================================================

module uart_debug_monitor #(
   parameter CLK_FREQ  = 50_000_000,  // 시스템 클럭 (50 MHz)
   parameter BAUD_RATE = 115_200      // UART 보드레이트
)(
   input  logic        clk,
   input  logic        rst_n,

   // === CPU 관찰 인터페이스 ===
   input  logic        wb_valid,      // WB 스테이지 유효 명령어
   input  logic [31:0] wb_pc,         // WB 스테이지 PC
   input  logic [31:0] wb_instr,      // WB 스테이지 명령어
   input  logic [4:0]  wb_rd,         // 목적 레지스터 번호
   input  logic [31:0] wb_rd_data,    // 목적 레지스터 기록 값
   input  logic        wb_reg_wen,    // 레지스터 쓰기 인에이블

   // === MMIO 제어 인터페이스 (APB) ===
   input  logic        psel,          // APB 선택
   input  logic        penable,       // APB 인에이블
   input  logic        pwrite,        // APB 쓰기
   input  logic [7:0]  paddr,         // APB 주소 (하위 8비트)
   input  logic [31:0] pwdata,        // APB 쓰기 데이터
   output logic [31:0] prdata,        // APB 읽기 데이터
   output logic        pready,        // APB 준비

   // === UART 출력 ===
   output logic        uart_tx        // UART TX 핀
);

   // ---------------------------------------------------------
   // 제어 레지스터
   // ---------------------------------------------------------
   // [0] enable      : 디버그 출력 활성화
   // [1] trace_pc    : PC 추적 활성화
   // [2] trace_reg   : 레지스터 변경 추적
   // [3] single_step : 단일 스텝 모드
   logic [31:0] ctrl_reg;
   logic [31:0] filter_pc_start;   // PC 필터 시작 주소
   logic [31:0] filter_pc_end;     // PC 필터 종료 주소

   wire  debug_enable  = ctrl_reg[0];
   wire  trace_pc      = ctrl_reg[1];
   wire  trace_reg     = ctrl_reg[2];
   wire  single_step   = ctrl_reg[3];

   // ---------------------------------------------------------
   // APB 레지스터 접근
   // ---------------------------------------------------------
   always_ff @(posedge clk or negedge rst_n) begin
      if (!rst_n) begin
         ctrl_reg         <= 32'h0000_0007;  // 기본: PC+레지스터 추적 활성
         filter_pc_start  <= 32'h0000_0000;
         filter_pc_end    <= 32'hFFFF_FFFF;
      end else if (psel && penable && pwrite) begin
         case (paddr)
            8'h00: ctrl_reg        <= pwdata;
            8'h04: filter_pc_start <= pwdata;
            8'h08: filter_pc_end   <= pwdata;
            default: ;
         endcase
      end
   end

   // APB 읽기
   always_comb begin
      case (paddr)
         8'h00:   prdata = ctrl_reg;
         8'h04:   prdata = filter_pc_start;
         8'h08:   prdata = filter_pc_end;
         8'h0C:   prdata = {30'b0, tx_busy, tx_fifo_full};
         default: prdata = 32'h0;
      endcase
   end

   assign pready = 1'b1;  // 항상 준비 (웨이트 스테이트 없음)

   // ---------------------------------------------------------
   // PC 필터 — 지정 범위의 PC만 출력
   // ---------------------------------------------------------
   logic pc_in_range;
   assign pc_in_range = (wb_pc >= filter_pc_start) &&
                        (wb_pc <= filter_pc_end);

   // ---------------------------------------------------------
   // 디버그 메시지 생성 FSM
   // ---------------------------------------------------------
   // 출력 형식: "[PC=XXXXXXXX] RdNN=XXXXXXXX\r\n"
   // Hex 변환 → ASCII 문자열 → UART TX FIFO 전송

   typedef enum logic [3:0] {
      S_IDLE,
      S_PREFIX,      // "[PC=" 출력
      S_PC_HEX,      // PC 값 8자리 hex 출력
      S_MID,         // "] " 출력
      S_RD_PREFIX,   // "Rd" 출력
      S_RD_NUM,      // 레지스터 번호 2자리 출력
      S_RD_EQ,       // "=" 출력
      S_RD_HEX,      // 레지스터 값 8자리 hex 출력
      S_NEWLINE      // "\r\n" 출력
   } state_t;

   state_t state, state_next;
   logic [3:0] char_idx;
   logic [3:0] char_idx_next;

   // 명령어 정보 래치
   logic [31:0] latched_pc;
   logic [4:0]  latched_rd;
   logic [31:0] latched_rd_data;
   logic        latched_has_rd;

   // TX FIFO 인터페이스
   logic       tx_fifo_push;
   logic [7:0] tx_fifo_data;
   logic       tx_fifo_full;
   logic       tx_busy;

   // Hex → ASCII 변환 함수
   function automatic logic [7:0] hex_to_ascii(input logic [3:0] nibble);
      if (nibble < 4'd10)
         return 8'h30 + {4'b0, nibble};  // '0'~'9'
      else
         return 8'h41 + {4'b0, nibble} - 8'd10;  // 'A'~'F'
   endfunction

   // PC의 특정 니블(4비트) 추출
   function automatic logic [3:0] get_nibble(
      input logic [31:0] value,
      input logic [3:0]  idx      // 7=MSB, 0=LSB
   );
      return value[idx*4 +: 4];
   endfunction

   // ---------------------------------------------------------
   // FSM 상태 전이
   // ---------------------------------------------------------
   always_ff @(posedge clk or negedge rst_n) begin
      if (!rst_n) begin
         state    <= S_IDLE;
         char_idx <= 4'd0;
      end else begin
         state    <= state_next;
         char_idx <= char_idx_next;
      end
   end

   // 명령어 정보 래치
   always_ff @(posedge clk or negedge rst_n) begin
      if (!rst_n) begin
         latched_pc      <= 32'h0;
         latched_rd      <= 5'h0;
         latched_rd_data <= 32'h0;
         latched_has_rd  <= 1'b0;
      end else if (state == S_IDLE && wb_valid && debug_enable && pc_in_range) begin
         latched_pc      <= wb_pc;
         latched_rd      <= wb_rd;
         latched_rd_data <= wb_rd_data;
         latched_has_rd  <= wb_reg_wen && (wb_rd != 5'd0);
      end
   end

   // ---------------------------------------------------------
   // FSM 조합 논리 — 문자 단위 출력 제어
   // ---------------------------------------------------------
   // 간략화된 구현: 실제 구현에서는 각 상태에서
   // 문자열의 각 바이트를 순차적으로 FIFO에 전송합니다.
   // 전체 코드는 지면 관계상 핵심 상태만 표시합니다.
   always_comb begin
      state_next    = state;
      char_idx_next = char_idx;
      tx_fifo_push  = 1'b0;
      tx_fifo_data  = 8'h00;

      case (state)
         S_IDLE: begin
            if (wb_valid && debug_enable && pc_in_range)
               state_next = S_PREFIX;
         end

         S_PREFIX: begin
            // "[PC=" → 4문자 순차 출력
            if (!tx_fifo_full) begin
               tx_fifo_push = 1'b1;
               case (char_idx)
                  4'd0: tx_fifo_data = 8'h5B;  // '['
                  4'd1: tx_fifo_data = 8'h50;  // 'P'
                  4'd2: tx_fifo_data = 8'h43;  // 'C'
                  4'd3: tx_fifo_data = 8'h3D;  // '='
                  default: ;
               endcase
               if (char_idx == 4'd3) begin
                  state_next    = S_PC_HEX;
                  char_idx_next = 4'd7;  // MSB 니블부터
               end else begin
                  char_idx_next = char_idx + 4'd1;
               end
            end
         end

         S_PC_HEX: begin
            // PC 값 8자리 hex 출력
            if (!tx_fifo_full) begin
               tx_fifo_push = 1'b1;
               tx_fifo_data = hex_to_ascii(
                  get_nibble(latched_pc, char_idx)
               );
               if (char_idx == 4'd0) begin
                  state_next    = S_MID;
                  char_idx_next = 4'd0;
               end else begin
                  char_idx_next = char_idx - 4'd1;
               end
            end
         end

         S_MID: begin
            // "] " → 2문자
            if (!tx_fifo_full) begin
               tx_fifo_push = 1'b1;
               case (char_idx)
                  4'd0: tx_fifo_data = 8'h5D;  // ']'
                  4'd1: tx_fifo_data = 8'h20;  // ' '
                  default: ;
               endcase
               if (char_idx == 4'd1) begin
                  if (latched_has_rd && trace_reg)
                     state_next = S_RD_PREFIX;
                  else
                     state_next = S_NEWLINE;
                  char_idx_next = 4'd0;
               end else begin
                  char_idx_next = char_idx + 4'd1;
               end
            end
         end

         S_NEWLINE: begin
            // "\r\n" → 2문자
            if (!tx_fifo_full) begin
               tx_fifo_push = 1'b1;
               case (char_idx)
                  4'd0: tx_fifo_data = 8'h0D;  // CR
                  4'd1: tx_fifo_data = 8'h0A;  // LF
                  default: ;
               endcase
               if (char_idx == 4'd1) begin
                  state_next    = S_IDLE;
                  char_idx_next = 4'd0;
               end else begin
                  char_idx_next = char_idx + 4'd1;
               end
            end
         end

         default: state_next = S_IDLE;
      endcase
   end

   // ---------------------------------------------------------
   // UART TX FIFO + 송신기 (Ch17 UART 모듈 재사용)
   // ---------------------------------------------------------
   // 16바이트 FIFO — 디버그 메시지 버퍼링
   logic       fifo_pop;
   logic [7:0] fifo_dout;
   logic       fifo_empty;

   sync_fifo #(
      .DATA_WIDTH (8),
      .DEPTH      (16)
   ) u_tx_fifo (
      .clk     (clk),
      .rst_n   (rst_n),
      .push    (tx_fifo_push),
      .din     (tx_fifo_data),
      .full    (tx_fifo_full),
      .pop     (fifo_pop),
      .dout    (fifo_dout),
      .empty   (fifo_empty)
   );

   // UART 송신기 인스턴스 (Ch17에서 설계한 모듈)
   uart_tx #(
      .CLK_FREQ  (CLK_FREQ),
      .BAUD_RATE (BAUD_RATE)
   ) u_uart_tx (
      .clk     (clk),
      .rst_n   (rst_n),
      .tx_data (fifo_dout),
      .tx_start(fifo_pop),
      .tx_busy (tx_busy),
      .tx_out  (uart_tx)
   );

   // FIFO에서 데이터가 있고 송신기가 유휴이면 전송 시작
   assign fifo_pop = !fifo_empty && !tx_busy;

endmodule
