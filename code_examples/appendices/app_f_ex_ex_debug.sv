// app_f_ex_ex_debug.sv
// F.4 Case 1: EX-EX 포워딩 버그 진단 코드
// 목표: EX-EX 포워딩이 제대로 작동하는지 검증
//
// 증상 시나리오:
//   add x1, x0, x0     // x1 = 0
//   addi x1, x1, 5     // x1을 사용해야 하는데 이전 값(0)을 사용 → 오류

// 정상 동작: 이전 명령어의 ALU 결과가 현재 명령어의 피연산자로 포워딩되어야 함

module forwarding_unit_debug
(
  input logic [4:0]  EX_MEM_rd,         // 이전 사이클의 쓰기 대상 레지스터
  input logic [4:0]  ID_EX_rs1,         // 현재 사이클의 첫 번째 읽기 대상
  input logic [4:0]  ID_EX_rs2,         // 현재 사이클의 두 번째 읽기 대상
  input logic        EX_MEM_reg_we,     // 이전 사이클의 레지스터 쓰기 신호

  output logic [1:0] forward_a,         // 첫 번째 피연산자의 포워딩 신호
  output logic [1:0] forward_b,         // 두 번째 피연산자의 포워딩 신호

  // 디버깅용 신호
  output logic       debug_forward_condition_a,
  output logic       debug_forward_condition_b
);

  // ===== 포워딩 조건 (Ch10.2에서 학습) =====
  // EX-EX 포워딩 활성화 조건:
  // 1. 이전 명령어가 레지스터에 쓰는가? (EX_MEM_reg_we == 1)
  // 2. 이전 명령어의 쓰기 대상이 x0이 아닌가? (EX_MEM_rd != 5'b0)
  // 3. 이전 명령어의 쓰기 대상이 현재 명령어의 읽기 소스와 같은가?

  // rs1에 대한 포워딩 판정
  assign forward_a =
    ((EX_MEM_rd == ID_EX_rs1) &&        // ✓ 조건 1: 읽기-쓰기 주소 일치
     (EX_MEM_reg_we == 1'b1) &&         // ✓ 조건 2: 이전 사이클이 쓰기 중
     (EX_MEM_rd != 5'b0)) ? 2'b01 :     // ✓ 조건 3: x0이 아님 (x0은 읽기 전용)
    2'b00;                              // 포워딩 불가

  // rs2에 대한 포워딩 판정 (동일 로직)
  assign forward_b =
    ((EX_MEM_rd == ID_EX_rs2) &&
     (EX_MEM_reg_we == 1'b1) &&
     (EX_MEM_rd != 5'b0)) ? 2'b01 :
    2'b00;

  // ===== 디버깅용 신호 (각 조건을 개별 추적) =====
  // rs1에 대한 각 조건 확인
  logic rd_rs1_match, rd_nonzero, reg_we_active;

  assign rd_rs1_match    = (EX_MEM_rd == ID_EX_rs1);      // 조건 A
  assign rd_nonzero      = (EX_MEM_rd != 5'b0);            // 조건 B
  assign reg_we_active   = (EX_MEM_reg_we == 1'b1);        // 조건 C

  assign debug_forward_condition_a = rd_rs1_match && rd_nonzero && reg_we_active;

  // rs2에 대한 조건 확인
  logic rd_rs2_match;
  assign rd_rs2_match = (EX_MEM_rd == ID_EX_rs2);
  assign debug_forward_condition_b = rd_rs2_match && rd_nonzero && reg_we_active;

endmodule

// ===== 테스트벤치: EX-EX 포워딩 검증 =====

module forwarding_debug_tb;
  logic [4:0]  EX_MEM_rd;
  logic [4:0]  ID_EX_rs1;
  logic [4:0]  ID_EX_rs2;
  logic        EX_MEM_reg_we;
  logic [1:0]  forward_a;
  logic [1:0]  forward_b;
  logic        debug_a, debug_b;

  forwarding_unit_debug dut (
    .EX_MEM_rd(EX_MEM_rd),
    .ID_EX_rs1(ID_EX_rs1),
    .ID_EX_rs2(ID_EX_rs2),
    .EX_MEM_reg_we(EX_MEM_reg_we),
    .forward_a(forward_a),
    .forward_b(forward_b),
    .debug_forward_condition_a(debug_a),
    .debug_forward_condition_b(debug_b)
  );

  initial begin
    // Test Case 1: 정상 포워딩 (add x1, x0, x0 다음 addi x1, x1, 5)
    // EX_MEM: x1에 값을 씀 (rd=1, reg_we=1)
    // ID_EX: x1을 읽음 (rs1=1, rs2=0)
    EX_MEM_rd = 5'd1;
    EX_MEM_reg_we = 1'b1;
    ID_EX_rs1 = 5'd1;
    ID_EX_rs2 = 5'd0;

    #10;
    $display("=== Test Case 1: 정상 포워딩 ===");
    $display("EX_MEM_rd=%d, ID_EX_rs1=%d, ID_EX_rs2=%d, reg_we=%b",
             EX_MEM_rd, ID_EX_rs1, ID_EX_rs2, EX_MEM_reg_we);
    $display("forward_a = %b (기대값: 2'b01), forward_b = %b (기대값: 2'b00)",
             forward_a, forward_b);
    $display("debug_a = %b (기대값: 1), debug_b = %b (기대값: 0)",
             debug_a, debug_b);

    if (forward_a == 2'b01 && forward_b == 2'b00) begin
      $display("✅ PASS: 포워딩 신호 정상\n");
    end else begin
      $display("❌ FAIL: 포워딩 신호 오류\n");
    end

    // Test Case 2: 포워딩 불필요 (다른 레지스터)
    EX_MEM_rd = 5'd2;     // x2에 값을 씀
    EX_MEM_reg_we = 1'b1;
    ID_EX_rs1 = 5'd1;     // x1을 읽음 (다른 레지스터!)
    ID_EX_rs2 = 5'd0;

    #10;
    $display("=== Test Case 2: 포워딩 불필요 ===");
    $display("EX_MEM_rd=%d, ID_EX_rs1=%d, ID_EX_rs2=%d, reg_we=%b",
             EX_MEM_rd, ID_EX_rs1, ID_EX_rs2, EX_MEM_reg_we);
    $display("forward_a = %b (기대값: 2'b00), forward_b = %b (기대값: 2'b00)",
             forward_a, forward_b);

    if (forward_a == 2'b00 && forward_b == 2'b00) begin
      $display("✅ PASS: 포워딩 불필요 시 신호 안 발동\n");
    end else begin
      $display("❌ FAIL: 포워딩 신호 오류\n");
    end

    // Test Case 3: x0에 쓰는 경우 (포워딩 불가)
    EX_MEM_rd = 5'd0;     // x0에 쓰려고 함 (실제로는 x0은 읽기 전용)
    EX_MEM_reg_we = 1'b1;
    ID_EX_rs1 = 5'd0;     // x0을 읽음
    ID_EX_rs2 = 5'd0;

    #10;
    $display("=== Test Case 3: x0 제외 조건 ===");
    $display("EX_MEM_rd=%d, ID_EX_rs1=%d, ID_EX_rs2=%d, reg_we=%b",
             EX_MEM_rd, ID_EX_rs1, ID_EX_rs2, EX_MEM_reg_we);
    $display("forward_a = %b (기대값: 2'b00), forward_b = %b (기대값: 2'b00)",
             forward_a, forward_b);

    if (forward_a == 2'b00 && forward_b == 2'b00) begin
      $display("✅ PASS: x0 제외 조건 작동\n");
    end else begin
      $display("❌ FAIL: x0 제외 조건 오류\n");
    end

    // Test Case 4: 이전 명령어가 쓰지 않는 경우
    EX_MEM_rd = 5'd1;
    EX_MEM_reg_we = 1'b0;  // ← 이번에는 쓰지 않음
    ID_EX_rs1 = 5'd1;
    ID_EX_rs2 = 5'd0;

    #10;
    $display("=== Test Case 4: 쓰기 신호 불활성 ===");
    $display("EX_MEM_rd=%d, ID_EX_rs1=%d, ID_EX_rs2=%d, reg_we=%b",
             EX_MEM_rd, ID_EX_rs1, ID_EX_rs2, EX_MEM_reg_we);
    $display("forward_a = %b (기대값: 2'b00), forward_b = %b (기대값: 2'b00)",
             forward_a, forward_b);

    if (forward_a == 2'b00 && forward_b == 2'b00) begin
      $display("✅ PASS: 쓰기 신호 불활성 시 포워딩 안 함\n");
    end else begin
      $display("❌ FAIL: 쓰기 신호 조건 오류\n");
    end

    $finish;
  end

endmodule

// ===== 디버깅 팁 =====
// 파형에서 추적할 신호:
// 1. EX_MEM_rd: 이전 명령어의 rd 값이 파이프라인 레지스터에 올바르게 래치되었나?
// 2. ID_EX_rs1, ID_EX_rs2: 현재 명령어의 rs1, rs2가 디코더에서 올바르게 추출되었나?
// 3. EX_MEM_reg_we: 이전 명령어의 쓰기 신호가 활성화되었나?
// 4. forward_a, forward_b: 최종 포워딩 신호가 기대값과 일치하나?
// 5. debug_forward_condition_a, debug_forward_condition_b: 각 조건의 개별 판정
//
// 만약 forward_a = 2'b00이어야 하는데 2'b01이면:
// → debug 신호로 어느 조건이 거짓인지 확인
// → 그 조건의 입력 신호(예: EX_MEM_rd)가 올바른지 점검
