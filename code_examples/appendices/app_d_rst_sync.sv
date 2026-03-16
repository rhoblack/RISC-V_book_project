// ============================================================
// 리셋 동기화기 — 비동기 리셋 → 동기 리셋 변환
// ============================================================
// 목적: 비동기 리셋 해제 시 메타스태빌리티 방지
// 방법: 2단 플립플롭 동기화 + 선택적 디바운서
// ============================================================
module rst_sync (
   input  logic clk,          // 시스템 클록
   input  logic rst_async_n,  // 비동기 리셋 입력 (액티브 로우, btnC)
   output logic rst_sync_n    // 동기화된 리셋 출력 (액티브 로우)
);

   // 2단 플립플롭 동기화기
   // (* async_reg = "true" *) 속성: Vivado에 CDC 레지스터임을 알림
   // → 배치 시 두 FF를 가까이 배치하여 경로 지연 최소화
   (* async_reg = "true" *)
   logic rst_meta;             // 메타스태빌리티 가능 (1단)

   (* async_reg = "true" *)
   logic rst_sync_reg;         // 안정화된 값 (2단)

   // 비동기 어서트(즉시 리셋), 동기 디어서트(클록 에지에서 해제)
   always_ff @(posedge clk or negedge rst_async_n) begin
      if (!rst_async_n) begin
         // 비동기 리셋: 즉시 활성화 (메타스태빌리티 위험 없음)
         rst_meta     <= 1'b0;
         rst_sync_reg <= 1'b0;
      end else begin
         // 동기 해제: 2단 FF를 통과하여 안정화
         rst_meta     <= 1'b1;
         rst_sync_reg <= rst_meta;
      end
   end

   assign rst_sync_n = rst_sync_reg;

endmodule