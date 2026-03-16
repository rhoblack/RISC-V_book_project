# Appendix D 기술 리뷰 결과

> **리뷰어**: 기술 리뷰어
> **리뷰 대상**: manuscripts/appendices/appendix_d.html (562줄)
> **리뷰 일자**: 2026-03-16
> **검증 기준**: Xilinx DS180 (Artix-7 Data Sheet), Digilent Basys 3 Reference Manual (Rev C), Basys 3 Master XDC

---

## 🔴 Critical Issues (기술 오류)

### D-C1: XC7A35T-1CPG236C 리소스 정확성 — 1건 발견 🔴

**CLB Slice당 FF 수 오류** (72행)
- **현재 표기**: "각 Slice = 4 LUT + 8 FF"
- **정확한 값**: 각 Slice = **4 LUT** + **8 FF** — Artix-7에서는 사실상 정확함 (DS180 Table 1: 각 Slice에 4개의 6-input LUT와 8개의 FF)
- ✅ PASS — 재검증 결과 정확

### D-C2: LUT 수 ✅ PASS
- 표기: 20,800개 ✅ (DS180: 5,200 Slices × 4 LUTs = 20,800)

### D-C3: FF 수 ✅ PASS
- 표기: 41,600개 ✅ (DS180: 5,200 Slices × 8 FFs = 41,600)

### D-C4: BRAM 수 ✅ PASS
- 표기: 36Kb × 50 = 1,800Kb ✅
- 18Kb × 100 표기도 정확 (36Kb를 2개의 18Kb로 분할 가능) ✅

### D-C5: DSP48E1 수 ✅ PASS
- 표기: 90개 ✅ (DS180 Table 1)

### D-C6: 시스템 클록 100MHz, 핀 W5 ✅ PASS
- 269행: `clk_100mhz` → `W5` ✅ (Basys 3 Master XDC 일치)

### D-C7: LED 핀 배치 (LD0~LD15) ✅ PASS
모든 16개 LED 핀 대조:
- led[0]=U16, led[1]=E19, led[2]=U19, led[3]=V19 ✅
- led[4]=W18, led[5]=U15, led[6]=U14, led[7]=V14 ✅
- led[8]=V13, led[9]=V3, led[10]=W3, led[11]=U3 ✅
- led[12]=P3, led[13]=N3, led[14]=P1, led[15]=L1 ✅
(Basys 3 Master XDC와 완벽 일치)

### D-C8: 스위치 핀 배치 (SW0~SW15) ✅ PASS
모든 16개 스위치 핀 대조:
- sw[0]=V17, sw[1]=V16, sw[2]=W16, sw[3]=W17 ✅
- sw[4]=W15, sw[5]=V15, sw[6]=W14, sw[7]=W13 ✅
- sw[8]=V2, sw[9]=T3, sw[10]=T2, sw[11]=R3 ✅
- sw[12]=W2, sw[13]=U1, sw[14]=T1, sw[15]=R2 ✅
(Basys 3 Master XDC와 완벽 일치)

### D-C9: UART 핀 — 기술 리뷰 체크리스트 업데이트 🔴

**UART 핀 번호 확인 필요**
- **App D 표기**: uart_rxd=B18, uart_txd=A18
- **기존 체크리스트**: TX=A2, RX=B1
- **Basys 3 Master XDC 기준**: Basys 3 USB-UART 브리지 핀은 실제로 **A18(TXD_OUT)**, **B18(RXD_IN)**
  - 주의: Digilent Reference Manual Rev C 기준, USB-UART 핀은 JA PMOD 영역이 아닌 USB 브리지 칩(FTDI FT2232HQ)에 연결됨
  - A18 = FPGA → USB (TXD) ✅
  - B18 = USB → FPGA (RXD) ✅
- **결론**: App D의 B18/A18이 정확. 기존 체크리스트의 A2/B1은 구버전 또는 다른 보드 기준으로 오류.
- ✅ PASS

### D-C10: 리셋 버튼 (BTNC) = U18 ✅ PASS
- 234행: btnC = U18 ✅ (Basys 3 Master XDC 일치)

### D-C11: 7-세그먼트 핀 ✅ PASS
세그먼트 핀 대조:
- seg[0](CA)=W7, seg[1](CB)=W6, seg[2](CC)=U8, seg[3](CD)=V8 ✅
- seg[4](CE)=U5, seg[5](CF)=V5, seg[6](CG)=U7 ✅
- dp=V7 ✅
- an[0]=U2, an[1]=U4, an[2]=V4, an[3]=W4 ✅
(Basys 3 Master XDC와 완벽 일치)

---

## 🟡 Major Issues

### D-M1: 클록 핀(W5)의 I/O 표준 표기 🟡
- **위치**: 269행
- **문제**: 클록 핀에 IOSTANDARD LVCMOS33을 적용했으나, 실제로 W5는 Basys 3에서 전용 클록 입력 핀이 아닌 일반 I/O를 통해 클록을 받는 구조. 이 자체는 문제가 아니지만, 클록 핀에 `IBUF → BUFG` 경로가 자동 삽입된다는 설명이 없음
- **수정 제안**: D.4절에서 MMCM 코드와 함께 "Vivado가 클록 입력에 IBUF를 자동 삽입하며, MMCM/PLL 출력에는 BUFG를 명시적으로 연결해야 한다"는 설명 추가 (이미 코드에 BUFG는 있으나 IBUF 설명 누락)

### D-M2: IOB 수 표기 검증 🟡
- **위치**: 113행
- **문제**: IOB "106개"로 표기했으나, XC7A35TCPG236-1 패키지는 **100개** User I/O (DS180 Table 1). 106은 dedicated pin 포함 수치일 수 있음
- **수정 제안**: DS180 정확한 수치 확인 후 수정. CPG236 패키지의 HR I/O = 100개, HP I/O = 0개. "User I/O: 100개"로 수정 권장

### D-M3: MMCM VCO 주파수 범위 미언급 🟡
- **위치**: D.4절 MMCM 코드 (312~313행)
- **문제**: VCO=1000MHz로 설정했는데, Artix-7 -1 스피드 그레이드의 VCO 범위는 600~1200MHz. 현재 설정(1000MHz)은 범위 내이지만, 독자가 파라미터를 수정할 때 VCO 범위 제약을 모르면 에러 발생
- **수정 제안**: 코드 주석에 "// VCO 범위: 600~1200MHz (-1 스피드)" 추가

### D-M4: 버튼 디바운싱 미언급 🟡
- **위치**: D.3.3 버튼 섹션
- **문제**: 기계식 버튼의 바운싱(bouncing) 현상과 디바운서 회로 필요성 미언급. 초보자가 버튼을 직접 리셋이나 입력으로 사용하면 다중 트리거 발생 가능
- **수정 제안**: tip 박스에 "기계식 버튼은 수 ms의 바운싱이 발생한다. 리셋 이외 용도로 사용 시 디바운서(debouncer) 회로를 추가해야 한다." 한 줄 추가

### D-M5: 7-세그먼트 액티브 로우 설명 보완 🟡
- **위치**: 277~279행 tip 박스
- **문제**: "7-세그먼트와 LED는 모두 액티브 로우(Active Low)"라고 했으나, LED는 **액티브 하이**임. 같은 문장에서 LED를 함께 언급하면서 "반면 led=1이면 LED 켜짐"이라고 하지만, 초반 문장이 혼동을 줄 수 있음
- **수정 제안**: "Basys 3의 7-세그먼트는 액티브 로우(Active Low)이다. seg=0이면 세그먼트 켜짐, an=0이면 자릿수 활성화. **반면 LED는 액티브 하이(Active High)**이므로 led=1이면 LED 켜진다."로 문장 분리

---

## 🟢 Minor Issues

### D-m1: Pmod 커넥터 핀 배치 누락 🟢
- **위치**: D.3절 전체
- **문제**: Pmod JA~JC 커넥터 핀 배치가 포함되어 있지 않음. Ch16 UART가 USB-UART를 사용하므로 Pmod는 필수는 아니나, 확장 프로젝트(Ch23~25)에서 필요할 수 있음
- **수정 제안**: "Pmod 핀 배치는 Digilent Basys 3 Reference Manual 참조" 한 줄 추가

### D-m2: 리소스 사용량 이력 표에 WNS 빈칸 🟢
- **위치**: D.5절 표 (389~456행)
- **문제**: WNS 열이 모두 "—"로 비어 있음. 템플릿 형태라고 명시했으나, 예상 WNS 값이라도 있으면 참고 가능
- **수정 제안**: 460행에서 이미 "예상값"임을 명시하고 있으므로, WNS도 예상값 기입 또는 현행 유지

### D-m3: MMCM 코드에서 미사용 출력 처리 🟢
- **위치**: 503~506행
- **문제**: 미사용 CLKOUT 포트를 빈 연결(`()`)로 처리. Vivado에서는 이것이 정상이나, 코딩 스타일 관점에서 주석이 있으면 좋음
- **현재**: `// ... 미사용 출력 생략` 주석이 이미 있음 ✅

---

## 본문 일관성 크로스 체크

| 항목 | App D | 본문 | 일치 |
|------|-------|------|------|
| 클록 핀 W5 | ✅ | Ch01 등 | ✅ |
| UART TX=A18, RX=B18 | ✅ | Ch16 확인 필요 | ⚠️ |
| LED 핀 배치 | ✅ | Ch01 LED 점멸 | ✅ |
| 리셋 BTNC=U18 | ✅ | 본문 공통 | ✅ |
| LUT 20,800개 | ✅ | CLAUDE.md | ✅ |
| BRAM 50×36Kb | ✅ | CLAUDE.md | ✅ |
| 시스템 클록 100MHz | ✅ | CLAUDE.md | ✅ |

---

## 요약

| 분류 | 건수 | 상세 |
|------|:----:|------|
| 🔴 Critical | **0건** | 모든 핀 배치/리소스 수치 정확 |
| 🟡 Major | **5건** | D-M1(IBUF 설명), D-M2(IOB 수 106→100), D-M3(VCO 범위), D-M4(버튼 디바운싱), D-M5(LED 액티브 하이 혼동) |
| 🟢 Minor | **2건** | D-m1(Pmod 누락), D-m2(WNS 빈칸) |

**기술 리뷰어 판정**: Critical 0건으로 핀 배치/리소스는 정확. Major 5건 중 D-M2(IOB 수)와 D-M5(LED 활성 수준 혼동 문장)은 수정 권장.
