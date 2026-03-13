// =============================================================================
// APB GPIO 컨트롤러 (APB GPIO Controller)
// Chapter 17.4 — APB 브리지와 주변 장치 연결
// RISC-V 프로세서 설계 완전정복
// =============================================================================
// 범용 입출력(GPIO) 컨트롤러. 방향 레지스터로 각 핀의 입출력을 개별 설정.
// Basys 3 매핑: LED[15:0] = 출력, SW[15:0] + BTN[4:0] = 입력.
// 외부 비동기 입력은 2단 플립플롭으로 동기화하여 메타안정성 방지.
// =============================================================================

module apb_gpio #(
   parameter GPIO_WIDTH = 32          // GPIO 핀 수 (Basys 3: LED 16 + SW 16 + BTN 5)
)(
   // APB 인터페이스
   input  logic        pclk,          // APB 클럭
   input  logic        preset_n,      // 비동기 리셋
   input  logic        psel,          // 슬레이브 선택
   input  logic        penable,       // 전송 활성화
   input  logic        pwrite,        // 쓰기(1) / 읽기(0)
   input  logic [4:0]  paddr,         // 주소 (바이트 단위)
   input  logic [31:0] pwdata,        // 쓰기 데이터
   output logic [31:0] prdata,        // 읽기 데이터
   output logic        pready,        // 항상 1

   // GPIO 물리 핀
   output logic [GPIO_WIDTH-1:0] gpio_out,    // 출력 핀
   input  logic [GPIO_WIDTH-1:0] gpio_in,     // 입력 핀
   output logic [GPIO_WIDTH-1:0] gpio_oe,     // 출력 인에이블 (방향)

   // 인터럽트 출력
   output logic        gpio_irq       // 인터럽트 요청
);

   // =========================================================================
   // 레지스터 맵 정의
   // =========================================================================
   localparam ADDR_GPIO_DIR    = 5'h00;  // 방향 레지스터 (1=출력, 0=입력)
   localparam ADDR_GPIO_OUT    = 5'h04;  // 출력 데이터 레지스터
   localparam ADDR_GPIO_IN     = 5'h08;  // 입력 데이터 레지스터 (읽기 전용)
   localparam ADDR_GPIO_INT_EN = 5'h0C;  // 인터럽트 활성화 (에지 감지)

   // =========================================================================
   // 내부 레지스터
   // =========================================================================
   logic [GPIO_WIDTH-1:0] dir_reg;        // 방향: 1=출력, 0=입력
   logic [GPIO_WIDTH-1:0] out_reg;        // 출력 데이터
   logic [GPIO_WIDTH-1:0] int_en_reg;     // 인터럽트 활성화 (상승 에지)

   // =========================================================================
   // 입력 동기화 — 2단 플립플롭 (메타안정성 방지)
   // =========================================================================
   logic [GPIO_WIDTH-1:0] gpio_in_sync_0;
   logic [GPIO_WIDTH-1:0] gpio_in_sync_1;
   logic [GPIO_WIDTH-1:0] gpio_in_prev;    // 에지 감지용 이전 값

   always_ff @(posedge pclk or negedge preset_n) begin
      if (!preset_n) begin
         gpio_in_sync_0 <= '0;
         gpio_in_sync_1 <= '0;
         gpio_in_prev   <= '0;
      end else begin
         gpio_in_sync_0 <= gpio_in;
         gpio_in_sync_1 <= gpio_in_sync_0;
         gpio_in_prev   <= gpio_in_sync_1;
      end
   end

   // =========================================================================
   // APB 레지스터 쓰기
   // =========================================================================
   logic apb_write, apb_read;
   assign apb_write = psel && penable && pwrite;
   assign apb_read  = psel && penable && !pwrite;

   always_ff @(posedge pclk or negedge preset_n) begin
      if (!preset_n) begin
         dir_reg    <= '0;          // 리셋 시 모든 핀 입력
         out_reg    <= '0;
         int_en_reg <= '0;
      end else if (apb_write) begin
         case (paddr)
            ADDR_GPIO_DIR:    dir_reg    <= pwdata[GPIO_WIDTH-1:0];
            ADDR_GPIO_OUT:    out_reg    <= pwdata[GPIO_WIDTH-1:0];
            ADDR_GPIO_INT_EN: int_en_reg <= pwdata[GPIO_WIDTH-1:0];
            default: ; // 무시
         endcase
      end
   end

   // =========================================================================
   // APB 레지스터 읽기
   // =========================================================================
   always_comb begin
      prdata = 32'h0;
      case (paddr)
         ADDR_GPIO_DIR:    prdata = {{(32-GPIO_WIDTH){1'b0}}, dir_reg};
         ADDR_GPIO_OUT:    prdata = {{(32-GPIO_WIDTH){1'b0}}, out_reg};
         ADDR_GPIO_IN:     prdata = {{(32-GPIO_WIDTH){1'b0}}, gpio_in_sync_1};
         ADDR_GPIO_INT_EN: prdata = {{(32-GPIO_WIDTH){1'b0}}, int_en_reg};
         default:          prdata = 32'h0;
      endcase
   end

   // APB는 웨이트 없이 즉시 응답
   assign pready = 1'b1;

   // =========================================================================
   // 출력 로직
   // =========================================================================
   // 방향이 출력(1)인 핀만 out_reg 값을 출력, 입력(0) 핀은 0 유지
   assign gpio_out = out_reg & dir_reg;
   assign gpio_oe  = dir_reg;

   // =========================================================================
   // 인터럽트 로직 — 상승 에지(Rising Edge) 감지
   // =========================================================================
   logic [GPIO_WIDTH-1:0] rising_edge;
   assign rising_edge = gpio_in_sync_1 & ~gpio_in_prev;

   // 입력 핀(!dir_reg)에서만 인터럽트 감지
   assign gpio_irq = |(rising_edge & int_en_reg & ~dir_reg);

endmodule
