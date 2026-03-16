# 부록 E 교육 설계 기획 (교육 설계자)

**작성일**: 2026-03-16
**역할**: 교육 설계자 (Instructional Designer)
**목표**: 부록 E "개발 도구 설치 가이드"의 학습 목표, 학습 흐름, 인지 부하 분석, 체크리스트 설계

---

## 1. 부록 E의 교육적 특징

부록 E는 본 교재와 달리 **순차적 학습이 아닌 참고용 가이드**이므로:

- **모듈성**: 각 섹션이 독립적으로 이해 가능해야 함
- **필수성 구분**: 어떤 도구는 필수(Ch01 이전), 어떤 도구는 선택(대체 수단 제공)
- **진입 장벽 낮추기**: 첫 설치 성공 경험이 자신감과 진행 의욕을 결정
- **실패 정상화**: 개발 환경 설치는 하드웨어 엔지니어링이 아닌 "소프트웨어 운영 문제"
- **점진적 성공**: 한 도구 설치 완료 → 검증 성공 → 다음 도구로 진행

---

## 2. 학습 목표 (블룸 분류)

| 섹션 | 학습 목표 | 블룸 수준 | 선행 조건 | 필수/선택 |
|------|----------|----------|----------|----------|
| **E.1** | Vivado 2024.x 프로젝트를 생성하고 LED 깜박이는 비트스트림을 생성할 수 있다 | **적용(Apply)** | 없음 | **필수** (Ch01.2 이전) |
| **E.2** | RISC-V 어셈블리 코드를 riscv-gnu-toolchain으로 컴파일하고 .hex 파일을 생성할 수 있다 | **적용(Apply)** | 없음 | **필수** (Ch03.10 이전) |
| **E.3** | VCS 또는 Vivado Simulator로 SystemVerilog 시뮬레이션을 실행하고 파형을 해석할 수 있다 | **이해(Understand)** | E.1 또는 기본 Verilog 지식 | **선택** (Vivado Simulator로 대체 가능) |
| **E.4** | 개발 도구 설치 중 발생한 일반적인 오류를 진단하고 해결 방법을 찾을 수 있다| **분석(Analyze)** | E.1~E.3 | **보조** (설치 오류 발생 시 참조) |

---

## 3. 학습 흐름 설계 (도입 → 개념 → 실습 → 정리)

### E.1 Vivado 2024.x 설치 및 검증

#### 3.1.1 **도입 (왜 이 도구가 필요한가?)**

**프레이밍**:
```
"이 교재는 Xilinx Basys 3 FPGA 보드에서 설계한 RISC-V 프로세서를 실행합니다.
하드웨어를 FPGA에 구현하려면:
  1. 설계 (SystemVerilog) ← Ch01~Ch25로 배웁니다
  2. 합성 (Synthesis) ← Vivado가 해줍니다
  3. 배치 & 라우팅 (P&R) ← Vivado가 해줍니다
  4. 비트스트림 생성 ← Vivado가 해줍니다
  5. FPGA 로드 ← Vivado IDE 버튼 클릭

Vivado는 이 모든 단계를 자동으로 처리하는 EDA 도구입니다."
```

**선행 조건**: 없음 (Ch01.2 이전 설치)

**학습 동기**:
- "환경 설정은 어려워 보이지만, 1회만 하면 됩니다."
- "첫 번째 성공(LED 깜박임)은 이 과정의 가장 감정적인 보상입니다."

#### 3.1.2 **개념 설명 (Vivado란?)**

**핵심 개념 3가지**:

1. **Vivado의 역할**: EDA(Electronic Design Automation) 통합 개발 환경
   - ISE의 후속 도구 (2013년부터 표준)
   - Xilinx Artix-7, Spartan-7, UltraScale 모두 지원
   - 우리는 Artix-7 XC7A35T (Basys 3) 사용

2. **설치 형태**:
   - Vivado Design Suite 2024.1 (최신 버전)
   - 선택 사항: ISE(구형), Vivado HLS, Vivado Lab Edition
   - 우리는 **Vivado Design Suite** 중 필수 도구만 선택

3. **설치 환경**:
   - 운영체제: Windows 10/11, Linux (이 교재는 Windows 기준)
   - 디스크: 최소 40GB 자유 공간
   - RAM: 최소 8GB (권장 16GB)
   - 라이선스: **무료 WebPACK 라이선스** (Basys 3는 완전 지원)

**설치 옵션 선택 기준**:

| 옵션 | 선택 여부 | 이유 |
|------|----------|------|
| Design Tools | ✅ 필수 | Vivado IDE, 합성, P&R, 비트스트림 생성 |
| DocNav | ⏳ 선택 | 온라인 문서로 충분 |
| Simulation (Vivado Simulator) | ✅ 권장 | VCS 라이선스 없으면 필수 |
| HLS | ⏳ 선택 | 고급 주제 (이 교재 범위 밖) |
| System Edition | ❌ 불필요 | 대학원 환경에서 WebPACK으로 충분 |

#### 3.1.3 **실습: Vivado 설치 절차**

**Step 1: WebPACK 라이선스 신청**
```
1. https://www.xilinx.com 방문
2. "Download" → "Vivado Design Suite 2024.1"
3. Windows 버전 다운로드 (약 12GB, 다운로드 시간 2~3시간)
4. 회원가입 시 WebPACK 라이선스 자동 활성화
   (대학 이메일 사용 권장 — 학생 할인 혜택)
```

**Step 2: 설치 실행**
```
1. 다운로드한 Vivado_*.exe 실행
2. "Install Vivado" 선택
3. 설치 경로: C:\Xilinx\Vivado\2024.1\ (기본값 권장)
4. 선택 항목:
   - Design Tools: ✅ (모든 항목 선택)
   - Vivado Simulator: ✅
   - Cable Drivers: ✅ (Basys 3 USB 연결용)
   - DocNav: ⏳ (선택사항)
5. 설치 완료: ~30분 (시스템 성능 따라 변동)
```

**Step 3: Vivado 첫 실행 및 라이선스 활성화**
```
1. "Vivado 2024.1" 바탕화면 아이콘 클릭 (또는 시작 메뉴에서 검색)
2. Splash Screen 대기 (~10초)
3. "Help" → "Manage License" → "Load License"
4. WebPACK 라이선스 활성화 확인 ("ISE/Vivado Design Suite LE WebPACK" 표시)
5. 메인 IDE 진입
```

**Step 4: Basys 3 드라이버 확인** (Windows 10/11)
```
1. Basys 3 USB 케이블로 PC 연결
2. 디바이스 관리자 열기 (Win+X → 디바이스 관리자)
3. "Xilinx USB Cable" 또는 "XC7 FPGA Programmer" 표시 확인
   - 미인식 시: Vivado 설치 폴더의 Cable Driver 수동 설치
     경로: C:\Xilinx\Vivado\2024.1\data\xilinx_drivers\
```

#### 3.1.4 **검증: LED 깜박이기 프로젝트**

**목표**: 설치 성공 확인 + Vivado 워크플로우 체험

**프로젝트 구조**:
```
vivado_led_blink/
  ├─ led_blink.sv          (SystemVerilog: LED PWM 제어)
  ├─ led_blink_tb.sv       (테스트벤치: 시뮬레이션)
  ├─ basys3.xdc            (제약 파일: 핀 배치)
  └─ bitstream/            (비트스트림 생성 결과)
      └─ led_blink.bit
```

**Vivado 프로젝트 생성 단계**:

1. **프로젝트 생성**
   ```
   File → New Project
   Project name: led_blink_test
   Location: C:\vivado_projects\
   Project type: RTL Project
   Device: Basys3 (xc7a35tcpg236-1)
   ```

2. **소스 파일 추가**
   ```verilog
   // led_blink.sv - 100MHz 클록으로 LED를 1Hz로 깜박임
   module led_blink(
       input  clk,        // 100 MHz from Basys3
       input  rst_n,      // active-low reset
       output led_out
   );
       logic [26:0] counter;  // ~1.3초 카운트

       always_ff @(posedge clk or negedge rst_n) begin
           if (!rst_n)
               counter <= 27'd0;
           else
               counter <= counter + 1'b1;
       end

       // counter의 MSB (약 0.67초)를 사용하여 LED 토글
       assign led_out = counter[26];
   endmodule
   ```

3. **XDC 제약 파일 추가** (Basys 3 핀 매핑)
   ```xdc
   # Basys 3 - 100 MHz 클록
   set_property -dict {PACKAGE_PIN W5 IOSTANDARD LVCMOS33} [get_ports clk]
   create_clock -add -name sys_clk_pin -period 10.00 -waveform {0 5} [get_ports clk]

   # Active-low Reset (Basys 3 보드: BTN3)
   set_property -dict {PACKAGE_PIN U18 IOSTANDARD LVCMOS33} [get_ports rst_n]

   # LED0 출력 (Basys 3 LED[0])
   set_property -dict {PACKAGE_PIN V17 IOSTANDARD LVCMOS33} [get_ports led_out]
   ```

4. **합성 실행**
   ```
   Flow → Run Synthesis
   (에러 없음 확인)
   ```

5. **배치 & 라우팅 실행**
   ```
   Flow → Run Implementation
   (경고는 무시해도 됨)
   ```

6. **비트스트림 생성**
   ```
   Flow → Generate Bitstream
   (생성 완료: led_blink.bit)
   ```

7. **FPGA 프로그래밍**
   ```
   Tools → Program Device → Basys3
   비트스트림 선택: led_blink.bit
   Program 버튼 클릭
   ```

**검증 결과**: Basys 3 의 LED[0]이 약 1Hz로 깜박임 (켜짐 0.67초 → 꺼짐 0.67초)

#### 3.1.5 **정리: 체크리스트**

Vivado 설치 완료 확인:
- [ ] Vivado 2024.1 설치 완료 (Help → About 에서 버전 확인)
- [ ] WebPACK 라이선스 활성화 (Help → Manage License)
- [ ] Basys 3 드라이버 인식 (Tools → Hardware Manager에서 "xc7a35t_0" 표시)
- [ ] LED 깜박이기 검증 성공 (FPGA 보드의 LED[0] 점멸 확인)
- [ ] Vivado 종료 및 재시작 가능 (안정성 확인)

**다음 단계**: "이제 Ch01부터 시작할 준비가 되었습니다! 첫 번째 성공을 축하합니다."

---

### E.2 riscv-gnu-toolchain 설치 (크로스 컴파일러)

#### 3.2.1 **도입**

**프레이밍**:
```
"Vivado는 하드웨어(FPGA)를 만드는 도구입니다.
그런데 하드웨어가 있어도 실행할 소프트웨어가 없으면 쓸모없습니다.

RISC-V 어셈블리 또는 C 코드를 작성해서:
  1. 컴파일 (riscv64-unknown-elf-gcc) ← riscv-gnu-toolchain
  2. .hex 파일 생성 (objcopy) ← riscv-gnu-toolchain
  3. FPGA IMEM에 로드 ← Vivado

이 과정을 통해 우리가 설계한 CPU가 실제 프로그램을 실행합니다."
```

**선행 조건**: 없음 (Ch03.10 이전)

**설치 난이도**: 중간 (Windows에서 직접 빌드는 복잡하므로 **사전 빌드 바이너리 권장**)

#### 3.2.2 **개념 설명**

**1. riscv-gnu-toolchain이란?**

GNU Toolchain을 RISC-V ISA로 크로스 컴파일한 도구 모음:
- **riscv64-unknown-elf-gcc**: C/어셈블리 컴파일러
- **riscv64-unknown-elf-objdump**: 바이너리 분석
- **riscv64-unknown-elf-objcopy**: 형식 변환 (ELF → hex)
- **riscv64-unknown-elf-gdb**: 디버거

**2. 설치 방식 비교**

| 방식 | 설명 | 난이도 | 설치 시간 |
|------|------|--------|----------|
| **사전 빌드 바이너리** | 이미 컴파일된 바이너리 다운로드 | ⭐ 낮음 | 5분 |
| **직접 빌드 (Linux)** | 소스에서 컴파일 (Linux/WSL) | ⭐⭐⭐ 높음 | 30~60분 |
| **직접 빌드 (Windows)** | MSYS2 또는 Git Bash 사용 | ⭐⭐⭐⭐ 매우 높음 | 60분+ |
| **Docker 컨테이너** | 사전 구성된 환경 사용 | ⭐⭐ 중간 | 10분 |

**권장**: Windows 사용자는 **사전 빌드 바이너리** (xPack 또는 SiFive)

#### 3.2.3 **실습: riscv-gnu-toolchain 설치**

**선택지 A: 사전 빌드 바이너리 (권장)**

**Step 1: xPack 다운로드**
```
1. https://xpack.github.io/riscv-none-embed-gcc/ 방문
2. "RISC-V Embedded GCC" 최신 버전 (예: 13.2.0)
3. Windows 버전 다운로드 (Windows x64 .zip, 약 500MB)
4. 예: xpack-riscv-none-embed-gcc-13.2.0-2-win32-x64.zip
```

**Step 2: 압축 해제**
```
1. C:\xpack\ 폴더 생성
2. xpack-*.zip 압축 해제 → C:\xpack\riscv-none-embed-gcc-13.2.0-2\
```

**Step 3: PATH 환경 변수 등록**
```
제어판 → 시스템 및 보안 → 시스템 → 고급 시스템 설정 → 환경 변수

변수명: PATH
변수값 추가: C:\xpack\riscv-none-embed-gcc-13.2.0-2\bin\

(기존 PATH 값과 ';' 로 구분)
```

**Step 4: 설치 확인 (PowerShell 또는 CMD)**
```powershell
riscv64-unknown-elf-gcc --version
# 출력 예:
# riscv64-unknown-elf-gcc (xPack GNU RISC-V Embedded GCC, riscv-none-embed) 13.2.0
```

#### 3.2.4 **검증: .hex 파일 생성**

**테스트 프로그램** (sample.c)

```c
// sample.c - 간단한 RISC-V C 프로그램
int main() {
    // x5 레지스터에 값 5 저장 (x5 = 5)
    volatile int value = 5;

    // 무한 루프 (프로세서가 계속 작동)
    while(1) {
        value = value + 1;
    }

    return 0;
}
```

**컴파일 및 .hex 생성**

```bash
# Step 1: C → 어셈블리 + 링크
riscv64-unknown-elf-gcc \
  -march=rv32i \
  -mabi=ilp32 \
  -nostartfiles \
  -Tlink.ld \
  sample.c -o sample.elf

# Step 2: ELF → Hex (FPGA 초기화용)
riscv64-unknown-elf-objcopy \
  -O verilog sample.elf sample.hex

# Step 3: 생성 확인
ls -la sample.hex
```

**expected output** (sample.hex의 처음 10줄):
```
@00000000
13 05 00 00
93 85 85 00
63 08 a5 00
...
```

(이 hex 파일을 Ch05에서 배우는 `$readmemh` 명령어로 IMEM에 로드)

#### 3.2.5 **정리: 체크리스트**

riscv-gnu-toolchain 설치 완료 확인:
- [ ] `riscv64-unknown-elf-gcc --version` 실행 가능
- [ ] `-march=rv32i` 플래그로 컴파일 성공
- [ ] sample.c → sample.elf → sample.hex 변환 성공
- [ ] sample.hex 파일 생성 (용량 ~2KB)
- [ ] Vivado의 $readmemh로 로드 가능 (Ch05.2 검증)

**다음 단계**: "이제 Ch03부터 RISC-V 어셈블리를 배울 준비가 되었습니다!"

---

### E.3 VCS / Verdi 설치 (고급: 선택사항)

#### 3.3.1 **도입**

**프레이밍**:
```
"우리는 지금까지:
  1. 하드웨어 설계: Vivado (SystemVerilog 합성)
  2. 소프트웨어 컴파일: riscv-gnu-toolchain (C/어셈블리 → hex)

그런데 대규모 설계는 Vivado Simulator보다 고성능 시뮬레이터가 필요합니다:
  - VCS: Synopsys의 상용 시뮬레이터 (업계 표준, 매우 빠름)
  - Verdi: Synopsys의 파형 뷰어 (직관적, 신호 추적 강력)

하지만 라이선스가 비싸서 (연 수천만 원), 대학원 환경에서만 사용 가능합니다."
```

**선행 조건**: E.1 (기본 SystemVerilog 이해)

**필수 여부**: ⏳ **선택사항** (Vivado Simulator로 충분, VCS는 성능 향상용)

#### 3.3.2 **개념 설명**

**1. VCS vs Vivado Simulator 비교**

| 항목 | Vivado Simulator | VCS |
|------|-----------------|-----|
| 라이선스 | 무료 (WebPACK) | 유료 (대학 라이선스) |
| 속도 | 느림 (수십만 사이클) | 매우 빠름 (수백만 사이클) |
| 신호 추적 | 기본 (GTKWave 호환) | 강력 (Verdi 내장) |
| 파형 분석 | 단순 | 고급 (계층적 검색, 신호 비교) |
| 적합 규모 | 소형~중형 설계 | 중형~대형 설계 |
| 이 교재 필요성 | ✅ 필수 (기본 시뮬레이션) | ⏳ 선택 (성능 향상) |

**2. Verdi의 역할**

VCS의 파형 파일(.fsdb)을 분석하는 GUI 도구:
- 신호 계층적 표시
- 신호 이름으로 빠른 검색
- 조건 설정 (신호 값 범위 필터링)
- 클록 사이클 정렬 (여러 클록 도메인 분석)

#### 3.3.3 **실습: VCS 설치 (대학원 환경 기준)**

**Step 1: 라이선스 확인**

VCS는 대학 라이선스로 제공되는 경우가 많음:
```
1. 소속 대학원의 "산학협력단" 또는 "컴퓨터 센터" 문의
2. "Synopsys 라이선스 서버" 주소 확인
   (예: license.server.com:27000)
3. 라이선스 서버의 VCS 사용 권한 확인
```

**Step 2: VCS 설치**

Synopsys 라이선스 서버가 구성되어 있으면:
```bash
# Windows의 경우, WSL2 (Linux) 또는 Linux 서버에서
vcs -version  # VCS 설치 확인

# 간단한 테스트벤치 컴파일
vcs -sv tb_simple.sv module.sv -o simv
./simv  # 시뮬레이션 실행
```

(자세한 설치는 대학원 IT 담당자나 선배에게 직접 문의 권장)

#### 3.3.4 **선택: Vivado Simulator로 충분한가?**

**Vivado Simulator 사용 권장 이유**:
- ✅ WebPACK에 포함 (라이선스 비용 0)
- ✅ Ch04~Ch22의 모든 테스트벤치 실행 가능
- ✅ GTKWave 또는 Vivado IDE 내장 뷰어로 파형 분석 가능
- ✅ 시뮬레이션 속도: 10만~100만 사이클 (이 교재 범위 내 충분)

**VCS 필요 시기**:
- 멀티코어 설계 (Ch25 이후)
- 대규모 시스템온칩 (1천만 사이클+)
- 실무 설계 환경 경험

**권장**: **Ch01~Ch22는 Vivado Simulator, Ch25 이후는 VCS** (시간 여유 시)

#### 3.3.5 **정리: 체크리스트 (VCS 사용 시)**

- [ ] 대학 라이선스 서버 확인 (IT 담당자 문의)
- [ ] VCS 설치 및 PATH 등록
- [ ] `vcs -version` 실행 가능
- [ ] 간단한 테스트벤치 컴파일 및 실행 성공
- [ ] Verdi로 .fsdb 파일 열기 가능 (신호 계층 표시)

---

### E.4 설치 오류 해결 FAQ (교육심리전문가 보강)

#### 3.4.1 **Vivado 설치 관련**

**Q1: "Vivado 설치 중 'Cannot find a supported device driver' 오류"**

**원인**: Xilinx 라이선스 서버 연결 실패
**해결**:
```
1. 방화벽 설정 확인 (Vivado.exe 아웃바운드 허용)
2. 라이선스 서버: 자동 → 수동 설정
   Help → Manage License → Load License → Manual
3. 또는 WebPACK 라이선스 재신청
```

**Q2: "Basys 3를 연결했는데 'No device found' 표시"**

**원인**: USB 드라이버 미설치 또는 USB 포트 오류
**해결**:
```
1. Basys 3 USB 케이블을 다른 포트에 연결
2. 디바이스 관리자에서 "Xilinx USB Cable" 찾기
   - 없으면: C:\Xilinx\Vivado\2024.1\data\xilinx_drivers\ 에서 드라이버 수동 설치
3. USB 케이블 교체 (Micro-B 타입, 데이터 전송 지원)
```

**Q3: "비트스트림 생성 중 'Out of Memory' 오류"**

**원인**: RAM 부족 (복잡한 설계 + 낮은 RAM)
**해결**:
```
1. 다른 프로그램 종료 (Chrome, Outlook 등)
2. 임시 파일 정리: C:\Users\USERNAME\AppData\Local\Temp\
3. Vivado 합성 옵션 조정:
   Synthesis Settings → Algorithm → "Area Reduction" 선택
```

#### 3.4.2 **riscv-gnu-toolchain 관련**

**Q4: "'riscv64-unknown-elf-gcc' is not recognized as an internal or external command"**

**원인**: PATH 환경 변수 미등록
**해결**:
```
1. 설치 경로 확인: C:\xpack\riscv-none-embed-gcc-13.2.0-2\bin\ 존재 확인
2. 환경 변수 추가:
   제어판 → 시스템 → 고급 시스템 설정 → 환경 변수 → PATH에 추가
3. PowerShell 또는 CMD 재시작
4. `riscv64-unknown-elf-gcc --version` 다시 시도
```

**Q5: "컴파일 성공했는데 .hex 파일이 안 생겨요"**

**원인**: objcopy 명령 누락 또는 문법 오류
**해결**:
```
# 올바른 명령:
riscv64-unknown-elf-objcopy -O verilog sample.elf sample.hex

# 검증:
ls -la sample.hex (파일 존재 확인)
type sample.hex (내용 확인 — 16진수 데이터 표시)
```

#### 3.4.3 **시뮬레이션 관련**

**Q6: "Vivado Simulator에서 신호가 X (unknown)로 표시됨"**

**원인**: 초기화되지 않은 신호 또는 클록 없음
**해결**:
```
1. 테스트벤치에서 clk/rst_n 신호 확인
2. 시뮬레이션 시간 확인 (너무 짧으면 신호 전파 안 됨)
3. 신호 정의 확인:
   logic [31:0] data = 32'h0000_0000;  // 명시적 초기화
```

#### 3.4.4 **실패 정상화 메시지**

```
"환경 설치는 하드웨어 엔지니어링이 아니라 '소프트웨어 운영 문제'입니다.

첫 시도에 성공하는 사람은 드뭅니다.
삼성, SK, 인텔 등 대기업 설계자들도 신입 때는 3~4회 시도 끝에 성공합니다.

한 단계씩 차근차근 진행하면 반드시 됩니다.
막히면 FAQ를 보거나 선배 / TA에게 물어보세요.
질문 자체는 부끄러운 게 아닙니다."
```

---

## 4. 인지 부하 분석

각 도구별 **신규 개념 수**와 **학습 난이도**:

| 도구 | 신규 개념 | 개념 목록 | 인지 부하 | 권장 학습 기간 | 주의점 |
|------|----------|---------|---------|-------------|-------|
| **Vivado** | ~15개 | 프로젝트 구조, 합성, P&R, 비트스트림, XDC, 드라이버, 라이선스 | **높음** | 4~6시간 | 설치 실패 가능성 높음 |
| **riscv-gnu-toolchain** | ~8개 | 크로스 컴파일, objcopy, march 플래그, ABI, hex 형식 | **중간** | 2~3시간 | PATH 환경변수 설정 필수 |
| **VCS/Verdi** | ~10개 | 컴파일 옵션, 시뮬레이션 실행, fsdb 형식, 신호 추적 | **높음** | 3~4시간 | 라이선스 복잡성 + 선택사항 |

**권장 학습 순서**:
1. **1차 세션**: E.1 Vivado만 (4~6시간)
   - 여유 갖고 설치, LED 검증 성공 경험
2. **2차 세션 (다음날)**: E.2 riscv-gnu-toolchain (2~3시간)
   - Vivado 성공 경험 후 자신감 상태 진행
3. **3차 세션 (선택)**: E.3 VCS/Verdi (3~4시간)
   - Ch15 이후 대규모 시뮬레이션 필요할 때

---

## 5. 체크리스트 (각 도구별)

### 5.1 Vivado 2024.1 설치 완료 확인

- [ ] **설치 완료**
  - [ ] Vivado 2024.1 폴더 (C:\Xilinx\Vivado\2024.1\) 존재
  - [ ] Vivado IDE 실행 가능 (바탕화면 또는 시작 메뉴 아이콘)

- [ ] **라이선스 활성화**
  - [ ] Help → About에서 "Vivado v2024.1" 확인
  - [ ] Help → Manage License에서 "ISE/Vivado Design Suite LE WebPACK" 활성화 표시

- [ ] **Basys 3 드라이버 인식**
  - [ ] USB 케이블로 Basys 3 연결
  - [ ] 디바이스 관리자 (Win+X → 디바이스 관리자)
  - [ ] "Xilinx USB Cable" 또는 "XC7 FPGA Programmer" 항목 표시
  - [ ] Tools → Hardware Manager → "xc7a35t_0" 인식 확인

- [ ] **LED 깜박이기 검증 성공**
  - [ ] Vivado에서 led_blink 프로젝트 생성
  - [ ] 합성 (Synthesis) 완료 (0 오류)
  - [ ] 구현 (Implementation) 완료 (경고 무시 가능)
  - [ ] 비트스트림 (Bitstream) 생성 완료 (led_blink.bit)
  - [ ] FPGA 프로그래밍: Program Device → led_blink.bit 선택 → Program
  - [ ] **Basys 3 LED[0]이 약 1Hz로 깜박임** ← 가장 중요한 검증

- [ ] **안정성 확인**
  - [ ] Vivado 종료 후 재시작 (시작 메뉴에서)
  - [ ] 메인 IDE 진입 가능 (라이선스 재확인 불필요)

### 5.2 riscv-gnu-toolchain 설치 완료 확인

- [ ] **도구 설치**
  - [ ] xpack-riscv-gnu-toolchain 압축 해제 (C:\xpack\)
  - [ ] PATH 환경 변수 등록 (제어판 → 환경 변수)

- [ ] **명령어 인식**
  - [ ] PowerShell/CMD에서 `riscv64-unknown-elf-gcc --version` 실행
  - [ ] 출력: "riscv64-unknown-elf-gcc (xPack GNU RISC-V) 13.2.0" 또는 유사
  - [ ] `riscv64-unknown-elf-objcopy --version` 실행 확인

- [ ] **컴파일 테스트**
  - [ ] sample.c 파일 생성 (위 예제 코드)
  - [ ] `riscv64-unknown-elf-gcc -march=rv32i -mabi=ilp32 -nostartfiles sample.c -o sample.elf`
  - [ ] sample.elf 파일 생성 (용량 ~3KB)
  - [ ] ELF 파일 유효성 확인: `riscv64-unknown-elf-objdump -d sample.elf` (어셈블리 출력)

- [ ] **Hex 파일 생성**
  - [ ] `riscv64-unknown-elf-objcopy -O verilog sample.elf sample.hex`
  - [ ] sample.hex 파일 생성 (용량 ~2KB)
  - [ ] 내용 확인: `type sample.hex` (16진수 데이터 표시)

- [ ] **Vivado와의 통합 확인** (Ch05 실습 시)
  - [ ] Vivado 프로젝트에서 $readmemh("sample.hex", imem)로 로드 가능

### 5.3 VCS/Verdi 설치 완료 확인 (선택사항)

- [ ] **라이선스 확인**
  - [ ] 대학 라이선스 서버 주소 확인 (담당자 문의)
  - [ ] `vcs -version` 실행 가능 ("vcs C-2023.12-1-SP1" 또는 유사)

- [ ] **간단한 시뮬레이션 실행**
  - [ ] 테스트벤치 파일(tb_simple.sv)과 모듈(module.sv) 준비
  - [ ] `vcs -sv tb_simple.sv module.sv -o simv`
  - [ ] simv 실행: `./simv` (또는 `simv.exe` on Windows)
  - [ ] 시뮬레이션 완료 메시지 표시

- [ ] **Verdi로 파형 분석**
  - [ ] VCS 시뮬레이션에서 .fsdb 파일 생성되는지 확인
  - [ ] `verdi -f verilog.f -ssf dump.fsdb &`
  - [ ] Verdi GUI 실행 (신호 계층 표시)

---

## 6. 실패 정상화 및 동기 부여

### 6.1 도구 설치의 특성

```
"여러분이 배운 Verilog는 '논리 설계'입니다.
하지만 환경 설치는 '소프트웨어 운영'입니다.

다릅니다. 완전히 다릅니다.

논리 설계는 '정답'이 있습니다: (A AND B) OR C 는 항상 같습니다.
하지만 환경 설치는 여러분의 PC, 버전, 라이선스 조합에 따라 다릅니다.

따라서 첫 시도에 실패하는 것이 '정상'입니다.
"
```

### 6.2 성공 경험의 중요성

```
"설치 성공 후 첫 번째 감정은 이렇습니다:
  '어? 된다고?' → '오, 됐다!' → '나도 할 수 있네!' → '다음 단계 해볼까?'

이 감정의 변화가 앞으로 20주 공부의 원동력이 됩니다.

따라서 이 부록은 여러분의 '첫 번째 성공 경험'을 가장 중요하게 여깁니다.
하나하나 차근차근, 서두르지 마세요."
```

### 6.3 막혔을 때

```
"막혔다면, 그것은 여러분의 능력 부족이 아닙니다.
단지 '이 조합은 우리가 예상한 대로 동작하지 않았다'는 뜻일 뿐입니다.

다음 단계:
  1. 이 FAQ (E.4)를 읽어보세요.
  2. FAQ에 없으면 선배나 TA에게 물어보세요.
  3. 그래도 안 되면 조교실의 '설치 완료 PC'에서 직접 보여달라고 하세요.

질문하는 것이 부끄럽지 않습니다. 오히려 설치 오류를 해결한 경험이
다음번 문제를 푸는 능력이 됩니다."
```

---

## 7. 선행 조건 명시

| 도구 | 선행 조건 | 필수/선택 | 시작 시점 |
|------|---------|----------|---------|
| **Vivado 2024.1** | 없음 | **필수** | **Ch01.2 이전** (1주차 첫날) |
| **riscv-gnu-toolchain** | 없음 | **필수** | **Ch03.10 이전** (2~3주차) |
| **VCS/Verdi** | Vivado 설치 + 기본 SystemVerilog | **선택** | Ch15 이후 (대규모 시뮬레이션 필요 시) |

### 7.1 Vivado 이전에 완료해야 할 것

- [ ] Windows 10/11 설치 (또는 Linux)
- [ ] 인터넷 연결 (라이선스 인증 필요)
- [ ] 디스크 40GB+ 자유 공간
- [ ] RAM 8GB 이상 (권장 16GB)

### 7.2 riscv-gnu-toolchain 이전에 완료해야 할 것

- [ ] Ch03 (RV32I 명령어 세트) 학습 권장
- [ ] (필수는 아니지만, 어셈블리 기초 이해가 도움됨)

---

## 8. HTML 원고 구조 (부록 E 작성 시 참고)

부록 E의 각 섹션은 다음 구조를 따릅니다:

```html
<section id="sec-E-1">
  <h2>E.1 Vivado 2024.1 설치 및 검증</h2>

  <!-- 학습 목표 -->
  <nav class="learning-objectives">
    <h3>이 절의 학습 목표</h3>
    <ul>
      <li>Vivado 개발 환경을 설치하고 설정할 수 있다 (적용/Apply)</li>
      <li>Basys 3 드라이버를 확인하고 정상 인식을 검증할 수 있다</li>
      <li>LED 깜박이기 프로젝트를 통해 FPGA 프로그래밍 전체 워크플로우를 경험할 수 있다</li>
    </ul>
  </nav>

  <!-- 도입 -->
  <h3>왜 Vivado를 배우는가?</h3>
  <p>이 교재는 Xilinx Basys 3 FPGA 보드에서 설계한 RISC-V 프로세서를 실행합니다...</p>

  <!-- 개념 -->
  <h3>Vivado 개발 환경의 이해</h3>
  <p>Vivado는 Xilinx 계열 FPGA를 설계하는 EDA 도구입니다...</p>

  <!-- 실습 -->
  <h3>Vivado 설치 및 검증 (Step-by-Step)</h3>
  <ol>
    <li>WebPACK 라이선스 신청</li>
    <li>Vivado 다운로드 및 설치</li>
    <li>드라이버 확인</li>
    <li>LED 깜박이기 프로젝트</li>
  </ol>

  <!-- 체크리스트 -->
  <aside class="metacognition">
    <strong>✅ 체크리스트</strong>
    <p>Vivado 설치 완료 확인:
      <input type="checkbox"> Vivado 2024.1 실행 가능<br/>
      <input type="checkbox"> WebPACK 라이선스 활성화<br/>
      <input type="checkbox"> Basys 3 드라이버 인식<br/>
      <input type="checkbox"> LED 깜박이기 성공<br/>
    </p>
  </aside>

  <!-- 다음 단계 -->
  <aside class="tip">
    <strong>🎉 축하합니다!</strong>
    <p>이제 Ch01부터 시작할 준비가 되었습니다. 첫 번째 성공을 축하합니다!</p>
  </aside>
</section>
```

---

## 최종 요약

| 항목 | 내용 |
|------|------|
| **교육 목표** | E1~E4: 4개 섹션, 학습목표 각 1~2개 |
| **학습 흐름** | 도입(왜) → 개념(무엇) → 실습(어떻게) → 정리(체크리스트) |
| **인지 부하** | 한 번에 1개 도구만 (Vivado 4-6h → riscv-toolchain 2-3h → VCS 선택) |
| **필수/선택** | Vivado & toolchain 필수, VCS 선택 |
| **실패 정상화** | "환경 설치 = 소프트웨어 운영, 논리 설계 ≠ 환경 설치" |
| **첫 성공 강조** | LED 깜박이기 성공 → 자신감과 진행 의욕 부여 |
| **FAQ (E.4)** | 6개 항목: Vivado 3개, toolchain 2개, 시뮬레이션 1개 |

---

**작성자**: 교육 설계자 (Instructional Designer)
**검토 예정**: 기술 저자, 초보자 독자, 교육심리전문가, 교육전문강사
