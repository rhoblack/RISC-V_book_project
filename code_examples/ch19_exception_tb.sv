// ============================================================================
// 예외/인터럽트 통합 테스트벤치
// Chapter 19 — 예외/인터럽트와 파이프라인 통합
// RISC-V 프로세서 설계 완전정복
// ============================================================================
// 검증 시나리오:
//   1. ECALL 예외 → 트랩 진입 → MRET 복귀
//   2. Illegal Instruction 예외
//   3. Load Misaligned 예외
//   4. 타이머 인터럽트 → 응답 시간 측정
//   5. 예외와 인터럽트 동시 발생 시 우선순위 검증
// ============================================================================

`timescale 1ns / 1ps

module exception_tb;

   // -----------------------------------------------------------------------
   // 클럭/리셋 생성
   // -----------------------------------------------------------------------
   logic clk;
   logic rst_n;

   localparam CLK_PERIOD = 10; // 100 MHz

   initial begin
      clk = 1'b0;
      forever #(CLK_PERIOD/2) clk = ~clk;
   end

   // -----------------------------------------------------------------------
   // DUT 인스턴스: 예외 처리 유닛
   // -----------------------------------------------------------------------
   // ID 스테이지 입력
   logic        id_illegal_instr;
   logic        id_ecall;
   logic        id_ebreak;
   logic [31:0] id_pc;

   // EX 스테이지 입력
   logic        ex_branch_misaligned;
   logic [31:0] ex_branch_target;
   logic [31:0] ex_pc;

   // MEM 스테이지 입력
   logic        mem_load_misaligned;
   logic        mem_store_misaligned;
   logic [31:0] mem_alu_result;
   logic [31:0] mem_pc;

   // 인터럽트 입력
   logic        ext_irq;
   logic        timer_irq;
   logic        sw_irq;

   // CSR 상태
   logic        mstatus_mie;
   logic        mie_meie;
   logic        mie_mtie;
   logic        mie_msie;
   logic [31:0] mtvec;

   // 출력
   logic        trap_taken;
   logic [31:0] trap_pc;
   logic [31:0] trap_mepc;
   logic [31:0] trap_mcause;
   logic [31:0] trap_mtval;
   logic        flush_if, flush_id, flush_ex, flush_mem;

   exception_unit u_dut (
      .clk                  (clk),
      .rst_n                (rst_n),
      .id_illegal_instr     (id_illegal_instr),
      .id_ecall             (id_ecall),
      .id_ebreak            (id_ebreak),
      .id_pc                (id_pc),
      .ex_branch_misaligned (ex_branch_misaligned),
      .ex_branch_target     (ex_branch_target),
      .ex_pc                (ex_pc),
      .mem_load_misaligned  (mem_load_misaligned),
      .mem_store_misaligned (mem_store_misaligned),
      .mem_alu_result       (mem_alu_result),
      .mem_pc               (mem_pc),
      .ext_irq              (ext_irq),
      .timer_irq            (timer_irq),
      .sw_irq               (sw_irq),
      .mstatus_mie          (mstatus_mie),
      .mie_meie             (mie_meie),
      .mie_mtie             (mie_mtie),
      .mie_msie             (mie_msie),
      .mtvec                (mtvec),
      .trap_taken           (trap_taken),
      .trap_pc              (trap_pc),
      .trap_mepc            (trap_mepc),
      .trap_mcause          (trap_mcause),
      .trap_mtval           (trap_mtval),
      .flush_if             (flush_if),
      .flush_id             (flush_id),
      .flush_ex             (flush_ex),
      .flush_mem            (flush_mem)
   );

   // -----------------------------------------------------------------------
   // 검증용 카운터 (인터럽트 응답 시간 측정)
   // -----------------------------------------------------------------------
   int irq_assert_cycle;
   int trap_taken_cycle;
   int response_time;

   // -----------------------------------------------------------------------
   // 테스트 태스크 정의
   // -----------------------------------------------------------------------

   // 모든 입력을 초기화
   task reset_inputs();
      id_illegal_instr     = 1'b0;
      id_ecall             = 1'b0;
      id_ebreak            = 1'b0;
      id_pc                = 32'd0;
      ex_branch_misaligned = 1'b0;
      ex_branch_target     = 32'd0;
      ex_pc                = 32'd0;
      mem_load_misaligned  = 1'b0;
      mem_store_misaligned = 1'b0;
      mem_alu_result       = 32'd0;
      mem_pc               = 32'd0;
      ext_irq              = 1'b0;
      timer_irq            = 1'b0;
      sw_irq               = 1'b0;
   endtask

   // 시스템 리셋
   task system_reset();
      rst_n = 1'b0;
      reset_inputs();
      mstatus_mie = 1'b1;     // 전역 인터럽트 인에이블
      mie_meie    = 1'b1;     // 외부 인터럽트 인에이블
      mie_mtie    = 1'b1;     // 타이머 인터럽트 인에이블
      mie_msie    = 1'b1;     // 소프트웨어 인터럽트 인에이블
      mtvec       = 32'h0000_1000; // 트랩 핸들러 주소
      repeat (3) @(posedge clk);
      rst_n = 1'b1;
      @(posedge clk);
   endtask

   // -----------------------------------------------------------------------
   // 시나리오 1: ECALL 예외
   // -----------------------------------------------------------------------
   task test_ecall();
      $display("\n===== 시나리오 1: ECALL 예외 =====");
      reset_inputs();
      @(posedge clk);

      // ECALL 명령어가 ID 스테이지에 도달
      id_ecall = 1'b1;
      id_pc    = 32'h0000_0100;
      @(posedge clk);

      // 검증: trap_taken 활성화, mcause = 11
      assert (trap_taken == 1'b1)
         else $error("[FAIL] ECALL: trap_taken이 활성화되지 않음");
      assert (trap_mcause == 32'd11)
         else $error("[FAIL] ECALL: mcause 불일치 (기대: 11, 실제: %0d)", trap_mcause);
      assert (trap_mepc == 32'h0000_0100)
         else $error("[FAIL] ECALL: mepc 불일치 (기대: 0x100, 실제: 0x%08h)", trap_mepc);
      assert (flush_if && flush_id)
         else $error("[FAIL] ECALL: 플러시 신호 미활성화");

      $display("[PASS] ECALL 예외: mcause=%0d, mepc=0x%08h", trap_mcause, trap_mepc);
      reset_inputs();
      repeat (2) @(posedge clk);
   endtask

   // -----------------------------------------------------------------------
   // 시나리오 2: Illegal Instruction 예외
   // -----------------------------------------------------------------------
   task test_illegal_instr();
      $display("\n===== 시나리오 2: Illegal Instruction 예외 =====");
      reset_inputs();
      @(posedge clk);

      id_illegal_instr = 1'b1;
      id_pc = 32'h0000_0200;
      @(posedge clk);

      assert (trap_taken == 1'b1)
         else $error("[FAIL] Illegal: trap_taken 미활성화");
      assert (trap_mcause == 32'd2)
         else $error("[FAIL] Illegal: mcause 불일치 (기대: 2, 실제: %0d)", trap_mcause);

      $display("[PASS] Illegal Instruction: mcause=%0d, mepc=0x%08h",
               trap_mcause, trap_mepc);
      reset_inputs();
      repeat (2) @(posedge clk);
   endtask

   // -----------------------------------------------------------------------
   // 시나리오 3: Load Misaligned 예외
   // -----------------------------------------------------------------------
   task test_load_misaligned();
      $display("\n===== 시나리오 3: Load Misaligned 예외 =====");
      reset_inputs();
      @(posedge clk);

      mem_load_misaligned = 1'b1;
      mem_alu_result      = 32'h0001_0003; // 비정렬 주소 (워드 접근)
      mem_pc              = 32'h0000_0300;
      @(posedge clk);

      assert (trap_taken == 1'b1)
         else $error("[FAIL] Load Misaligned: trap_taken 미활성화");
      assert (trap_mcause == 32'd4)
         else $error("[FAIL] Load Misaligned: mcause 불일치 (기대: 4, 실제: %0d)",
                     trap_mcause);
      assert (trap_mtval == 32'h0001_0003)
         else $error("[FAIL] Load Misaligned: mtval 불일치");

      $display("[PASS] Load Misaligned: mcause=%0d, mtval=0x%08h",
               trap_mcause, trap_mtval);
      reset_inputs();
      repeat (2) @(posedge clk);
   endtask

   // -----------------------------------------------------------------------
   // 시나리오 4: 타이머 인터럽트 + 응답 시간 측정
   // -----------------------------------------------------------------------
   task test_timer_interrupt();
      $display("\n===== 시나리오 4: 타이머 인터럽트 =====");
      reset_inputs();
      @(posedge clk);

      // 타이머 인터럽트 어설트
      timer_irq = 1'b1;
      mem_pc    = 32'h0000_0400; // 현재 실행 중인 명령어
      irq_assert_cycle = $time / CLK_PERIOD;
      @(posedge clk);

      if (trap_taken) begin
         trap_taken_cycle = $time / CLK_PERIOD;
         response_time = trap_taken_cycle - irq_assert_cycle;
         $display("[PASS] 타이머 인터럽트: mcause=0x%08h, 응답시간=%0d 사이클",
                  trap_mcause, response_time);
      end else begin
         $error("[FAIL] 타이머 인터럽트: trap_taken 미활성화");
      end

      assert (trap_mcause == 32'h8000_0007)
         else $error("[FAIL] 타이머: mcause 불일치 (기대: 0x80000007)");

      reset_inputs();
      repeat (2) @(posedge clk);
   endtask

   // -----------------------------------------------------------------------
   // 시나리오 5: 예외 + 인터럽트 동시 발생 → 예외 우선
   // -----------------------------------------------------------------------
   task test_priority();
      $display("\n===== 시나리오 5: 예외/인터럽트 우선순위 =====");
      reset_inputs();
      @(posedge clk);

      // 동기 예외 + 비동기 인터럽트 동시 발생
      mem_load_misaligned = 1'b1;
      mem_alu_result      = 32'h0001_0001;
      mem_pc              = 32'h0000_0500;
      timer_irq           = 1'b1;
      @(posedge clk);

      // 동기 예외가 우선: mcause = 4 (Load Misaligned)
      assert (trap_mcause == 32'd4)
         else $error("[FAIL] 우선순위: 동기 예외가 인터럽트보다 우선되어야 함 (mcause=%0d)",
                     trap_mcause);

      $display("[PASS] 우선순위: 동기 예외(mcause=%0d)가 인터럽트보다 우선 처리됨",
               trap_mcause);
      reset_inputs();
      repeat (2) @(posedge clk);
   endtask

   // -----------------------------------------------------------------------
   // 메인 테스트 시퀀스
   // -----------------------------------------------------------------------
   initial begin
      $display("================================================================");
      $display(" Chapter 19 예외/인터럽트 통합 테스트벤치");
      $display("================================================================");

      system_reset();

      test_ecall();
      test_illegal_instr();
      test_load_misaligned();
      test_timer_interrupt();
      test_priority();

      $display("\n================================================================");
      $display(" 모든 테스트 시나리오 완료");
      $display("================================================================");
      $finish;
   end

   // 파형 덤프
   initial begin
      $dumpfile("ch19_exception_tb.vcd");
      $dumpvars(0, exception_tb);
   end

endmodule