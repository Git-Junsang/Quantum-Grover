# 200 MHz 판(hardware_bram/configurations/final_200mhz) 회귀. verilator 로 빌드하고 돌립니다.
#
#   make lint            통신 계층 + 어댑터 + Main IP lint (이 판 소스)
#   make real            통신 계약 회귀 T1~T10 (tb_bbht_rvx, 열거 포함)를 이 판 소스로
#   make driver          펌웨어 드라이버(bbht_grover_driver.c)를 붙인 공동 시뮬 (tb_driver)
#   make predicate500    네 술어 x 500 워크로드 Normal + 체크포인트를 SW 기준모델과 대조
#                        (술어 넷 동시, 40분~1시간)
#   make predicate500-ref
#                        같은 워크로드를 보드 정본 구성 K3/H3-E4-M2(공용 src, 100 MHz 판)로
#   make equiv           위 두 결과를 실행마다 맞댐. 사이클을 뺀 전 열이 같아야 하고,
#                        사이클은 두 판의 비를 보고합니다
#   QUICK=<시드 수>      셋 다 시드를 앞에서부터 이만큼만 돌립니다 (예: QUICK=10 이면 400 실행,
#                        몇 분). 보고기는 --partial 로 돕니다
#   make clean
#
# 이 판의 소스
#
#   200 MHz 에 맞추려고 레지스터 경계를 더한 RTL 은 ../src/ 에 있고, 거기 없는 파일은
#   공용 hardware_bram/src/ 의 것을 그대로 씁니다(OVERLAY). 모델 파라미터는 보드 정본과
#   같은 K3/H3-E4-M2 이고 어댑터도 같은 내용입니다.
#
#   더한 레지스터 경계는 지연만 늘리고 값을 바꾸지 않아야 합니다. 그래서 equiv 가 이 판의
#   핵심 근거입니다 -- 결과 인덱스 · 시도 수 · REQUESTED_ITERATIONS · 물리 반복 · STATUS 가 100 MHz 판과
#   실행마다 같고, 사이클만 달라야 합니다.
#
# 빌드 디렉터리를 /tmp 로 빼는 이유는 hardware_bram/sim/Makefile 머리말과 같습니다 (저장소 경로의 공백).

BRAM_DIR  = ../../..
REPO_DIR  = $(BRAM_DIR)/..
SRC_DIR   = $(BRAM_DIR)/src
MODEL_SRC = ../src
TB_DIR    = $(BRAM_DIR)/testbench
FW_DIR    = $(BRAM_DIR)/firmware
CSR_DIR   = $(REPO_DIR)/spec/generated
ADAPTER   = $(MODEL_SRC)/bbht_grover_core_adapter.v
REF_ADAPTER = ../../final/src/bbht_grover_core_adapter.v

# hardware_bram/sim/Makefile 의 CORE_FILES 와 같은 열 개 + 통신 계층 셋입니다.
CORE_FILES = bbht_grover_main_ip.v \
             grover_arithmetic.v grover_bbht.v grover_checkpoint.v \
             grover_iteration.v grover_loader.v grover_measurement.v \
             grover_memories.v grover_policy.v grover_status.v
COMM_FILES = bbht_rvx_wrapper.v bbht_grover_mmio.v bbht_ahb_loader.v

# 이 판에 있으면 이 판 것, 없으면 공용 것.
pick       = $(if $(wildcard $(MODEL_SRC)/$(1)),$(MODEL_SRC)/$(1),$(SRC_DIR)/$(1))
SRCS_200   = $(foreach f,$(COMM_FILES) $(CORE_FILES),$(call pick,$(f)))
SRCS_REF   = $(addprefix $(SRC_DIR)/,$(COMM_FILES) $(CORE_FILES))

FROZEN_WNO = -Wno-DECLFILENAME -Wno-WIDTHEXPAND -Wno-WIDTHTRUNC \
             -Wno-LATCH -Wno-UNOPTFLAT -Wno-CMPCONST

.PHONY: csr lint real driver predicate500 predicate500-ref predicate500-wl equiv clean overlay

csr:
	@python3 $(REPO_DIR)/spec/gen_csr.py > /dev/null

# 어느 파일이 이 판 것인지 찍습니다.
overlay:
	@for f in $(COMM_FILES) $(CORE_FILES); do \
	     if [ -f $(MODEL_SRC)/$$f ]; then echo "  200MHz  $$f"; else echo "  공용    $$f"; fi; done

# 어댑터를 /tmp 로 복사해 절대경로로 넘깁니다 (no_checkpoint_baseline 판 sim/Makefile 의 adapter-tmp 와 같은 이유).
LINT_DIR = /tmp/sjs_200m_lint
lint: csr
	@rm -rf $(LINT_DIR); mkdir -p $(LINT_DIR)
	@cp $(SRCS_200) $(ADAPTER) $(LINT_DIR)/
	verilator --lint-only $(FROZEN_WNO) -I$(CSR_DIR) -I$(SRC_DIR) \
	          $(addprefix $(LINT_DIR)/,$(COMM_FILES) $(CORE_FILES) bbht_grover_core_adapter.v) \
	          --top-module bbht_rvx_wrapper
	@echo "lint 통과 (통신 계층 + 어댑터 + Main IP, 200 MHz 판)"

#---------------------------------------------------------------------
# 통신 계약 회귀와 드라이버 공동 시뮬 -- hardware_bram/sim 의 real · driver 와 같은
# 테스트벤치를 이 판 소스로 빌드합니다. 소스를 /tmp 로 모으는 이유는 lint 와 같습니다.
#---------------------------------------------------------------------
CORE_DEFS  = -DGUARD_POLLS=3000000 -DSIM_TIMEOUT_NS=4000_000_000
REAL_BUILD = /tmp/sjs_200m_real
DRV_BUILD  = /tmp/sjs_200m_drv
DRV_DEFS   = -DBBHT_HOST_TEST -DBBHT_NO_PRINTF -DBBHT_TIMEOUT=20000000

real: csr
	@rm -rf $(REAL_BUILD); mkdir -p $(REAL_BUILD)/src
	@cp $(SRCS_200) $(ADAPTER) $(TB_DIR)/tb_bbht_rvx.v $(TB_DIR)/ahb_sram_model.v \
	    $(SRC_DIR)/grover_param.vh $(CSR_DIR)/bbht_grover_csr.vh $(REAL_BUILD)/src/
	@verilator --binary --timing -Wno-fatal -Wno-DECLFILENAME -I$(REAL_BUILD)/src $(CORE_DEFS) \
	     $(REAL_BUILD)/src/tb_bbht_rvx.v \
	     $(addprefix $(REAL_BUILD)/src/,$(COMM_FILES) bbht_grover_core_adapter.v $(CORE_FILES)) \
	     $(REAL_BUILD)/src/ahb_sram_model.v --top-module tb_bbht_rvx \
	     --Mdir $(REAL_BUILD) -o sim_real > $(REAL_BUILD)/build.log 2>&1 \
	     || { tail -20 $(REAL_BUILD)/build.log; exit 1; }
	@$(REAL_BUILD)/sim_real

driver: csr
	@rm -rf $(DRV_BUILD); mkdir -p $(DRV_BUILD)/src
	@cp $(SRCS_200) $(ADAPTER) $(TB_DIR)/tb_driver.cpp $(SRC_DIR)/grover_param.vh \
	    $(CSR_DIR)/bbht_grover_csr.vh $(CSR_DIR)/bbht_grover_regs.h \
	    $(FW_DIR)/bbht_grover_driver.c $(FW_DIR)/bbht_grover_driver.h $(DRV_BUILD)/src/
	@gcc -c -O2 $(DRV_DEFS) -I$(DRV_BUILD)/src $(DRV_BUILD)/src/bbht_grover_driver.c -o $(DRV_BUILD)/driver.o
	@verilator --cc --exe --build -Wno-fatal -Wno-DECLFILENAME --Mdir $(DRV_BUILD)/obj \
	     -CFLAGS "$(DRV_DEFS) -I$(DRV_BUILD)/src" -LDFLAGS "$(DRV_BUILD)/driver.o" -I$(DRV_BUILD)/src \
	     $(addprefix $(DRV_BUILD)/src/,$(COMM_FILES) bbht_grover_core_adapter.v $(CORE_FILES)) \
	     --top-module bbht_rvx_wrapper $(DRV_BUILD)/src/tb_driver.cpp \
	     -o sim_drv > $(DRV_BUILD)/build.log 2>&1 || { tail -20 $(DRV_BUILD)/build.log; exit 1; }
	@$(DRV_BUILD)/obj/sim_drv

#---------------------------------------------------------------------
# Predicate500
#
# 하네스 · 자극 · 기댓값 · 보고기는 hardware_bram/ 공용입니다. 두 판을 같은 함수로
# 만들고 다른 것은 소스 목록뿐입니다 ($(1) = 빌드 폴더, $(2) = 소스, $(3) = 어댑터).
#---------------------------------------------------------------------
PRED500_WL     = /tmp/sjs_pred500_wl
PRED500_PREDS ?= LT GT EQ RANGE
BENCH_DEFS     = -DBBHT_HOST_TEST -DBBHT_NO_PRINTF -DBBHT_TIMEOUT=200000000
BUILD_200      = /tmp/sjs_pred500_200m
BUILD_REF      = /tmp/sjs_pred500_200m_ref

# QUICK=<n> 이면 시드를 앞에서 n 개만 쓰는 자극 폴더를 따로 만듭니다(데이터셋은 공용 것을 가리킴).
QUICK         ?=
WL_RUN         = $(if $(QUICK),/tmp/sjs_pred500_wl_q$(QUICK),$(PRED500_WL))
PARTIAL        = $(if $(QUICK),--partial,)

define pred500_build
	@rm -rf $(1); mkdir -p $(1)/src
	@cp $(TB_DIR)/tb_predicate500.cpp $(2) $(1)/src/
	@cp $(3) $(1)/src/bbht_grover_core_adapter.v
	@cp $(SRC_DIR)/grover_param.vh $(1)/src/
	@cp $(CSR_DIR)/bbht_grover_csr.vh $(CSR_DIR)/bbht_grover_regs.h $(1)/src/
	@cp $(FW_DIR)/bbht_grover_driver.c $(FW_DIR)/bbht_grover_driver.h $(1)/src/
	@gcc -c -O2 $(BENCH_DEFS) -I$(1)/src $(1)/src/bbht_grover_driver.c -o $(1)/driver.o
	@verilator --cc --exe --build -j 4 -Wno-fatal -Wno-DECLFILENAME \
	     --Mdir $(1)/obj \
	     -CFLAGS "$(BENCH_DEFS) -I$(1)/src -O2" \
	     -LDFLAGS "$(1)/driver.o" -I$(1)/src \
	     $(foreach f,$(COMM_FILES) $(CORE_FILES) bbht_grover_core_adapter.v,$(1)/src/$(f)) \
	     --top-module bbht_rvx_wrapper $(1)/src/tb_predicate500.cpp \
	     -o bench > $(1)/build.log 2>&1 \
	     || { tail -20 $(1)/build.log; exit 1; }
endef

define pred500_run
	@echo "Predicate500 실행 중 ($(PRED500_PREDS) 동시$(if $(QUICK), · 시드 $(QUICK)개,)) -> $(1)"
	@pids=""; for p in $(PRED500_PREDS); do \
	     WL_DIR=$(WL_RUN) WL_LIST=$(PRED500_WL)/workloads_$$p.txt \
	         $(1)/obj/bench > $(1)/pred_$$p.csv \
	         2> $(1)/pred_$$p.log & pids="$$pids $$!"; \
	 done; rc=0; for pid in $$pids; do wait $$pid || rc=1; done; exit $$rc
	@python3 $(BRAM_DIR)/sim/predicate500_report.py --branch bram $(PARTIAL) \
	     $(foreach p,$(PRED500_PREDS),$(1)/pred_$(p).csv) \
	     | tee $(1)/report.txt
endef

predicate500-wl:
	@test -f $(PRED500_WL)/seeds.txt || \
	     python3 $(REPO_DIR)/software/reference_model_develop/tb_stimulus/dump_predicate500_workload.py --out $(PRED500_WL)
	@if [ -n "$(QUICK)" ]; then mkdir -p $(WL_RUN) && \
	     head -n $(QUICK) $(PRED500_WL)/seeds.txt > $(WL_RUN)/seeds.txt; fi

predicate500: csr predicate500-wl
	$(call pred500_build,$(BUILD_200),$(SRCS_200),$(ADAPTER))
	$(call pred500_run,$(BUILD_200))

predicate500-ref: csr predicate500-wl
	$(call pred500_build,$(BUILD_REF),$(SRCS_REF),$(REF_ADAPTER))
	$(call pred500_run,$(BUILD_REF))

equiv:
	@python3 equiv_check.py $(BUILD_200) $(BUILD_REF) $(PRED500_PREDS)

clean:
	rm -rf $(LINT_DIR) $(BUILD_200) $(BUILD_REF) $(REAL_BUILD) $(DRV_BUILD)
