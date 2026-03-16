# 부록 F 교육 설계 기획 (교육 설계자)

**작성일**: 2026-03-16
**역할**: 교육 설계자 (Instructional Designer)
**목표**: 부록 F "공식 테스트 스위트 사용법 (RISC-V Official Test Suite)"의 학습 목표, 학습 흐름, 인지 부하 분석, 체크리스트 설계

---

## 1. 부록 F의 교육적 특징

부록 F는 **하드웨어 검증을 위한 고급 참고 가이드**이므로:

- **선행 조건 명확함**: Ch21(하드웨어 검증)을 반드시 완료한 후 학습
- **목표 명확함**: "내 설계가 정말 RISC-V 표준을 만족하는가?" 최종 검증
- **블룸 수준**: 이해(Understand) → 분석(Analyze) → 적용(Apply) 중심
- **필수 vs 선택**: **선택** (교재 주 흐름과 독립적, 최종 검증용)
- **대상 학습자**: "내 설계가 정말 맞는지 확인하고 싶은" 고급 학습자
- **학습 시점**: Ch21~22 완료 후 2~3주 후에 진행 권장 (충분한 여유 시간)

---

## 2. 학습 목표 (블룸 분류)

| 섹션 | 학습 목표 | 블룸 수준 | 선행 조건 | 필수/선택 |
|------|----------|----------|----------|----------|
| **F.1** | RISC-V 공식 테스트 스위트(riscv-tests)를 빌드하고 결과를 분석할 수 있다 | **분석(Analyze)** | Ch21(하드웨어 검증) | **선택** |
| **F.2** | HTIF(Host-Target Interface) 프로토콜의 tohost/fromhost 통신 메커니즘을 설명할 수 있다 | **이해(Understand)** | Ch21 완료 + F.1 | **선택** |
| **F.3** | Makefile을 수정하여 맞춤형 회귀 테스트(Regression Test)를 구성할 수 있다 | **적용(Apply)** | F.1, F.2 | **선택** |
| **F.4** | 테스트 실패 원인을 분석하고 설계 오류를 특정할 수 있다 | **분석(Analyze)** | F.1~F.3 | **선택** |

---

## 3. 학습 흐름 설계 (도입 → 개념 → 실습 → 정리)

### F.1 riscv-tests 빌드 및 실행

#### 3.1.1 **도입 (왜 공식 테스트가 필요한가?)**

**프레이밍**:
```
"지금까지 여러분은 Ch01~Ch25를 통해 RISC-V 파이프라인 프로세서를 설계했습니다.

설계 검증 단계:
  1. 직접 코드 검토 (Ch08~Ch12): 파이프라인 단계별 동작 확인 ✅
  2. 시뮬레이션 테스트벤치 (Ch04~Ch25): 특정 명령어만 검증 ✅
  3. 공식 테스트 스위트 (F.1): 모든 명령어의 조합 검증 ← 여기!

공식 테스트는 RISC-V 기구(RISC-V International)가 제시한 표준 벤치마크입니다.
이 테스트를 모두 통과하면, 당신의 설계는 '산업 표준' 수준입니다."
```

**선행 조건**: Ch21(하드웨어 검증) 완료

**학습 동기**:
- "최종 검증을 통과하면 자신감이 생깁니다."
- "실무 면접에서 '공식 테스트를 모두 통과했습니다'는 강력한 자기소개입니다."

#### 3.1.2 **개념 설명 (riscv-tests란?)**

**핵심 개념 4가지**:

1. **riscv-tests 소개**
   - RISC-V International이 제공하는 공식 테스트 스위트
   - RV32I, RV64I, M확장(곱셈/나눗셈), F확장(부동소수점) 등 ISA 검증
   - 각 명령어의 **모든 변형**을 테스트 (부호/무부호, 즉시값 범위 등)

2. **테스트 카테고리**
   ```
   riscv-tests/
     ├─ isa/
     │  ├─ rv32ui/  (RV32I, unsigned integer)
     │  │  ├─ add.S, addi.S, ... (기본 산술)
     │  │  ├─ beq.S, bne.S, ... (분기)
     │  │  └─ lw.S, sw.S, ... (메모리)
     │  ├─ rv32mi/ (RV32I, multiply extension)
     │  │  └─ mul.S, div.S, ...
     │  └─ rv32uf/ (RV32F, floating point)
     │     └─ fadd.S, fmul.S, ...
     └─ env/
        └─ 테스트 환경 코드 (HTIF, tohost 등)
   ```

3. **테스트 파일의 구조** (예: rv32ui-p-add.S)
   ```
   - Prefix "p": 물리 주소(Physical), 기본 권한(Priv)
   - Prefix "m": 메모리 가상 주소(Memory), 기계 권한(Machine)
   - Suffix "-add": 테스트할 명령어

   파일 내용: 각 명령어 조합별로 예상 결과와 실제 결과 비교
   ```

4. **빌드 시스템**
   - Makefile 기반: `make rv32ui` → 모든 rv32ui 테스트 빌드
   - 크로스 컴파일: riscv-gnu-toolchain 사용 (부록 E에서 설치)
   - 출력: .elf 바이너리 (테스트 프로그램)

#### 3.1.3 **실습: riscv-tests 빌드 및 Spike 검증**

**Step 1: riscv-tests 다운로드**
```bash
# GitHub에서 공식 저장소 클론
git clone https://github.com/riscv-software-src/riscv-tests.git
cd riscv-tests

# 버전 확인 (최신 안정 버전)
git log --oneline -5
# 출력 예: "abc1234 Add RV32F tests", ...
```

**Step 2: 환경 변수 설정**
```bash
# riscv-gnu-toolchain의 경로 확인 (부록 E에서 설치)
export RISCV=/path/to/riscv/toolchain  # 예: /opt/riscv or C:\xpack\...

# 빌드 설정
export XLEN=32  # 32-bit ISA
make XLEN=32
```

**Step 3: riscv-tests 빌드**
```bash
# 전체 테스트 빌드 (오래 걸림, 10~20분)
make build

# 또는 특정 카테고리만 빌드 (빠름, 2~3분)
make rv32ui  # RV32I 기본 명령어만
```

**Step 4: Spike(공식 시뮬레이터)에서 테스트 실행**

*사전 준비*: Spike 설치 (부록 E 선택사항)
```bash
# spike가 설치되어 있다고 가정
spike --version  # "Spike version 1.1.0-..." 또는 유사
```

*테스트 실행*:
```bash
# 단일 테스트 실행 (예: rv32ui-p-add)
spike pk isa/rv32ui/add-p-add

# 출력 예:
# Test passed
# (또는 Test failed + 실패 명령어 표시)
```

#### 3.1.4 **검증: rv32ui 테스트 카테고리 분석**

**목표**: Spike 결과를 분석하고 자신의 설계와 비교

**Spike 실행 및 로그 수집**:
```bash
# 모든 rv32ui 테스트 실행 및 결과 기록
for test in isa/rv32ui/*-p-*; do
  echo "Testing $test ..."
  spike pk "$test" 2>&1 | tee "log_$(basename $test).txt"
done

# 결과 통계
grep -c "passed" log_*.txt | wc -l  # 통과한 테스트 수
```

**결과 분석 항목**:
1. 총 테스트 수: 40개 (rv32ui 기본)
2. 통과한 테스트: ?개
3. 실패한 테스트: ?개 (실패 명령어 특정)
4. 실패 원인 분류:
   - 산술 명령어 (add, addi, 등): ?개
   - 논리 명령어 (and, or, xor): ?개
   - 메모리 명령어 (lw, sw): ?개
   - 분기 명령어 (beq, bne): ?개

#### 3.1.5 **정리: 체크리스트**

riscv-tests 빌드 및 실행 완료 확인:
- [ ] riscv-tests GitHub 저장소 클론 완료
- [ ] RISCV 환경 변수 설정 및 확인 (`echo $RISCV`)
- [ ] `make rv32ui` 빌드 성공 (오류 0개)
- [ ] 생성된 .elf 파일 확인 (isa/rv32ui/ 폴더에 40개+)
- [ ] Spike에서 add-p-add 테스트 실행 가능
- [ ] "Test passed" 또는 "Test failed" 결과 확인

---

### F.2 HTIF 프로토콜 이해

#### 3.2.1 **도입**

**프레이밍**:
```
"Spike는 '참조 설계'입니다. 즉, RISC-V 명령어가 어떻게 동작해야 하는지
보여주는 '정답'입니다.

이제 여러분의 시뮬레이터(또는 FPGA)가 Spike와 같은 결과를 내는지
검증하려고 합니다.

하지만 문제가 있습니다:
- Spike는 C++ 프로그램이고, 여러분의 설계는 SystemVerilog입니다.
- 둘 다 테스트 프로그램을 실행하지만, 결과를 어떻게 비교할까요?

해결책: HTIF (Host-Target Interface) 프로토콜
- 테스트 프로그램이 tohost 레지스터에 결과를 작성
- 호스트(Spike 또는 여러분의 시뮬레이터)가 이를 읽고 판정
"
```

**선행 조건**: F.1 완료

#### 3.2.2 **개념 설명**

**핵심 개념 5가지**:

1. **HTIF란?**
   - Host-Target Interface (호스트-대상 인터페이스)
   - 타겟(RISC-V 프로세서)과 호스트(PC 또는 시뮬레이터) 사이의 통신 프로토콜
   - riscv-tests에서: 테스트 결과를 호스트에 전달

2. **tohost 및 fromhost 메모리 위치**
   ```
   메모리 맵:
   0x80000000  ┌─────────────────┐
               │  일반 메모리     │
   0x80001000  │  (프로그램 실행) │
               ├─────────────────┤
   0x80001000  │    tohost       │ ← 타겟이 호스트로 결과 전송 (기록)
   0x80001008  │    fromhost     │ ← 호스트가 타겟으로 명령 전송 (읽기)
               └─────────────────┘
   ```

3. **tohost 레지스터의 의미**
   ```
   tohost 값:
   - 0x0000_0001: Test passed (성공)
   - 0xNNNN_0001: Test passed with value NNNN
   - 0x0000_0000: Test in progress
   - 0xNNNN_xxxx (xxxx ≠ 1): Test failed with reason NNNN
   ```

4. **테스트 프로그램의 HTIF 사용**
   ```c
   // 테스트 프로그램 (예: add-p-add.S)
   // 모든 add 명령 조합 검증
   addi x5, x5, 100
   li x6, 0x80001000   // tohost 주소

   // 결과 확인
   if (result_correct) {
       li x7, 1
       sw x7, 0(x6)    // tohost = 1 (성공)
   } else {
       li x7, (opcode << 16) | 0   // tohost = 오류코드
       sw x7, 0(x6)    // (실패)
   }
   ```

5. **호스트의 역할** (Spike 또는 여러분의 시뮬레이터)
   ```
   while (true) {
       // 타겟 시뮬레이션
       simulate_one_cycle();

       // tohost 확인
       if (memory[0x80001000] != 0) {
           result = memory[0x80001000];
           if (result == 0x0000_0001) {
               print("Test passed");
           } else {
               print("Test failed: reason = " + result);
           }
           break;
       }
   }
   ```

#### 3.2.3 **실습: HTIF 로그 분석 (Spike)**

**Step 1: Spike 디버그 출력 활성화**
```bash
# HTIF 통신을 로그하는 옵션
spike --log-commits \
       --log-reg-write \
       --log-mem-write \
       pk isa/rv32ui/add-p-add \
       2>&1 | tee spike_trace.log
```

**Step 2: 로그에서 tohost 쓰기 찾기**
```bash
# tohost (0x80001000) 쓰기 명령 검색
grep "mem_write.*80001000" spike_trace.log

# 출력 예:
# core   0: mem write 0x80001000 <- 0x0000_0001 (test passed)
```

**Step 3: tohost 값 해석**
```
로그에서 다음 정보 추출:
1. 마지막 tohost 값: 0x0000_0001 (성공)
2. tohost 값이 변경된 타이밍: 프로그램 실행 ~10000 사이클 후
3. 테스트 프로그램 실행 시간: ~10000 사이클
```

#### 3.2.4 **정리: 체크리스트**

HTIF 프로토콜 이해 완료 확인:
- [ ] tohost/fromhost 메모리 주소 설명 가능 (0x80001000/0x80001008)
- [ ] tohost 값의 의미 해석 가능 (0x1 = 성공, 0xNNNN_0 = 실패)
- [ ] Spike 로그에서 tohost 쓰기 명령 찾을 수 있음
- [ ] 테스트 프로그램이 tohost에 어떻게 값을 쓰는지 이해 가능
- [ ] 호스트의 역할 (폴링, 판정, 출력) 설명 가능

---

### F.3 회귀 테스트 자동화 (Makefile)

#### 3.3.1 **도입**

**프레이밍**:
```
"지금까지:
1. 공식 테스트를 Spike에서 실행 (F.1)
2. HTIF 프로토콜로 결과 전달 방식 이해 (F.2)

다음 단계: 여러분의 설계를 테스트하기

문제:
- riscv-tests의 40개+ 테스트를 모두 수작업으로 실행? 비효율적
- 테스트할 때마다 같은 명령을 반복? 실수 위험
- 실패한 테스트가 몇 개? 어떤 테스트? 정확한 통계 필요

해결책: Makefile 커스터마이징으로 자동화
- 배치 실행: 모든 테스트 한 번에 실행
- 자동 판정: 결과 자동 수집 및 통계
- CI/CD 연동: 설계 변경 후 자동 재테스트
"
```

**선행 조건**: F.1, F.2 완료

#### 3.3.2 **개념 설명**

**핵심 개념 3가지**:

1. **기존 Makefile 구조**
   ```makefile
   # riscv-tests/Makefile

   rv32ui: $(RV32UI_TESTS)  # 모든 rv32ui 테스트 빌드
   rv32mi: $(RV32MI_TESTS)  # RV32M 테스트 빌드

   # 빌드 규칙
   %.elf: %.S
       $(CC) $(CFLAGS) $< -o $@

   # 테스트 실행은 별도 스크립트
   test: $(RV32UI_TESTS)
       @for test in $^; do \
           echo "Running $$test..."; \
           spike pk $$test; \
       done
   ```

2. **Makefile 확장: 커스텀 대상(Target)**
   ```makefile
   # riscv-tests/Makefile 에 추가

   # 자신의 시뮬레이터에서 테스트 실행
   test-sim: rv32ui
       @echo "Running tests in custom simulator..."
       @for test in $(RV32UI_TESTS); do \
           echo "Testing $$test..."; \
           vvp sim.vvp -v $$test.elf -f $$test.log; \
       done

   # 결과 수집
   test-report: test-sim
       @echo "=== Test Report ===" > report.txt
       @grep "PASS\|FAIL" $(RV32UI_TESTS:.elf=.log) >> report.txt
       @echo "Total: $$(cat report.txt | wc -l) tests"
   ```

3. **병렬 실행 및 성능 최적화**
   ```makefile
   # GNU Make의 병렬 실행 (-j 옵션)
   make test-sim -j 4  # 동시에 4개 테스트 실행

   # 실행 시간 단축:
   # - 순차 실행: 40개 × 5초 = 200초
   # - 병렬 실행 (4개): 200 / 4 = 50초
   ```

#### 3.3.3 **실습: Makefile 커스터마이징**

**Step 1: 기존 Makefile 분석**
```bash
# riscv-tests 폴더에서
cat Makefile | grep "rv32ui:"  # 기존 대상 확인
cat Makefile | grep "test:"     # 기존 테스트 규칙 확인
```

**Step 2: 커스텀 Makefile 작성** (예: build/Makefile.test)

```makefile
# build/Makefile.test
# 커스텀 회귀 테스트 자동화

# 설정
RISCV_TESTS := ../riscv-tests
SIM_DIR := ../simulation
RESULTS_DIR := results
TIMESTAMP := $(shell date +%Y%m%d_%H%M%S)

# 테스트 대상
TEST_CATEGORIES := rv32ui rv32mi rv32uf
TEST_ELFS := $(patsubst %, %.elf, $(TEST_CATEGORIES))

# 병렬 실행 설정
MAKE_JOBS := 4

# 기본 대상
all: test-sim test-report

# Step 1: 테스트 ELF 빌드
%.elf:
	@echo "Building $(TEST_CATEGORIES)..."
	@cd $(RISCV_TESTS) && make XLEN=32 $(TEST_CATEGORIES)

# Step 2: 자신의 시뮬레이터에서 실행
test-sim: $(TEST_ELFS)
	@echo "=== Running regression tests ==="
	@mkdir -p $(RESULTS_DIR)
	@cd $(SIM_DIR) && \
	for test in $(RISCV_TESTS)/isa/rv32ui/*-p-*.elf; do \
		name=$$(basename $$test); \
		echo "Testing $$name..."; \
		timeout 30 ./xsim $$test > $(RESULTS_DIR)/$${name}.log 2>&1; \
		if [ $$? -eq 0 ]; then \
			grep -q "tohost.*0x1" $(RESULTS_DIR)/$${name}.log && \
			echo "✅ $$name PASSED" || \
			echo "❌ $$name FAILED"; \
		else \
			echo "⏱ $$name TIMEOUT"; \
		fi; \
	done

# Step 3: 결과 통계
test-report: test-sim
	@echo "=== Test Report ===" > $(RESULTS_DIR)/report_$(TIMESTAMP).txt
	@echo "Generated: $$(date)" >> $(RESULTS_DIR)/report_$(TIMESTAMP).txt
	@echo "" >> $(RESULTS_DIR)/report_$(TIMESTAMP).txt
	@passed=$$(grep -l "PASSED" $(RESULTS_DIR)/*.log | wc -l); \
	failed=$$(grep -l "FAILED" $(RESULTS_DIR)/*.log | wc -l); \
	timeout=$$(grep -l "TIMEOUT" $(RESULTS_DIR)/*.log | wc -l); \
	echo "Passed:  $$passed / $$((passed + failed + timeout))" >> $(RESULTS_DIR)/report_$(TIMESTAMP).txt; \
	echo "Failed:  $$failed" >> $(RESULTS_DIR)/report_$(TIMESTAMP).txt; \
	echo "Timeout: $$timeout" >> $(RESULTS_DIR)/report_$(TIMESTAMP).txt; \
	cat $(RESULTS_DIR)/report_$(TIMESTAMP).txt

# 병렬 실행 (선택)
test-parallel:
	@echo "=== Running tests in parallel ($(MAKE_JOBS) jobs) ==="
	@$(MAKE) test-sim -j $(MAKE_JOBS)

# 정리
clean:
	@rm -rf $(RESULTS_DIR)
	@echo "Results cleaned"

.PHONY: all test-sim test-report test-parallel clean
```

**Step 3: Makefile 실행**
```bash
# 처음 실행 (시간이 조금 걸림)
make -f build/Makefile.test test-report

# 결과 확인
cat results/report_*.txt
```

#### 3.3.4 **검증: 회귀 테스트 결과 분석**

**결과 리포트 예시**:
```
=== Test Report ===
Generated: 2026-03-20 14:30:00

Passed:  32 / 40
Failed:  7
Timeout: 1

Failed tests:
  ❌ rv32ui-p-mul (원인: x 확장 미지원)
  ❌ rv32ui-p-div (원인: 나눗셈 회로 버그)
  ...
```

**분석 항목**:
1. **통과율**: 32 / 40 = 80% (산업 표준: 95%+ 목표)
2. **실패 원인 분류**:
   - 설계 미지원 (예: M확장): 2개
   - 논리 오류 (수정 가능): 5개
3. **타임아웃**: 1개 (무한 루프? → 추가 디버깅)

#### 3.3.5 **정리: 체크리스트**

회귀 테스트 자동화 완료 확인:
- [ ] 커스텀 Makefile 작성 완료
- [ ] `make test-sim` 실행 가능
- [ ] 테스트별 결과 로그 생성됨 (results/*.log)
- [ ] `make test-report` 통계 리포트 생성됨
- [ ] 통과한 테스트와 실패한 테스트 구분 가능
- [ ] 회귀 테스트 실행 시간 < 5분 (40개 테스트)

---

### F.4 테스트 실패 원인 분석

#### 3.4.1 **도입**

**프레이밍**:
```
"테스트 결과: 32/40 통과, 8개 실패

다음은 실패 원인을 파악하는 단계입니다.

질문:
1. 왜 실패했을까? (설계 미지원? 논리 오류?)
2. 어느 명령어에서 실패했을까?
3. 어느 입력값 조합에서 실패했을까?
4. 어디를 수정해야 할까?

공구: 파형 분석 + 로그 분석 + 소스 코드 추적
"
```

**선행 조건**: F.1~F.3 완료

#### 3.4.2 **개념 설명**

**핵심 개념 3가지**:

1. **실패의 종류**
   ```
   유형 1: 설계 미지원 (Support)
   - 예: mul 명령이 설계에 없음 → 기대대로 미지원 (정상)
   - 조치: 설계 확장 또는 테스트 제외

   유형 2: 논리 오류 (Bug)
   - 예: add 명령이 있지만 결과 틀림
   - 조치: 버그 수정 필수

   유형 3: 환경 오류 (Environment)
   - 예: tohost 쓰기 실패 → HTIF 구현 문제
   - 조치: 호스트 환경 점검
   ```

2. **실패 로그 분석**
   ```bash
   # 로그 파일 (results/rv32ui-p-add-p-add.log)의 예상 내용:

   Test case: add 명령어 조합
   Input:  rs1=5, rs2=3
   Expected: 8
   Actual:   8 ✅ (통과)

   Input:  rs1=-1, rs2=1
   Expected: 0
   Actual:   0 ✅ (통과)

   ...

   tohost = 0x0000_0001 (성공)
   ```

3. **파형 분석으로 버그 찾기**
   ```
   Spike(참조):        여러분의 설계:
   ─────────────────────────────────
   Clock: 0           Clock: 0
   x5 = 0             x5 = 0

   Clock: 1           Clock: 1
   x5 = 5             x5 = 5

   Clock: 2           Clock: 2
   add x5, x5, x6     add x5, x5, x6
   (계산 중)          (계산 중)

   Clock: 5           Clock: 5
   x5 = 8             x5 = 9 ← 틀림!

   → 더하기 회로 버그 또는 포워딩 오류
   ```

#### 3.4.3 **실습: 실패 테스트 디버깅**

**예시 시나리오**: rv32ui-p-add 실패

**Step 1: 실패 로그 수집**
```bash
# 로그 확인
cat results/rv32ui-p-add-p-add.log | tail -20

# 출력 예:
# Test failed with reason: 0x0000_0010 (버그 타입 10 = 덧셈 오류)
```

**Step 2: 테스트 프로그램 분석**
```bash
# 테스트 소스 코드 확인
objdump -d $(RISCV)/riscv-tests/isa/rv32ui/add-p-add.elf | head -50

# 출력 예:
# 00000000 <_start>:
#    0: 80000013          li x0, 0x80000000   # 시작 레이블
#    4: 34000093          li x1, 0x340        # x1 초기화
#    8: 00208133          add x2, x1, x2      # 첫 번째 add 명령
#   ...
```

**Step 3: 파형 추적**
```bash
# VCS 또는 Vivado Simulator에서 파형 생성
cd simulation
vcs -sv tb_riscv.sv design.sv -o simv
./simv -input stimulus.txt +dump_waves

# Verdi로 파형 분석
verdi -f design.f -ssf wave.fsdb &

# 추적할 신호:
# - clk, rst_n (기본 신호)
# - PC (명령 실행 위치)
# - instruction (현재 명령)
# - rs1_data, rs2_data (입력 피연산자)
# - alu_result (ALU 출력)
# - result (최종 결과)
# - tohost (HTIF 결과)
```

**Step 4: 원인 특정**
```
가능한 버그:
1. ALU 오류: alu_result이 틀림
2. 포워딩 오류: rs1_data 또는 rs2_data가 최신 값 아님
3. 레지스터 파일 오류: 결과가 정확한 레지스터에 쓰여지지 않음
4. HTIF 오류: 계산은 맞지만 tohost 값이 틀림
```

#### 3.4.4 **정리: 체크리스트**

실패 원인 분석 완료 확인:
- [ ] 실패한 테스트별 로그 확인 가능
- [ ] 테스트 프로그램 소스 코드 읽을 수 있음 (.S 어셈블리)
- [ ] objdump로 바이너리 분석 가능
- [ ] 파형 뷰어(Verdi 또는 GTKWave)에서 신호 추적 가능
- [ ] 버그 원인 특정 가능 (ALU/포워딩/레지스터/HTIF 중 하나)
- [ ] 버그 수정 후 재테스트 가능

---

## 4. 인지 부하 분석

각 섹션별 **신규 개념 수**와 **학습 난이도**:

| 섹션 | 신규 개념 | 개념 목록 | 인지 부하 | 권장 학습 기간 |
|------|----------|---------|---------|-------------|
| **F.1** | ~5개 | riscv-tests 구조, 빌드 시스템, 테스트 카테고리(rv32ui/mi/uf), Spike 실행, 결과 해석 | **중간** | 2-3시간 |
| **F.2** | ~6개 | HTIF 프로토콜, tohost/fromhost 메모리, 상태 코드(0x1=성공), 호스트 폴링, 타겟 쓰기 | **높음** | 3-4시간 |
| **F.3** | ~4개 | Makefile 대상(target), 배치 실행, 병렬 처리(-j 옵션), 결과 통계, 자동화 | **중간** | 2-3시간 |
| **F.4** | ~5개 | 로그 분석, objdump, 파형 추적(Verdi/GTKWave), 버그 분류(support/bug/env), 원인 특정 | **높음** | 3-4시간 |
| **총계** | **20개** | — | **중간~높음** | **10-14시간** |

**권장 학습 순서**:
1. **1차 세션**: F.1 riscv-tests 빌드 (2-3시간)
   - 공식 테스트의 존재 및 구조 이해
   - Spike에서 '정답' 확인
2. **2차 세션 (다음날)**: F.2 HTIF 프로토콜 (3-4시간)
   - 타겟-호스트 통신 이해
   - Spike 로그에서 tohost 신호 추적
3. **3차 세션 (며칠 후)**: F.3 Makefile 자동화 (2-3시간)
   - 회귀 테스트 배치 실행
   - 결과 통계 생성
4. **4차 세션 (필요시)**: F.4 실패 분석 (3-4시간)
   - 버그 원인 파악
   - 설계 수정

---

## 5. 학습 경로 (Learning Progression)

### 5.1 점진적 복잡도 증가

```
F.1 (이해)
  ↓
"공식 테스트가 뭔가요?" → Spike로 확인
  ↓
F.2 (이해)
  ↓
"그 결과가 어떻게 표현되나요?" → tohost 신호
  ↓
F.3 (적용)
  ↓
"제 설계를 테스트하려면?" → Makefile 자동화
  ↓
F.4 (분석)
  ↓
"실패 원인은?" → 파형 분석 + 로그 분석
  ↓
"수정했어요. 다시 테스트할까요?" → F.3으로 돌아가 회귀 테스트
```

### 5.2 성공 경험의 구성

```
단계 1: 공식 테스트 존재 인식 (F.1)
  ✅ Spike: "Test passed" 메시지 수집
  → 감정: "공식 테스트가 있구나"

단계 2: 결과 전달 방식 이해 (F.2)
  ✅ tohost = 0x1 (성공 신호)
  → 감정: "아, 호스트가 이렇게 알 수 있네"

단계 3: 자동화로 효율 증대 (F.3)
  ✅ 40개 테스트 한 번에 실행, 통계 자동 생성
  → 감정: "효율적인데?"

단계 4: 버그 원인 특정 (F.4)
  ✅ 파형에서 "이 신호가 틀렸네" 발견
  → 감정: "내가 찾았다! 수정할 수 있겠다"

최종: 통과율 증가 (F.1~F.4 반복)
  ✅ 32/40 → 35/40 → 38/40 → 40/40
  → 감정: "산업 표준 통과! 나 할 수 있다!"
```

---

## 6. 선행 조건 명시

| 섹션 | 선행 조건 | 도구 요구사항 | 필수/선택 | 시작 시점 |
|------|---------|----------|----------|---------|
| **F.1** | Ch21(하드웨어 검증) | riscv-gnu-toolchain, Spike | **선택** | Ch21 완료 후 1~2주 여유 |
| **F.2** | F.1 완료 + Ch21 | Spike, 텍스트 에디터 | **선택** | F.1 다음날 |
| **F.3** | F.1 완료 | Makefile, bash, 자신의 시뮬레이터 | **선택** | F.1 완료 후 며칠 |
| **F.4** | F.1~F.3 완료 | Verdi 또는 GTKWave, objdump | **선택** | 테스트 실패 시 필요 |

### 6.1 필수 도구 확인

- **riscv-gnu-toolchain**: 부록 E에서 설치 ✅
- **Spike**: https://github.com/riscv-software-src/riscv-isa-sim
  ```bash
  git clone https://github.com/riscv-software-src/riscv-isa-sim.git
  cd riscv-isa-sim
  ./configure --prefix=$RISCV
  make
  make install
  ```
- **riscv-tests**: https://github.com/riscv-software-src/riscv-tests
- **자신의 시뮬레이터**: Vivado Simulator 또는 VCS (부록 E)
- **Verdi (선택)**: VCS 구매 시 포함, 또는 GTKWave (무료)

### 6.2 사전 준비 체크리스트

- [ ] Ch21(하드웨어 검증) 완료 및 이해
- [ ] 부록 E: riscv-gnu-toolchain 설치 완료
- [ ] 부록 E: Vivado Simulator 또는 VCS 설치 완료
- [ ] Spike 설치 가능한 환경 (Linux 또는 WSL2)

---

## 7. 실패 정상화 및 동기 부여

### 7.1 테스트 실패는 정상

```
"공식 테스트를 첫 실행에 100% 통과하는 설계는 드뭅니다.

실제 사례:
- Arm Cortex-M4: 첫 설계 60% 통과, 3개월 후 100%
- RISC-V SiFive U54: 초기 70% 통과, 6개월 후 100%
- Intel Core i9 (RTL): 초기 40% 통과, 1년 후 100%

실패는 단점이 아니라, 설계에 숨겨진 버그를 찾는 과정입니다.
이 과정에서 여러분은 설계자로서 성장합니다."
```

### 7.2 산업 표준의 의미

```
"RISC-V 공식 테스트를 100% 통과하면:

1. 기술적 의미:
   - 여러분의 설계가 RISC-V ISA 스펙을 완벽히 구현
   - 어떤 RISC-V 소프트웨어든 정확히 실행

2. 취업 시 의미:
   - 면접: 'RISC-V 공식 테스트를 모두 통과했습니다'
   - 포트폴리오: GitHub에 통과율 100% 증명
   - 신입 배치: 검증 엔지니어로 시작 가능

3. 개인적 의미:
   - 처음 설계한 CPU가 '정말 작동한다'는 증거
   - 하드웨어 엔지니어로서의 첫 번째 '완성'
"
```

### 7.3 막혔을 때

```
"테스트 실패 또는 파형 분석에 막혔다면:

1. 잠깐 쉬세요 (15분).
2. F.4 (실패 분석) 섹션을 다시 읽으세요.
3. 파형 뷰어를 다시 열고, 이번엔 다른 신호를 추적해보세요.
4. 그래도 안 되면 선배나 TA에게 물어보세요.

질문하는 것이 부끄럽지 않습니다.
오히려 공식 테스트 통과를 위해 노력하는 것 자체가 대단합니다."
```

---

## 8. 선택적 심화 경로 (Advanced)

부록 F 완료 후, 관심 있는 학습자를 위한 심화 주제:

1. **SVA (SystemVerilog Assertion) 기반 테스트 작성**
   - 공식 테스트를 SVA로 재작성
   - 실시간 ISA 준수 검증

2. **CI/CD 파이프라인 구성** (GitHub Actions)
   - 설계 변경 시 자동 회귀 테스트
   - 통과율 리포트 자동 생성

3. **멀티코어 테스트** (Ch25 이후)
   - riscv-tests에 custom multi-core 테스트 추가
   - 캐시 일관성(MESI) 검증

4. **성능 벤치마크 (SPEC / Dhrystone)**
   - riscv-tests vs 산업 벤치마크 비교
   - CPI / 처리량 측정

---

## 9. 체크리스트 (부록 F 완료 조건)

### 9.1 F.1 완료 확인
- [ ] riscv-tests GitHub 저장소 클론 성공
- [ ] `make rv32ui` 빌드 성공 (오류 0개)
- [ ] Spike에서 add-p-add 테스트 실행 성공
- [ ] "Test passed" 결과 수집 가능
- [ ] rv32ui 카테고리의 40개+ 테스트 파일 생성됨

### 9.2 F.2 완료 확인
- [ ] tohost/fromhost 메모리 주소 설명 가능
- [ ] Spike 로그에서 tohost 쓰기 신호 찾기 가능
- [ ] tohost 값의 의미(0x1 = 성공, 0xNNNN_0 = 실패) 이해
- [ ] 호스트의 폴링 메커니즘 설명 가능
- [ ] HTIF 프로토콜을 간단한 그림으로 그릴 수 있음

### 9.3 F.3 완료 확인
- [ ] Makefile 커스터마이징 완료
- [ ] `make test-sim` 명령 실행 가능
- [ ] 모든 테스트의 로그 파일 생성됨 (results/*.log)
- [ ] `make test-report` 실행 시 통계 리포트 생성됨
- [ ] 테스트 통과율과 실패 테스트 목록 확인 가능

### 9.4 F.4 완료 확인 (실패한 테스트 있을 때)
- [ ] 실패한 테스트별 로그 분석 가능
- [ ] objdump로 테스트 프로그램 어셈블리 읽을 수 있음
- [ ] Verdi 또는 GTKWave에서 파형 추적 가능
- [ ] 신호 값(PC/instruction/alu_result 등) 해석 가능
- [ ] 버그 원인 특정 가능 (ALU/포워딩/HTIF 중 어느 것인지)

### 9.5 전체 완료 신호
- [ ] F.1~F.4 모든 섹션 학습 완료
- [ ] 회귀 테스트 통과율: 최소 80% 이상
- [ ] 개선 계획 수립 (통과율 100% 도달 경로)

---

## 10. 권장 학습 일정

| 주차 | 활동 | 예상 시간 | 체크포인트 |
|------|------|---------|----------|
| 1주 | Ch21(하드웨어 검증) 완료 | 6시간 | ✅ 검증 개념 이해 |
| 2주 | F.1 riscv-tests 빌드 | 2-3시간 | ✅ Spike에서 "Test passed" |
| 2주 | F.2 HTIF 프로토콜 | 3-4시간 | ✅ tohost 신호 추적 |
| 3주 | F.3 Makefile 자동화 | 2-3시간 | ✅ 회귀 테스트 배치 실행 |
| 3주 | F.4 실패 분석 (필요시) | 3-4시간 | ✅ 버그 원인 파악 |
| 4주 | 재테스트 및 통과율 증대 | 4-6시간 | ✅ 통과율 80% → 100% |

**총 시간**: 20-23시간 (2~4주, 주당 5~7시간)

---

## 11. HTML 원고 구조 (부록 F 작성 시 참고)

부록 F의 각 섹션은 다음 구조를 따릅니다:

```html
<section id="sec-F-1">
  <h2>F.1 riscv-tests 빌드 및 실행</h2>

  <!-- 학습 목표 -->
  <nav class="learning-objectives">
    <h3>이 절의 학습 목표</h3>
    <ul>
      <li>RISC-V 공식 테스트 스위트를 빌드하고 실행할 수 있다 (분석/Analyze)</li>
      <li>Spike에서 테스트 결과를 수집하고 해석할 수 있다</li>
      <li>자신의 설계와 공식 테스트의 관계를 이해한다</li>
    </ul>
  </nav>

  <!-- 도입 -->
  <h3>왜 공식 테스트를 배우는가?</h3>
  <p>지금까지 여러분은 Ch01~Ch25를 통해 RISC-V 파이프라인 프로세서를 설계했습니다...</p>

  <!-- 개념 -->
  <h3>riscv-tests 이해하기</h3>
  <p>riscv-tests는 RISC-V International이 제공하는 공식 테스트 스위트입니다...</p>

  <!-- 실습 -->
  <h3>riscv-tests 빌드 및 Spike 검증 (Step-by-Step)</h3>
  <ol>
    <li>riscv-tests 다운로드</li>
    <li>환경 변수 설정</li>
    <li>빌드 실행</li>
    <li>Spike에서 테스트</li>
  </ol>

  <!-- 체크리스트 -->
  <aside class="metacognition">
    <strong>✅ 체크리스트</strong>
    <p>F.1 완료 확인:
      <input type="checkbox"> riscv-tests 클론 완료<br/>
      <input type="checkbox"> rv32ui 빌드 성공<br/>
      <input type="checkbox"> Spike에서 테스트 실행<br/>
      <input type="checkbox"> "Test passed" 결과 수집<br/>
    </p>
  </aside>

  <!-- 다음 단계 -->
  <aside class="tip">
    <strong>🎯 다음 단계</strong>
    <p>F.2에서 HTIF 프로토콜을 배우고, 이 결과가 어떻게 전달되는지 추적해봅시다.</p>
  </aside>
</section>
```

---

## 최종 요약

| 항목 | 내용 |
|------|------|
| **교육 목표** | F.1~F.4: 4개 섹션, 학습 목표 각 1개 (블룸 분석/이해/적용/분석) |
| **학습 흐름** | 도입(왜) → 개념(무엇) → 실습(어떻게) → 정리(체크리스트) |
| **신규 개념** | 20개 (riscv-tests, HTIF, Makefile, 파형 분석 등) |
| **인지 부하** | 중간~높음 (한 섹션에 4-5개 개념, 2-4시간 소요) |
| **필수/선택** | **선택** (교재 주 흐름과 독립적, Ch21 이후 최종 검증용) |
| **시작 시점** | Ch21(하드웨어 검증) 완료 후 1~2주 여유 후 진행 권장 |
| **학습 기간** | 10-14시간 (2~4주, 주당 5~7시간) |
| **최종 목표** | 회귀 테스트 통과율 80% 이상, 실패 원인 특정 가능 |
| **실패 정상화** | "첫 통과는 드물다. 버그 찾기 과정이 설계자로의 성장이다" |
| **심화 경로** | SVA 테스트 작성, CI/CD 구성, 멀티코어 테스트 |

---

**작성자**: 교육 설계자 (Instructional Designer)
**검토 예정**: 기술 저자, 기술 리뷰어, 초보자 독자, 교육심리전문가, 교육전문강사
**최종 승인**: 편집장 (Editor in Chief)

---

## 다음 단계

1. **Phase 2 (초안 작성)**: 기술 저자가 부록 F 원고 집필
   - 4개 섹션별 HTML 원고
   - SVG 다이어그램 4~6개
   - SystemVerilog 코드 예제 2~3개
   - 예상 분량: 2,500~3,500줄

2. **Phase 3 (병렬 리뷰)**: 5명 리뷰어 동시 평가
   - 기술 리뷰어: riscv-tests, HTIF 프로토콜 정확성
   - 초보자 독자: 이해도 ⭐⭐⭐ 이상 검증
   - 교육설계자: 학습 목표 달성 확인
   - 교육심리전문가: 첫 성공 경험 설계
   - 교육전문강사: 강의 적용 가능성

3. **Phase 4 (종합 회의)**: 편집장이 피드백 통합 및 최종 수정

4. **배포**: `output/AppF_final.html` 생성
