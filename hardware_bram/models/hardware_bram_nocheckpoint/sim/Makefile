# 체크포인트 없는 판(hardware_bram/models/hardware_bram_nocheckpoint) 회귀. verilator 로 빌드하고 돌립니다.
#
#   make                 ports + lint + real (몇 분)
#   make ports           포트 계약(wrapper 19 + core 61)을 이 판 어댑터로 대조
#   make lint            통신 계층 + 이 판의 어댑터 + Main IP lint
#   make real            통신 계약 T1~T9 를 실물 코어(이 판 구성)로
#   make predicate500    네 술어 x 500 워크로드 Normal 을 SW 기준모델과 대조
#                        (술어 넷 동시, 2분쯤)
#   make predicate500-ref
#                        같은 워크로드를 K3/H3-E4 모델(체크포인트 판을
#                        M1=M2=0 으로 둔 것)로 Normal 로 돌린 기준값 (2분쯤)
#   make equiv           위 두 결과를 실행마다 전 열 대조 (predicate500 과
#                        predicate500-ref 를 먼저 돌려 두어야 합니다)
#   make clean
#
# 이 판은 소스를 거의 갖지 않습니다. Main IP 와 통신 계층은 공용
# hardware_bram/src/ 의 것을 그대로 쓰고, 이 판의 것은 파라미터와
# burst 처리만 다른 어댑터(../src/bbht_grover_core_adapter.v) 하나입니다.
# 테스트벤치와 보고 스크립트도 hardware_bram/ 공용 것을 씁니다.
#
# equiv 가 이 판의 핵심 근거입니다. 체크포인트 판의 NORMAL 은 E4 진폭 메모리의
# 슬롯 0 만 쓰므로, 체크포인트 하드웨어를 generate 로 뺀 이 판의 NORMAL 과
# 사이클까지 같아야 합니다. 같다면 "체크포인트를 뺀 것 말고는 바뀐 것이
# 없다" 가 실행 2,000 개로 확인됩니다.
#
# 빌드 디렉터리를 /tmp 로 빼는 이유는 hardware_bram/sim/Makefile
# 머리말과 같습니다 (저장소 경로의 공백).

BRAM_DIR  = ../../..
REPO_DIR  = $(BRAM_DIR)/..
SRC_DIR   = $(BRAM_DIR)/src
TB_DIR    = $(BRAM_DIR)/testbench
FW_DIR    = $(BRAM_DIR)/firmware
CSR_DIR   = $(REPO_DIR)/software/contract/generated
ADAPTER   = ../src/bbht_grover_core_adapter.v
# predicate500-ref 의 기준. 체크포인트 판(K3/H3-E4-M2)에서 M1/M2 만 끈 모델입니다.
REF_ADAPTER = ../../hardware_bram_K3H3_E4/src/bbht_grover_core_adapter.v

# hardware_bram/sim/Makefile 의 CORE_FILES 와 같은 열 개입니다.
CORE_FILES = bbht_grover_main_ip.v \
             grover_arithmetic.v grover_bbht.v grover_checkpoint.v \
             grover_iteration.v grover_loader.v grover_measurement.v \
             grover_memories.v grover_policy.v grover_status.v
CORE_SRCS  = $(addprefix $(SRC_DIR)/,$(CORE_FILES))
COMM_LAYER = $(SRC_DIR)/bbht_rvx_wrapper.v $(SRC_DIR)/bbht_grover_mmio.v \
             $(SRC_DIR)/bbht_ahb_loader.v

FROZEN_WNO = -Wno-DECLFILENAME -Wno-WIDTHEXPAND -Wno-WIDTHTRUNC \
             -Wno-LATCH -Wno-UNOPTFLAT -Wno-CMPCONST
CORE_DEFS  = -DGUARD_POLLS=3000000 -DSIM_TIMEOUT_NS=4000_000_000

.PHONY: all csr ports adapter-tmp lint real predicate500 predicate500-ref equiv clean

all: ports lint real

csr:
	@python3 $(REPO_DIR)/software/contract/gen_csr.py > /dev/null

ports:
	@python3 $(REPO_DIR)/software/contract/check_ports.py real nocheckpoint

# 어댑터를 /tmp 로 복사해 절대경로로 넘깁니다. verilator 는 상대경로 파일을
# -I 디렉터리 기준으로 먼저 찾아서, ../src/bbht_grover_core_adapter.v 를 넘기면
# -I$(SRC_DIR) 기준의 다른 어댑터를 집어 올 수 있습니다 (2026-09-25 에 이것으로
# real 이 체크포인트 판으로 돌았습니다). 2026-10-06 부터 공용 src/ 에는 어댑터가
# 없어 그 일은 다시 안 생기지만, 같은 이름 파일이 다시 생겨도 안전하도록 둡니다.
ADAPTER_TMP = /tmp/sjs_nockpt_adapter/bbht_grover_core_adapter.v
adapter-tmp:
	@mkdir -p $(dir $(ADAPTER_TMP)) && cp $(ADAPTER) $(ADAPTER_TMP)
	@grep -q "CHECKPOINT_ENABLE  = 0" $(ADAPTER_TMP) \
	     || { echo "체크포인트 없는 어댑터가 아닙니다: $(ADAPTER_TMP)"; exit 1; }

lint: csr adapter-tmp
	verilator --lint-only $(FROZEN_WNO) -I$(CSR_DIR) -I$(SRC_DIR) \
	          $(COMM_LAYER) $(ADAPTER_TMP) $(CORE_SRCS) --top-module bbht_rvx_wrapper
	@echo "lint 통과 (통신 계층 + 체크포인트 없는 어댑터 + Main IP)"

REAL_BUILD = /tmp/sjs_nockpt_real
real: csr adapter-tmp
	@mkdir -p $(REAL_BUILD)
	verilator --binary --timing -Wno-fatal -Wno-DECLFILENAME \
	          -I$(CSR_DIR) -I$(SRC_DIR) -I$(TB_DIR) $(CORE_DEFS) \
	          $(TB_DIR)/tb_bbht_rvx.v $(COMM_LAYER) $(ADAPTER_TMP) $(CORE_SRCS) \
	          $(TB_DIR)/ahb_sram_model.v --top-module tb_bbht_rvx \
	          --Mdir $(REAL_BUILD) -o sim_real > $(REAL_BUILD)/build.log 2>&1 \
	    || { tail -20 $(REAL_BUILD)/build.log; exit 1; }
	@$(REAL_BUILD)/sim_real

#---------------------------------------------------------------------
# Predicate500 (Normal 만)
#
# 하네스·자극·기댓값·보고기는 hardware_bram/ 공용입니다. PRED500_MODES=normal
# 로 Normal 만 돌리고, 보고기는 --branch nocheckpoint 로 물리 반복을 기준모델
# NORMAL 열과 맞댑니다.
#
# 두 판을 같은 함수로 만듭니다 ($(1) = 빌드 폴더). 다른 것은 어댑터뿐입니다.
# predicate500-ref 의 어댑터는 K3H3_E4 모델의 것입니다. 2026-10-06 전에는
# 체크포인트 판 어댑터에서 M1/M2 기본값만 sed 로 0 으로 바꾼 사본을 빌드
# 폴더에서 만들었는데, 그 사본과 K3H3_E4 모델 어댑터는 파라미터 기본값이
# 같고 본문도 같습니다.
#---------------------------------------------------------------------
PRED500_WL    = /tmp/sjs_pred500_wl
PRED500_PREDS ?= LT GT EQ RANGE
BENCH_DEFS    = -DBBHT_HOST_TEST -DBBHT_NO_PRINTF -DBBHT_TIMEOUT=200000000
NOCKPT_BUILD  = /tmp/sjs_pred500_nockpt
REF_BUILD     = /tmp/sjs_pred500_ckpt_m0

# pred500_prep: 빌드 폴더를 새로 만들고 공통 소스와 드라이버를 모읍니다.
#               어댑터는 부르는 쪽이 $(1)/src/ 에 따로 넣습니다.
# pred500_obj : 모은 소스로 벤치 실행 파일을 만듭니다 (체크포인트 판과 같은 플래그).
define pred500_prep
	@rm -rf $(1); mkdir -p $(1)/src
	@cp $(TB_DIR)/tb_predicate500.cpp $(COMM_LAYER) $(CORE_SRCS) $(1)/src/
	@cp $(SRC_DIR)/grover_param.vh $(1)/src/
	@cp $(CSR_DIR)/bbht_grover_csr.vh $(CSR_DIR)/bbht_grover_regs.h $(1)/src/
	@cp $(FW_DIR)/bbht_grover_driver.c $(FW_DIR)/bbht_grover_driver.h $(1)/src/
	@gcc -c -O2 $(BENCH_DEFS) -I$(1)/src $(1)/src/bbht_grover_driver.c -o $(1)/driver.o
endef

define pred500_obj
	@verilator --cc --exe --build -j 4 -Wno-fatal -Wno-DECLFILENAME \
	     --Mdir $(1)/obj \
	     -CFLAGS "$(BENCH_DEFS) -I$(1)/src -O2" \
	     -LDFLAGS "$(1)/driver.o" -I$(1)/src \
	     $(foreach f,$(notdir $(COMM_LAYER) $(CORE_SRCS)),$(1)/src/$(f)) \
	     $(1)/src/bbht_grover_core_adapter.v \
	     --top-module bbht_rvx_wrapper $(1)/src/tb_predicate500.cpp \
	     -o bench > $(1)/build.log 2>&1 \
	     || { tail -20 $(1)/build.log; exit 1; }
endef

define pred500_run
	@echo "Predicate500 Normal 실행 중 ($(PRED500_PREDS) 동시) -> $(1)"
	@pids=""; for p in $(PRED500_PREDS); do \
	     PRED500_MODES=normal WL_DIR=$(PRED500_WL) WL_LIST=$(PRED500_WL)/workloads_$$p.txt \
	         $(1)/obj/bench > $(1)/pred_$$p.csv \
	         2> $(1)/pred_$$p.log & pids="$$pids $$!"; \
	 done; rc=0; for pid in $$pids; do wait $$pid || rc=1; done; exit $$rc
endef

predicate500-wl:
	@python3 $(REPO_DIR)/software/rtl_vectors/tools/dump_predicate500_workload.py --out $(PRED500_WL)

predicate500: csr predicate500-wl
	$(call pred500_prep,$(NOCKPT_BUILD))
	@cp $(ADAPTER) $(NOCKPT_BUILD)/src/bbht_grover_core_adapter.v
	$(call pred500_obj,$(NOCKPT_BUILD))
	$(call pred500_run,$(NOCKPT_BUILD))
	@python3 $(BRAM_DIR)/sim/predicate500_report.py --branch nocheckpoint \
	     $(foreach p,$(PRED500_PREDS),$(NOCKPT_BUILD)/pred_$(p).csv) \
	     | tee $(NOCKPT_BUILD)/report.txt

predicate500-ref: csr predicate500-wl
	$(call pred500_prep,$(REF_BUILD))
	@cp $(REF_ADAPTER) $(REF_BUILD)/src/bbht_grover_core_adapter.v
	@grep -q "CHECKPOINT_ENABLE  = 1" $(REF_BUILD)/src/bbht_grover_core_adapter.v \
	     && grep -q "MEAS_M2_ENABLE     = 0" $(REF_BUILD)/src/bbht_grover_core_adapter.v \
	     || { echo "기준 어댑터가 K3/H3-E4(M1=M2=0) 가 아닙니다"; exit 1; }
	$(call pred500_obj,$(REF_BUILD))
	$(call pred500_run,$(REF_BUILD))
	@python3 $(BRAM_DIR)/sim/predicate500_report.py --branch bram \
	     $(foreach p,$(PRED500_PREDS),$(REF_BUILD)/pred_$(p).csv) \
	     | tee $(REF_BUILD)/report.txt

equiv:
	@python3 equiv_check.py $(NOCKPT_BUILD) $(REF_BUILD) $(PRED500_PREDS)

clean:
	rm -rf $(REAL_BUILD) $(NOCKPT_BUILD) $(REF_BUILD)
