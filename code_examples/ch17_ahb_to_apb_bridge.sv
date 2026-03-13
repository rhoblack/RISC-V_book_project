// =============================================================================
// AHB-to-APB 브리지 (AHB-to-APB Bridge)
// Chapter 17.2 — APB 브리지와 주변 장치 연결
// RISC-V 프로세서 설계 완전정복
// =============================================================================
// AHB-Lite 마스터 인터페이스와 APB 슬레이브 인터페이스를 연결하는 프로토콜 변환 브리지.
// 3-상태 FSM(IDLE → SETUP → ACCESS)으로 동작하며,
// AHB 측에서 HREADY를 제어하여 웨이트 스테이트를 삽입합니다.
// =============================================================================

module ahb_to_apb_bridge #(
   parameter ADDR_WIDTH = 32,                     // 주소 버스 폭
   parameter DATA_WIDTH = 32,                     // 데이터 버스 폭
   parameter NUM_SLAVES = 4                       // APB 슬레이브 수
)(
   // 시스템 신호
   input  logic                    hclk,          // AHB 클럭 (= PCLK)
   input  logic                    hreset_n,      // 비동기 리셋 (액티브 로우)

   // AHB Slave 인터페이스 (CPU/마스터 → 브리지)
   input  logic [ADDR_WIDTH-1:0]   haddr,         // AHB 주소
   input  logic [1:0]              htrans,        // 전송 타입 (IDLE/NONSEQ)
   input  logic                    hwrite,        // 쓰기(1) / 읽기(0)
   input  logic [2:0]              hsize,         // 전송 크기
   input  logic [DATA_WIDTH-1:0]   hwdata,        // 쓰기 데이터
   output logic [DATA_WIDTH-1:0]   hrdata,        // 읽기 데이터
   output logic                    hready_out,    // 전송 완료 신호
   output logic                    hresp,         // 응답 (0=OKAY)

   // APB Master 인터페이스 (브리지 → 슬레이브)
   output logic [ADDR_WIDTH-1:0]   paddr,         // APB 주소
   output logic [NUM_SLAVES-1:0]   psel,          // 슬레이브 선택
   output logic                    penable,       // 전송 활성화
   output logic                    pwrite,        // 쓰기(1) / 읽기(0)
   output logic [DATA_WIDTH-1:0]   pwdata,        // 쓰기 데이터
   input  logic [DATA_WIDTH-1:0]   prdata,        // 읽기 데이터
   input  logic                    pready         // 슬레이브 준비 완료
);

   // =========================================================================
   // FSM 상태 정의
   // =========================================================================
   typedef enum logic [1:0] {
      ST_IDLE   = 2'b00,     // 유휴 상태: APB 전송 없음
      ST_SETUP  = 2'b01,     // 설정 단계: PSEL=1, PENABLE=0
      ST_ACCESS = 2'b10      // 접근 단계: PSEL=1, PENABLE=1
   } state_t;

   state_t state, next_state;

   // AHB 전송 타입 상수
   localparam HTRANS_IDLE   = 2'b00;
   localparam HTRANS_NONSEQ = 2'b10;

   // =========================================================================
   // AHB 측 주소/제어 래치 레지스터
   // =========================================================================
   // AHB는 파이프라인 전송이므로, 주소 단계(T1)에서 주소/제어를 캡처하고
   // 데이터 단계(T2)에서 HWDATA를 사용합니다.
   logic [ADDR_WIDTH-1:0] addr_reg;
   logic                  write_reg;
   logic                  valid_reg;    // 유효한 전송이 래치됨

   // AHB 주소 단계 캡처 (유효한 전송일 때만)
   always_ff @(posedge hclk or negedge hreset_n) begin
      if (!hreset_n) begin
         addr_reg  <= '0;
         write_reg <= 1'b0;
         valid_reg <= 1'b0;
      end else if (hready_out && (htrans == HTRANS_NONSEQ)) begin
         addr_reg  <= haddr;
         write_reg <= hwrite;
         valid_reg <= 1'b1;
      end else if (state == ST_ACCESS && pready) begin
         valid_reg <= 1'b0;
      end
   end

   // =========================================================================
   // FSM 상태 레지스터
   // =========================================================================
   always_ff @(posedge hclk or negedge hreset_n) begin
      if (!hreset_n)
         state <= ST_IDLE;
      else
         state <= next_state;
   end

   // =========================================================================
   // FSM 다음 상태 로직
   // =========================================================================
   always_comb begin
      next_state = state;

      case (state)
         ST_IDLE: begin
            // AHB에서 유효한 전송이 들어오면 SETUP으로 진입
            if (htrans == HTRANS_NONSEQ && hready_out)
               next_state = ST_SETUP;
         end

         ST_SETUP: begin
            // SETUP 단계는 항상 1사이클 → ACCESS로 전이
            next_state = ST_ACCESS;
         end

         ST_ACCESS: begin
            if (pready) begin
               // 슬레이브가 완료 → 다음 전송이 대기 중이면 SETUP, 아니면 IDLE
               if (valid_reg)
                  next_state = ST_SETUP;
               else
                  next_state = ST_IDLE;
            end
            // pready=0이면 ACCESS 상태 유지 (웨이트 스테이트)
         end

         default: next_state = ST_IDLE;
      endcase
   end

   // =========================================================================
   // APB 슬레이브 선택 디코더 (주소 상위 비트 기반)
   // =========================================================================
   // 주소 맵 (4KB 단위):
   //   Slave 0: 0x4000_0000 ~ 0x4000_0FFF (UART)
   //   Slave 1: 0x4000_1000 ~ 0x4000_1FFF (GPIO)
   //   Slave 2: 0x4000_2000 ~ 0x4000_2FFF (Timer)
   //   Slave 3: 0x4000_3000 ~ 0x4000_3FFF (예약)
   logic [NUM_SLAVES-1:0] psel_decoded;

   always_comb begin
      psel_decoded = '0;
      case (addr_reg[13:12])
         2'b00: psel_decoded[0] = 1'b1;   // UART
         2'b01: psel_decoded[1] = 1'b1;   // GPIO
         2'b10: psel_decoded[2] = 1'b1;   // Timer
         2'b11: psel_decoded[3] = 1'b1;   // Reserved
         default: psel_decoded  = '0;
      endcase
   end

   // =========================================================================
   // APB 출력 신호 생성
   // =========================================================================
   always_comb begin
      paddr   = addr_reg;
      pwrite  = write_reg;
      pwdata  = hwdata;       // AHB 데이터 단계에서 직접 전달

      case (state)
         ST_SETUP: begin
            psel    = psel_decoded;
            penable = 1'b0;
         end

         ST_ACCESS: begin
            psel    = psel_decoded;
            penable = 1'b1;
         end

         default: begin
            psel    = '0;
            penable = 1'b0;
         end
      endcase
   end

   // =========================================================================
   // AHB 응답 신호
   // =========================================================================
   // HREADY: IDLE/SETUP에서는 즉시 ready (새 주소 수신 가능)
   //         ACCESS에서는 PREADY가 올 때까지 대기
   always_comb begin
      case (state)
         ST_IDLE:   hready_out = 1'b1;
         ST_SETUP:  hready_out = 1'b0;    // SETUP 진입 시 1사이클 대기
         ST_ACCESS: hready_out = pready;   // 슬레이브 응답 대기
         default:   hready_out = 1'b1;
      endcase
   end

   // 읽기 데이터는 APB 슬레이브에서 직접 전달
   assign hrdata = prdata;

   // 항상 OKAY 응답 (에러 응답 미지원)
   assign hresp = 1'b0;

endmodule
