// ============================================================================
// 멀티사이클 CPU 통합 테스트벤치
// Chapter 08 — FSM 기반 제어 유닛
// RISC-V 프로세서 설계 완전정복
// ============================================================================
// R/I/S/B/U/J 타입 명령어 종합 검증
// 메모리 모델 포함 (명령어 + 데이터 통합 메모리)
// ============================================================================

`timescale 1ns / 1ps

module multicycle_cpu_tb;

   // =======================================================================
   // 테스트벤치 신호
   // =======================================================================
   logic        clk;
   logic        rst_n;
   logic [31:0] mem_addr;
   logic [31:0] mem_wdata;
   logic [31:0] mem_rdata;
   logic        mem_read;
   logic        mem_write;
   logic [31:0] debug_pc;
   logic [3:0]  debug_state;

   // =======================================================================
   // 통합 메모리 모델 (명령어 + 데이터)
   // =======================================================================
   // 멀티사이클에서는 IMEM과 DMEM을 하나의 메모리로 공유
   // 주소 공간: 0x0000_0000 ~ 0x0000_3FFF (16KB)
   // =======================================================================
   logic [31:0] memory [0:4095];   // 4K 워드 = 16KB

   // 동기 읽기/쓰기 (1사이클 지연)
   always_ff @(posedge clk) begin
      if (mem_read)
         mem_rdata <= memory[mem_addr[13:2]];  // 워드 정렬 주소
      if (mem_write)
         memory[mem_addr[13:2]] <= mem_wdata;
   end

   // =======================================================================
   // DUT (Device Under Test) 인스턴스
   // =======================================================================
   multicycle_cpu_top u_dut (
      .clk         (clk),
      .rst_n       (rst_n),
      .mem_addr    (mem_addr),
      .mem_wdata   (mem_wdata),
      .mem_rdata   (mem_rdata),
      .mem_read    (mem_read),
      .mem_write   (mem_write),
      .debug_pc    (debug_pc),
      .debug_state (debug_state)
   );

   // =======================================================================
   // 클럭 생성: 10ns 주기 (100MHz)
   // =======================================================================
   initial clk = 1'b0;
   always #5 clk = ~clk;

   // =======================================================================
   // FSM 상태 이름 변환 (파형 디버깅용)
   // =======================================================================
   function automatic string state_name(input logic [3:0] state);
      case (state)
         4'b0000: return "IF";
         4'b0001: return "ID";
         4'b0010: return "EX_R";
         4'b0011: return "EX_M";
         4'b0100: return "EX_B";
         4'b0101: return "EX_U";
         4'b0110: return "MEM";
         4'b0111: return "WB_R";
         4'b1000: return "WB_M";
         4'b1001: return "WB_U";
         default: return "???";
      endcase
   endfunction

   // =======================================================================
   // 테스트 프로그램 초기화
   // =======================================================================
   // RV32I 명령어를 메모리에 직접 로드
   // 각 명령어의 32비트 인코딩을 수작업으로 배치
   // =======================================================================
   task automatic load_test_program();
      // --- 테스트 프로그램 ---
      // 목적: R/I/S/B/U/J 타입 명령어 종합 검증
      //
      // 주소  | 명령어          | 설명
      // ------|----------------|----------------------------------
      // 0x00  | ADDI x1, x0, 5 | x1 = 5
      // 0x04  | ADDI x2, x0, 3 | x2 = 3
      // 0x08  | ADD  x3, x1, x2| x3 = x1 + x2 = 8
      // 0x0C  | SUB  x4, x1, x2| x4 = x1 - x2 = 2
      // 0x10  | AND  x5, x1, x2| x5 = x1 & x2 = 1
      // 0x14  | OR   x6, x1, x2| x6 = x1 | x2 = 7
      // 0x18  | SW   x3, 0(x0) | mem[0x100] = x3 (주소 변경: 0x100)
      //       |  (실제: SW x3, 256(x0)) → mem[256] = 8
      // 0x1C  | LW   x7, 0(x0) | x7 = mem[0x100] = 8 (주소: 256(x0))
      //       |  (실제: LW x7, 256(x0))
      // 0x20  | BEQ  x1, x2, 8 | x1 != x2 → 분기 불성립 (다음 명령어)
      // 0x24  | ADDI x8, x0, 99| x8 = 99 (BEQ 미성립 시 실행)
      // 0x28  | BEQ  x3, x3, 8 | x3 == x3 → 분기 성립 (0x30으로)
      // 0x2C  | ADDI x9, x0, 77| x9 = 77 (BEQ 성립 시 건너뜀)
      // 0x30  | LUI  x10, 0x12345| x10 = 0x12345000
      // 0x34  | JAL  x11, 8    | x11 = PC+4 = 0x38, PC = 0x3C
      // 0x38  | ADDI x12,x0, 55| 건너뛰어야 하는 명령어
      // 0x3C  | ADDI x13,x0, 42| x13 = 42 (JAL 목표)
      // 0x40  | NOP (ADDI x0,x0,0) | 종료

      // ADDI x1, x0, 5     → imm=5, rs1=0, funct3=000, rd=1, opcode=0010011
      memory[0]  = 32'h00500093;   // ADDI x1, x0, 5

      // ADDI x2, x0, 3
      memory[1]  = 32'h00300113;   // ADDI x2, x0, 3

      // ADD x3, x1, x2     → funct7=0000000, rs2=2, rs1=1, funct3=000, rd=3, opcode=0110011
      memory[2]  = 32'h002081B3;   // ADD x3, x1, x2

      // SUB x4, x1, x2     → funct7=0100000
      memory[3]  = 32'h40208233;   // SUB x4, x1, x2

      // AND x5, x1, x2
      memory[4]  = 32'h0020F2B3;   // AND x5, x1, x2

      // OR x6, x1, x2
      memory[5]  = 32'h0020E333;   // OR x6, x1, x2

      // SW x3, 256(x0)     → S타입: imm=256=0x100
      memory[6]  = 32'h10302023;   // SW x3, 256(x0)

      // LW x7, 256(x0)     → I타입: imm=256
      memory[7]  = 32'h10002383;   // LW x7, 256(x0)

      // BEQ x1, x2, 8      → B타입: offset=8
      memory[8]  = 32'h00208463;   // BEQ x1, x2, 8

      // ADDI x8, x0, 99
      memory[9]  = 32'h06300413;   // ADDI x8, x0, 99

      // BEQ x3, x3, 8      → 자기 자신과 비교 → 항상 성립
      memory[10] = 32'h00318463;   // BEQ x3, x3, 8

      // ADDI x9, x0, 77    → 건너뛰어야 함
      memory[11] = 32'h04D00493;   // ADDI x9, x0, 77

      // LUI x10, 0x12345
      memory[12] = 32'h12345537;   // LUI x10, 0x12345

      // JAL x11, 8          → J타입: offset=8
      memory[13] = 32'h008005EF;   // JAL x11, 8

      // ADDI x12, x0, 55   → 건너뛰어야 함
      memory[14] = 32'h03700613;   // ADDI x12, x0, 55

      // ADDI x13, x0, 42   → JAL 목표
      memory[15] = 32'h02A00693;   // ADDI x13, x0, 42

      // NOP (프로그램 종료)
      memory[16] = 32'h00000013;   // ADDI x0, x0, 0
      memory[17] = 32'h00000013;   // NOP
      memory[18] = 32'h00000013;   // NOP
   endtask

   // =======================================================================
   // 검증 태스크: 레지스터 값 확인
   // =======================================================================
   task automatic check_reg(
      input int unsigned reg_num,
      input logic [31:0] expected,
      input string       description
   );
      logic [31:0] actual;
      actual = u_dut.reg_file[reg_num];
      if (actual === expected) begin
         $display("[PASS] x%0d = 0x%08h (%s)", reg_num, actual, description);
      end else begin
         $display("[FAIL] x%0d = 0x%08h, expected 0x%08h (%s)",
                  reg_num, actual, expected, description);
      end
   endtask

   // =======================================================================
   // 메인 테스트 시퀀스
   // =======================================================================
   initial begin
      $display("============================================");
      $display(" 멀티사이클 CPU 통합 테스트 시작");
      $display(" Chapter 08 — FSM 기반 제어 유닛");
      $display("============================================");

      // 메모리 초기화
      for (int i = 0; i < 4096; i++)
         memory[i] = 32'h0000_0013;   // NOP으로 초기화

      // 테스트 프로그램 로드
      load_test_program();

      // 리셋 시퀀스
      rst_n = 1'b0;
      repeat(3) @(posedge clk);
      rst_n = 1'b1;
      $display("\n[INFO] 리셋 해제, 프로그램 실행 시작\n");

      // 프로그램 실행 대기
      // 각 명령어는 3~5 사이클 소요
      // 17개 명령어 × 최대 5 사이클 = 85 사이클
      repeat(200) begin
         @(posedge clk);
         // FSM 상태 모니터링 (옵션)
         if (debug_state == 4'b0000)  // IF 상태 진입 시
            $display("[TRACE] PC=0x%08h, State=%s, Cycle=%0t",
                     debug_pc, state_name(debug_state), $time);
      end

      // =================================================================
      // 결과 검증
      // =================================================================
      $display("\n============================================");
      $display(" 레지스터 검증 결과");
      $display("============================================");

      check_reg(1,  32'd5,          "ADDI x1, x0, 5");
      check_reg(2,  32'd3,          "ADDI x2, x0, 3");
      check_reg(3,  32'd8,          "ADD x3, x1, x2 = 5+3");
      check_reg(4,  32'd2,          "SUB x4, x1, x2 = 5-3");
      check_reg(5,  32'd1,          "AND x5, x1, x2 = 5&3");
      check_reg(6,  32'd7,          "OR  x6, x1, x2 = 5|3");
      check_reg(7,  32'd8,          "LW  x7, 256(x0) = mem[256]");
      check_reg(8,  32'd99,         "ADDI x8, x0, 99 (BEQ 미성립)");
      check_reg(9,  32'd0,          "x9 = 0 (BEQ 성립으로 건너뜀)");
      check_reg(10, 32'h12345000,   "LUI x10, 0x12345");
      check_reg(12, 32'd0,          "x12 = 0 (JAL로 건너뜀)");
      check_reg(13, 32'd42,         "ADDI x13, x0, 42 (JAL 목표)");

      // 메모리 검증: Store 명령어
      $display("\n[MEM CHECK] memory[64] = 0x%08h (expected 0x00000008)",
               memory[64]);   // 주소 256 = 워드 인덱스 64

      $display("\n============================================");
      $display(" 테스트 완료");
      $display("============================================");

      $finish;
   end

   // =======================================================================
   // 파형 덤프 (VCS/Vivado 시뮬레이터)
   // =======================================================================
   initial begin
      $dumpfile("multicycle_cpu_tb.vcd");
      $dumpvars(0, multicycle_cpu_tb);
   end

   // =======================================================================
   // 타임아웃 보호
   // =======================================================================
   initial begin
      #50000;
      $display("[TIMEOUT] 시뮬레이션 타임아웃 (50us)");
      $finish;
   end

endmodule
