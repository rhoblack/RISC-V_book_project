// ============================================================
// Chapter 21 — ILA 디버그 프로브 래퍼 모듈
// RISC-V 프로세서 설계 완전정복
// ============================================================
// Vivado ILA IP를 인스턴스화하여 핵심 신호를 관찰하는 모듈.
// 합성 가능 — Vivado에서 ILA IP를 생성 후 연결합니다.
// ============================================================

module ila_debug_core (
   input  logic        clk,           // 시스템 클럭
   input  logic        rst_n,         // 비동기 리셋 (액티브 로우)

   // === 파이프라인 관찰 신호 ===
   input  logic [31:0] pc_if,         // IF 스테이지 PC
   input  logic [31:0] instr_if,      // IF 스테이지 명령어
   input  logic [31:0] pc_wb,         // WB 스테이지 PC (커밋 완료)
   input  logic [31:0] alu_result_ex, // EX 스테이지 ALU 결과

   // === 해저드 제어 신호 ===
   input  logic        stall,         // 파이프라인 스톨
   input  logic        flush,         // 파이프라인 플러시
   input  logic [1:0]  forward_a,     // 포워딩 MUX A 선택
   input  logic [1:0]  forward_b,     // 포워딩 MUX B 선택

   // === 메모리/캐시 신호 ===
   input  logic        icache_hit,    // I-캐시 히트
   input  logic        dcache_hit,    // D-캐시 히트
   input  logic [31:0] mem_addr,      // 메모리 접근 주소
   input  logic [31:0] mem_wdata,     // 메모리 쓰기 데이터

   // === 성능 카운터 ===
   input  logic [31:0] mcycle_lo,     // mcycle 하위 32비트
   input  logic [31:0] minstret_lo    // minstret 하위 32비트
);

   // ---------------------------------------------------------
   // ILA IP 인스턴스 (Vivado IP Catalog에서 생성)
   // 프로브 수: 8, 각 프로브 폭: 32비트
   // 샘플 깊이: 1024
   // ---------------------------------------------------------
   // Vivado에서 "ILA (Integrated Logic Analyzer)" IP를 다음
   // 설정으로 생성하십시오:
   //   - Number of Probes: 8
   //   - Sample Data Depth: 1024
   //   - Probe Width: 모두 32
   //   - Trigger: probe0 (PC) 기본 설정
   //
   // 생성된 IP 이름: ila_0 (기본값)
   // ---------------------------------------------------------

   // 프로브 신호 패킹 — 관련 신호를 32비트로 묶음
   logic [31:0] hazard_status;
   logic [31:0] cache_status;

   // 해저드 상태를 하나의 프로브로 패킹
   assign hazard_status = {
      24'b0,
      forward_b,         // [5:4] 포워딩 B
      forward_a,         // [3:2] 포워딩 A
      flush,             // [1]   플러시
      stall              // [0]   스톨
   };

   // 캐시 상태를 하나의 프로브로 패킹
   assign cache_status = {
      30'b0,
      dcache_hit,        // [1] D-캐시 히트
      icache_hit         // [0] I-캐시 히트
   };

   // ---------------------------------------------------------
   // ILA IP 인스턴스화
   // 주의: 아래 코드는 Vivado에서 ILA IP를 생성한 후
   //       자동 생성되는 인스턴스 템플릿을 사용합니다.
   //       IP 미생성 시 합성 오류가 발생합니다.
   // ---------------------------------------------------------
   ila_0 u_ila (
      .clk    (clk),
      .probe0 (pc_if),          // 트리거 기본 대상
      .probe1 (instr_if),       // 현재 명령어
      .probe2 (pc_wb),          // 커밋 PC
      .probe3 (alu_result_ex),  // ALU 결과
      .probe4 (hazard_status),  // 해저드 제어 상태
      .probe5 (cache_status),   // 캐시 히트/미스
      .probe6 (mcycle_lo),      // 사이클 카운터
      .probe7 (minstret_lo)     // 명령어 카운터
   );

   // ---------------------------------------------------------
   // 디버깅 팁:
   // 1. 트리거 조건 예시:
   //    - PC = 특정 주소 → 특정 함수 진입 시점 캡처
   //    - stall == 1 → 스톨 발생 순간 캡처
   //    - icache_hit == 0 → 캐시 미스 패턴 관찰
   //
   // 2. Trigger Position을 50%로 설정하면
   //    트리거 전후 512샘플씩 캡처하여 맥락 파악 용이
   //
   // 3. Window 모드 사용 시 여러 트리거 이벤트를
   //    하나의 캡처 버퍼에 저장 가능
   // ---------------------------------------------------------

endmodule
