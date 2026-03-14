#!/usr/bin/env python3
###############################################################################
# ch21_design_optimization.py
# PPA (Power-Performance-Area) 설계점 탐색 및 Pareto Frontier 계산
#
# 용도:
#   다양한 설계 옵션(파이프라인 깊이, 주파수, 최적화 레벨 등)의
#   성능/전력/면적 데이터를 입력받아 Pareto optimal frontier를 계산하고
#   최적의 설계점을 시각화합니다.
#
# 사용법:
#   python3 ch21_design_optimization.py
#
# 출력:
#   - Pareto frontier 설계점 목록
#   - Performance vs Power 그래프
#   - Performance vs Area 그래프
#   - 3D 시각화 (선택)
###############################################################################

import sys
import math
import matplotlib.pyplot as plt
from mpl_toolkits.mplot3d import Axes3D

###############################################################################
# 설계점 데이터 (실제 프로젝트에서는 Vivado 결과를 파싱해서 생성)
###############################################################################

class Design:
    """설계점을 나타내는 클래스"""
    def __init__(self, name, perf_mhz, power_mw, area_lut, cpi=1.0):
        self.name = name
        self.perf_mhz = perf_mhz      # 최대 동작 주파수 (MHz)
        self.power_mw = power_mw      # 평균 전력 소비 (mW)
        self.area_lut = area_lut      # LUT 사용량
        self.cpi = cpi                # 사이클/명령어

    @property
    def epi(self):
        """에너지/명령어 (Energy Per Instruction) 계산"""
        if self.perf_mhz == 0:
            return float('inf')
        return (self.power_mw / 1000.0) * self.cpi / self.perf_mhz * 1e9  # nJ/instr

    @property
    def ipc(self):
        """명령어/사이클 (Instruction Per Cycle) = 1/CPI"""
        return 1.0 / self.cpi if self.cpi > 0 else 0.0

    def __repr__(self):
        return (f"{self.name:12s}: {self.perf_mhz:3.0f}MHz, "
                f"{self.power_mw:6.1f}mW, {self.area_lut:6.0f}LUT, "
                f"EPI={self.epi:.2f}nJ")


###############################################################################
# 설계 데이터셋 (예시: 파이프라인 깊이에 따른 설계 변형)
###############################################################################

designs = [
    # 기본 설계들 (Ch20 마무리 단계의 상태)
    Design("A: 3-stage",      40,    280,  4500,  2.5),   # 얕은 파이프라인
    Design("B: 5-stage",      50,    350,  5200,  1.2),   # 표준 파이프라인
    Design("C: 7-stage",      65,    420,  6300,  1.0),   # 깊은 파이프라인
    Design("D: 8-stage",      75,    500,  7000,  0.95),  # 매우 깊은 파이프라인

    # 최적화된 설계들 (Clock Gating, 메모리 선택 등)
    Design("E: 5-stage+CG",   50,    310,  5300,  1.2),   # Clock Gating 추가
    Design("F: 5-stage+Mem",  48,    330,  4800,  1.3),   # LUTRAM 최적화
    Design("G: 5-stage+Both", 50,    290,  5000,  1.2),   # CG + Mem 최적화

    # DVFS 또는 저전력 설계들
    Design("H: 5-stage DVFS", 30,    180,  5200,  2.0),   # 저전압/저주파
    Design("I: 5-stage DVFS+", 40,   220,  5200,  1.5),   # 중간 DVFS

    # 지배당하는 설계 (비교용)
    Design("X: Suboptimal",   45,    400,  6500,  2.0),   # 모든 면에서 비효율
]

###############################################################################
# Pareto Frontier 계산
###############################################################################

def is_dominated(design, others):
    """
    design이 다른 설계에 지배당하는지 확인.

    설계 A가 B에 의해 지배당한다는 것은:
      A의 모든 목표가 B 이상 나쁜데,
      최소한 하나는 B보다 훨씬 나쁜 경우.

    여기서는 maximize(performance), minimize(power), minimize(area) 사용.
    """
    for other in others:
        if other == design:
            continue

        # B가 A를 지배하는가?
        better_perf = other.perf_mhz >= design.perf_mhz * 0.95  # 성능 비슷하거나 나음
        better_power = other.power_mw <= design.power_mw * 1.05  # 전력 비슷하거나 낮음
        better_area = other.area_lut <= design.area_lut * 1.05  # 면적 비슷하거나 작음

        # 최소한 하나는 더 나음
        strictly_better = (
            (other.perf_mhz > design.perf_mhz and
             other.power_mw <= design.power_mw and
             other.area_lut <= design.area_lut) or
            (other.perf_mhz >= design.perf_mhz and
             other.power_mw < design.power_mw and
             other.area_lut <= design.area_lut) or
            (other.perf_mhz >= design.perf_mhz and
             other.power_mw <= design.power_mw and
             other.area_lut < design.area_lut)
        )

        if strictly_better:
            return True

    return False


def find_pareto_frontier(designs):
    """Pareto optimal 설계점 찾기"""
    frontier = [d for d in designs if not is_dominated(d, designs)]
    # 성능순 정렬
    return sorted(frontier, key=lambda d: d.perf_mhz)


###############################################################################
# 메인 분석
###############################################################################

def main():
    print("=" * 70)
    print("  PPA 트레이드오프 분석: Pareto Frontier 계산")
    print("=" * 70)
    print()

    # 전체 설계점 출력
    print("[1] 모든 설계점:")
    print("-" * 70)
    for design in sorted(designs, key=lambda d: d.name):
        print(f"  {design}")
    print()

    # Pareto Frontier 계산
    pareto = find_pareto_frontier(designs)

    print(f"[2] Pareto Optimal Frontier ({len(pareto)}개 설계):")
    print("-" * 70)
    for design in pareto:
        print(f"  {design}")
    print()

    # 최적 설계점 추천 (목표별)
    print("[3] 목표별 추천 설계점:")
    print("-" * 70)

    # 성능 최우선
    best_perf = max(pareto, key=lambda d: d.perf_mhz)
    print(f"  🚀 최고 성능: {best_perf.name} ({best_perf.perf_mhz:.0f}MHz)")

    # 전력 최우선
    best_power = min(pareto, key=lambda d: d.power_mw)
    print(f"  🔋 최저 전력: {best_power.name} ({best_power.power_mw:.1f}mW)")

    # 면적 최우선
    best_area = min(pareto, key=lambda d: d.area_lut)
    print(f"  📦 최소 면적: {best_area.name} ({best_area.area_lut:.0f}LUT)")

    # 에너지 효율 최우선 (EPI)
    best_epi = min(pareto, key=lambda d: d.epi)
    print(f"  ⚡ 최고 에너지 효율: {best_epi.name} (EPI={best_epi.epi:.2f}nJ)")

    # 균형 설계 (3D 거리 기반)
    print()
    print("[4] 정규화 거리 기반 선택:")
    print("-" * 70)

    # 정규화 (0~1 범위로)
    perf_max = max(d.perf_mhz for d in pareto)
    perf_min = min(d.perf_mhz for d in pareto)
    power_max = max(d.power_mw for d in pareto)
    power_min = min(d.power_mw for d in pareto)
    area_max = max(d.area_lut for d in pareto)
    area_min = min(d.area_lut for d in pareto)

    def normalized_distance(d):
        """
        이상적인 점 (성능 최고, 전력 최저, 면적 최소)까지의 거리.
        더 작을수록 균형잡힌 설계.
        """
        norm_perf = (d.perf_mhz - perf_min) / (perf_max - perf_min + 1e-6)
        norm_power = 1.0 - (d.power_mw - power_min) / (power_max - power_min + 1e-6)
        norm_area = 1.0 - (d.area_lut - area_min) / (area_max - area_min + 1e-6)

        return math.sqrt(
            (1.0 - norm_perf)**2 +
            (1.0 - norm_power)**2 +
            (1.0 - norm_area)**2
        )

    balanced = min(pareto, key=normalized_distance)
    print(f"  ⚖️  균형설계: {balanced.name}")
    print(f"      성능: {balanced.perf_mhz:.0f}MHz")
    print(f"      전력: {balanced.power_mw:.1f}mW")
    print(f"      면적: {balanced.area_lut:.0f}LUT")
    print(f"      거리: {normalized_distance(balanced):.3f}")

    print()

    # =========================================================================
    # 시각화 1: Performance vs Power (2D)
    # =========================================================================

    fig, axes = plt.subplots(2, 2, figsize=(14, 10))

    # --- 그래프 1: 모든 설계점 ---
    ax = axes[0, 0]
    all_perf = [d.perf_mhz for d in designs]
    all_power = [d.power_mw for d in designs]
    all_names = [d.name for d in designs]

    ax.scatter(all_perf, all_power, s=100, alpha=0.6, c='lightblue', edgecolors='blue', label='All designs')
    pareto_perf = [d.perf_mhz for d in pareto]
    pareto_power = [d.power_mw for d in pareto]
    ax.scatter(pareto_perf, pareto_power, s=200, alpha=1.0, c='red', edgecolors='darkred',
               marker='*', label='Pareto frontier')

    # 레이블 추가
    for design in designs:
        ax.annotate(design.name, (design.perf_mhz, design.power_mw),
                   fontsize=8, ha='right')

    ax.set_xlabel('Performance (MHz)', fontsize=11)
    ax.set_ylabel('Power (mW)', fontsize=11)
    ax.set_title('Performance vs Power', fontsize=12, fontweight='bold')
    ax.grid(True, alpha=0.3)
    ax.legend()

    # --- 그래프 2: Performance vs Area ---
    ax = axes[0, 1]
    all_area = [d.area_lut for d in designs]

    ax.scatter(all_perf, all_area, s=100, alpha=0.6, c='lightgreen', edgecolors='green', label='All designs')
    pareto_area = [d.area_lut for d in pareto]
    ax.scatter(pareto_perf, pareto_area, s=200, alpha=1.0, c='red', edgecolors='darkred',
               marker='*', label='Pareto frontier')

    for design in designs:
        ax.annotate(design.name, (design.perf_mhz, design.area_lut),
                   fontsize=8, ha='right')

    ax.set_xlabel('Performance (MHz)', fontsize=11)
    ax.set_ylabel('Area (LUT)', fontsize=11)
    ax.set_title('Performance vs Area', fontsize=12, fontweight='bold')
    ax.grid(True, alpha=0.3)
    ax.legend()

    # --- 그래프 3: Power vs Area ---
    ax = axes[1, 0]
    ax.scatter(all_power, all_area, s=100, alpha=0.6, c='lightyellow', edgecolors='orange', label='All designs')
    ax.scatter(pareto_power, pareto_area, s=200, alpha=1.0, c='red', edgecolors='darkred',
               marker='*', label='Pareto frontier')

    for design in designs:
        ax.annotate(design.name, (design.power_mw, design.area_lut),
                   fontsize=8, ha='right')

    ax.set_xlabel('Power (mW)', fontsize=11)
    ax.set_ylabel('Area (LUT)', fontsize=11)
    ax.set_title('Power vs Area', fontsize=12, fontweight='bold')
    ax.grid(True, alpha=0.3)
    ax.legend()

    # --- 그래프 4: EPI 분석 ---
    ax = axes[1, 1]
    all_epi = [d.epi for d in designs]
    pareto_epi = [d.epi for d in pareto]

    ax.scatter(all_perf, all_epi, s=100, alpha=0.6, c='lightcoral', edgecolors='red', label='All designs')
    ax.scatter(pareto_perf, pareto_epi, s=200, alpha=1.0, c='darkred', edgecolors='darkred',
               marker='*', label='Pareto frontier')

    for design in designs:
        ax.annotate(design.name, (design.perf_mhz, design.epi),
                   fontsize=8, ha='right')

    ax.set_xlabel('Performance (MHz)', fontsize=11)
    ax.set_ylabel('EPI (nJ/instr)', fontsize=11)
    ax.set_title('Performance vs Energy Efficiency', fontsize=12, fontweight='bold')
    ax.grid(True, alpha=0.3)
    ax.legend()

    plt.tight_layout()
    plt.savefig('ppa_analysis.png', dpi=150, bbox_inches='tight')
    print("✓ Saved: ppa_analysis.png")

    # =========================================================================
    # 시각화 2: 3D Pareto Surface (선택)
    # =========================================================================

    fig = plt.figure(figsize=(12, 9))
    ax = fig.add_subplot(111, projection='3d')

    # Pareto 설계점
    pareto_perf = [d.perf_mhz for d in pareto]
    pareto_power = [d.power_mw for d in pareto]
    pareto_area = [d.area_lut for d in pareto]
    pareto_names = [d.name for d in pareto]

    # 산점도
    ax.scatter(pareto_perf, pareto_power, pareto_area, s=200, c='red', marker='*', label='Pareto frontier')

    # 레이블
    for i, design in enumerate(pareto):
        ax.text(design.perf_mhz, design.power_mw, design.area_lut,
               '  ' + design.name, fontsize=9)

    # 축 레이블
    ax.set_xlabel('Performance (MHz)', fontsize=11)
    ax.set_ylabel('Power (mW)', fontsize=11)
    ax.set_zlabel('Area (LUT)', fontsize=11)
    ax.set_title('3D PPA Pareto Surface', fontsize=12, fontweight='bold')

    plt.savefig('ppa_3d.png', dpi=150, bbox_inches='tight')
    print("✓ Saved: ppa_3d.png")

    print()
    print("=" * 70)
    print("  분석 완료!")
    print("=" * 70)


if __name__ == '__main__':
    main()
