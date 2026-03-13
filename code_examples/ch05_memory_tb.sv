//=============================================================================
// 모듈명  : memory_tb
// 파일명  : ch05_memory_tb.sv
// 설명    : IMEM/DMEM 통합 테스트벤치
//           - IMEM: .hex 파일 로드 및 명령어 읽기 검증
//           - DMEM: 바이트/하프워드/워드 스토어-로드 시퀀스 검증
//           - 부호 확장/제로 확장 정확성 검증
//           - 바이트 인에이블 동작 검증
// 저자    : RISC-V 프로세서 설계 완전정복
// 표준    : SystemVerilog IEEE 1800-2017
//=============================================================================

`timescale 1ns / 1ps

module memory_tb;

   //--------------------------------------------------------------------------
   // 테스트벤치 신호 선언
   //--------------------------------------------------------------------------
   logic        clk;
   logic        rst_n;

   // IMEM 인터페이스
   logic [31:0] imem_pc;
   logic [31:0] imem_instr;

   // DMEM 인터페이스
   logic [31:0] dmem_addr;
   logic [31:0] dmem_wdata;
   logic        dmem_write;
   logic [2:0]  dmem_funct3;
   logic [31:0] dmem_rdata;

   // 테스트 결과 카운터
   int          test_pass;
   int          test_fail;
   int          test_total;

   //--------------------------------------------------------------------------
   // 클록 생성 (주기: 10ns = 100MHz)
   //--------------------------------------------------------------------------
   initial clk = 1'b0;
   always #5 clk = ~clk;

   //--------------------------------------------------------------------------
   // DUT 인스턴스: 명령어 메모리 (IMEM)
   //--------------------------------------------------------------------------
   instruction_memory #(
      .ADDR_WIDTH (12),
      .INIT_FILE  ("test_program.hex")
   ) u_imem (
      .pc_i    (imem_pc),
      .instr_o (imem_instr)
   );

   //--------------------------------------------------------------------------
   // DUT 인스턴스: 데이터 메모리 (DMEM)
   //--------------------------------------------------------------------------
   data_memory #(
      .ADDR_WIDTH (12)
   ) u_dmem (
      .clk_i       (clk),
      .rst_ni      (rst_n),
      .addr_i      (dmem_addr),
      .wdata_i     (dmem_wdata),
      .mem_write_i (dmem_write),
      .funct3_i    (dmem_funct3),
      .rdata_o     (dmem_rdata)
   );

   //--------------------------------------------------------------------------
   // funct3 상수 정의 (가독성)
   //--------------------------------------------------------------------------
   localparam logic [2:0] F3_B  = 3'b000;  // Byte
   localparam logic [2:0] F3_H  = 3'b001;  // Halfword
   localparam logic [2:0] F3_W  = 3'b010;  // Word
   localparam logic [2:0] F3_BU = 3'b100;  // Byte Unsigned
   localparam logic [2:0] F3_HU = 3'b101;  // Halfword Unsigned

   //--------------------------------------------------------------------------
   // 검증 태스크: 기대값과 실제값 비교
   //--------------------------------------------------------------------------
   task automatic check_result(
      input string test_name,
      input logic [31:0] expected,
      input logic [31:0] actual
   );
      test_total++;
      if (expected === actual) begin
         test_pass++;
         $display("[PASS] %s: expected=0x%08h, actual=0x%08h", test_name, expected, actual);
      end else begin
         test_fail++;
         $display("[FAIL] %s: expected=0x%08h, actual=0x%08h", test_name, expected, actual);
      end
   endtask

   //--------------------------------------------------------------------------
   // DMEM 쓰기 태스크
   //--------------------------------------------------------------------------
   task automatic dmem_store(
      input logic [31:0] addr,
      input logic [31:0] data,
      input logic [2:0]  funct3
   );
      @(negedge clk);          // 클록 하강 에지에서 입력 안정화
      dmem_addr   = addr;
      dmem_wdata  = data;
      dmem_funct3 = funct3;
      dmem_write  = 1'b1;
      @(posedge clk);          // 상승 에지에서 쓰기 수행
      #1;                       // 약간의 지연 (전파 시간)
      dmem_write  = 1'b0;
   endtask

   //--------------------------------------------------------------------------
   // DMEM 읽기 태스크
   //--------------------------------------------------------------------------
   task automatic dmem_load(
      input  logic [31:0] addr,
      input  logic [2:0]  funct3,
      output logic [31:0] data
   );
      @(negedge clk);
      dmem_addr   = addr;
      dmem_funct3 = funct3;
      dmem_write  = 1'b0;
      #1;                       // 비동기 읽기 안정화 대기
      data = dmem_rdata;
   endtask

   //--------------------------------------------------------------------------
   // 메인 테스트 시퀀스
   //--------------------------------------------------------------------------
   initial begin
      // 초기화
      test_pass  = 0;
      test_fail  = 0;
      test_total = 0;
      rst_n      = 1'b0;
      dmem_write = 1'b0;
      dmem_addr  = 32'h0;
      dmem_wdata = 32'h0;
      dmem_funct3 = F3_W;
      imem_pc    = 32'h0;

      // 리셋 해제
      #20;
      rst_n = 1'b1;
      #10;

      $display("============================================================");
      $display("  메모리 서브시스템 테스트벤치 시작");
      $display("============================================================");

      //----------------------------------------------------------------------
      // 테스트 1: IMEM 명령어 읽기 검증
      //----------------------------------------------------------------------
      $display("\n--- 테스트 1: IMEM 명령어 읽기 ---");

      imem_pc = 32'h0000_0000;  // 첫 번째 명령어 주소
      #2;
      // 주의: test_program.hex가 없으면 NOP(0x00000013)이 읽힘
      $display("  IMEM[0x000] = 0x%08h", imem_instr);

      imem_pc = 32'h0000_0004;  // 두 번째 명령어 (PC+4)
      #2;
      $display("  IMEM[0x004] = 0x%08h", imem_instr);

      imem_pc = 32'h0000_0008;  // 세 번째 명령어 (PC+8)
      #2;
      $display("  IMEM[0x008] = 0x%08h", imem_instr);

      //----------------------------------------------------------------------
      // 테스트 2: DMEM 워드 스토어/로드 (SW/LW)
      //----------------------------------------------------------------------
      $display("\n--- 테스트 2: 워드 스토어/로드 (SW/LW) ---");

      // SW: 0xDEAD_BEEF를 주소 0x00에 저장
      dmem_store(32'h0001_0000, 32'hDEAD_BEEF, F3_W);
      begin
         logic [31:0] read_data;
         dmem_load(32'h0001_0000, F3_W, read_data);
         check_result("SW/LW 0xDEADBEEF", 32'hDEAD_BEEF, read_data);
      end

      // SW: 0x1234_5678을 주소 0x04에 저장
      dmem_store(32'h0001_0004, 32'h1234_5678, F3_W);
      begin
         logic [31:0] read_data;
         dmem_load(32'h0001_0004, F3_W, read_data);
         check_result("SW/LW 0x12345678", 32'h1234_5678, read_data);
      end

      //----------------------------------------------------------------------
      // 테스트 3: DMEM 바이트 스토어/로드 (SB/LB/LBU)
      //----------------------------------------------------------------------
      $display("\n--- 테스트 3: 바이트 스토어/로드 (SB/LB/LBU) ---");

      // 먼저 워드 전체를 0으로 초기화
      dmem_store(32'h0001_0010, 32'h0000_0000, F3_W);

      // SB: 0xA5를 바이트 오프셋 0에 저장
      dmem_store(32'h0001_0010, 32'h0000_00A5, F3_B);
      begin
         logic [31:0] read_data;
         // LBU: 제로 확장 읽기
         dmem_load(32'h0001_0010, F3_BU, read_data);
         check_result("SB/LBU byte0=0xA5", 32'h0000_00A5, read_data);

         // LB: 부호 확장 읽기 (0xA5의 MSB=1이므로 부호 확장)
         dmem_load(32'h0001_0010, F3_B, read_data);
         check_result("SB/LB byte0=0xA5(sign-ext)", 32'hFFFF_FFA5, read_data);
      end

      // SB: 0x7F를 바이트 오프셋 1에 저장
      dmem_store(32'h0001_0011, 32'h0000_007F, F3_B);
      begin
         logic [31:0] read_data;
         // LBU: 제로 확장
         dmem_load(32'h0001_0011, F3_BU, read_data);
         check_result("SB/LBU byte1=0x7F", 32'h0000_007F, read_data);

         // LB: 부호 확장 (0x7F의 MSB=0이므로 제로 확장과 동일)
         dmem_load(32'h0001_0011, F3_B, read_data);
         check_result("SB/LB byte1=0x7F(sign-ext)", 32'h0000_007F, read_data);
      end

      // SB: 0x80을 바이트 오프셋 2에 저장 (부호 확장 경계값)
      dmem_store(32'h0001_0012, 32'h0000_0080, F3_B);
      begin
         logic [31:0] read_data;
         dmem_load(32'h0001_0012, F3_B, read_data);
         check_result("SB/LB byte2=0x80(sign-ext)", 32'hFFFF_FF80, read_data);

         dmem_load(32'h0001_0012, F3_BU, read_data);
         check_result("SB/LBU byte2=0x80(zero-ext)", 32'h0000_0080, read_data);
      end

      //----------------------------------------------------------------------
      // 테스트 4: DMEM 하프워드 스토어/로드 (SH/LH/LHU)
      //----------------------------------------------------------------------
      $display("\n--- 테스트 4: 하프워드 스토어/로드 (SH/LH/LHU) ---");

      // 주소 0x20을 0으로 초기화
      dmem_store(32'h0001_0020, 32'h0000_0000, F3_W);

      // SH: 0x8765를 하위 하프워드에 저장
      dmem_store(32'h0001_0020, 32'h0000_8765, F3_H);
      begin
         logic [31:0] read_data;
         // LHU: 제로 확장
         dmem_load(32'h0001_0020, F3_HU, read_data);
         check_result("SH/LHU lower=0x8765", 32'h0000_8765, read_data);

         // LH: 부호 확장 (0x8765의 MSB=1)
         dmem_load(32'h0001_0020, F3_H, read_data);
         check_result("SH/LH lower=0x8765(sign-ext)", 32'hFFFF_8765, read_data);
      end

      // SH: 0x1234를 상위 하프워드에 저장
      dmem_store(32'h0001_0022, 32'h0000_1234, F3_H);
      begin
         logic [31:0] read_data;
         // LHU: 제로 확장 (상위 하프워드)
         dmem_load(32'h0001_0022, F3_HU, read_data);
         check_result("SH/LHU upper=0x1234", 32'h0000_1234, read_data);

         // LW: 전체 워드 확인 (상위 0x1234 + 하위 0x8765)
         dmem_load(32'h0001_0020, F3_W, read_data);
         check_result("Full word after SH×2", 32'h1234_8765, read_data);
      end

      //----------------------------------------------------------------------
      // 테스트 5: 연속 주소 스토어/로드 (데이터 무결성)
      //----------------------------------------------------------------------
      $display("\n--- 테스트 5: 연속 주소 데이터 무결성 ---");

      // 4개 연속 워드 저장
      dmem_store(32'h0001_0100, 32'hAAAA_AAAA, F3_W);
      dmem_store(32'h0001_0104, 32'hBBBB_BBBB, F3_W);
      dmem_store(32'h0001_0108, 32'hCCCC_CCCC, F3_W);
      dmem_store(32'h0001_010C, 32'hDDDD_DDDD, F3_W);

      // 역순으로 읽기 검증
      begin
         logic [31:0] read_data;
         dmem_load(32'h0001_010C, F3_W, read_data);
         check_result("Sequential[3]=0xDDDDDDDD", 32'hDDDD_DDDD, read_data);

         dmem_load(32'h0001_0108, F3_W, read_data);
         check_result("Sequential[2]=0xCCCCCCCC", 32'hCCCC_CCCC, read_data);

         dmem_load(32'h0001_0104, F3_W, read_data);
         check_result("Sequential[1]=0xBBBBBBBB", 32'hBBBB_BBBB, read_data);

         dmem_load(32'h0001_0100, F3_W, read_data);
         check_result("Sequential[0]=0xAAAAAAAA", 32'hAAAA_AAAA, read_data);
      end

      //----------------------------------------------------------------------
      // 테스트 6: 바이트 인에이블 독립성 검증
      //----------------------------------------------------------------------
      $display("\n--- 테스트 6: 바이트 인에이블 독립성 ---");

      // 워드 전체를 0xFF로 초기화
      dmem_store(32'h0001_0200, 32'hFFFF_FFFF, F3_W);

      // Byte 0만 0x11로 변경 (나머지 바이트는 0xFF 유지)
      dmem_store(32'h0001_0200, 32'h0000_0011, F3_B);

      begin
         logic [31:0] read_data;
         dmem_load(32'h0001_0200, F3_W, read_data);
         check_result("Byte0 only write", 32'hFFFF_FF11, read_data);
      end

      // Byte 2만 0x22로 변경
      dmem_store(32'h0001_0202, 32'h0000_0022, F3_B);

      begin
         logic [31:0] read_data;
         dmem_load(32'h0001_0200, F3_W, read_data);
         check_result("Byte2 only write", 32'hFF22_FF11, read_data);
      end

      //----------------------------------------------------------------------
      // 테스트 결과 요약
      //----------------------------------------------------------------------
      $display("\n============================================================");
      $display("  테스트 완료");
      $display("  총 테스트: %0d | 통과: %0d | 실패: %0d",
               test_total, test_pass, test_fail);
      if (test_fail == 0)
         $display("  ★ 모든 테스트 통과! ★");
      else
         $display("  ✗ %0d개 테스트 실패", test_fail);
      $display("============================================================");

      #20;
      $finish;
   end

   //--------------------------------------------------------------------------
   // 시뮬레이션 타임아웃 보호
   //--------------------------------------------------------------------------
   initial begin
      #100_000;
      $display("[TIMEOUT] 시뮬레이션이 100us를 초과하여 강제 종료합니다.");
      $finish;
   end

   //--------------------------------------------------------------------------
   // VCD 파형 덤프 (선택)
   //--------------------------------------------------------------------------
   initial begin
      $dumpfile("memory_tb.vcd");
      $dumpvars(0, memory_tb);
   end

endmodule
