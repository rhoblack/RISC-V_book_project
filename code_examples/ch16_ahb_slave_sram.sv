//=============================================================================
// AHB-Lite Slave: SRAM 컨트롤러
// - 16KB (4096 워드) SRAM, BRAM 추론 가능
// - Address Phase / Data Phase 분리 처리
// - OKAY/ERROR 응답, 웨이트 스테이트 없음 (0-wait)
// - Basys 3 (XC7A35T) 합성 대상
//=============================================================================
module ahb_slave_sram
   import ahb_pkg::*;
#(
   parameter int MEM_DEPTH   = 4096,   // 메모리 깊이 (워드 단위)
   parameter int ADDR_BITS   = 12      // log2(MEM_DEPTH)
)(
   // 글로벌 신호
   input  logic                       hclk,       // AHB 클럭
   input  logic                       hreset_n,   // 비동기 리셋 (액티브 로우)

   // AHB-Lite 슬레이브 입력
   input  logic                       hsel,       // 슬레이브 선택 (디코더에서)
   input  logic [AHB_ADDR_WIDTH-1:0]  haddr,      // 주소
   input  htrans_t                    htrans,     // 전송 타입
   input  logic                       hwrite,     // 쓰기 신호
   input  hsize_t                     hsize,      // 전송 크기
   input  logic [AHB_DATA_WIDTH-1:0]  hwdata,     // 쓰기 데이터
   input  logic                       hready_in,  // 이전 슬레이브의 HREADY

   // AHB-Lite 슬레이브 출력
   output logic [AHB_DATA_WIDTH-1:0]  hrdata,     // 읽기 데이터
   output logic                       hready_out, // 전송 완료
   output hresp_t                     hresp       // 응답 상태
);

   //--------------------------------------------------------------------------
   // SRAM 메모리 배열 (BRAM 추론)
   //--------------------------------------------------------------------------
   logic [31:0] mem [0:MEM_DEPTH-1];

   //--------------------------------------------------------------------------
   // 주소 페이즈 래치 (Address Phase → Data Phase 변환)
   // AHB 핵심 규칙: 주소는 Address Phase에 도착하고,
   //                데이터는 다음 사이클(Data Phase)에 처리
   //--------------------------------------------------------------------------
   logic                      valid_r;    // 유효 전송 래치
   logic                      write_r;    // 쓰기 방향 래치
   logic [ADDR_BITS-1:0]      addr_r;     // 워드 주소 래치
   logic                      error_r;    // 주소 범위 오류 래치

   // 유효 전송 판별: HSELx AND (NONSEQ 또는 SEQ)
   wire valid_transfer = hsel && hready_in &&
                         (htrans == HTRANS_NONSEQ || htrans == HTRANS_SEQ);

   // 주소 범위 검사: ADDR_BITS 상위 비트가 0이 아니면 범위 초과
   wire addr_in_range = (haddr[AHB_ADDR_WIDTH-1:ADDR_BITS+2] == '0);

   //--------------------------------------------------------------------------
   // 주소 래치 레지스터 (posedge hclk)
   //--------------------------------------------------------------------------
   always_ff @(posedge hclk or negedge hreset_n) begin
      if (!hreset_n) begin
         valid_r <= 1'b0;
         write_r <= 1'b0;
         addr_r  <= '0;
         error_r <= 1'b0;
      end else if (hready_in) begin
         valid_r <= valid_transfer;
         write_r <= hwrite;
         addr_r  <= haddr[ADDR_BITS+1:2];  // 바이트 주소 → 워드 주소
         error_r <= valid_transfer && !addr_in_range;
      end
   end

   //--------------------------------------------------------------------------
   // SRAM 쓰기 (Data Phase에서 실행)
   //--------------------------------------------------------------------------
   always_ff @(posedge hclk) begin
      if (valid_r && write_r && !error_r)
         mem[addr_r] <= hwdata;
   end

   //--------------------------------------------------------------------------
   // SRAM 읽기 (Data Phase에서 실행)
   //--------------------------------------------------------------------------
   always_ff @(posedge hclk) begin
      if (valid_r && !write_r && !error_r)
         hrdata <= mem[addr_r];
      else
         hrdata <= '0;
   end

   //--------------------------------------------------------------------------
   // 응답 생성
   // - 0-wait state: HREADY 항상 HIGH
   // - 주소 범위 초과 시 ERROR 응답
   //--------------------------------------------------------------------------
   assign hready_out = 1'b1;   // 웨이트 스테이트 없음
   assign hresp      = error_r ? HRESP_ERROR : HRESP_OKAY;

endmodule
