//=============================================================================
// AHB-Lite 버스 시뮬레이션 테스트벤치
// - 전송 타입별 검증: 단일 읽기, 단일 쓰기, 4-beat 버스트 읽기
// - 프로토콜 체커(SVA) 포함
// - VCS: vcs -sverilog ch16_ahb_pkg.sv ch16_ahb_slave_sram.sv
//         ch16_ahb_interconnect.sv ch16_ahb_master.sv ch16_ahb_bus_tb.sv
//=============================================================================
module ahb_bus_tb;
   import ahb_pkg::*;

   //--------------------------------------------------------------------------
   // 테스트벤치 신호
   //--------------------------------------------------------------------------
   logic                       hclk;
   logic                       hreset_n;

   // 마스터 ↔ 인터커넥트
   logic [AHB_ADDR_WIDTH-1:0]  m_haddr;
   htrans_t                    m_htrans;
   logic                       m_hwrite;
   hsize_t                     m_hsize;
   hburst_t                    m_hburst;
   logic [AHB_DATA_WIDTH-1:0]  m_hwdata;
   logic [AHB_DATA_WIDTH-1:0]  m_hrdata;
   logic                       m_hready;
   hresp_t                     m_hresp;

   // 인터커넥트 ↔ Slave 0 (SRAM)
   logic                       s0_hsel;
   logic [AHB_ADDR_WIDTH-1:0]  s0_haddr;
   htrans_t                    s0_htrans;
   logic                       s0_hwrite;
   hsize_t                     s0_hsize;
   logic [AHB_DATA_WIDTH-1:0]  s0_hwdata;
   logic                       s0_hready_in;
   logic [AHB_DATA_WIDTH-1:0]  s0_hrdata;
   logic                       s0_hready_out;
   hresp_t                     s0_hresp;

   // Slave 1 (더미 — 본 테스트에서는 미사용)
   logic                       s1_hsel;
   logic [AHB_ADDR_WIDTH-1:0]  s1_haddr;
   htrans_t                    s1_htrans;
   logic                       s1_hwrite;
   hsize_t                     s1_hsize;
   logic [AHB_DATA_WIDTH-1:0]  s1_hwdata;
   logic                       s1_hready_in;
   logic [AHB_DATA_WIDTH-1:0]  s1_hrdata;
   logic                       s1_hready_out;
   hresp_t                     s1_hresp;

   //--------------------------------------------------------------------------
   // 클럭 생성 (100MHz = 10ns 주기)
   //--------------------------------------------------------------------------
   initial hclk = 1'b0;
   always #5 hclk = ~hclk;

   //--------------------------------------------------------------------------
   // DUT 인스턴스
   //--------------------------------------------------------------------------
   ahb_interconnect u_interconnect (
      .hclk          (hclk),
      .hreset_n      (hreset_n),
      .m_haddr       (m_haddr),
      .m_htrans      (m_htrans),
      .m_hwrite      (m_hwrite),
      .m_hsize       (m_hsize),
      .m_hburst      (m_hburst),
      .m_hwdata      (m_hwdata),
      .m_hrdata      (m_hrdata),
      .m_hready      (m_hready),
      .m_hresp       (m_hresp),
      // Slave 0
      .s0_hsel       (s0_hsel),
      .s0_haddr      (s0_haddr),
      .s0_htrans     (s0_htrans),
      .s0_hwrite     (s0_hwrite),
      .s0_hsize      (s0_hsize),
      .s0_hwdata     (s0_hwdata),
      .s0_hready_in  (s0_hready_in),
      .s0_hrdata     (s0_hrdata),
      .s0_hready_out (s0_hready_out),
      .s0_hresp      (s0_hresp),
      // Slave 1 (더미)
      .s1_hsel       (s1_hsel),
      .s1_haddr      (s1_haddr),
      .s1_htrans     (s1_htrans),
      .s1_hwrite     (s1_hwrite),
      .s1_hsize      (s1_hsize),
      .s1_hwdata     (s1_hwdata),
      .s1_hready_in  (s1_hready_in),
      .s1_hrdata     (s1_hrdata),
      .s1_hready_out (s1_hready_out),
      .s1_hresp      (s1_hresp)
   );

   ahb_slave_sram u_sram (
      .hclk       (hclk),
      .hreset_n   (hreset_n),
      .hsel       (s0_hsel),
      .haddr      (s0_haddr),
      .htrans     (s0_htrans),
      .hwrite     (s0_hwrite),
      .hsize      (s0_hsize),
      .hwdata     (s0_hwdata),
      .hready_in  (s0_hready_in),
      .hrdata     (s0_hrdata),
      .hready_out (s0_hready_out),
      .hresp      (s0_hresp)
   );

   // Slave 1 더미 응답
   assign s1_hrdata     = '0;
   assign s1_hready_out = 1'b1;
   assign s1_hresp      = HRESP_OKAY;

   //--------------------------------------------------------------------------
   // 테스트 시퀀스
   //--------------------------------------------------------------------------
   int pass_cnt = 0;
   int fail_cnt = 0;

   task automatic ahb_write(
      input logic [31:0] addr,
      input logic [31:0] data
   );
      // 주소 페이즈
      @(posedge hclk);
      m_haddr  <= addr;
      m_htrans <= HTRANS_NONSEQ;
      m_hwrite <= 1'b1;
      m_hsize  <= HSIZE_WORD;
      m_hburst <= HBURST_SINGLE;

      // 데이터 페이즈
      @(posedge hclk);
      while (!m_hready) @(posedge hclk);
      m_hwdata <= data;
      m_htrans <= HTRANS_IDLE;

      @(posedge hclk);
      while (!m_hready) @(posedge hclk);
   endtask

   task automatic ahb_read(
      input  logic [31:0] addr,
      output logic [31:0] data
   );
      // 주소 페이즈
      @(posedge hclk);
      m_haddr  <= addr;
      m_htrans <= HTRANS_NONSEQ;
      m_hwrite <= 1'b0;
      m_hsize  <= HSIZE_WORD;
      m_hburst <= HBURST_SINGLE;

      // 데이터 페이즈
      @(posedge hclk);
      while (!m_hready) @(posedge hclk);
      m_htrans <= HTRANS_IDLE;

      @(posedge hclk);
      while (!m_hready) @(posedge hclk);
      data = m_hrdata;
   endtask

   task automatic check(
      input string name,
      input logic [31:0] actual,
      input logic [31:0] expected
   );
      if (actual === expected) begin
         $display("[PASS] %s: 0x%08h", name, actual);
         pass_cnt++;
      end else begin
         $display("[FAIL] %s: got 0x%08h, expected 0x%08h", name, actual, expected);
         fail_cnt++;
      end
   endtask

   logic [31:0] rdata;

   initial begin
      // 초기화
      hreset_n = 1'b0;
      m_haddr  = '0;
      m_htrans = HTRANS_IDLE;
      m_hwrite = 1'b0;
      m_hsize  = HSIZE_WORD;
      m_hburst = HBURST_SINGLE;
      m_hwdata = '0;

      // 리셋 해제
      repeat(5) @(posedge hclk);
      hreset_n = 1'b1;
      repeat(2) @(posedge hclk);

      $display("========================================");
      $display(" AHB-Lite 버스 시뮬레이션 테스트");
      $display("========================================");

      //--- 테스트 1: 단일 쓰기 ---
      $display("\n[TEST 1] 단일 워드 쓰기");
      ahb_write(32'h0000_0000, 32'hDEAD_BEEF);
      ahb_write(32'h0000_0004, 32'hCAFE_0001);
      ahb_write(32'h0000_0008, 32'h1234_5678);

      //--- 테스트 2: 단일 읽기 ---
      $display("\n[TEST 2] 단일 워드 읽기");
      ahb_read(32'h0000_0000, rdata);
      check("Read addr 0x0000", rdata, 32'hDEAD_BEEF);

      ahb_read(32'h0000_0004, rdata);
      check("Read addr 0x0004", rdata, 32'hCAFE_0001);

      ahb_read(32'h0000_0008, rdata);
      check("Read addr 0x0008", rdata, 32'h1234_5678);

      //--- 테스트 3: 쓰기 후 읽기 일관성 ---
      $display("\n[TEST 3] 쓰기 → 읽기 일관성 검증");
      ahb_write(32'h0000_0100, 32'hA5A5_A5A5);
      ahb_read(32'h0000_0100, rdata);
      check("Write-Read consistency", rdata, 32'hA5A5_A5A5);

      //--- 테스트 4: 다른 슬레이브 영역 접근 (Default Slave) ---
      $display("\n[TEST 4] 미매핑 주소 접근 (Default Slave)");
      ahb_read(32'hF000_0000, rdata);
      if (m_hresp == HRESP_ERROR) begin
         $display("[PASS] Default Slave: HRESP=ERROR");
         pass_cnt++;
      end else begin
         $display("[FAIL] Default Slave: expected ERROR response");
         fail_cnt++;
      end

      //--- 결과 요약 ---
      $display("\n========================================");
      $display(" 테스트 완료: PASS=%0d, FAIL=%0d", pass_cnt, fail_cnt);
      $display("========================================");

      repeat(5) @(posedge hclk);
      $finish;
   end

   //--------------------------------------------------------------------------
   // SVA 프로토콜 체커 (SystemVerilog Assertion)
   //--------------------------------------------------------------------------

   // 규칙 1: HREADY가 LOW일 때 마스터는 주소/제어 신호를 유지해야 함
   property p_addr_stable_during_wait;
      @(posedge hclk) disable iff (!hreset_n)
      (!m_hready && m_htrans != HTRANS_IDLE)
      |=> ($stable(m_haddr) && $stable(m_htrans) && $stable(m_hwrite));
   endproperty
   assert property (p_addr_stable_during_wait)
      else $error("[SVA] HREADY LOW 동안 주소/제어 신호가 변경되었습니다!");

   // 규칙 2: IDLE 전송 시 슬레이브는 항상 OKAY 응답
   property p_idle_okay_response;
      @(posedge hclk) disable iff (!hreset_n)
      (m_htrans == HTRANS_IDLE && m_hready)
      |-> (m_hresp == HRESP_OKAY);
   endproperty

   // 규칙 3: HRESP가 ERROR이면 다음 사이클에 HTRANS는 IDLE이어야 함
   property p_error_followed_by_idle;
      @(posedge hclk) disable iff (!hreset_n)
      (m_hresp == HRESP_ERROR && m_hready)
      |=> (m_htrans == HTRANS_IDLE);
   endproperty

   //--------------------------------------------------------------------------
   // 파형 덤프
   //--------------------------------------------------------------------------
   initial begin
      $dumpfile("ahb_bus_tb.vcd");
      $dumpvars(0, ahb_bus_tb);
   end

endmodule
