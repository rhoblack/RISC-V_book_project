//=============================================================================
// AHB-Lite 공통 패키지
// - 전송 타입, 버스트 타입, 응답 코드 등 상수 정의
// - AMBA 3 AHB-Lite Protocol Specification 기반
//=============================================================================
package ahb_pkg;

   // HTRANS[1:0] — 전송 타입
   typedef enum logic [1:0] {
      HTRANS_IDLE   = 2'b00,   // 버스 유휴 상태
      HTRANS_BUSY   = 2'b01,   // 버스트 중 지연 (마스터가 준비 안됨)
      HTRANS_NONSEQ = 2'b10,   // 단일 전송 또는 버스트의 첫 번째 전송
      HTRANS_SEQ    = 2'b11    // 버스트의 연속 전송
   } htrans_t;

   // HBURST[2:0] — 버스트 타입
   typedef enum logic [2:0] {
      HBURST_SINGLE = 3'b000,  // 단일 전송
      HBURST_INCR   = 3'b001,  // 길이 미정 증분 버스트
      HBURST_WRAP4  = 3'b010,  // 4-beat 랩핑 버스트
      HBURST_INCR4  = 3'b011,  // 4-beat 증분 버스트
      HBURST_WRAP8  = 3'b100,  // 8-beat 랩핑 버스트
      HBURST_INCR8  = 3'b101,  // 8-beat 증분 버스트
      HBURST_WRAP16 = 3'b110,  // 16-beat 랩핑 버스트
      HBURST_INCR16 = 3'b111   // 16-beat 증분 버스트
   } hburst_t;

   // HSIZE[2:0] — 전송 크기
   typedef enum logic [2:0] {
      HSIZE_BYTE  = 3'b000,   // 8비트 (1바이트)
      HSIZE_HALF  = 3'b001,   // 16비트 (하프워드)
      HSIZE_WORD  = 3'b010    // 32비트 (워드)
   } hsize_t;

   // HRESP — 전송 응답
   typedef enum logic {
      HRESP_OKAY  = 1'b0,     // 전송 성공
      HRESP_ERROR = 1'b1      // 전송 오류
   } hresp_t;

   // AHB 주소 폭, 데이터 폭 파라미터
   parameter int AHB_ADDR_WIDTH = 32;
   parameter int AHB_DATA_WIDTH = 32;

endpackage
