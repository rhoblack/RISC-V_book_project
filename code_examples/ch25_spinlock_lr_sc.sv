// ============================================================================
// LR/SC (Load-Reserved / Store-Conditional) 실행 유닛
// - RISC-V A 확장의 LR.W / SC.W 명령어를 파이프라인 EX/MEM 스테이지에서 처리
// - 교육용 단순화 모델: 단일 예약 세트(Single Reservation Set)
// - 합성 가능, Basys 3 대상
// ============================================================================
module lr_sc_unit (
   input  logic        clk,
   input  logic        rst_n,

   // 파이프라인 EX 스테이지 인터페이스
   input  logic        ex_lr_w,       // LR.W 명령어 실행 중
   input  logic        ex_sc_w,       // SC.W 명령어 실행 중
   input  logic [31:0] ex_addr,       // 메모리 주소 (rs1 + offset)
   input  logic [31:0] ex_wdata,      // SC.W 기록 데이터 (rs2 값)

   // 외부 스누핑 입력 (다른 코어의 메모리 접근 감시)
   input  logic        snoop_valid,   // 다른 코어의 메모리 접근 발생
   input  logic [31:0] snoop_addr,    // 다른 코어가 접근한 주소
   input  logic        snoop_write,   // 다른 코어의 쓰기 접근 여부

   // 메모리 인터페이스 출력
   output logic        mem_rd,        // 메모리 읽기 요청 (LR.W)
   output logic        mem_wr,        // 메모리 쓰기 요청 (SC.W 성공 시)
   output logic [31:0] mem_addr,      // 메모리 주소
   output logic [31:0] mem_wdata,     // 메모리 기록 데이터

   // SC.W 결과 (rd 레지스터에 기록)
   output logic        sc_success,    // SC.W 성공 여부 (0=성공, 1=실패)
   output logic        sc_result_valid // SC.W 결과 유효
);

   // 예약 레지스터 (Reservation Register)
   logic        reservation_valid;     // 예약 유효 여부
   logic [31:0] reservation_addr;      // 예약된 주소

   // 예약 일치 판정 (워드 정렬 주소 비교)
   logic addr_match;
   assign addr_match = reservation_valid &&
                       (reservation_addr[31:2] == ex_addr[31:2]);

   // ---------------------------------------------------------------
   // 예약 레지스터 관리
   // ---------------------------------------------------------------
   always_ff @(posedge clk or negedge rst_n) begin
      if (!rst_n) begin
         reservation_valid <= 1'b0;
         reservation_addr  <= 32'h0;
      end
      else begin
         // 우선순위: (1) SC.W 실행 → 예약 해제
         //           (2) 스누핑으로 무효화
         //           (3) LR.W 실행 → 새 예약 설정
         if (ex_sc_w) begin
            // SC.W가 실행되면 성공/실패와 무관하게 예약 해제
            reservation_valid <= 1'b0;
         end
         else if (snoop_valid && reservation_valid &&
                  (snoop_addr[31:2] == reservation_addr[31:2])) begin
            // 다른 코어가 예약된 주소에 쓰기 → 예약 무효화
            // (읽기에 의한 무효화는 구현에 따라 선택적)
            if (snoop_write)
               reservation_valid <= 1'b0;
         end
         else if (ex_lr_w) begin
            // LR.W 실행 → 새로운 예약 설정
            reservation_valid <= 1'b1;
            reservation_addr  <= ex_addr;
         end
      end
   end

   // ---------------------------------------------------------------
   // 메모리 인터페이스 및 SC 결과 생성
   // ---------------------------------------------------------------
   always_comb begin
      // 기본값
      mem_rd          = 1'b0;
      mem_wr          = 1'b0;
      mem_addr        = ex_addr;
      mem_wdata       = ex_wdata;
      sc_success      = 1'b0;
      sc_result_valid = 1'b0;

      if (ex_lr_w) begin
         // LR.W: 메모리 읽기 수행 (예약은 FF에서 설정)
         mem_rd = 1'b1;
      end
      else if (ex_sc_w) begin
         sc_result_valid = 1'b1;
         if (addr_match) begin
            // 예약이 유효하고 주소 일치 → SC 성공
            mem_wr     = 1'b1;
            sc_success = 1'b1;  // rd ← 0 (성공)
         end
         else begin
            // 예약 무효 또는 주소 불일치 → SC 실패
            mem_wr     = 1'b0;  // 메모리 쓰기 안 함
            sc_success = 1'b0;  // rd ← 1 (실패) — 주의: RISC-V에서 0=성공
         end
      end
   end

   // 참고: RISC-V 스펙에서 SC.W의 rd 값
   // - 0: Store-Conditional 성공
   // - 비영(nonzero): Store-Conditional 실패
   // sc_success = 1이면 rd에 0을, sc_success = 0이면 rd에 1을 기록

endmodule
