// ============================================================================
// ch12_pipeline_complete_tb.sv
// Chapter 12 — 구조적 해저드와 파이프라인 완성
// RISC-V 프로세서 설계 완전정복
// ============================================================================
// DUT: rv32i_pipeline_complete
//
// 테스트 시나리오:
//   시나리오 1 (최소 검증): R/I 타입 5개 시퀀스
//     ADD/SUB/LW/SW 포워딩 + Load-Use 스톨 동작 확인
//   시나리오 2 (버블정렬): 배열 [64,5,66,30,88,17,42,9] 정렬 후 검증
//
// 테스트벤치 메모리 초기화 방식:
//   dut.u_imem.mem[i] = 기계어  (IMEM 직접 초기화)
//   dut.u_dmem.mem[i] = 데이터  (DMEM 직접 초기화)
//
// 합격/불합격 판정:
//   $display("[PASS]") / $display("[FAIL]")
// ============================================================================

`timescale 1ns / 1ps

module rv32i_pipeline_complete_tb;

   // =========================================================================
   // 클록 및 리셋
   // =========================================================================
   logic clk, rst_n;

   // 클록 생성 (10ns 주기 = 100MHz)
   initial clk = 0;
   always #5 clk = ~clk;

   // =========================================================================
   // DUT 인스턴스
   // =========================================================================
   rv32i_pipeline_complete #(
      .DATA_WIDTH (32),
      .ADDR_WIDTH (32),
      .RF_DEPTH   (32),
      .IMEM_DEPTH (256),     // 256 워드 = 1KB (버블정렬 충분)
      .DMEM_DEPTH (256),
      .IMEM_INIT  ("")       // 테스트벤치에서 직접 초기화
   ) dut (
      .clk   (clk),
      .rst_n (rst_n)
   );

   // =========================================================================
   // 시나리오 선택
   // =========================================================================
   integer scenario;

   // =========================================================================
   // 메인 테스트
   // =========================================================================
   initial begin
      $display("========================================================");
      $display("  rv32i_pipeline_complete 통합 테스트벤치");
      $display("  Chapter 12 — 구조적 해저드와 파이프라인 완성");
      $display("========================================================");

      // --- 리셋 ---
      rst_n = 0;
      repeat(4) @(posedge clk);
      rst_n = 1;

      // =====================================================================
      // 시나리오 1: 최소 검증 (R/I 타입 + 포워딩 + Load-Use)
      // =====================================================================
      $display("\n[시나리오 1] 최소 검증 — R/I/LW/SW 시퀀스");
      $display("목적: 포워딩 유닛 및 Load-Use 스톨 기본 동작 확인\n");

      // IMEM 초기화 (기계어)
      // ADDI x1, x0, 10   →  x1 = 10
      // ADDI x2, x0, 20   →  x2 = 20
      // ADD  x3, x1, x2   →  x3 = 30 (EX-EX 포워딩: x1, x2)
      // SW   x3, 0(x0)    →  mem[0] = 30
      // LW   x4, 0(x0)    →  x4 = 30 (Load-Use 스톨 발생)
      // ADD  x5, x4, x3   →  x5 = 60 (MEM-EX 포워딩: x4)
      // ADDI x0, x0, 0    →  NOP (종료 마커)

      dut.u_imem.mem[0]  = 32'h00A00093;   // ADDI x1,  x0, 10
      dut.u_imem.mem[1]  = 32'h01400113;   // ADDI x2,  x0, 20
      dut.u_imem.mem[2]  = 32'h002081B3;   // ADD  x3,  x1, x2
      dut.u_imem.mem[3]  = 32'h00302023;   // SW   x3,  0(x0)
      dut.u_imem.mem[4]  = 32'h00002203;   // LW   x4,  0(x0)
      dut.u_imem.mem[5]  = 32'h003202B3;   // ADD  x5,  x4, x3
      dut.u_imem.mem[6]  = 32'h00000013;   // NOP
      dut.u_imem.mem[7]  = 32'h00000013;   // NOP
      dut.u_imem.mem[8]  = 32'h00000013;   // NOP
      dut.u_imem.mem[9]  = 32'h00000013;   // NOP

      // DMEM 초기화 (시나리오 1에서는 0으로)
      for (int i = 0; i < 16; i++) begin
         dut.u_dmem.mem[i] = 32'b0;
      end

      // 실행 (30 클럭 대기 — 파이프라인 drain)
      repeat(30) @(posedge clk);

      // 결과 검증
      check_scenario1();

      // =====================================================================
      // 리셋 후 시나리오 2 준비
      // =====================================================================
      rst_n = 0;
      repeat(4) @(posedge clk);
      rst_n = 1;

      // =====================================================================
      // 시나리오 2: 버블정렬 검증
      // =====================================================================
      $display("\n[시나리오 2] 버블정렬 검증");
      $display("입력: [64, 5, 66, 30, 88, 17, 42, 9]");
      $display("기대: [5, 9, 17, 30, 42, 64, 66, 88]\n");

      // IMEM 초기화 — 버블정렬 기계어
      // bubble_sort: N=8, 배열 베이스=0 (DMEM 바이트 주소 0번부터)
      //
      // 어셈블리 → 기계어 (GNU as 출력 기준, 오프셋은 바이트):
      // [0x000] ADDI x13, x0, 8      (N=8)
      // [0x004] ADDI x10, x0, 0      (배열 베이스=0)
      // [0x008] ADDI x11, x0, 0      (i=0)
      // [outer_loop: 0x00C]
      // [0x00C] ADDI x16, x13, -1    (N-1=7)
      // [0x010] BGE  x11, x16, done  (+88 = 0x058 → PC=0x068 근사)
      // [0x014] ADDI x12, x0, 0      (j=0)
      // [inner_loop: 0x018]
      // [0x018] SUB  x17, x16, x11   (N-1-i)
      // [0x01C] BGE  x12, x17, outer_next (+xx → outer_next)
      // [0x020] SLLI x18, x12, 2     (j*4)
      // [0x024] ADD  x19, x10, x18   (&a[j])
      // [0x028] LW   x14, 0(x19)     (a[j])
      // [0x02C] LW   x15, 4(x19)     (a[j+1])
      // [0x030] BGE  x15, x14, no_swap (a[j]<=a[j+1])
      // [0x034] SW   x15, 0(x19)     (교환)
      // [0x038] SW   x14, 4(x19)     (교환)
      // [no_swap: 0x03C]
      // [0x03C] ADDI x12, x12, 1     (j++)
      // [0x040] JAL  x0, inner_loop  (→ 0x018, offset=-40)
      // [outer_next: 0x044]
      // [0x044] ADDI x11, x11, 1     (i++)
      // [0x048] JAL  x0, outer_loop  (→ 0x00C, offset=-60)
      // [done: 0x04C]
      // [0x04C] ADDI x0, x0, 0       (NOP)
      //
      // [주의] BGE 오프셋은 PC 상대 바이트 오프셋 (짝수, 부호 있음)
      // done 주소 = 0x04C, outer_loop = 0x00C, outer_next = 0x044, inner_loop = 0x018

      // BGE x11, x16, done: 0x010 → done(0x04C): offset = 0x04C - 0x010 = 0x3C = 60
      // BGE x12, x17, outer_next: 0x01C → outer_next(0x044): offset = 0x044-0x01C = 0x28 = 40
      // BGE x15, x14, no_swap: 0x030 → no_swap(0x03C): offset = 0x03C-0x030 = 0xC = 12
      // JAL x0, inner_loop: 0x040 → 0x018: offset = 0x018-0x040 = -0x28 = -40
      // JAL x0, outer_loop: 0x048 → 0x00C: offset = 0x00C-0x048 = -0x3C = -60

      // BGE  x11, x16, +60:  imm=60=0x3C, B타입, funct3=101(BGE)
      //   rs1=x11=01011, rs2=x16=10000, imm[12]=0, imm[11]=0, imm[10:5]=001111, imm[4:1]=0000
      //   inst[31:25]=0_00111_1, inst[24:20]=10000, inst[19:15]=01011, inst[14:12]=101
      //   inst[11:8]=0000, inst[7]=0, inst[6:0]=1100011
      //   = 0x0305DE63
      // BGE  x12, x17, +40:  imm=40=0x28, B타입, funct3=101(BGE)
      //   rs1=x12=01100, rs2=x17=10001, imm[12]=0, imm[11]=0, imm[10:5]=001010, imm[4:1]=0000
      //   = 0x03165463 (funct3=101, 이전 0x03164463은 funct3=100=BLT — 오류)
      // BGE  x15, x14, +12:  imm=12=0xC, B타입, funct3=101(BGE)
      //   = 0x00E7D663 (정상)
      // JAL  x0, -40:   J타입 imm=-40=0xFFFFFFD8
      //   = 0xFD9FF06F
      // JAL  x0, -60:   J타입 imm=-60=0xFFFFFFC4
      //   = 0xFC5FF06F

      dut.u_imem.mem[0]  = 32'h00800693;   // [0x000] ADDI x13, x0,  8
      dut.u_imem.mem[1]  = 32'h00000513;   // [0x004] ADDI x10, x0,  0
      dut.u_imem.mem[2]  = 32'h00000593;   // [0x008] ADDI x11, x0,  0
      // outer_loop: PC=0x00C (word idx=3)
      dut.u_imem.mem[3]  = 32'hFFF68813;   // [0x00C] ADDI x16, x13, -1
      dut.u_imem.mem[4]  = 32'h0305DE63;   // [0x010] BGE  x11, x16, +60 (done)    [C1 수정: funct3=101=BGE]
      dut.u_imem.mem[5]  = 32'h00000613;   // [0x014] ADDI x12, x0,  0
      // inner_loop: PC=0x018 (word idx=6)
      dut.u_imem.mem[6]  = 32'h40B808B3;   // [0x018] SUB  x17, x16, x11
      dut.u_imem.mem[7]  = 32'h03165463;   // [0x01C] BGE  x12, x17, +40 (outer_next) [C1 수정: funct3=101=BGE]
      dut.u_imem.mem[8]  = 32'h00261913;   // [0x020] SLLI x18, x12, 2
      dut.u_imem.mem[9]  = 32'h012509B3;   // [0x024] ADD  x19, x10, x18   [C2 수정: rd=x19(10011), 이전 0x01250933은 rd=x18]
      dut.u_imem.mem[10] = 32'h0009A703;   // [0x028] LW   x14, 0(x19)
      dut.u_imem.mem[11] = 32'h0049A783;   // [0x02C] LW   x15, 4(x19)
      dut.u_imem.mem[12] = 32'h00E7D663;   // [0x030] BGE  x15, x14, +12 (no_swap)
      dut.u_imem.mem[13] = 32'h00F9A023;   // [0x034] SW   x15, 0(x19)
      dut.u_imem.mem[14] = 32'h00E9A223;   // [0x038] SW   x14, 4(x19)
      // no_swap: PC=0x03C (word idx=15)
      dut.u_imem.mem[15] = 32'h00160613;   // [0x03C] ADDI x12, x12, 1
      dut.u_imem.mem[16] = 32'hFD9FF06F;   // [0x040] JAL  x0, -40 (inner_loop)
      // outer_next: PC=0x044 (word idx=17)
      dut.u_imem.mem[17] = 32'h00158593;   // [0x044] ADDI x11, x11, 1
      dut.u_imem.mem[18] = 32'hFC5FF06F;   // [0x048] JAL  x0, -60 (outer_loop)
      // done: PC=0x04C (word idx=19)
      dut.u_imem.mem[19] = 32'h00000013;   // [0x04C] ADDI x0, x0, 0 (NOP/done)

      // NOP 패딩 (파이프라인 drain용)
      for (int i = 20; i < 30; i++) begin
         dut.u_imem.mem[i] = 32'h00000013;
      end

      // DMEM 초기화 — 정렬 대상 배열 [64, 5, 66, 30, 88, 17, 42, 9]
      // 바이트 주소 0~31 (워드 단위 인덱스 0~7)
      // DMEM 주소 = 바이트 주소 / 4 (워드 단위)
      dut.u_dmem.mem[0] = 32'd64;    // a[0] = 64
      dut.u_dmem.mem[1] = 32'd5;     // a[1] = 5
      dut.u_dmem.mem[2] = 32'd66;    // a[2] = 66
      dut.u_dmem.mem[3] = 32'd30;    // a[3] = 30
      dut.u_dmem.mem[4] = 32'd88;    // a[4] = 88
      dut.u_dmem.mem[5] = 32'd17;    // a[5] = 17
      dut.u_dmem.mem[6] = 32'd42;    // a[6] = 42
      dut.u_dmem.mem[7] = 32'd9;     // a[7] = 9

      // 실행 (버블정렬 N=8: 최대 N*(N-1)/2 = 28패스 × 명령어수 × 사이클마진)
      // 여유 있게 2000 클럭 대기
      $display("버블정렬 실행 중...");
      repeat(2000) @(posedge clk);

      // 결과 검증
      check_bubble_sort();

      $display("\n========================================================");
      $display("  테스트 완료");
      $display("========================================================");
      $finish;
   end

   // =========================================================================
   // Task: 시나리오 1 검증
   // =========================================================================
   task check_scenario1;
      $display("--- 시나리오 1 결과 검증 ---");
      // x3 = 30 (ADD x1+x2, 포워딩)
      // x4 = 30 (LW, Load-Use 스톨 후 메모리에서 읽기)
      // x5 = 60 (ADD x4+x3, MEM-EX 포워딩)
      // DMEM[0] = 30 (SW 결과)

      if (dut.u_dmem.mem[0] === 32'd30) begin
         $display("[PASS] DMEM[0] = 30 (SW 정상 동작)");
      end else begin
         $display("[FAIL] DMEM[0] = %0d (기대: 30)", dut.u_dmem.mem[0]);
      end

      // 레지스터 파일 직접 확인 (시뮬레이션에서만 가능)
      if (dut.u_rf.rf[5] === 32'd60) begin
         $display("[PASS] x5 = 60 (포워딩 + Load-Use 스톨 정상)");
      end else begin
         $display("[FAIL] x5 = %0d (기대: 60)", dut.u_rf.rf[5]);
         $display("       포워딩 유닛 또는 Load-Use 스톨 확인 필요");
      end
   endtask

   // =========================================================================
   // Task: 버블정렬 결과 검증
   // =========================================================================
   task check_bubble_sort;
      logic [31:0] expected [0:7];
      logic [31:0] actual   [0:7];
      integer      fail_cnt;
      integer      i;

      // 기대값 설정
      expected[0] = 32'd5;
      expected[1] = 32'd9;
      expected[2] = 32'd17;
      expected[3] = 32'd30;
      expected[4] = 32'd42;
      expected[5] = 32'd64;
      expected[6] = 32'd66;
      expected[7] = 32'd88;

      // 실제값 읽기 (DMEM 워드 인덱스 = 바이트주소 / 4)
      for (i = 0; i < 8; i++) begin
         actual[i] = dut.u_dmem.mem[i];
      end

      $display("--- 버블정렬 결과 ---");
      $display("인덱스  실제값   기대값  판정");
      fail_cnt = 0;
      for (i = 0; i < 8; i++) begin
         if (actual[i] === expected[i]) begin
            $display("a[%0d]   %3d     %3d    OK", i, actual[i], expected[i]);
         end else begin
            $display("a[%0d]   %3d     %3d    FAIL <<<", i, actual[i], expected[i]);
            fail_cnt++;
         end
      end

      $display("");
      if (fail_cnt == 0) begin
         $display("╔══════════════════════════════════════════════╗");
         $display("║  [PASS] 버블정렬 완료!                       ║");
         $display("║  모든 해저드 처리가 정확히 동작하였습니다.  ║");
         $display("║  포워딩 + Load-Use 스톨 + 분기 플러시       ║");
         $display("║  + WB-ID 포워딩 모두 검증 완료!             ║");
         $display("╚══════════════════════════════════════════════╝");
      end else begin
         $display("[FAIL] 버블정렬 실패: %0d개 원소 불일치", fail_cnt);
         $display("디버깅 순서:");
         $display("  1. forward_a, forward_b 신호 타이밍 확인");
         $display("  2. pc_en, if_id_en Load-Use 스톨 확인");
         $display("  3. branch_taken_ex 직후 flush 타이밍 확인");
      end

      // 오름차순 정렬 여부 자동 검증 (독립 확인)
      $display("\n--- 오름차순 정렬 자동 검증 ---");
      begin
         logic sorted;
         sorted = 1'b1;
         for (i = 0; i < 7; i++) begin
            if (actual[i] > actual[i+1]) begin
               sorted = 1'b0;
               $display("[WARN] 정렬 오류: a[%0d]=%0d > a[%0d]=%0d",
                        i, actual[i], i+1, actual[i+1]);
            end
         end
         if (sorted)
            $display("[PASS] 오름차순 정렬 확인 완료");
      end
   endtask

   // =========================================================================
   // 타임아웃 감시 (무한 루프 방지)
   // =========================================================================
   initial begin
      #500000;  // 500,000ns = 50,000 클럭 (100MHz 기준)
      $display("[TIMEOUT] 최대 실행 시간 초과 — 무한 루프 의심");
      $display("확인 사항: BLT/BGE 분기 조건, 루프 카운터 증가 로직");
      $finish;
   end

   // =========================================================================
   // 파형 덤프 (Vivado XSim / VCS / Verdi)
   // =========================================================================
   initial begin
      $dumpfile("ch12_pipeline_complete_tb.vcd");
      $dumpvars(0, rv32i_pipeline_complete_tb);
   end

endmodule
