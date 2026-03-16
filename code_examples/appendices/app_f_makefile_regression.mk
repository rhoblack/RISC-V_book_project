# app_f_makefile_regression.mk
# 회귀 테스트 자동화 Makefile
# 사용법: make -f app_f_makefile_regression.mk test-report

# ===== 설정 =====
RISCV_TESTS := ../riscv-tests
RESULTS_DIR := results
TIMESTAMP := $(shell date +%Y%m%d_%H%M%S)
SPIKE := spike

# ===== 테스트 대상 =====
# rv32ui 테스트 파일 찾기 (wildcard 함수 사용)
RV32UI_TESTS := $(wildcard $(RISCV_TESTS)/isa/rv32ui/*-p-*.elf)

# 테스트 이름만 추출 (로그 파일명 생성용)
RV32UI_NAMES := $(notdir $(RV32UI_TESTS))
RV32UI_LOGS := $(RV32UI_NAMES:%=$(RESULTS_DIR)/%.log)

# ===== 기본 대상 (target) =====
all: test-report

# ===== Step 1: riscv-tests 빌드 (선행 조건) =====
$(RISCV_TESTS)/isa/rv32ui:
	@echo "Checking riscv-tests..."
	@if [ ! -d "$(RISCV_TESTS)" ]; then \
		echo "Error: riscv-tests directory not found"; \
		echo "Run: cd .. && git clone https://github.com/riscv-software-src/riscv-tests.git"; \
		exit 1; \
	fi
	@if [ ! -f "$(RISCV_TESTS)/isa/rv32ui/add-p-add.elf" ]; then \
		echo "Building riscv-tests rv32ui..."; \
		cd $(RISCV_TESTS) && make XLEN=32 rv32ui; \
	fi

# ===== Step 2: 개별 테스트 실행 규칙 =====
# Makefile의 "pattern rule"
$(RESULTS_DIR)/%.elf.log: $(RISCV_TESTS)/isa/rv32ui/%.elf | $(RESULTS_DIR)
	@name=$$(basename $* .elf); \
	echo "Testing $$name ..."; \
	if $(SPIKE) pk $< > $@ 2>&1; then \
		if grep -q "Test passed" $@; then \
			echo "  ✅ PASSED"; \
		else \
			echo "  ❌ FAILED"; \
		fi; \
	else \
		echo "  ⏱️  TIMEOUT or ERROR"; \
	fi

# ===== Step 3: 결과 디렉터리 생성 =====
$(RESULTS_DIR):
	@mkdir -p $(RESULTS_DIR)

# ===== Step 4: 테스트 실행 =====
test-sim: $(RISCV_TESTS)/isa/rv32ui $(RESULTS_DIR) $(RV32UI_LOGS)
	@echo ""
	@echo "=== All tests completed ==="

# ===== Step 5: 결과 리포트 생성 =====
test-report: test-sim
	@echo "=== Generating Report ==="
	@report_file="$(RESULTS_DIR)/report_$(TIMESTAMP).txt"; \
	echo "=== Test Report ===" > $$report_file; \
	echo "Generated: $$(date)" >> $$report_file; \
	echo "XLEN: 32" >> $$report_file; \
	echo "Test Suite: riscv-tests" >> $$report_file; \
	echo "" >> $$report_file; \
	\
	passed=0; \
	failed=0; \
	timeout=0; \
	for log in $(RESULTS_DIR)/*.elf.log; do \
		if grep -q "Test passed" $$log 2>/dev/null; then \
			passed=$$((passed + 1)); \
		elif grep -q "TIMEOUT" $$log 2>/dev/null; then \
			timeout=$$((timeout + 1)); \
		else \
			failed=$$((failed + 1)); \
		fi; \
	done; \
	\
	total=$$((passed + failed + timeout)); \
	if [ $$total -gt 0 ]; then \
		percentage=$$((passed * 100 / total)); \
	else \
		percentage=0; \
	fi; \
	\
	echo "Passed:  $$passed / $$total" >> $$report_file; \
	echo "Failed:  $$failed / $$total" >> $$report_file; \
	echo "Timeout: $$timeout / $$total" >> $$report_file; \
	echo "Percentage: $$percentage%" >> $$report_file; \
	echo "" >> $$report_file; \
	\
	if [ $$failed -gt 0 ]; then \
		echo "Failed Tests:" >> $$report_file; \
		for log in $(RESULTS_DIR)/*.elf.log; do \
			if ! grep -q "Test passed" $$log 2>/dev/null && ! grep -q "TIMEOUT" $$log 2>/dev/null; then \
				name=$$(basename $$log .elf.log); \
				echo "  - $$name" >> $$report_file; \
			fi; \
		done; \
		echo "" >> $$report_file; \
	fi; \
	\
	cat $$report_file; \
	echo ""; \
	echo "Full report saved to: $$report_file"

# ===== Step 6: 병렬 실행 (선택, -j 옵션 사용) =====
# 사용법: make -f app_f_makefile_regression.mk test-parallel
test-parallel: test-sim
	@echo "Parallel execution completed"

# ===== Step 7: 정리 =====
clean:
	@rm -rf $(RESULTS_DIR)
	@echo "Results cleaned"

# ===== Step 8: 도움말 =====
help:
	@echo "=== riscv-tests Regression Testing ==="
	@echo ""
	@echo "Targets:"
	@echo "  make test-sim          - Run all tests sequentially"
	@echo "  make test-report       - Run tests and generate report"
	@echo "  make test-parallel     - Run tests in parallel (add -j 4)"
	@echo "  make clean             - Remove results directory"
	@echo "  make help              - Show this help"
	@echo ""
	@echo "Usage Examples:"
	@echo "  make -f app_f_makefile_regression.mk test-report"
	@echo "  make -f app_f_makefile_regression.mk test-parallel -j 4"
	@echo "  make -f app_f_makefile_regression.mk clean"

# ===== Phony targets (파일이 아닌 목표) =====
.PHONY: all test-sim test-report test-parallel clean help

# ===== 기본 make 옵션 =====
# 에러 발생 시에도 계속 진행 (테스트 모두 실행하기 위함)
.IGNORE: test-sim
