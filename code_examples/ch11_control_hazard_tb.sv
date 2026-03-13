// ============================================================================
// ch11_control_hazard_tb.sv
// Chapter 11 -- 제어 해저드와 분기 처리 테스트벤치
// RISC-V 프로세서 설계 완전정복
// ============================================================================
// 테스트 시나리오:
//   1. BEQ taken   -- flush 동작, wrong-path 제거 검증
//   2. BNE not-taken -- 정상 실행, 플러시 없음 검증
//   3. Load-JALR hazard -- 스톨 후 JALR 정상 실행
//   4. 루프 마일스톤 -- 1~10 합산 (x2 = 55) 검증
// ============================================================================
//
// [루프 마일스톤 프로그램 어셈블리]
//   0x00: addi x1, x0, 1      # i = 1
//   0x04: addi x2, x0, 0      # sum = 0
//   0x08: addi x3, x0, 11     # limit = 11
//   loop (0x0C):
//   0x0C: add  x2, x2, x1     # sum += i
//   0x10: addi x1, x1, 1      # i++
//   0x14: bne  x1, x3, loop   # if i != 11, goto loop
//   0x18: nop
//   결과: x2 = 1+2+...+10 = 55 = 0x37
// ============================================================================

`timescale 1ns / 1ps

module rv32i_pipeline_branch_tb;

   // =========================================================================
   // DUT 포트
   // =========================================================================
   logic clk;
   logic rst_n;

   rv32i_pipeline_branch #(
      .IMEM_DEPTH(256),
      .DMEM_DEPTH(256),
      .IMEM_INIT ("")
   ) dut (
      .clk   (clk),
      .rst_n (rst_n)
   );

   // =========================================================================
   // 클록 생성 (10ns 주기 = 100MHz)
   // =========================================================================
   initial clk = 1'b0;
   always #5 clk = ~clk;

   // =========================================================================
   // 명령어 메모리 초기화 (루프 합산 프로그램)
   // =========================================================================
   initial begin
      // 0x00: addi x1, x0, 1  (rd=1, rs1=0, imm=1)
      dut.u_imem.mem[0]  = 32'h00100093;
      // 0x04: addi x2, x0, 0  (rd=2, rs1=0, imm=0)
      dut.u_imem.mem[1]  = 32'h00000113;
      // 0x08: addi x3, x0, 11 (rd=3, rs1=0, imm=11)
      dut.u_imem.mem[2]  = 32'h00B00193;
      // loop: 0x0C
      // 0x0C: add  x2, x2, x1 (rd=2, rs1=2, rs2=1)
      //   funct7=0000000, rs2=x1(00001), rs1=x2(00010), funct3=000, rd=x2(00010), opcode=0110011
      dut.u_imem.mem[3]  = 32'h00110133;
      // 0x10: addi x1, x1, 1  (rd=1, rs1=1, imm=1)
      dut.u_imem.mem[4]  = 32'h00108093;
      // 0x14: bne  x1, x3, -8 (offset=-8 -> 0x0C)
      //   BNE: opcode=1100011, funct3=001
      //   offset=-8: PC(0x14) + (-8) = 0x0C (loop label)
      //   imm_B(-8): imm[12]=1,imm[11]=1,imm[10:5]=111111,imm[4:1]=1000
      //   Encoding: FE309CE3
      dut.u_imem.mem[5]  = 32'hFE309CE3;
      // 0x18: nop
      dut.u_imem.mem[6]  = 32'h00000013;
      dut.u_imem.mem[7]  = 32'h00000013;
      dut.u_imem.mem[8]  = 32'h00000013;
      dut.u_imem.mem[9]  = 32'h00000013;
      for (int i = 10; i < 256; i++)
         dut.u_imem.mem[i] = 32'h00000013;
   end

   // =========================================================================
   // 시나리오 1: BEQ taken — flush 동작, wrong-path 제거 검증
   // 프로그램:
   //   0x00: addi x1, x0, 5    # x1 = 5
   //   0x04: addi x2, x0, 5    # x2 = 5
   //   0x08: beq  x1, x2, +8   # x1==x2 → taken, PC=0x10
   //   0x0C: addi x3, x0, 99   # wrong-path: should NOT execute
   //   0x10: addi x4, x0, 42   # correct-path: x4 = 42
   // 기대: x3=0 (wrong-path 실행되지 않음), x4=42
   // =========================================================================
   task automatic run_scenario1();
      integer i;
      // 명령어 메모리 초기화
      for (i = 0; i < 256; i++)
         dut.u_imem.mem[i] = 32'h00000013; // NOP
      // 0x00: addi x1, x0, 5  → rd=1, rs1=0, imm=5
      dut.u_imem.mem[0] = 32'h00500093;
      // 0x04: addi x2, x0, 5  → rd=2, rs1=0, imm=5
      dut.u_imem.mem[1] = 32'h00500113;
      // 0x08: beq x1, x2, +8  → offset=+8: BEQ opcode=1100011, funct3=000
      //   imm_B(+8): imm[12]=0,imm[11]=0,imm[10:5]=000000,imm[4:1]=1000 → 0x00208463
      dut.u_imem.mem[2] = 32'h00208463;
      // 0x0C: addi x3, x0, 99 → wrong-path (should be flushed)
      dut.u_imem.mem[3] = 32'h06300193;
      // 0x10: addi x4, x0, 42 → correct-path: x4 = 42
      dut.u_imem.mem[4] = 32'h02A00213;

      // 리셋
      rst_n = 1'b0;
      repeat(3) @(posedge clk);
      rst_n = 1'b1;
      repeat(20) @(posedge clk);
      #1;

      $display("------------------------------------------------------------");
      $display("[시나리오 1] BEQ taken — flush 동작 검증");
      if (dut.u_rf.regs[3] === 32'h00000000)
         $display("[PASS] x3 = 0 (wrong-path 명령어 실행되지 않음)");
      else
         $display("[FAIL] x3 = %0d (기대: 0, wrong-path가 실행됨)", dut.u_rf.regs[3]);
      if (dut.u_rf.regs[4] === 32'h0000002A)
         $display("[PASS] x4 = 42 (correct-path 명령어 정상 실행)");
      else
         $display("[FAIL] x4 = %0d (기대: 42)", dut.u_rf.regs[4]);
   endtask

   // =========================================================================
   // 시나리오 2: BNE not-taken — 정상 실행, 플러시 없음 검증
   // 프로그램:
   //   0x00: addi x1, x0, 7    # x1 = 7
   //   0x04: addi x2, x0, 7    # x2 = 7 (same value)
   //   0x08: bne  x1, x2, +8   # x1==x2 → not-taken (no flush)
   //   0x0C: addi x3, x0, 55   # correct-path: x3 = 55
   //   0x10: addi x4, x0, 10   # next instruction: x4 = 10
   // 기대: x3=55 (not-taken 시 flush 없음, 연속 실행)
   // =========================================================================
   task automatic run_scenario2();
      integer i;
      for (i = 0; i < 256; i++)
         dut.u_imem.mem[i] = 32'h00000013; // NOP
      // 0x00: addi x1, x0, 7
      dut.u_imem.mem[0] = 32'h00700093;
      // 0x04: addi x2, x0, 7
      dut.u_imem.mem[1] = 32'h00700113;
      // 0x08: bne x1, x2, +8  → x1==x2이므로 not-taken
      //   imm_B(+8): 0x00209463
      dut.u_imem.mem[2] = 32'h00209463;
      // 0x0C: addi x3, x0, 55 → not-taken이므로 정상 실행
      dut.u_imem.mem[3] = 32'h03700193;
      // 0x10: addi x4, x0, 10
      dut.u_imem.mem[4] = 32'h00A00213;

      // 리셋
      rst_n = 1'b0;
      repeat(3) @(posedge clk);
      rst_n = 1'b1;
      repeat(20) @(posedge clk);
      #1;

      $display("------------------------------------------------------------");
      $display("[시나리오 2] BNE not-taken — 플러시 없음 검증");
      if (dut.u_rf.regs[3] === 32'h00000037)
         $display("[PASS] x3 = 55 (not-taken, 정상 연속 실행)");
      else
         $display("[FAIL] x3 = %0d (기대: 55)", dut.u_rf.regs[3]);
      if (dut.u_rf.regs[4] === 32'h0000000A)
         $display("[PASS] x4 = 10 (PC+4 연속 실행 확인)");
      else
         $display("[FAIL] x4 = %0d (기대: 10)", dut.u_rf.regs[4]);
   endtask

   // =========================================================================
   // 시나리오 3: Load-JALR 해저드 — 스톨 후 JALR 정상 실행
   // 프로그램:
   //   0x00: addi x1, x0, 0x10  # x1 = 0x10 (JALR 타겟 임시값)
   //   0x04: sw   x1, 0(x0)     # 메모리[0] = 0x10
   //   0x08: lw   x2, 0(x0)     # x2 = 메모리[0] = 0x10  (load)
   //   0x0C: jalr x0, 0(x2)     # PC = x2 + 0 = 0x10     (Load-JALR hazard)
   //   0x10: addi x3, x0, 77    # JALR 타겟: x3 = 77
   // 기대: x3=77 (JALR이 올바른 x2 값으로 점프, 스톨 자동 삽입됨)
   // =========================================================================
   task automatic run_scenario3();
      integer i;
      for (i = 0; i < 256; i++)
         dut.u_imem.mem[i] = 32'h00000013; // NOP
      // 0x00: addi x1, x0, 16 (0x10)
      dut.u_imem.mem[0] = 32'h01000093;
      // 0x04: sw x1, 0(x0)  → rs2=x1(00001), rs1=x0(00000), imm=0, funct3=010, opcode=0100011
      //   = 0x00102023
      dut.u_imem.mem[1] = 32'h00102023;
      // 0x08: lw x2, 0(x0)  → rd=x2(00010), rs1=x0(00000), imm=0, funct3=010, opcode=0000011
      //   = 0x00002103
      dut.u_imem.mem[2] = 32'h00002103;
      // 0x0C: jalr x0, 0(x2)  → rd=x0(00000), rs1=x2(00010), imm=0, funct3=000, opcode=1100111
      //   = 0x00010067
      dut.u_imem.mem[3] = 32'h00010067;
      // 0x10 (mem[4]): addi x3, x0, 77 → x3 = 77 (JALR 점프 타겟)
      dut.u_imem.mem[4] = 32'h04D00193;

      // 리셋
      rst_n = 1'b0;
      repeat(3) @(posedge clk);
      rst_n = 1'b1;
      repeat(30) @(posedge clk);
      #1;

      $display("------------------------------------------------------------");
      $display("[시나리오 3] Load-JALR 해저드 — 스톨 후 JALR 정상 실행");
      if (dut.u_rf.regs[3] === 32'h0000004D)
         $display("[PASS] x3 = 77 (JALR이 올바른 주소(0x10)로 점프, x3 정상 실행)");
      else
         $display("[FAIL] x3 = %0d (기대: 77, Load-JALR 해저드 처리 오류)", dut.u_rf.regs[3]);
   endtask

   // =========================================================================
   // 리셋 및 실행 (시나리오 순차 실행 후 루프 마일스톤)
   // =========================================================================
   initial begin
      // 시나리오 1: BEQ taken flush 검증
      run_scenario1();

      // 시나리오 2: BNE not-taken 검증
      run_scenario2();

      // 시나리오 3: Load-JALR 해저드 검증
      run_scenario3();

      // 시나리오 4: 루프 마일스톤 — 명령어 메모리 재초기화
      begin : scenario4
         integer i;
         for (i = 0; i < 256; i++)
            dut.u_imem.mem[i] = 32'h00000013;
         // 0x00: addi x1, x0, 1
         dut.u_imem.mem[0]  = 32'h00100093;
         // 0x04: addi x2, x0, 0
         dut.u_imem.mem[1]  = 32'h00000113;
         // 0x08: addi x3, x0, 11
         dut.u_imem.mem[2]  = 32'h00B00193;
         // loop: 0x0C
         // 0x0C: add  x2, x2, x1 (rd=2, rs1=2, rs2=1) = 0x00110133
         dut.u_imem.mem[3]  = 32'h00110133;
         // 0x10: addi x1, x1, 1
         dut.u_imem.mem[4]  = 32'h00108093;
         // 0x14: bne  x1, x3, -8 (loop)
         dut.u_imem.mem[5]  = 32'hFE309CE3;
      end

      // 리셋 후 루프 실행
      rst_n = 1'b0;
      repeat(3) @(posedge clk);
      rst_n = 1'b1;

      // 루프 10회 + 파이프라인 플러시 오버헤드 = 충분한 사이클
      repeat(150) @(posedge clk);
      #1;

      $display("============================================================");
      $display("[Ch11 루프 마일스톤 검증 결과]");
      $display("============================================================");

      // 검증 1: x2 = 55 (1+2+...+10)
      if (dut.u_rf.regs[2] === 32'h00000037) begin
         $display("[PASS] x2 = 0x%08h = %0d (기대: 55) -- 루프 합산 정확",
                  dut.u_rf.regs[2], dut.u_rf.regs[2]);
      end else begin
         $display("[FAIL] x2 = 0x%08h = %0d (기대: 0x37 = 55)",
                  dut.u_rf.regs[2], dut.u_rf.regs[2]);
      end

      // 검증 2: x1 = 11 (루프 탈출 시 카운터)
      if (dut.u_rf.regs[1] === 32'h0000000B) begin
         $display("[PASS] x1 = %0d (기대: 11) -- 루프 카운터 정확",
                  dut.u_rf.regs[1]);
      end else begin
         $display("[FAIL] x1 = %0d (기대: 11) -- 카운터 오류",
                  dut.u_rf.regs[1]);
      end

      // 검증 3: x3 = 11 (limit 변경 없음)
      if (dut.u_rf.regs[3] === 32'h0000000B) begin
         $display("[PASS] x3 = %0d (기대: 11) -- limit 보존",
                  dut.u_rf.regs[3]);
      end else begin
         $display("[FAIL] x3 = %0d (기대: 11)", dut.u_rf.regs[3]);
      end

      $display("============================================================");
      $finish;
   end

   // =========================================================================
   // 파형 덤프
   // =========================================================================
   initial begin
      $dumpfile("ch11_pipeline_branch_tb.vcd");
      $dumpvars(0, rv32i_pipeline_branch_tb);
   end

   // =========================================================================
   // 제어 해저드 신호 실시간 모니터
   // =========================================================================
   always @(posedge clk) begin
      if (rst_n) begin
         if (dut.branch_taken_ex) begin
            $display("[%4t ns] BRANCH TAKEN: PC=%08h -> target=%08h",
                     $time, dut.pc, dut.branch_target);
         end
         if (dut.jal_id) begin
            $display("[%4t ns] JAL: if_id_pc=%08h -> jal_target=%08h",
                     $time, dut.if_id_pc, dut.jal_target);
         end
         if (dut.jalr_taken_ex) begin
            $display("[%4t ns] JALR: target=%08h", $time, dut.jalr_target);
         end
         if (dut.load_use_stall) begin
            $display("[%4t ns] LOAD-USE STALL", $time);
         end
         if (dut.if_id_flush) begin
            $display("[%4t ns] IF/ID FLUSH (if_id=%b id_ex=%b)",
                     $time, dut.if_id_flush, dut.id_ex_flush);
         end
      end
   end

endmodule
