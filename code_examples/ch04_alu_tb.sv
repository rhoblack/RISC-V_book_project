// =============================================================================
// 모듈명: alu_tb
// 설  명: ALU 단위 테스트벤치 — 10가지 연산 + 경계값 검증
// 파  일: ch04_alu_tb.sv
// 표  준: IEEE 1800-2017 (SystemVerilog)
// 저  자: RISC-V 프로세서 설계 완전정복 — Chapter 04
// =============================================================================

`timescale 1ns / 1ps

module alu_tb;

   // === 신호 선언 ===
   logic [31:0] operand_a;
   logic [31:0] operand_b;
   logic [3:0]  alu_ctrl;
   logic [31:0] alu_result;
   logic        alu_zero;

   // === DUT 인스턴스 ===
   alu u_alu (
      .operand_a  (operand_a),
      .operand_b  (operand_b),
      .alu_ctrl   (alu_ctrl),
      .alu_result (alu_result),
      .alu_zero   (alu_zero)
   );

   // === ALU 제어 코드 상수 (가독성 향상) ===
   localparam logic [3:0] ALU_ADD  = 4'b0000;
   localparam logic [3:0] ALU_SUB  = 4'b0001;
   localparam logic [3:0] ALU_AND  = 4'b0010;
   localparam logic [3:0] ALU_OR   = 4'b0011;
   localparam logic [3:0] ALU_XOR  = 4'b0100;
   localparam logic [3:0] ALU_SLL  = 4'b0101;
   localparam logic [3:0] ALU_SRL  = 4'b0110;
   localparam logic [3:0] ALU_SRA  = 4'b0111;
   localparam logic [3:0] ALU_SLT  = 4'b1000;
   localparam logic [3:0] ALU_SLTU = 4'b1001;

   // === 테스트 통계 ===
   int pass_count = 0;
   int fail_count = 0;
   int test_count = 0;

   // === 검증 태스크: 기대값과 비교 ===
   task automatic check(
      input string   test_name,
      input [31:0]   expected_result,
      input          expected_zero
   );
      test_count++;
      #1; // 조합 논리 안정화 대기

      if (alu_result !== expected_result || alu_zero !== expected_zero) begin
         $display("[FAIL] %s: result=0x%08h (expected 0x%08h), zero=%b (expected %b)",
                  test_name, alu_result, expected_result, alu_zero, expected_zero);
         fail_count++;
      end else begin
         $display("[PASS] %s: result=0x%08h, zero=%b",
                  test_name, alu_result, alu_zero);
         pass_count++;
      end
   endtask

   // === 메인 테스트 시퀀스 ===
   initial begin
      $display("==========================================================");
      $display(" ALU 단위 테스트벤치 시작");
      $display("==========================================================");

      // -------------------------------------------------------
      // 1. ADD 테스트
      // -------------------------------------------------------
      $display("\n--- ADD 테스트 ---");
      operand_a = 32'd10;    operand_b = 32'd20;    alu_ctrl = ALU_ADD;
      check("ADD: 10 + 20", 32'd30, 1'b0);

      operand_a = 32'hFFFF_FFFF; operand_b = 32'd1; alu_ctrl = ALU_ADD;
      check("ADD: 오버플로 (0xFFFFFFFF + 1)", 32'd0, 1'b1);

      operand_a = 32'h7FFF_FFFF; operand_b = 32'd1; alu_ctrl = ALU_ADD;
      check("ADD: 양수 최대 + 1", 32'h8000_0000, 1'b0);

      // -------------------------------------------------------
      // 2. SUB 테스트
      // -------------------------------------------------------
      $display("\n--- SUB 테스트 ---");
      operand_a = 32'd30;    operand_b = 32'd10;    alu_ctrl = ALU_SUB;
      check("SUB: 30 - 10", 32'd20, 1'b0);

      operand_a = 32'd10;    operand_b = 32'd10;    alu_ctrl = ALU_SUB;
      check("SUB: 10 - 10 (제로 플래그)", 32'd0, 1'b1);

      operand_a = 32'd0;     operand_b = 32'd1;     alu_ctrl = ALU_SUB;
      check("SUB: 0 - 1 (언더플로)", 32'hFFFF_FFFF, 1'b0);

      // -------------------------------------------------------
      // 3. AND 테스트
      // -------------------------------------------------------
      $display("\n--- AND 테스트 ---");
      operand_a = 32'hFF00_FF00; operand_b = 32'h0F0F_0F0F; alu_ctrl = ALU_AND;
      check("AND: 0xFF00FF00 & 0x0F0F0F0F", 32'h0F00_0F00, 1'b0);

      operand_a = 32'hAAAA_AAAA; operand_b = 32'h5555_5555; alu_ctrl = ALU_AND;
      check("AND: 교번 패턴 (결과 0)", 32'd0, 1'b1);

      // -------------------------------------------------------
      // 4. OR 테스트
      // -------------------------------------------------------
      $display("\n--- OR 테스트 ---");
      operand_a = 32'hFF00_0000; operand_b = 32'h00FF_0000; alu_ctrl = ALU_OR;
      check("OR: 0xFF000000 | 0x00FF0000", 32'hFFFF_0000, 1'b0);

      // -------------------------------------------------------
      // 5. XOR 테스트
      // -------------------------------------------------------
      $display("\n--- XOR 테스트 ---");
      operand_a = 32'hFFFF_FFFF; operand_b = 32'hFFFF_FFFF; alu_ctrl = ALU_XOR;
      check("XOR: 동일 값 (결과 0)", 32'd0, 1'b1);

      operand_a = 32'hA5A5_A5A5; operand_b = 32'h5A5A_5A5A; alu_ctrl = ALU_XOR;
      check("XOR: 보수 패턴", 32'hFFFF_FFFF, 1'b0);

      // -------------------------------------------------------
      // 6. SLL (논리 좌측 시프트) 테스트
      // -------------------------------------------------------
      $display("\n--- SLL 테스트 ---");
      operand_a = 32'd1;     operand_b = 32'd4;     alu_ctrl = ALU_SLL;
      check("SLL: 1 << 4", 32'd16, 1'b0);

      operand_a = 32'd1;     operand_b = 32'd31;    alu_ctrl = ALU_SLL;
      check("SLL: 1 << 31 (MSB 설정)", 32'h8000_0000, 1'b0);

      // 하위 5비트만 사용 확인 (시프트량 32는 0과 동일)
      operand_a = 32'd1;     operand_b = 32'd32;    alu_ctrl = ALU_SLL;
      check("SLL: 1 << 32 (shamt=0, 하위 5비트)", 32'd1, 1'b0);

      // -------------------------------------------------------
      // 7. SRL (논리 우측 시프트) 테스트
      // -------------------------------------------------------
      $display("\n--- SRL 테스트 ---");
      operand_a = 32'h8000_0000; operand_b = 32'd4;  alu_ctrl = ALU_SRL;
      check("SRL: 0x80000000 >> 4 (상위 0 채움)", 32'h0800_0000, 1'b0);

      // -------------------------------------------------------
      // 8. SRA (산술 우측 시프트) 테스트
      // -------------------------------------------------------
      $display("\n--- SRA 테스트 ---");
      operand_a = 32'h8000_0000; operand_b = 32'd4;  alu_ctrl = ALU_SRA;
      check("SRA: 0x80000000 >>> 4 (부호 비트 확장)", 32'hF800_0000, 1'b0);

      operand_a = 32'h7FFF_FFFF; operand_b = 32'd4;  alu_ctrl = ALU_SRA;
      check("SRA: 양수 시프트 (상위 0 유지)", 32'h07FF_FFFF, 1'b0);

      // -------------------------------------------------------
      // 9. SLT (부호 있는 비교) 테스트
      // -------------------------------------------------------
      $display("\n--- SLT 테스트 ---");
      operand_a = 32'hFFFF_FFFF; operand_b = 32'd1;  alu_ctrl = ALU_SLT;
      check("SLT: -1 < 1 (참)", 32'd1, 1'b0);

      operand_a = 32'd1;     operand_b = 32'hFFFF_FFFF; alu_ctrl = ALU_SLT;
      check("SLT: 1 < -1 (거짓)", 32'd0, 1'b1);

      operand_a = 32'd5;     operand_b = 32'd5;     alu_ctrl = ALU_SLT;
      check("SLT: 5 < 5 (같으면 거짓)", 32'd0, 1'b1);

      // -------------------------------------------------------
      // 10. SLTU (부호 없는 비교) 테스트
      // -------------------------------------------------------
      $display("\n--- SLTU 테스트 ---");
      operand_a = 32'd1;     operand_b = 32'hFFFF_FFFF; alu_ctrl = ALU_SLTU;
      check("SLTU: 1 < 0xFFFFFFFF (참, 부호 없음)", 32'd1, 1'b0);

      operand_a = 32'hFFFF_FFFF; operand_b = 32'd1;  alu_ctrl = ALU_SLTU;
      check("SLTU: 0xFFFFFFFF < 1 (거짓, 부호 없음)", 32'd0, 1'b1);

      // -------------------------------------------------------
      // 결과 요약
      // -------------------------------------------------------
      $display("\n==========================================================");
      $display(" 테스트 완료: 총 %0d개 | 통과 %0d개 | 실패 %0d개",
               test_count, pass_count, fail_count);
      if (fail_count == 0)
         $display(" *** 모든 테스트 통과! ***");
      else
         $display(" *** 실패한 테스트가 있습니다. 위의 [FAIL] 항목을 확인하십시오. ***");
      $display("==========================================================");
      $finish;
   end

endmodule
