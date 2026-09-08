# hardware_dram 회귀. verilator 로 빌드하고 돌립니다.
#
#   make            ports lint store prep core 를 순서대로
#   make store      grover_dram_amp_store 단위 (지연 0 / 백프레셔 두 벌)
#   make prep       grover_dram_prep_seq 단위 -- 체크포인트 K/H 를 대신하는 부분
#   make core       Main IP 통합 (통신 계층 없이 코어만)
#   make equiv      hardware_bram 과 궤적 대조 + 비용 비교 (오래 걸립니다)
#   make lint       합성 대상 RTL 만 lint
#   make ports      PJK 인수인계 포트 계약 대조
#   make clean
#
# 빌드 디렉터리를 저장소 밖으로 빼는 이유는 hardware_bram/sim/Makefile 과
# 같습니다. 이 저장소 경로에 공백이 들어 있어서 verilator 가 만들어 주는
# Makefile 을 GNU Make 가 제자리에서 못 돌립니다. --Mdir 로 공백 없는 곳을
# 지정하면 그대로 돌아갑니다.
#
# 통신 계층(APB CSR / AHB 적재기 / RVX wrapper) 회귀는 여기 없습니다.
# 그쪽은 나중에 따로 붙습니다. 여기 있는 것은 전부 Main IP 와 DRAM 경로
# 자체를 보는 것입니다.

BUILD    ?= /tmp/dram_build

RTL_DIR   = ../src
V2_DIR    = ../src_v2
TB_DIR    = ../testbench
CSR_DIR   = ../../software/csr/generated
BRAM_V2   = ../../hardware_bram/src_v2

# 합성 경로에 들어가는 코어 파일만 적습니다. glob 을 쓰면 안 됩니다.
DRAM_CORE = $(V2_DIR)/lpsoc_bbht_grover_main_ip.v \
            $(V2_DIR)/grover_arithmetic.v \
            $(V2_DIR)/grover_dram_random.v \
            $(V2_DIR)/grover_dram_amp_store.v \
            $(V2_DIR)/grover_dram_prep_seq.v \
            $(V2_DIR)/grover_dram_queue.v \
            $(V2_DIR)/grover_dram_shot_fsm.v \
            $(V2_DIR)/grover_iteration.v \
            $(V2_DIR)/grover_loader.v \
            $(V2_DIR)/grover_measurement.v \
            $(V2_DIR)/grover_memories.v \
            $(V2_DIR)/grover_status.v

# equiv 대조용. hardware_bram 쪽은 읽기만 하고 절대 고치지 않습니다.
BRAM_CORE = $(BRAM_V2)/lpsoc_bbht_grover_main_ip.v \
            $(BRAM_V2)/grover_arithmetic.v $(BRAM_V2)/grover_bbht.v \
            $(BRAM_V2)/grover_checkpoint.v $(BRAM_V2)/grover_iteration.v \
            $(BRAM_V2)/grover_loader.v $(BRAM_V2)/grover_measurement.v \
            $(BRAM_V2)/grover_memories.v $(BRAM_V2)/grover_policy.v \
            $(BRAM_V2)/grover_status.v

VFLAGS    = -Wno-fatal -Wno-DECLFILENAME -I$(V2_DIR) -I$(TB_DIR)
BRAMFLAGS = -Wno-fatal -Wno-DECLFILENAME -I$(BRAM_V2) -I$(TB_DIR)

# DRAM 지연 두 벌. 실물 MIG 지연을 알게 되면 SLOW 쪽 숫자만 바꾸면 됩니다.
FAST = -GWR_LAT=0 -GRD_LAT=1  -GBEAT_GAP=0 -GSTALL_EN=0
SLOW = -GWR_LAT=9 -GRD_LAT=31 -GBEAT_GAP=1 -GSTALL_EN=1

.PHONY: all regress ports lint store prep core equiv clean

all: regress

regress: ports lint store prep core

#---------------------------------------------------------------------
# 포트 계약. hardware_bram 과 같은 wrapper 19 + core 61 을 지켜야 합니다.
#---------------------------------------------------------------------
ports:
	@python3 ../../software/contract/check_ports.py dram

#---------------------------------------------------------------------
# 합성 대상만 lint. 테스트벤치와 DRAM 모델은 뺍니다.
#
# hardware_bram 의 lint-real 과 같은 이유로 -Wall 을 안 씁니다. src_v2 의
# 재사용 파일들이 원래 내는 폭 경고가 수십 건이라 회귀가 거기서 멈춥니다.
#---------------------------------------------------------------------
lint:
	@verilator --lint-only -Wno-DECLFILENAME \
	          -Wno-WIDTHEXPAND -Wno-WIDTHTRUNC -Wno-LATCH -Wno-UNOPTFLAT \
	          -Wno-CMPCONST \
	          -I$(CSR_DIR) -I$(V2_DIR) -I$(TB_DIR) \
	          $(RTL_DIR)/bbht_rvx_wrapper.v $(RTL_DIR)/bbht_grover_mmio.v \
	          $(RTL_DIR)/bbht_ahb_loader.v $(RTL_DIR)/bbht_grover_core_adapter.v \
	          $(DRAM_CORE) --top-module bbht_rvx_wrapper
	@echo "lint 통과"

#---------------------------------------------------------------------
# store/restore 단위. 지연 0 과 백프레셔 두 벌을 다 돌립니다.
#
# 두 벌이 필요한 이유: amp_store 의 STORE FSM 은 dram_wr_valid 를 든 채
# ready 를 기다리는 동안 amp_mem 의 읽기 출력이 유지된다는 전제로 짜여
# 있습니다. 지연 0 모델에서는 그 전제가 시험되지 않습니다.
#---------------------------------------------------------------------
STORE_SRCS = $(TB_DIR)/tb_dram_amp_store.v $(TB_DIR)/dram_burst_model.v \
             $(V2_DIR)/grover_dram_amp_store.v $(V2_DIR)/grover_memories.v

store:
	@mkdir -p $(BUILD)
	@verilator --binary --timing $(VFLAGS) $(FAST) $(STORE_SRCS) \
	          --top-module tb_dram_amp_store --Mdir $(BUILD)/store_fast -o sim \
	          > $(BUILD)/store_fast_build.log 2>&1 \
	          || { tail -30 $(BUILD)/store_fast_build.log; exit 1; }
	@$(BUILD)/store_fast/sim | tee $(BUILD)/store_fast.log
	@grep -q '^PASS' $(BUILD)/store_fast.log || { echo "store (지연 0) 실패"; exit 1; }
	@verilator --binary --timing $(VFLAGS) $(SLOW) $(STORE_SRCS) \
	          --top-module tb_dram_amp_store --Mdir $(BUILD)/store_slow -o sim \
	          > $(BUILD)/store_slow_build.log 2>&1 \
	          || { tail -30 $(BUILD)/store_slow_build.log; exit 1; }
	@$(BUILD)/store_slow/sim | tee $(BUILD)/store_slow.log
	@grep -q '^PASS' $(BUILD)/store_slow.log || { echo "store (백프레셔) 실패"; exit 1; }

#---------------------------------------------------------------------
# prep 시퀀서 단위. 이 갈래가 K/H 를 안 쓴다는 주장이 걸린 자리입니다.
#---------------------------------------------------------------------
PREP_SRCS = $(TB_DIR)/tb_dram_prep_seq.v $(TB_DIR)/dram_burst_model.v \
            $(V2_DIR)/grover_dram_prep_seq.v $(V2_DIR)/grover_dram_amp_store.v \
            $(V2_DIR)/grover_dram_queue.v $(V2_DIR)/grover_memories.v

prep:
	@mkdir -p $(BUILD)
	@verilator --binary --timing $(VFLAGS) $(PREP_SRCS) \
	          --top-module tb_dram_prep_seq --Mdir $(BUILD)/prep -o sim \
	          > $(BUILD)/prep_build.log 2>&1 \
	          || { tail -30 $(BUILD)/prep_build.log; exit 1; }
	@$(BUILD)/prep/sim | tee $(BUILD)/prep.log
	@grep -q '^PASS' $(BUILD)/prep.log || { echo "prep 실패"; exit 1; }
	@verilator --binary --timing $(VFLAGS) $(SLOW) $(PREP_SRCS) \
	          --top-module tb_dram_prep_seq --Mdir $(BUILD)/prep_slow -o sim \
	          > $(BUILD)/prep_slow_build.log 2>&1 \
	          || { tail -30 $(BUILD)/prep_slow_build.log; exit 1; }
	@$(BUILD)/prep_slow/sim | tee $(BUILD)/prep_slow.log
	@grep -q '^PASS' $(BUILD)/prep_slow.log || { echo "prep (백프레셔) 실패"; exit 1; }

#---------------------------------------------------------------------
# Main IP 통합.
#---------------------------------------------------------------------
CORE_SRCS = $(TB_DIR)/tb_dram_core.v $(TB_DIR)/dram_burst_model.v $(DRAM_CORE)

core:
	@mkdir -p $(BUILD)
	@verilator --binary --timing $(VFLAGS) -DGD_DRAM_BRANCH $(CORE_SRCS) \
	          --top-module tb_dram_core --Mdir $(BUILD)/core -o sim \
	          > $(BUILD)/core_build.log 2>&1 \
	          || { tail -30 $(BUILD)/core_build.log; exit 1; }
	@$(BUILD)/core/sim | tee $(BUILD)/core_dram.log
	@grep -q '^PASS' $(BUILD)/core_dram.log || { echo "core 실패"; exit 1; }

#---------------------------------------------------------------------
# 궤적 대조. 같은 테스트벤치를 hardware_bram Main IP 에도 물려서
# 세 벌(dram / bram Normal / bram K4H4)을 같은 자극으로 돌립니다.
#
# 이게 이 갈래의 정합성 근거입니다. 보드에서 검증된 v0.9.8 과 답도 궤적도
# 같아야 하고, 비용만 달라야 합니다.
#---------------------------------------------------------------------
equiv: core
	@mkdir -p $(BUILD)
	@verilator --binary --timing $(BRAMFLAGS) -GCKPT_AUTO=0 $(TB_DIR)/tb_dram_core.v $(BRAM_CORE) \
	          --top-module tb_dram_core --Mdir $(BUILD)/core_bram -o sim \
	          > $(BUILD)/core_bram_build.log 2>&1 \
	          || { tail -30 $(BUILD)/core_bram_build.log; exit 1; }
	@$(BUILD)/core_bram/sim | tee $(BUILD)/core_bram.log
	@verilator --binary --timing $(BRAMFLAGS) -GCKPT_AUTO=1 $(TB_DIR)/tb_dram_core.v $(BRAM_CORE) \
	          --top-module tb_dram_core --Mdir $(BUILD)/core_k4h4 -o sim \
	          > $(BUILD)/core_k4h4_build.log 2>&1 \
	          || { tail -30 $(BUILD)/core_k4h4_build.log; exit 1; }
	@$(BUILD)/core_k4h4/sim | tee $(BUILD)/core_k4h4.log
	@python3 equiv_report.py $(BUILD)/core_dram.log $(BUILD)/core_bram.log \
	                         $(BUILD)/core_k4h4.log

clean:
	rm -rf $(BUILD)
