# Chapter 25 기술 리뷰

## 요약
- **Critical**: 1건
- **Major**: 3건
- **Minor**: 2건
- **최종 평가**: ⭐⭐⭐⭐ (4/5)
  - RISC-V ISA 명령어 인코딩에 심각한 오류 존재
  - SystemVerilog 코드 구조 및 합성 가능성 양호
  - 테스트벤치 설계 우수, 모든 핵심 시나리오 커버
  - 교육용 단순화 수준 적절

---

## 🔴 Critical Issues

### C1: RISC-V LR/SC 명령어 인코딩 오류
- **위치**: 섹션 25.2 "RISC-V A 확장 명령어 인코딩" (라인 335-368)
- **현상**:
  ```
  manuscript (잘못됨):
  LR.W: funct7 = 0010001 (라인 341)
  SC.W: funct7 = 0011000 (라인 346)

  is_lr 검증: funct7 == 7'b0010001 (라인 364)
  is_sc 검증: funct7 == 7'b0011000 (라인 367)
  ```

- **원인**: RISC-V ISA Manual v2.2 A 확장 스펙 불일치
  - **정정된 스펙**:
    - LR.W: funct7 = `0001000` (7'b0001000, not 0010001)
    - SC.W: funct7 = `0001100` (7'b0001100, not 0011000)
  - 오류의 결과: 파이프라인이 LR/SC 명령어를 올바르게 디코딩하지 못함
  - 하드웨어 합성 후 실제 ISA와 불일치하여 멀티코어 시스템에서 동작 불가

- **해결**:
  ```systemverilog
  // 정정된 코드
  is_lr = (opcode == 7'b101111) && (funct3 == 3'b010) &&
          (funct7 == 7'b0001000) && (instr[24:20] == 5'b00000);

  is_sc = (opcode == 7'b101111) && (funct3 == 3'b010) &&
          (funct7 == 7'b0001100);

  // 또한 주석의 설명도 수정:
  // LR.W: funct7 = 0001000 (not 1100001, 0010001)
  // SC.W: funct7 = 0001100 (not 0011000)
  ```

- **영향**:
  - 합성 후 실제 RISC-V 하드웨어에서 LR/SC 명령어 실행 불가
  - Ch17(멀티코어 설계)의 ISA 정합성 검증 필수

---

## 🟡 Major Issues

### M1: LR/SC 결과값 해석 역순 (코드 vs 주석)
- **위치**: lr_sc_unit.sv 및 manuscript (라인 99, 464-465, 1000-1005)
- **현상**:
  ```systemverilog
  // 라인 99-100 (코드)
  sc_success = 1'b1;  // rd ← 0 (성공)  [주석이 잘못됨]
  sc_success = 1'b0;  // rd ← 1 (실패)  [주석이 잘못됨]

  // RISC-V 스펙의 실제 의미
  // sc_success는 결과값이 아니라 내부 신호
  // rd에 기록되어야 할 값:
  // - SC 성공: rd ← 0
  // - SC 실패: rd ← 1 (또는 다른 비영값)
  ```

- **원인**: 코드 로직과 주석의 불일치
  - 코드에서 `sc_success`는 성공 여부를 나타내는 내부 신호 (1=성공, 0=실패)
  - 하지만 실제 RISC-V ISA에서 rd 레지스터에 기록되는 값은 역순
  - 주석이 이를 명확히 하지 못함

- **해결**:
  ```systemverilog
  // 명확성 개선
  if (addr_match) begin
     // 예약 일치: SC 성공
     mem_wr = 1'b1;
     // RISC-V ISA: rd ← 0을 의미하므로
     // 로직 계층에서는 sc_success=1로 표시하되,
     // WB 스테이지에서 rd ← (sc_success==0 ? 0 : 1) 처리 필요
     sc_success = 1'b1;  // "성공했다"는 의미
  end else begin
     mem_wr = 1'b0;
     sc_success = 1'b0;  // "실패했다"는 의미
  end

  // 주석 추가:
  // sc_success=1 → rd에 기록할 값은 0 (RISC-V 성공)
  // sc_success=0 → rd에 기록할 값은 1 (RISC-V 실패)
  ```

- **영향**: WB 스테이지에서 rd 레지스터 기록 시 반전 로직 필수

### M2: always_comb 블록에서 미정의 경로 존재 가능성
- **위치**: lr_sc_unit.sv의 always_comb (라인 76-102)
- **현상**:
  ```systemverilog
  // 문제: mem_addr과 mem_wdata가 조건부로만 설정
  always_comb begin
     mem_rd = 1'b0;
     mem_wr = 1'b0;
     mem_addr = ex_addr;      // 항상 할당됨 (OK)
     mem_wdata = ex_wdata;    // 항상 할당됨 (OK)
     // ... 나머지는 조건부
  end
  ```

- **원인**: Vivado/VCS 합성기가 경고 발생 가능성
  - `always_comb` 사용으로 대부분 안전하지만
  - ex_lr_w, ex_sc_w 모두 0인 경우, sc_result_valid가 미정의 상태일 수 있음

- **해결**:
  ```systemverilog
  always_comb begin
     // 기본값 명시적 설정 (모든 출력)
     mem_rd          = 1'b0;
     mem_wr          = 1'b0;
     mem_addr        = ex_addr;
     mem_wdata       = ex_wdata;
     sc_success      = 1'b0;
     sc_result_valid = 1'b0;  // 명시적으로 추가 (이미 있으므로 OK)

     // 조건부 처리
     if (ex_lr_w) begin
        mem_rd = 1'b1;
     end else if (ex_sc_w) begin
        sc_result_valid = 1'b1;
        if (addr_match) begin
           mem_wr = 1'b1;
           sc_success = 1'b1;
        end
     end
  end
  ```
- **현재 상태**: 코드가 이미 기본값을 명시적으로 설정하므로 OK (감지되지 않음)

### M3: 스핀락 구현 설명의 논리 오류
- **위치**: Manuscript 라인 565-567
- **현상**:
  ```
  "5. 성공: 임계 영역 진입, lock = 1로 설정되어 다른 코어 진입 방지"

  실제 스핀락 로직:
  - LR.W로 lock 값 읽기
  - SC.W에서 x0(zero, 값=0)을 lock에 기록
  - 따라서 lock = 0이 되어야 함 (unlock 상태)
  ```

- **원인**: 주석 코드와 설명의 불일치
  ```assembly
  sc.w  t1, x0, (a0)    // x0(zero) = 0을 lock에 저장 (언락)
  ```
  - 코드는 "x0을 저장 (언락)"이라고 명시했으나
  - 설명은 "lock = 1로 설정"이라고 모순됨
  - 실제 스핀락 관례: lock=1이 잠금, lock=0이 해제 (또는 그 반대)
  - 이 코드에서는 lock=0이 해제 상태 (맞음)

- **해결**: 설명 문장 수정
  ```
  기존: "성공: 임계 영역 진입, lock = 1로 설정되어 다른 코어 진입 방지"
  수정: "성공: 임계 영역 진입, lock = 0으로 설정되어 임계 영역 획득 (다른 코어는 loop)"

  또는 더 명확하게:
  "성공: SC에서 x0(=0)을 lock에 저장하여 "언락" 상태로 변경.
   이제 이 코어가 임계 영역을 점유하고 있으며, 다른 코어들은
   LR에서 lock!=0을 읽을 때까지 계속 spin."
  ```

---

## 🟢 Minor Issues

### S1: 변수명 일관성 (대소문자 혼용)
- **위치**: mesi_tracker.sv와 manuscript (상태 인코딩)
- **현상**:
  ```systemverilog
  // 코드에서는 일관되게 대문자:
  localparam logic [1:0] MODIFIED  = 2'b00;
  localparam logic [1:0] EXCLUSIVE = 2'b01;
  localparam logic [1:0] SHARED    = 2'b10;
  localparam logic [1:0] INVALID   = 2'b11;

  // 하지만 주석에는 소문자/혼합:
  "Modified: 이 캐시만 유일한 최신 복사본 보유"
  ```

- **원인**: RISC-V 문서와 교재의 관례 차이
  - RISC-V ISA Manual은 Modified, Exclusive, Shared, Invalid로 대문자 시작
  - 코드 스타일은 VERILOG_STYLE (ALL_CAPS)

- **해결**: 소수 영향, 스타일 일관성 권장만 필요
  - 현재 코드는 합성 가능하고 동작 정확

### S2: Testbench 주소 범위 제한
- **위치**: ch25_lr_sc_unit_tb.sv (라인 70, 94, 126)
- **현상**:
  ```systemverilog
  // 테스트 주소들이 모두 워드 정렬됨
  ex_addr = 32'h0000_1000;
  ex_addr = 32'h0000_2000;
  ex_addr = 32'h0000_3000;

  // 예약 일치 판정: [31:2] 비교 (워드 정렬)
  addr_match = (reservation_addr[31:2] == ex_addr[31:2]);

  // 하지만 비정렬 주소(예: 0x1001, 0x1003)는 테스트되지 않음
  ```

- **원인**: RISC-V LR.W는 32비트(또는 64비트) 명령어이므로 워드 정렬 필수
  - 비정렬 주소 테스트는 불필요하나
  - 엣지 케이스(0x1FFF vs 0x2000 경계) 테스트 추가 권장

- **해결**: 선택사항, 교육용 충분함

---

## ✅ SystemVerilog 정확성 검증

### 합성 가능성
- **mesi_tracker.sv**: ✅ 합성 가능
  - always_ff + always_comb 분리 정확
  - 모든 상태 전이 명시적
  - default 케이스 포함 (좋은 습관)

- **lr_sc_unit.sv**: ✅ 합성 가능
  - FF는 예약 레지스터만 관리
  - Comb는 메모리 인터페이스 + SC 결과
  - 명시적 기본값 할당

### Basys 3 FPGA 리소스 적합성
- MESI 상태: 2비트/라인 (매우 경량)
- LR/SC 예약: 33비트 (1비트 valid + 32비트 address)
- 전체: ✅ Basys 3의 BRAM/FF 부족 문제 없음

### IEEE 1800-2017 준수
- ✅ logic, always_ff, always_comb 정확 사용
- ✅ 비블로킹 할당(<= in always_ff, = in always_comb)
- ⚠️ Testbench에서 $display 사용 (시뮬레이션 전용, 합성 불가 - 의도적)

---

## ✅ RISC-V ISA 스펙 검증

### LR/SC 인코딩 (CRITICAL)
- ❌ **funct7 값이 잘못됨** (C1 참조)
- ✅ opcode (7'b101111) 정확
- ✅ funct3 (3'b010) 정확
- ✅ rs2 제약 (LR은 rs2=00000) 정확

### SC 결과값 의미
- ⚠️ **rd 값 해석 복잡함** (M1 참조)
- 코드 로직은 정확하나 주석 및 설명에서 혼란 야기

### MESI 상태 전이
- ✅ 4가지 상태 정의 정확 (M, E, S, I)
- ✅ 상태 전이 조건 정확
  - Modified: bus_rd→Shared (flush), bus_rdx→Invalid (flush+invalidate)
  - Exclusive: pr_wr→Modified (Silent), bus_rd→Shared, bus_rdx→Invalid
  - Shared: pr_wr→Modified (do_bus_rdx), bus_rdx→Invalid
  - Invalid: pr_rd→(mem_shared ? Shared : Exclusive), pr_wr→Modified

---

## ✅ Testbench 검증

### MESI Tracker TB
- ✅ 모든 6가지 핵심 시나리오 커버
  1. Invalid → Exclusive (단독 Read)
  2. Exclusive → Modified (로컬 Write)
  3. Modified → Shared (BusRd)
  4. Shared → Invalid (BusRdX)
  5. Invalid → Shared (공유 Read)
  6. Shared → Modified (Write + BusRdX)
- ✅ Assertion 문으로 검증
- ✅ VCD 덤프 설정

### LR/SC Unit TB
- ✅ 3가지 핵심 시나리오
  1. LR → SC 성공 (간섭 없음)
  2. LR → 스누핑 무효화 → SC 실패
  3. LR → SC 주소 불일치 → 실패
- ✅ 스누핑 시그널 검증
- ✅ Assertion 문으로 검증

### 미검증 항목
- ❌ 2코어 동시 접근 시나리오 (실제 멀티코어 환경)
  - 단일 코어 관점에서만 검증
  - Ch17(멀티코어 통합)에서 시뮬레이션 필요
- ❌ 경쟁 조건(Race Condition) 타이밍 검증
  - 스누핑과 SC 사이의 타이밍 경합 미테스트

---

## 종합 의견

### RISC-V RV32A 스펙 준수도: ⭐⭐ (2/5)
**Critical Issue (C1) 때문에 현재 상태로는 RISC-V 스펙 미준수**
- funct7 인코딩이 잘못되어 ISA와 불일치
- 정정 후에는 ⭐⭐⭐⭐⭐ 수준

### Basys 3 FPGA 합성 가능성: ⭐⭐⭐⭐⭐ (5/5)
- 리소스 사용량 매우 경량
- 모든 신호가 합성 가능
- 다음 스테이지와의 인터페이스 명확

### MESI 프로토콜 설계: ⭐⭐⭐⭐⭐ (5/5)
- 4가지 상태 전이 로직 정확
- 버스 스누핑 시그널 처리 정확
- Testbench로 충분히 검증

### LR/SC 설계: ⭐⭐⭐⭐ (4/5)
- 예약 메커니즘 정확 (단, ISA 인코딩 오류)
- 스누핑 무효화 처리 정확
- 주석 및 설명 명확화 필요

### 교육 품질 (부가 검토)
- **도입**: 멀티코어 문제를 구체적 예제로 잘 설명 (도서관 비유, Google Docs 비유)
- **개념**: MESI 상태, 상태 전이 명확
- **구현**: 실제 SystemVerilog 코드 포함, 학습 경로 명확
- **확장**: Lock-Free 알고리즘, 뮤텍스 언급 (교과서적 좋음)

---

## ✍️ 수정 요청 전 체크리스트

### 필수 수정 (승인 조건)
- [ ] C1: RISC-V LR/SC funct7 값 정정 (0001000, 0001100)
  - 파일: manuscript line 337, 341, 346, 364, 367
  - 파일: ch25_spinlock_lr_sc.sv 내 주석 확인

### 권장 수정 (Major)
- [ ] M1: sc_success 결과값 해석 및 주석 명확화
- [ ] M2: always_comb 기본값 명시 (이미 OK, 생략 가능)
- [ ] M3: 스핀락 설명 lock=0/1 상태 명확화

### 선택 사항 (Minor)
- [ ] S1: 상태 이름 대소문자 일관성 (합성에 영향 없음)
- [ ] S2: Testbench 엣지 케이스 추가 (교육용으로는 충분함)

---

## 다음 리뷰어를 위한 주의사항

1. **Ch17 멀티코어 통합 시**: MESI + LR/SC 상호작용 검증 필수
   - 2코어 동시 접근 시뮬레이션 추가 권장
   - 스누핑 신호 우선순위 확인

2. **명령어 디코딩**: LR/SC funct7 값 정정 후 파이프라인 컨트롤 신호 재검증

3. **WB 스테이지**: SC 결과를 rd에 기록할 때 반전 로직 필요 여부 확인
   - sc_success=1 → rd=0, sc_success=0 → rd=1 (또는 rd=nonzero)

4. **AMBA 프로토콜**: 버스 스누핑 신호(bus_rd, bus_rdx)가 Ch16-17의 AHB/APB와 매핑되는지 확인

---

## 최종 평가

**현재 상태**: ⭐⭐⭐⭐ (4/5) - **승인 불가**
- Critical Issue 1건 존재 (RISC-V ISA 인코딩 오류)

**수정 후 예상**: ⭐⭐⭐⭐⭐ (5/5) - **승인 가능**
- C1 정정 시 모든 Critical/Major 해결
- 교육용 멀티코어/캐시 일관성 입문서로 우수
