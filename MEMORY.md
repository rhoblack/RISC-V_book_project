# RISC-V 교재 프로젝트 메모리

## 에이전트 실행 규칙

에이전트 역할 정의는 **CLAUDE.md에 직접 포함**되어 있음 → agents/*.md 별도 Read 불필요.
spawn prompt에 역할명과 임무만 명시하면 됨.

| 역할 | CLAUDE.md 섹션 |
|------|---------------|
| 편집장 (Team Lead) | "편집장" 섹션 |
| 기술 저자 | "기술 저자" 섹션 |
| 기술 리뷰어 | "기술 리뷰어" 섹션 |
| 초보자 독자 | "초보자 독자" 섹션 |
| 교육 설계자 | "교육 설계자" 섹션 |
| 교육심리전문가 | "교육심리전문가" 섹션 |
| 교육전문강사 | "교육전문강사" 섹션 |

## 프로젝트 현황 (2026-03-13)

- 완료: Ch01~Ch18 (18/25, 72%)
- 다음: Ch19 — 예외와 인터럽트 처리

## Ch18 집필 완료 (2026-03-13)

- **원고**: manuscripts/part7/chapter18.html (1,594줄)
- **output**: output/Ch18_CSR과_특권_수준_final.html
- **편집장 최종 승인**: ✅ Critical 0건, Major 0건 (Phase 4 수정 7건 완료)
- **이해도 ⭐⭐⭐⭐⭐, 교육설계 ⭐⭐⭐⭐⭐, 심리적안전 ⭐⭐⭐⭐⭐, 강사적합도 ⭐⭐⭐⭐⭐**
- **신규 SVG 3개**: ch18_sec01_privilege_levels.svg, ch18_sec02_csr_map.svg, ch18_sec03_csr_instruction.svg
- **코드 2개**: ch18_csr_unit.sv, ch18_csr_tb.sv
- **핵심 설계 결정**:
  - 구현 CSR 7개: mstatus(0x300), mie(0x304), mtvec(0x305), mscratch(0x340), mepc(0x341), mcause(0x342), mip(0x344)
  - mstatus WPRI 마스크: `32'h0000_1888` (MIE[3]+MPIE[7]+MPP[12:11])
  - mip: 레지스터 없음 — 조합 논리로 하드웨어 직결 합성 (RORL, 소프트웨어 쓰기 불가)
  - irq_pending: `mstatus_reg[3] & |(mie_reg & mip_wire)` (3단계 조건)
  - CSR 쓰기 우선순위: rst_n > trap_en > mret_en > csr_we
  - trap_en 시: MPIE←MIE, MIE←0, MPP←2'b11(M-mode), mepc←trap_pc, mcause←trap_cause
  - **mret_en 시: MIE←MPIE, MPIE←1, MPP←2'b11 (M-mode only 스펙 준수 — U-mode 미구현 시 최소 권한=M-mode)**
  - mtvec Vectored 주소 계산(BASE+4×cause): Ch19에서 수행 (Ch18은 레지스터 값만 출력)
  - CSR 명령어 6종: CSRRW(001)/CSRRS(010)/CSRRC(011)/CSRRWI(101)/CSRRSI(110)/CSRRCI(111)
  - 쓰기 조건: RW/RWI 항상, RS/RC는 rs1≠x0, RSI/RCI는 uimm≠0
  - 테스트벤치: 3단계 점진적 검증 (쓰기/읽기 → 비트마스크 → 인터럽트마스킹)
  - MRET mstatus 최종값: 32'h1888 (MIE=1[3] + MPIE=1[7] + MPP=11[12:11])
- **감정 곡선**: 낯섦→친숙화(MMIO/레지스터파일 연결)→이해(7개만/3비트만)→성취(3단계PASS)→기대(Ch19)
- **Ch19 인터페이스**: trap_en, mret_en, trap_pc, trap_cause (입력) / mtvec_out, mepc_out, irq_pending (출력)
- **Phase 4 수정 7건**: C1(MPP←2'b11 스펙 수정), C2(TB 기대값 32'h1888), RORL aside, mip_wire 비트 aside, 비트이동 설명, 119 비유 한계, 성취선언, 연습문제 5번 비계

## Ch17 집필 완료 (2026-03-13)

- **원고**: manuscripts/part6/chapter17.html (~2,805줄)
- **output**: output/Ch17_APB_브리지와_주변_장치_연결_final.html
- **편집장 최종 승인**: ✅ Critical 0건, Major 0건 (Phase 4 수정 11건 완료)
- **이해도 ⭐⭐⭐⭐⭐, 교육설계 ⭐⭐⭐⭐⭐, 심리적안전 ⭐⭐⭐⭐⭐, 강사적합도 ⭐⭐⭐⭐⭐**
- **신규 SVG 7개**: ch17_sec01_apb_protocol, ch17_sec02_ahb_apb_bridge, ch17_sec03_uart_block, ch17_sec03_uart_timing(신규), ch17_sec04_gpio_block, ch17_sec05_timer_block, ch17_sec06_system_integration
- **코드 6개**: ch17_ahb_to_apb_bridge.sv, ch17_apb_uart.sv, ch17_apb_gpio.sv, ch17_apb_timer.sv, ch17_peripheral_top.sv, ch17_peripheral_tb.sv
- **핵심 설계 결정**:
  - APB 2단계: Setup Phase(PSEL=1, PENABLE=0) → Enable Phase(PSEL=1, PENABLE=1)
  - AHB-to-APB 브리지 FSM: ST_IDLE → ST_SETUP → ST_ACCESS
  - hready_out: IDLE=1, SETUP=0, ACCESS=pready (AHB 마스터 대기 제어)
  - 주소 디코더: addr_reg[13:12] → UART(0xFFFF_0xxx), GPIO(0xFFFF_1xxx), Timer(0xFFFF_2xxx)
  - UART 8N1: baud_div = CLK_FREQ/(BAUD_RATE×16) = 54 @ 115200 baud/100MHz
  - TX FSM: TX_IDLE→TX_START→TX_DATA→TX_STOP, RX FSM 동일 구조
  - UART int_status_reg: 단일 always_ff (W1C 클리어 > 이벤트 세트 우선순위)
  - baud_div=0 방어: 최솟값 2로 클램프 (언더플로우 방지)
  - GPIO 2-FF 동기화기: gpio_in→gpio_in_sync_0→gpio_in_sync_1 (메타안정성 방지)
  - 상승 에지 인터럽트: rising_edge = gpio_in_sync_1 & ~gpio_in_prev
  - Timer: prescale_tick → count++, count==cmp → int_pending → timer_irq → Ch19 mip.MTIP
  - PRDATA MUX: psel[0:2] 기반 (기본값 1'b1로 교착 방지)
  - Basys 3: Silicon Laboratories CP2102 USB-UART 브리지
  - TB 태스크: AHB-Lite 규격 준수 — HREADY=1 확인 후 새 주소 구동
- **Phase 4 수정 11건**: BUG-1~3(다중드라이버/주소주석/CP2102), C2~C3 코드, 비유한계문구×2, valid_reg 설명, FIFO설명+aside, W1C 우선순위 설명, UART 타이밍 SVG, 메타인지+성취선언
- 다음: Ch18 — 인터럽트 컨트롤러

## Ch17 집필 완료 (2026-03-13)

- **원고**: manuscripts/part6/chapter17.html (2,805줄)
- **output**: output/Ch17_APB_브리지와_주변_장치_연결_final.html
- **편집장 최종 승인**: ✅ Critical 0건, Major 0건
- **이해도 ⭐⭐⭐⭐⭐, 교육설계 ⭐⭐⭐⭐⭐, 심리적안전 ⭐⭐⭐⭐⭐, 강사적합도 ⭐⭐⭐⭐⭐**
- **신규 SVG**: figures/ch17_sec03_uart_timing.svg (UART 8N1 비트타이밍 + 16× 오버샘플링)
- **Phase 4 수정 8건**:
  1. 17.1절 고속도로/골목길 비유 한계 문구 추가 (I1: 파이프라인 유무가 핵심 차이)
  2. 17.2절 valid_reg 연속 전송(Back-to-Back) 시나리오 단락 추가 (B2, C1)
  3. 17.3절 모스부호 비유 한계 문구 추가 (I2: NRZ vs 가변길이 인코딩)
  4. 17.3절 FIFO 원형 버퍼 원리 설명 단락 추가 (B1: wr_ptr/rd_ptr, Full/Empty 판별)
  5. 17.3절 $clog2 실무 팁 aside 추가 (B1 연계)
  6. 17.3절 W1C 단일 블록 우선순위 설명 단락 추가 (B3: IEEE 1800-2017 다중드라이버)
  7. 17.3절 UART 비트타이밍 SVG 삽입 (교육심리 필수: 그림 17-3b)
  8. 17.7절 metacognition aside + 성취 선언 문단 추가 (교육심리/교육설계)
- **핵심 설계 결정**:
  - APB 프로토콜: Setup(PSEL=1,PENABLE=0) + Enable(PSEL=1,PENABLE=1) 2단계
  - AHB-to-APB 브리지: 3상태 FSM (IDLE→SETUP→ACCESS), addr_reg/write_reg 래치
  - APB 주소 맵: UART=0xFFFF_0000, GPIO=0xFFFF_1000, Timer=0xFFFF_2000 (addr[13:12])
  - UART: 8N1, 16× 오버샘플링, TX/RX 8엔트리 FIFO, baud_div=54@115200/100MHz
  - GPIO: 2단 FF 동기화기, DIR 레지스터, gpio_out=out_reg&dir_reg
  - Timer: 프리스케일러+비교기, W1C INT_STAT, AUTO_RELOAD, timer_irq→Ch19 mip.MTIP
  - peripheral_top: PRDATA/PREADY MUX (psel 기반), pready_mux 기본=1'b1(교착방지)
  - 검증: ahb_write/ahb_read 태스크, UART 루프백, baud_div=2(시뮬 속도 최적화)

## Ch16 집필 완료 (2026-03-13)

- **원고**: manuscripts/part6/chapter16.html (~1,650줄)
- **output**: output/Ch16_AMBA_AHB_버스_설계_final.html
- **편집장 최종 승인**: ✅ Critical 0건, Major 0건 (Phase 4 수정 12건 완료)
- **이해도 ⭐⭐⭐⭐⭐, 교육설계 ⭐⭐⭐⭐⭐, 심리적안전 ⭐⭐⭐⭐⭐, 강사적합도 ⭐⭐⭐⭐⭐**
- **신규 SVG 5개**: ch16_sec01_protocol_problem, ch16_sec02_amba_family, ch16_sec04_ahb_timing, ch16_sec05_ahb_master_fsm, ch16_sec07_ahb_interconnect
- **코드 4개 (HTML 내 포함)**: ahb_master_bridge.sv, ahb_sram_slave.sv, ahb_interconnect.sv, ahb_tb.sv
- **핵심 설계 결정**:
  - AHB-Lite 채택 (ARM IHI0033A, 단일 마스터)
  - Master FSM 5상태: M_IDLE → M_ADDR → M_WAIT(HREADY=0) / M_DATA(HREADY=1) → M_DONE
  - **addr_lat 래치 시점**: `state == M_IDLE && cache_req` (M_ADDR 진입 직전, HREADY 무관)
  - HWDATA는 M_DATA 상태에서만 구동 (1사이클 파이프라인 규칙)
  - M_DATA에서 HREADY=1 확인 후 M_DONE 전이 (데이터 페이즈 Wait 처리)
  - HREADY=0 시 HADDR/HTRANS/HSIZE/HWRITE/HWDATA 전부 동결 의무
  - Slave 래치 조건: HSEL && HTRANS[1] && HREADY_in (3가지 모두 필수)
  - Wait State FSM: S_IDLE → S_WAIT(N사이클) → S_DONE(1사이클). WAIT_CYCLES=N이면 총 지연 N+1사이클
  - SRAM 초기화: `initial` 블록으로 시뮬레이션 X-propagation 방지 (합성 도구 무시)
  - HRDATA MUX: 1사이클 지연된 hsel_d 사용 (파이프라인 타이밍 보정)
  - HREADY MUX: 단일 전송(NONSEQ→IDLE) 패턴 전용 (back-to-back 시 hsel_d 기반으로 변경 필요)
  - 인터커넥트: HSEL 주소 디코더 (0x0000=IMEM / 0x0001=DMEM / 0xFFFF=APB)
  - SVA 3종: `|->` (overlapping) 연산자 — HREADY=0인 현재 사이클에 신호 안정 검사
  - Ch15 자체 프로토콜 → AHB 신호 대응표 (16.2절)
  - APB Bridge (0xFFFF_xxxx) Ch17 예약 슬롯 배치
- **Phase 4 수정 12건**: C1~C4 Critical, M1~M2 Major, M5 SVA, E1~E2 교육설계, P2 심리, I1~I3 강사

## Ch15 집필 완료 (2026-03-12)

- **원고**: manuscripts/part5/chapter15.html (1,055줄)
- **output**: output/Ch15_메모리_컨트롤러와_캐시_메모리_인터페이스_final.html
- **편집장 최종 승인**: ✅ Critical 0건, Major 0건
- **이해도 ⭐⭐⭐⭐⭐, 교육설계 ⭐⭐⭐⭐⭐, 심리적안전 ⭐⭐⭐⭐⭐, 강사적합도 ⭐⭐⭐⭐⭐**
- **신규 SVG 4개**: ch15_sec01_integrated_fsm, ch15_sec02_burst_timing, ch15_sec02_dcache_fsm, ch15_sec03_perf_analysis
- **신규 코드 3개**: ch15_mem_controller.sv, ch15_cache_system.sv, ch15_cache_tb.sv
- **핵심 설계 결정**:
  - 통합 메모리 컨트롤러: D-Cache 우선 고정 우선순위 중재기 (ARB_IDLE→SERVE_D→DRAIN_D→SERVE_I→DRAIN_I)
  - 버스트 전송: 8-beat (8×32비트=32바이트=1캐시라인), beat_cnt[2:0]
  - BRAM 동기 읽기 처리: ARB_DRAIN 상태 추가로 마지막 워드 손실 방지
  - 미스 페널티: I-Cache=12사이클, D-Cache(Clean)=12사이클, D-Cache(Dirty)=22사이클
  - FSM 확장: I-Cache WAIT_GRANT 추가, D-Cache WAIT_WB_GRANT/WAIT_REFILL_GRANT 추가
  - D-Cache Data Array: `(* ram_style = "distributed" *)` LUTRAM (조합 읽기 지원)
  - 성능 카운터: cycle_cnt, instr_cnt, icache_miss_cnt, dcache_miss_cnt (합성 가능)
  - Part 5 마일스톤 달성: 3단계 벤치마크(순차→스래싱→개선), 히트율/CPI 측정
- **Phase 4 수정 14건**: C1~C4 Critical, M1~M6 Major, B1~B2 초보자, P1~P4 심리, I1~I2 강사

## Ch14 집필 완료 (2026-03-12)

- **원고**: manuscripts/part5/chapter14.html (1,407줄)
- **output**: output/Ch14_L1_데이터_캐시와_쓰기_정책_final.html
- **편집장 최종 승인**: ✅ Critical 0건, Major 0건
- **이해도 ⭐⭐⭐⭐, 교육설계 ⭐⭐⭐⭐⭐, 심리적안전 ⭐⭐⭐⭐**
- **신규 SVG 6개**: ch14_sec01~sec06 (write_policy_comparison, writeback_cache_structure, 2way_set_associative, dcache_pipeline_integration, dcache_fsm, cache_coherence_issue)
- **신규 코드 3개**: ch14_dcache_direct_mapped_wb.sv, ch14_dcache_2way_wb.sv, ch14_dcache_tb.sv
- **핵심 설계 결정**:
  - D-Cache(2-Way): 4KB, 64세트, Tag[31:11]=21비트, Index[10:5]=6비트, Offset[4:0]=5비트
  - D-Cache(직접매핑): 4KB, 128라인, Tag[31:12]=20비트, Index[11:5]=7비트
  - Write-Back 정책: Dirty 비트 1비트, Eviction 시에만 메모리 기록
  - FSM 5상태: IDLE → TAG_CHECK → WRITE_BACK → REFILL → UPDATE
  - LRU: 세트당 1비트 (0=Way0이 LRU, 1=Way1이 LRU)
  - latched_replace_way: TAG_CHECK 시점 래치 → WRITE_BACK/REFILL에서 일관 사용
  - dcache_stall: 미스 시 전체 파이프라인 동결 (모든 레지스터 Hold)
  - pipeline_stall = load_use_stall || icache_stall || dcache_stall
  - Byte Enable: funct3 기반 (SW=4'b1111, SH=4'b0011, SB=4'b0001)
  - FENCE.I: I-Cache valid bit 전체 리셋
  - TB 주소: 0x0000_0100 / 0x0010_0100 / 0x0020_0100 → 모두 index=8 매핑
- **Phase 4 수정 7건**: 비유 한계 문구, FSM SVG 참조 안내, latched_replace_way 설명, byte_en 출처, FENCE.I 의사코드 명시, 14.7절 보강

## Ch13 집필 완료 (2026-03-12)

- **원고**: manuscripts/part5/chapter13.html (~1,077줄)
- **편집장 최종 승인**: ✅ 이해도 ⭐⭐⭐⭐⭐
- **핵심 설계**: I-Cache 4KB/직접매핑/128엔트리, Tag[31:12]=20비트, Index[11:5]=7비트
- **신호 우선순위**: `flush > icache_stall > load_use_stall`

## Ch12 집필 완료 (2026-03-12)

- **핵심 설계**: WB-ID 포워딩(레지스터 파일 내부), rv32i_pipeline_complete top 모듈
- **성능**: 단일사이클 ~25MHz/CPI=1.0, 멀티사이클 ~50MHz/CPI≈4.1, 파이프라인 ~65MHz/CPI≈1.2

## Ch11 집필 완료 (2026-03-11)

- **핵심 설계**: 분기 판정 EX 스테이지, 2사이클 버블, JAL=1사이클/JALR=2사이클 버블

## Ch10 집필 완료 (2026-03-11)

- **핵심 설계**: forwarding_unit (EX-EX > MEM-EX), hazard_detection_unit (Load-Use stall)

## Ch09 집필 완료 (2026-03-11)

- **핵심 설계**: 파이프라인 레지스터 4종, Harvard 구조, NOP=32'h0000_0013

## Ch08 집필 완료 (2026-03-11)

- **핵심 설계**: Moore FSM 17상태, always_ff+always_comb, CPI_avg≈4.1

## HTML 원고 코드 하이라이팅 구현 (2026-03-11)

- **방식**: Highlight.js CDN (v11.9.0, atom-one-dark 테마)
- **변환 처리**: `language-systemverilog` → `language-verilog` (JS로 런타임 변환)
- **HTML 이스케이프**: `<pre><code>` 내부 `<`, `>`, `&` 반드시 이스케이프

## output 폴더 규칙

- 집필 완료 파일: `output/ChNN_챕터제목_final.html`
- 경로 변환: `../../templates/` → `../templates/`, `../../figures/` → `../figures/`
- 현재 _final 적용 완료: Ch01~Ch18

## 주요 경로

- 원고: manuscripts/partN/chapterNN.html
- output: output/ChNN_챕터제목_final.html
- 리뷰 로그: review_logs/
- SVG: figures/
- 코드: code_examples/
