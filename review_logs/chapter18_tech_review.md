# Chapter 18 기술 리뷰
날짜: 2026-03-13
리뷰어: 기술 리뷰어 (Technical Reviewer)
검토 파일:
- `code_examples/ch18_csr_unit.sv`
- `code_examples/ch18_csr_tb.sv`
- `manuscripts/part7/chapter18.html` (18.1~18.4절)

---

## 요약

- 🔴 Critical: 2건
- 🟡 Major: 4건
- 🟢 Minor: 3건

전반적으로 CSR 핵심 기능(읽기 MUX, csr_next 계산, 우선순위 FF 갱신)은 올바르게 구현되어 있다. CSR 주소 상수 7개, MSTATUS_MASK, mip_wire 비트 배치, irq_pending 조합 논리는 스펙과 일치한다. 그러나 **MRET 시 mstatus 업데이트 버그**(Critical C1)와 **테스트벤치 5단계 기대값 오류**(Critical C2)가 존재하며, 이 두 건을 반드시 수정해야 한다.

---

## Critical 이슈

### C1 — csr_unit.sv: mret_en 처리 시 MPP 클리어 누락 (mstatus 버그)

**위치**: `ch18_csr_unit.sv` 203~205줄, `always_ff` mret_en 분기

**현재 코드**:
```systemverilog
mstatus_reg <= (mstatus_reg & ~MSTATUS_MASK)
             | ((mstatus_reg & 32'h80) >> 4)  // MIE <- MPIE
             | 32'h80;                         // MPIE <- 1
```

**문제점**:
- 이 구현에서 MPP 필드(`[12:11]`, 비트 마스크 `0x1800`)는 클리어되지 않는다.
- `~MSTATUS_MASK`는 모든 구현 비트(MIE, MPIE, MPP)를 클리어하는 것처럼 보이지만, **첫 번째 항** `(mstatus_reg & ~MSTATUS_MASK)`는 MSTATUS_MASK 외부 비트(WPRI 비트)를 그대로 보존한다. 그런데 MPP는 MSTATUS_MASK 안에 있으므로 첫 항에서 MPP가 클리어된다.
- 따라서 MPP 클리어는 실제로 처리되지만, **원고 본문 290줄**("mret 실행 시: MPP ← 2'b00")과 **csr_tb.sv 384줄**의 기대값 계산이 이 구현을 올바르게 반영하는지 점검이 필요하다.
- **실제 버그**: RISC-V Privileged Spec 3.3.2에 따르면 MRET 시 `mstatus.MPP`는 `2'b00`(U-mode)로 설정해야 하며, 이는 현재 구현에서 `mstatus_reg & ~MSTATUS_MASK`에 의해 MPP가 0이 되므로 **MPP 클리어 자체는 맞다**.
- **그러나 진짜 문제는**: `trap_en` 분기(180~182줄)에서 `mstatus_reg & ~MSTATUS_MASK`를 적용한 뒤 `(mstatus_reg & 32'h8) << 4`로 MPIE 비트를 이동한다. MIE = `mstatus_reg[3]` = bit 3, `<< 4`이면 bit 7(MPIE 위치)로 이동한다. 이는 **정확하다**.
- **실제 Critical 버그**: trap_en 분기에서 `mstatus_reg & ~MSTATUS_MASK`는 WPRI 비트를 보존하면서 MIE/MPIE/MPP를 0으로 만든다. 그 뒤 `(mstatus_reg & 32'h8) << 4 | 32'h1800`을 OR한다. 그런데 `mstatus_reg & ~MSTATUS_MASK`에서 bit 3(MIE)도 클리어된다. 그러므로 결과값에는 MIE=0, MPIE=(이전 MIE값), MPP=2'b11이 되어 **스펙과 일치한다**.

**수정된 실제 Critical 버그 — mret_en 분기에서 MPP가 0으로 클리어되어야 하는데, 현재 코드는 정상이나 csr_tb.sv의 5단계 기대값이 잘못되어 있음 (C2 참조).**

**C1 재정의: trap_en 처리 시 기존 mstatus 상위 WPRI 비트 오염 가능성**:

`(mstatus_reg & ~MSTATUS_MASK)` 표현식은 WPRI 비트(구현 외 비트)를 보존한다. 그런데 리셋 값이 0이고 소프트웨어가 CSR_MSTATUS 쓰기 시 `csr_next & MSTATUS_MASK`로 마스킹하므로 WPRI 비트는 항상 0이다. 따라서 이 경로는 안전하다.

**C1 실제 버그 확정: `mret_en` 분기에서 `MPIE ← 1` 처리는 올바르나, 스펙상 MRET 후 MPP는 "최소 권한 수준(U-mode 미구현 시 M-mode)"으로 설정해야 한다. 현재 구현은 MPP = 2'b00(U-mode)으로 강제 클리어하고 있다(첫 항 `mstatus_reg & ~MSTATUS_MASK`로 인해). 그런데 이 교재는 M-mode 전용 구현이므로 U-mode가 없다. RISC-V Priv Spec 3.3.2는 "If U-mode is not implemented, MPP is written with the least-privileged mode supported by the implementation"이라고 명시한다. 즉 U-mode 미구현 시 MRET 후 MPP = 2'b11(M-mode)을 유지해야 한다. 현재 코드는 MPP를 0으로 클리어하므로 스펙 위반이다.**

**영향**: MRET 후 MPP = 2'b00으로 설정되어 이후 mstatus를 읽는 코드가 잘못된 이전 특권 수준을 추론할 수 있다. 다만 M-mode 전용 교재로서 MPP를 소프트웨어가 직접 확인하지 않으면 실질적 동작에 영향은 없지만 스펙 준수 측면에서 수정이 필요하다.

**수정 방향**:
```systemverilog
// mret_en: MIE←MPIE, MPIE←1, MPP←2'b11 (M-mode only 구현)
mstatus_reg <= (mstatus_reg & ~MSTATUS_MASK)
             | ((mstatus_reg & 32'h80) >> 4)  // MIE <- MPIE
             | 32'h80                          // MPIE <- 1
             | 32'h1800;                       // MPP <- 2'b11 (M-mode only)
```

또한 원고 290줄 "MPP ← 2'b00"도 "MPP ← 2'b11 (M-mode only 구현에서는 M-mode로 복귀)"로 정정해야 한다.

---

### C2 — csr_tb.sv: 5단계 MRET 후 mstatus 기대값 오류

**위치**: `ch18_csr_tb.sv` 382~384줄

**현재 코드**:
```systemverilog
// 기대값: MIE=1(0x8) + MPIE=1(0x80) = 0x88
csr_read(MSTATUS, read_val);
check(read_val, 32'h88, "mret mstatus restore");
```

**문제점**:
MRET 전 mstatus 상태를 추적하면:
1. 트랩 진입 전: `csr_write(MSTATUS, CSR_OP_RW, 32'h8)` → mstatus = 0x8 (MIE=1)
2. 트랩 진입(`trap_en=1`): MPIE←MIE(1), MIE←0, MPP←2'b11 → mstatus = 0x80 | 0x1800 = 0x1880
3. MRET(`mret_en=1`): MIE←MPIE(1), MPIE←1, MPP←? → mstatus = 0x8 | 0x80 | MPP항

- C1에서 확인한 대로, 현재 구현에서 MRET 후 MPP = 0이므로 mstatus = 0x88이 된다.
- 그러나 C1의 스펙 수정(MPP ← 2'b11)을 적용하면 mstatus = 0x88 | 0x1800 = 0x1888이 되어야 한다.
- **C1 수정을 채택할 경우**: 기대값을 `32'h1888`로 변경해야 한다.
- **C1 수정을 채택하지 않을 경우**: 현재 기대값 `32'h88`은 현재 구현과 일치하므로 TB 자체 버그는 아니나, 스펙 불일치 상태다.

**결론**: C1 수정(스펙 준수)을 전제로 TB 기대값도 `32'h1888`로 수정 필요. C1과 C2는 연동 이슈다.

---

## Major 이슈

### M1 — csr_unit.sv: CSRRS/CSRRC에서 rs1=x0 조건 처리 미구현 (스펙 준수)

**위치**: `ch18_csr_unit.sv` csr_next always_comb 블록 및 원고 714~720줄

**현재 구현**: `csr_we` 신호가 외부(파이프라인 디코더)에서 결정되어 csr_unit에 전달된다.
CSRRS/CSRRC에서 `rs1 = x0`이면 쓰기를 발생시키지 않아야 한다는 스펙 요건이 있다.

**현재 상태 및 문제**:
- csr_unit 모듈 자체는 `csr_we` 외부 입력에 전적으로 의존한다. 즉, `rs1 == 0` 조건 판단은 이 모듈 외부(디코더)에서 처리되어야 한다.
- 이 사실이 원고에서 명확히 언급되지 않으면, 독자가 "csr_unit 내부에서 처리된다"고 오해할 수 있다.
- 원고 750~752줄에서 "CSRRS/CSRRC에서 rs1 = x0이면 CSR 값을 변경하지 않습니다"라고 설명은 있으나, **이 처리가 파이프라인 디코더에서 `csr_we` 생성 시 담당한다는 설계 결정이 원고에 명시되지 않았다**.
- csr_tb.sv에서도 이 조건(rs1=x0일 때 csr_we=0)에 대한 테스트가 없다.

**요구 사항**:
- 원고 18.3절 또는 csr_unit.sv 주석에 "rs1=x0 조건은 파이프라인 디코더에서 csr_we를 0으로 설정함으로써 처리한다"는 설명 추가.
- csr_tb.sv에 `csr_we=0`으로 CSRRS 시뮬레이션하는 테스트 케이스 추가 권장.

---

### M2 — csr_unit.sv: mstatus 읽기 시 WPRI 비트 처리 이중 확인

**위치**: `ch18_csr_unit.sv` 123줄

**현재 코드**:
```systemverilog
CSR_MSTATUS:  csr_rdata = mstatus_reg & MSTATUS_MASK; // WPRI 마스킹
```

**상태**: 읽기 시 MSTATUS_MASK 적용은 정확하다. WPRI 비트는 읽기 시 0으로 반환되어야 한다는 스펙을 준수한다. ✓

**그러나 쓰기 시도**: 소프트웨어가 CSRRW로 mstatus에 전체 값을 쓸 때(214줄):
```systemverilog
CSR_MSTATUS:  mstatus_reg  <= csr_next & MSTATUS_MASK;
```
이것도 정확하다. ✓

**추가 점검 사항**: `csr_next` 계산에서 `csr_rdata`를 기반으로 한다. `csr_rdata`는 이미 MSTATUS_MASK로 마스킹된 값이다. 따라서 CSRRS/CSRRC 연산 시:
```
csr_next = csr_rdata | csr_wdata  (CSRRS)
         = (mstatus_reg & MASK) | csr_wdata
```
이 결과에 다시 `& MSTATUS_MASK`를 적용하므로 WPRI 비트 오염 없음. 정확하다. ✓

**Minor로 재분류**: 동작 정확성에는 문제 없으나, 원고에서 "읽기 시 마스킹" + "쓰기 시 마스킹" 이중 방어 이유를 설명하면 이해도 향상에 도움. → M2를 Minor로 하향 조정 (아래 Minor 목록 참조).

---

### M2 — csr_unit.sv: mtvec MODE 필드 WARL 처리 불일치

**위치**: `ch18_csr_unit.sv` 221줄 vs 원고 800줄

**현재 csr_unit.sv 코드**:
```systemverilog
CSR_MTVEC:    mtvec_reg    <= csr_next;  // 그대로 저장
```

**현재 원고 코드(800줄)**:
```systemverilog
CSR_MTVEC:    mtvec_reg    <= {csr_next[31:2], csr_next[1:0]}; // MODE 저장
```

**문제**: 원고 본문 338~341줄에서 "MODE 필드에서 2'b10과 2'b11은 구현 미지원(WARL)으로 2'b00(Direct)으로 강제 처리한다"고 명시했으나, csr_unit.sv 구현은 MODE 필드를 그대로 저장한다 (WARL 처리 없음).

원고 내 예시 코드(800줄)도 `{csr_next[31:2], csr_next[1:0]}`로 단순 재조합이며 WARL 강제가 없다. 원고 설명과 코드 모두 일관성 없음.

**영향**: MODE=2 또는 MODE=3 값이 mtvec에 저장되면, Ch19 트랩 벡터 계산에서 예상치 못한 동작 발생 가능.

**수정 방향**:
```systemverilog
// mtvec WARL: MODE=0(Direct) 또는 MODE=1(Vectored)만 허용
// MODE=2,3은 0으로 강제
CSR_MTVEC: mtvec_reg <= {csr_next[31:2], (csr_next[1:0] == 2'b01) ? 2'b01 : 2'b00};
```
또는 원고 설명("Direct 모드만 구현")과 일치하도록 항상 `{csr_next[31:2], 2'b00}`으로 처리.

---

### M3 — csr_tb.sv: csr_write 태스크의 타이밍 문제 (잠재적 레이스 컨디션)

**위치**: `ch18_csr_tb.sv` 109~120줄, `csr_write` 태스크

**현재 코드**:
```systemverilog
task csr_write(...);
   csr_addr  = addr;
   csr_we    = 1'b1;
   csr_op    = op;
   csr_wdata = wdata;
   @(posedge clk);   // 클럭 엣지에서 레지스터에 기록됨
   #1;               // 셋업 타임 마진
endtask
```

**문제**: 태스크 시작 시 신호를 즉시 구동(`=`)하고 바로 `@(posedge clk)`를 기다린다. 만약 직전 클럭 엣지로부터의 경과 시간이 충분하지 않으면(예: 이전 `@(posedge clk); #1` 직후 호출 시), 셋업 타임이 확보되지 않은 상태에서 다음 posedge가 포착될 수 있다.

**실제 영향**: 5단계 시뮬레이션에서:
```systemverilog
csr_write(MSTATUS, CSR_OP_RW, 32'h8);   // MIE=1 설정
trap_pc    = 32'h0000_2000;
trap_cause = 32'h8000_0007;
trap_en    = 1'b1;
@(posedge clk); #1;                      // 같은 클럭 엣지?
```
`csr_write` 완료 직후 `trap_en=1`로 설정되는데, `csr_write` 내부 `@(posedge clk)` 직후 `#1` 딜레이 후 `trap_en`이 설정된다. 이 경우 trap_en 업데이트와 다음 posedge 사이 셋업 타임이 충분히 확보된다. 타이밍은 허용 범위 내이나, 실제 VCS 시뮬레이션에서 `#1` 딜레이 의존성이 생기므로 **교재 코드 예시로는 취약한 설계**다.

**수정 방향**: `csr_write` 태스크 시작 부분에 `@(negedge clk)` 또는 `#1` 선행 딜레이 추가로 클럭 엣지와의 거리 확보. 또는 Non-blocking 대입(`<=`) 사용.

---

### M4 — csr_tb.sv: 5단계에서 trap_en 기간 중 csr_we 신호 처리 미정의

**위치**: `ch18_csr_tb.sv` 354~361줄

**현재 코드**:
```systemverilog
csr_write(MSTATUS, CSR_OP_RW, 32'h8);   // MIE=1
trap_pc    = 32'h0000_2000;
trap_cause = 32'h8000_0007;
trap_en    = 1'b1;
@(posedge clk); #1;
trap_en    = 1'b0;
```

**문제**: `csr_write` 태스크는 내부적으로 `@(posedge clk); #1;`으로 종료하며, 이후 `csr_we`가 1 상태로 남아 있다. (`csr_write` 태스크에 csr_we=0 처리가 없다.)

태스크 종료 후 `csr_we = 1`인 상태에서 `trap_en = 1`을 설정하고 `@(posedge clk)`를 기다리면, 같은 posedge에서 `trap_en=1`과 `csr_we=1`이 동시에 활성화된다. csr_unit.sv의 우선순위 로직에서 `trap_en > csr_we`이므로 trap_en이 처리되지만, 교재 독자가 이 상황을 보면 혼란스러울 수 있다.

또한 5단계 csr_write 태스크 종료 후 csr_we 상태를 명시적으로 0으로 해제하는 코드가 없다.

**수정 방향**: `csr_write` 태스크 마지막 또는 해당 테스트 블록에서 `csr_we = 1'b0` 명시적 해제 추가.

---

## Minor 이슈

### N1 — csr_unit.sv: mepc 하위 비트 처리 — 스펙 정밀도

**위치**: `ch18_csr_unit.sv` 13줄 주석, 186줄, 227줄

**현재 코드 주석**:
```
// mepc 하위 1비트: 항상 0으로 강제 (4바이트 정렬)
```

**스펙 확인**: RISC-V Privileged Spec 3.1.14에 따르면 IALIGN=32(C 확장 미구현 시)인 경우 mepc[1:0]을 0으로 강제할 수도 있으나, 표준적으로는 mepc[0]만 0으로 강제(IALIGN=16인 경우에도 최소 bit[0]=0)한다. 현재 구현은 mepc[0]=0으로 처리하므로 정확하다.

다만 주석 "4바이트 정렬"은 mepc[1]도 0이어야 한다는 오해를 줄 수 있다. 현재 코드는 bit[0]만 0으로 강제하므로 (예: `32'h0000_1003` → `32'h0000_1002` — 즉 bit[1]은 보존됨) 실제로는 "2바이트 정렬" 동작이다. 교재의 RV32I 환경에서는 bit[1]도 0이어야 하나 이는 소프트웨어 책임이다. 주석을 "하위 1비트 강제 0 (IALIGN=32, WARL)"으로 수정 권장.

---

### N2 — 원고 chapter18.html: CSR 주소 설명 표 오류

**위치**: `manuscripts/part7/chapter18.html` 122~138줄 (접근 권한 표)

**현재 내용**:
```
[11:10] 접근 권한: 11 = 읽기 전용(Read-Only), 그 외 = 읽기/쓰기
[9:8]   최소 접근 권한: 00 = U-mode, 01 = S-mode, 10 = S-mode(HS), 11 = M-mode
```

**문제**: RISC-V Priv Spec Table 2.1에 따르면 [9:8] 인코딩에서 `10`은 "Hypervisor-level (S/HS mode)"가 아니라 단순히 예약된 S-mode 변형이다. 정확한 값은:
- `00` = User/Application (U-mode)
- `01` = Supervisor (S-mode)
- `10` = Hypervisor / Reserved (S-mode in H extension context)
- `11` = Machine (M-mode)

현재 표기 `10 = S-mode(HS)`는 완전히 틀리지는 않으나 "HS-mode"라는 별칭이 독자에게 생소할 수 있다. "10 = Hypervisor(또는 예약)" 또는 단순히 "10 = 예약(이 교재에서 미사용)"으로 표기 권장.

---

### N3 — 원고 chapter18.html: 원고 내 약식 csr_tb 코드와 실제 파일 불일치

**위치**: `manuscripts/part7/chapter18.html` 936~983줄 (18.4절 약식 TB 코드)

**문제**: 원고 18.4절에 포함된 약식 테스트벤치 코드(모듈명 `csr_tb`)는 실제 배포 파일(`ch18_csr_tb.sv`, 모듈명 `ch18_csr_tb`)과 다르다. 원고 내 코드는 별도 설명 없이 실제 파일과 구조가 다르므로(예: `csr_write` 태스크 구현 방식, 모듈 인스턴스화 방식 등) 독자가 원고 코드를 그대로 따라 작성하면 파일을 직접 사용할 수 없다.

**권장**: 원고 내 코드가 "교육용 발췌"임을 명시("전체 코드는 ch18_csr_tb.sv 참조")하거나, 모듈명 및 구조를 실제 파일과 일치시킬 것.

---

## 세부 체크리스트 결과

| 항목 | 결과 | 비고 |
|------|------|------|
| CSR 주소 7개 상수 스펙 일치 | ✅ | 0x300~0x344 모두 정확 |
| MSTATUS_MASK = 0x1888 검증 | ✅ | MIE[3]+MPIE[7]+MPP[12:11] 합산 정확 |
| mip_wire 비트 할당 | ✅ | ext_irq[11], timer_irq[7], sw_irq[3] 정확 |
| trap_en: MPIE←MIE 처리 | ✅ | `(mstatus_reg & 32'h8) << 4` 정확 |
| trap_en: MIE←0 처리 | ✅ | OR 없이 0으로 처리됨 |
| trap_en: MPP←2'b11 | ✅ | `32'h1800` OR 처리 |
| trap_en: mepc←{trap_pc[31:1],0} | ✅ | 하위 1비트 강제 0 |
| trap_en: mcause←trap_cause | ✅ | 직접 대입 |
| mret_en: MIE←MPIE 처리 | ✅ | `(mstatus_reg & 32'h80) >> 4` 정확 |
| mret_en: MPIE←1 처리 | ✅ | `32'h80` OR 처리 |
| mret_en: MPP←2'b00 (스펙 확인 필요) | 🔴 | M-only 구현 시 MPP←2'b11이 스펙 준수 (C1) |
| csr_next 6개 연산 정확성 | ✅ | 모두 정확 |
| CSR_MIP 쓰기 무시 | ✅ | `CSR_MIP: ;` 처리 |
| mstatus WPRI 마스크 읽기 시 적용 | ✅ | `mstatus_reg & MSTATUS_MASK` |
| mstatus WPRI 마스크 쓰기 시 적용 | ✅ | `csr_next & MSTATUS_MASK` |
| mepc 하위 1비트 강제 0 | ✅ | 읽기/쓰기/trap_en 모두 처리 |
| irq_pending 조합 논리 | ✅ | `mstatus_reg[3] & |(mie_reg & mip_wire)` |
| DUT 포트 연결 정확성 (TB) | ✅ | 모든 포트 일치 |
| CSRRS rs1=x0 처리 명시 | 🟡 | 외부 처리 설계 결정 미명시 (M1) |
| mtvec WARL MODE 처리 | 🟡 | 원고 설명과 코드 불일치 (M2) |
| TB 타이밍 안전성 | 🟡 | csr_write 태스크 레이스 컨디션 (M3) |
| TB 5단계 csr_we 상태 관리 | 🟡 | trap_en 구간 csr_we=1 잠재적 혼란 (M4) |
| TB 5단계 MRET 기대값 | 🔴 | C1 수정 연동 시 0x1888 변경 필요 (C2) |

---

## 최종 의견

`csr_unit.sv`의 핵심 기능은 전반적으로 견고하게 구현되어 있다. CSR 주소, 비트 마스크, 읽기 MUX, 쓰기 우선순위, irq_pending 로직 모두 RISC-V Privileged Architecture v1.12 스펙과 일치한다.

**반드시 수정이 필요한 항목은 두 가지다**:

1. **C1**: M-mode only 구현에서 MRET 후 MPP는 2'b00이 아닌 2'b11로 유지해야 한다. csr_unit.sv와 원고 설명 양쪽을 수정해야 한다.
2. **C2**: C1 수정에 따라 csr_tb.sv 5단계 MRET 기대값을 `32'h88` → `32'h1888`로 변경해야 한다.

Major 이슈 중 M1(rs1=x0 처리 설계 결정 명시), M2(mtvec WARL 원고-코드 일관성), M3/M4(TB 타이밍 및 신호 상태 관리)는 교육용 코드 품질 향상을 위해 수정 권장한다. M1과 M2는 독자가 파이프라인 통합 시 설계 오류를 범할 수 있는 경로이므로 원고 보완이 특히 중요하다.

Critical 2건 수정 완료 후 재검토를 권장한다.
