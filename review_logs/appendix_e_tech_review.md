# 부록 E 기술 리뷰

**검토자**: 기술 리뷰어 (Technical Reviewer)
**검토일**: 2026-03-16
**원고**: manuscripts/appendices/appendix_e.html (1,189줄)
**코드 예제**: app_e_vivado_tcl_script.tcl, app_e_toolchain_asm_to_hex.sh, app_e_vivado_sim_testbench.sv
**SVG**: app_e_tool_requirements.svg, app_e_vivado_flow.svg, app_e_toolchain_flow.svg

---

## 종합 평가

| 항목 | 평가 | 근거 |
|------|------|------|
| Vivado 정확성 | ⭐⭐⭐⭐ | 설치 절차 정확, 핀 매핑 검증 완료. 버전 표기 이슈 1건 (M1) |
| riscv-toolchain 정확성 | ⭐⭐⭐⭐ | 명령어/플래그 정확, xPack 설명 충분. 도구 이름 불일치 1건 (C1) |
| VCS/Sim 비교 | ⭐⭐⭐⭐⭐ | 라이선스 정책 정확, 비교 명확, 선택사항 분류 적절 |
| 코드 품질 | ⭐⭐⭐⭐ | TCL/Bash/SV 모두 실행 가능 구조. linker.ld 누락 이슈 1건 (C2) |
| SVG 정확성 | ⭐⭐⭐⭐⭐ | 도구 체인 흐름, 요구사항 비교 모두 기술적으로 정확 |

---

## Critical Issues (2건)

### C1. 🔴 xPack 도구 이름 불일치: `riscv64-unknown-elf-gcc` vs `riscv-none-embed-gcc`

**위치**: E.2 전체 (line 494~600, 특히 Step 1~4)

**문제**: xPack RISC-V Embedded GCC의 실행 파일 접두사는 `riscv-none-embed-` 또는 최신 버전에서는 `riscv-none-elf-`이다. 그러나 원고에서는 xPack을 설치하라고 안내하면서도, 실행 명령어는 `riscv64-unknown-elf-gcc`를 사용하고 있다.

- xPack 설치 시 실행 파일: `riscv-none-embed-gcc` (또는 `riscv-none-elf-gcc`)
- 원고에서 안내하는 명령어: `riscv64-unknown-elf-gcc`

이 불일치로 인해 독자가 xPack을 설치한 후 `riscv64-unknown-elf-gcc --version`을 실행하면 **"명령어를 찾을 수 없습니다"** 오류가 발생한다. 초보자는 이 시점에서 설치 실패로 오인하고 포기할 가능성이 높다.

**수정 방안** (택 1):
- **(A) xPack 기준 통일**: 모든 명령어를 `riscv-none-elf-gcc`로 변경하고, 스크립트의 TOOLCHAIN_PREFIX도 수정
- **(B) riscv64 기준 통일**: xPack 대신 SiFive/GitHub 공식 릴리즈(`riscv64-unknown-elf-` 접두사)를 권장 다운로드로 변경
- **(권장: B안)**: GitHub `riscv-collab/riscv-gnu-toolchain` 릴리즈 페이지에서 `riscv64-unknown-elf-` 접두사 사전 빌드 바이너리 제공. 이 경우 원고의 모든 명령어와 일치함.

### C2. 🔴 Bash 스크립트에서 `linker.ld` 참조하지만 제공 없음

**위치**: app_e_toolchain_asm_to_hex.sh (line 55, 65), 원고 E.2.4 (line 633~640)

**문제**:
- Bash 스크립트(app_e_toolchain_asm_to_hex.sh)는 `-T linker.ld` 옵션으로 링커 스크립트를 참조한다.
- 그러나 `linker.ld` 파일이 제공되지 않으며, 원고에서도 생성 방법을 안내하지 않는다.
- 원고 본문의 컴파일 예제(line 633~640)에서는 `-T` 옵션 없이 `-nostartfiles -nostdlib`만 사용하여 불일치 발생.

`linker.ld` 없이 `-T linker.ld`를 지정하면 gcc가 "cannot open linker script file" 오류를 발생시킨다.

**수정 방안**:
- **(A)** Bash 스크립트에서 `-T linker.ld` 제거하고 원고 본문과 동일하게 `-nostartfiles -nostdlib`만 사용 (간단한 검증 목적에 충분)
- **(B)** 간단한 linker.ld 예제를 함께 제공 (ENTRY(_start), MEMORY 섹션 포함)
- **(권장: A안)**: 부록 E는 설치 검증 목적이므로 링커 스크립트 없이 단순 컴파일이 적절

---

## Major Issues (3건)

### M1. 🟡 Vivado 버전 표기: "2024.1" 고정 vs 최신 버전 안내

**위치**: E.1 전체 (line 115, 163, 279 등)

**문제**: 원고는 "Vivado 2024.1"을 명시하고 있으나, Xilinx/AMD는 2024.2, 2025.1 등 후속 버전을 정기 릴리즈한다. 교재 출판 시점에 2024.1이 구버전이 될 수 있다.

**수정 방안**: "Vivado 2024.1 (또는 이후 버전)"과 같이 표기하거나, "이 교재는 Vivado 2024.1 기준으로 작성되었으나, 이후 버전에서도 동일한 절차가 적용된다"는 문구 추가.

### M2. 🟡 sample.c 코드 블록에 잘못된 language class 적용

**위치**: line 618

**문제**: C 코드인 `sample.c`에 `class="language-verilog"` 가 적용되어 있다. 코드 하이라이팅이 올바르지 않게 표시된다.

```html
<pre><code class="language-verilog">
// sample.c - 간단한 RISC-V C 프로그램
```

**수정 방안**: `class="language-c"` 로 변경하고, Highlight.js C 언어 모듈 로드 추가:
```html
<script src="https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.9.0/languages/c.min.js"></script>
```

### M3. 🟡 HTML 본문 내 TCL 소스 코드의 `<=` 이스케이프 불일치

**위치**: line 1042~1043 (전체 소스 코드 섹션의 TCL 코드)

**문제**: 전체 소스 코드 섹션의 TCL 블록 내 SystemVerilog 코드에서 `<=` 가 `&lt;=` 로 이스케이프되어 있다. 이것은 HTML `<pre><code>` 블록 안이므로 이스케이프가 필요하지만, 이 코드는 TCL의 `set sv_content { ... }` 블록 안에 있으므로 실제 TCL 실행 시에는 `<=` 가 원본이어야 한다.

독립 코드 파일(app_e_vivado_tcl_script.tcl)에서는 올바르게 `<=`로 되어 있으므로, HTML 내 인라인 코드만 이스케이프하면 된다. 현재 상태가 HTML 렌더링 관점에서는 올바르다. 다만, 독자가 HTML에서 복사할 경우 `&lt;=`가 그대로 복사될 수 있으므로, "전체 소스 코드는 code_examples/ 폴더에서 직접 다운로드하세요"라는 안내를 추가 권장.

---

## Minor Issues (5건)

### m1. 🟢 BTN3 핀 매핑 정밀도

**위치**: line 393~394

**문제**: Basys 3에서 BTN3(우측 버튼)의 핀은 `U18`이 아닌 `T18`일 수 있다. Basys 3 공식 XDC 마스터 파일에 따르면:
- btnU (위): T18
- btnL (왼): W19
- btnR (오): T17
- btnD (아래): U17
- btnC (중앙): U18

원고에서 U18을 사용하고 있으며 이는 btnC(중앙 버튼)에 해당한다. "BTN3"이라는 라벨과 실제 핀(U18=btnC)이 혼동될 수 있다. 초보자를 위해 "중앙 버튼(btnC, U18)"으로 명확히 표기하는 것을 권장.

### m2. 🟢 LED 깜박이기 주기 계산 보완

**위치**: line 372, 381

**문제**: 27비트 카운터의 MSB(counter[26])를 사용하면 토글 주기는 2^27 / 100MHz = 약 1.34초이며, LED는 약 0.75Hz로 깜박인다. 원고에서 "약 1Hz"라고 표현하고 있는데, 정확히는 0.75Hz이다. "약 0.75Hz (1.34초 주기)"로 수정하거나, 정확히 1Hz를 원하면 counter == 49,999,999 비교 방식으로 변경 가능.

### m3. 🟢 `</p>` 와 `</div>` 태그 순서 오류

**위치**: line 466~467

**문제**: HTML 태그 중첩 오류가 있다:
```html
            </p>     ← </p>가 먼저 닫힘
            </div>   ← </div> (analogy div)
```
이 위치에서 `<div class="analogy">` 안에 `<p>` 태그 없이 `</p>`가 닫혀 있다. `</p>` 를 제거하거나, analogy div 내부 텍스트를 `<p>` 태그로 감싸야 한다.

### m4. 🟢 Highlight.js C 언어 모듈 미로드

**위치**: line 1173~1186

**문제**: Highlight.js 로드 스크립트에서 `verilog.min.js`, `tcl.min.js`, `bash.min.js`는 로드하지만, `c.min.js`는 로드하지 않는다. M2와 연계하여 sample.c 코드의 하이라이팅을 위해 C 모듈 추가 필요.

### m5. 🟢 Basys 3 보드 파트 번호 `part0:1.2` 확인

**위치**: app_e_vivado_tcl_script.tcl (line 20)

```tcl
set_property board_part digilentinc.com:basys3:part0:1.2 [current_project]
```

Digilent의 보드 파일 버전이 업데이트되면 `part0:1.2` 대신 `part0:1.3` 등이 될 수 있다. Vivado에서 보드 파일이 없으면 오류가 발생하므로, 주석으로 "Vivado에서 Board Repository를 업데이트하세요 (Tools → Settings → Board Repository)" 안내 추가 권장.

---

## 강점

1. **설치 절차의 단계별 구조**: Step 1~4 방식의 step-box 구조가 매우 명확하며, 초보자가 따라하기 쉽다.
2. **LED 깜박이기 검증 프로젝트**: 설치 확인을 실제 FPGA 프로그래밍으로 검증하는 접근이 교육적으로 우수하다.
3. **VCS/Vivado Simulator 비교**: 선택사항을 명확히 분류하고 "대부분 Vivado Simulator로 충분하다"는 결론이 독자의 결정 부담을 줄여준다.
4. **FAQ 구성**: 실제로 빈번한 6가지 오류를 선정하여 원인→해결 구조로 제시, 실용적이다.
5. **체크리스트 제공**: 각 섹션 끝의 체크리스트가 독자의 자기 검증을 돕는다.
6. **TCL 자동화 스크립트**: 강사용 자동화 스크립트 제공이 실습 시간 절약에 효과적이다.
7. **Bash 스크립트 에러 처리**: `$? -ne 0` 검사로 각 단계 실패 시 중단 처리가 잘 되어 있다.
8. **테스트벤치 구조**: VCD 파형 덤프, 자동 검증(counter != 0), 한국어 출력 메시지가 포함된 교육용 테스트벤치로 적절하다.

---

## 개선 권장사항 (선택)

1. **Basys 3 XDC 마스터 파일 참조**: Digilent GitHub에서 공식 Basys3_Master.xdc 파일을 다운로드하여 사용하라는 안내 추가 (핀 매핑 실수 방지)
2. **WSL2 대안 안내**: Windows에서 riscv-gnu-toolchain 사용 시 WSL2를 통한 Linux 네이티브 사용이 더 안정적이라는 팁 추가 가능
3. **Vivado 프로젝트 모드 vs Non-Project 모드**: TCL 스크립트가 프로젝트 모드를 사용하고 있는데, 이는 적절한 선택임 (초보자 친화적). 별도 변경 불필요.

---

## 최종 판정

⏳ **수정 필요** (Critical 2건 해결 후 승인 가능)

- **C1** (xPack 도구 이름 불일치): 독자가 반드시 실패하는 치명적 오류. 도구 접두사 통일 필수.
- **C2** (linker.ld 미제공): Bash 스크립트 실행 시 반드시 실패. 스크립트 수정 또는 파일 제공 필요.
- **M1~M3**: Critical 수정 시 함께 반영 권장.

Critical 2건과 Major 3건 수정 후에는 **승인 가능** 수준이다.
원고 전반의 기술 정확성과 구조는 우수하며, 위 이슈만 해결하면 초보자가 안정적으로 따라할 수 있는 설치 가이드가 된다.
