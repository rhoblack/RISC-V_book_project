//=============================================================================
// AHB-Lite 인터커넥트: 단일 마스터 버스
// - 주소 디코더: HADDR 상위 4비트로 슬레이브 선택
// - 슬레이브 MUX: 활성 슬레이브의 응답을 마스터에 전달
// - 기본 슬레이브: 미매핑 주소에 ERROR 응답
// - 메모리 맵:
//     0x0000_0000 ~ 0x0000_3FFF : Slave 0 (SRAM, 16KB)
//     0x4000_0000 ~ 0x4FFF_FFFF : Slave 1 (APB Bridge)
//     기타 주소                  : Default Slave (ERROR)
//=============================================================================
module ahb_interconnect
   import ahb_pkg::*;
#(
   parameter int N_SLAVES = 2  // 슬레이브 개수
)(
   // 글로벌 신호
   input  logic                       hclk,
   input  logic                       hreset_n,

   // 마스터 인터페이스 (입력)
   input  logic [AHB_ADDR_WIDTH-1:0]  m_haddr,
   input  htrans_t                    m_htrans,
   input  logic                       m_hwrite,
   input  hsize_t                     m_hsize,
   input  hburst_t                    m_hburst,
   input  logic [AHB_DATA_WIDTH-1:0]  m_hwdata,

   // 마스터 인터페이스 (출력)
   output logic [AHB_DATA_WIDTH-1:0]  m_hrdata,
   output logic                       m_hready,
   output hresp_t                     m_hresp,

   // Slave 0 인터페이스 (SRAM)
   output logic                       s0_hsel,
   output logic [AHB_ADDR_WIDTH-1:0]  s0_haddr,
   output htrans_t                    s0_htrans,
   output logic                       s0_hwrite,
   output hsize_t                     s0_hsize,
   output logic [AHB_DATA_WIDTH-1:0]  s0_hwdata,
   output logic                       s0_hready_in,
   input  logic [AHB_DATA_WIDTH-1:0]  s0_hrdata,
   input  logic                       s0_hready_out,
   input  hresp_t                     s0_hresp,

   // Slave 1 인터페이스 (APB Bridge)
   output logic                       s1_hsel,
   output logic [AHB_ADDR_WIDTH-1:0]  s1_haddr,
   output htrans_t                    s1_htrans,
   output logic                       s1_hwrite,
   output hsize_t                     s1_hsize,
   output logic [AHB_DATA_WIDTH-1:0]  s1_hwdata,
   output logic                       s1_hready_in,
   input  logic [AHB_DATA_WIDTH-1:0]  s1_hrdata,
   input  logic                       s1_hready_out,
   input  hresp_t                     s1_hresp
);

   //--------------------------------------------------------------------------
   // 주소 디코더 (Address Decoder)
   // HADDR[31:28]로 슬레이브 선택
   //--------------------------------------------------------------------------
   logic hsel_default;  // 기본 슬레이브 선택

   always_comb begin
      // 기본값: 모든 선택 해제
      s0_hsel      = 1'b0;
      s1_hsel      = 1'b0;
      hsel_default = 1'b0;

      case (m_haddr[31:28])
         4'h0: s0_hsel = 1'b1;       // 0x0xxx_xxxx → SRAM
         4'h4: s1_hsel = 1'b1;       // 0x4xxx_xxxx → APB Bridge
         default: hsel_default = 1'b1; // 미매핑 → Default Slave
      endcase
   end

   //--------------------------------------------------------------------------
   // 공유 버스 신호 분배
   // 마스터의 주소/제어/데이터 신호를 모든 슬레이브에 동시 전달
   //--------------------------------------------------------------------------
   assign s0_haddr     = m_haddr;
   assign s0_htrans    = m_htrans;
   assign s0_hwrite    = m_hwrite;
   assign s0_hsize     = m_hsize;
   assign s0_hwdata    = m_hwdata;

   assign s1_haddr     = m_haddr;
   assign s1_htrans    = m_htrans;
   assign s1_hwrite    = m_hwrite;
   assign s1_hsize     = m_hsize;
   assign s1_hwdata    = m_hwdata;

   //--------------------------------------------------------------------------
   // 슬레이브 선택 래치 (Data Phase에서 올바른 응답 선택)
   // 주소 페이즈의 HSEL을 래치하여 데이터 페이즈에서 MUX 제어
   //--------------------------------------------------------------------------
   logic [1:0] sel_r;  // [0]=Slave0, [1]=Slave1

   always_ff @(posedge hclk or negedge hreset_n) begin
      if (!hreset_n)
         sel_r <= 2'b00;
      else if (m_hready)
         sel_r <= {s1_hsel, s0_hsel};
   end

   //--------------------------------------------------------------------------
   // 슬레이브 MUX (응답 멀티플렉서)
   // 래치된 선택 신호로 활성 슬레이브의 응답을 마스터에 전달
   //--------------------------------------------------------------------------
   always_comb begin
      case (sel_r)
         2'b01: begin  // Slave 0 (SRAM)
            m_hrdata = s0_hrdata;
            m_hready = s0_hready_out;
            m_hresp  = s0_hresp;
         end
         2'b10: begin  // Slave 1 (APB Bridge)
            m_hrdata = s1_hrdata;
            m_hready = s1_hready_out;
            m_hresp  = s1_hresp;
         end
         default: begin  // Default Slave
            m_hrdata = '0;
            m_hready = 1'b1;
            m_hresp  = HRESP_ERROR;
         end
      endcase
   end

   //--------------------------------------------------------------------------
   // HREADY 입력 신호 분배
   // 각 슬레이브는 현재 활성 슬레이브의 HREADY를 받아야 함
   //--------------------------------------------------------------------------
   assign s0_hready_in = m_hready;
   assign s1_hready_in = m_hready;

endmodule
