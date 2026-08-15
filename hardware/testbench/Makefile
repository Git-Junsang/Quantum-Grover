#=====================================================================
# hardware/testbench/Makefile -- iverilog 회귀 진입점 (소유자 A)
#
#   make regress   전 테스트벤치를 순서대로 돌립니다
#   make tb_xxx    하나만 돌립니다
#   make wave TB=tb_grover_top   VCD 를 남깁니다
#
# 자기 tb 만 통과하는 것은 통과가 아닙니다. main 으로 머지하기 전에
# regress 가 전부 초록이어야 합니다.
#=====================================================================
SRC_DIR := ../src
BUILD   := build

IVERILOG := iverilog
VVP      := vvp
IVFLAGS  := -g2012 -I $(SRC_DIR) -Wall

RTL := $(wildcard $(SRC_DIR)/*.v)

TESTS := tb_predicate \
         tb_two_mean_calc \
         tb_iter_rom \
         tb_cache_ctrl \
         tb_ctrl_fsm \
         tb_grover_amp \
         tb_grover_top

.PHONY: regress clean $(TESTS)

regress: $(TESTS)
	@echo "==================================================="
	@echo " 회귀 전체 통과"
	@echo "==================================================="

$(TESTS): %: $(BUILD)/%.vvp
	@echo "--- $@ ---"
	@$(VVP) $<

$(BUILD)/%.vvp: %.v $(RTL) | $(BUILD)
	@$(IVERILOG) $(IVFLAGS) -o $@ $< $(RTL)

$(BUILD):
	@mkdir -p $(BUILD)

wave: $(BUILD)/$(TB).vvp
	$(VVP) $< -vcd

clean:
	rm -rf $(BUILD) *.vcd
