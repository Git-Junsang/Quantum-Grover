# 통신 계층 회귀. verilator 로 빌드하고 돌립니다.
#
#   make        스텁 갈래 회귀 (몇 초)
#   make real   통신 계층 + 어댑터 + Main IP
#   make top    최상단 bbht_bram_top 회귀 (Q14 전체 적재, NORMAL/CKPT 짝,
#               열거까지. 빌드 포함 1분 30초쯤)
#   make lint   lint 만
#   make bench250 / bench500
#               250쌍 / 500 워크로드 궤적 벤치 (20분 / 40분쯤)
#   make predicate500
#               네 술어 x 500 워크로드를 SW 기준모델과 대조 (40분~1시간)
#   make console-gen
#               콘솔 GEN 생성기가 SW 생성기와 같은 배열을 내는지 (몇 초)
#   make console-seq
#               SoC 시뮬 bbht_console 스크립트와 같은 순서의 기준값 (30초쯤)
#   make ports-models / lint-models
#               모델 열 개의 어댑터 전부를 포트 계약 · lint 로 확인 (lint 는 몇 분)
#   make clean
#
# 어느 모델을 물리는가 -- MODEL
#
#   hardware_bram/ 의 src · testbench · firmware 는 모든 모델이 같이 씁니다.
#   모델마다 다른 것은 models/hardware_bram_<모델>/src/bbht_grover_core_adapter.v
#   하나(K·H·E·M 파라미터 기본값)라서, 어댑터가 들어가는 타깃(real · bench250 ·
#   bench500 · predicate500 · console-seq)은 MODEL 로 고릅니다. 기본값은 보드
#   정본 구성 K3H3_E4_M2 입니다.
#
#     make real MODEL=K4H4_E4
#
#   보고 스크립트(bench250/500_report.py, predicate500_report.py --branch bram)의
#   비교 상대는 K3H3_E4_M2 의 보드 실측과 K3/H3 기준모델이라, 다른 모델로 돌린
#   bench · predicate500 은 논리 궤적만 맞고 물리 반복 · 사이클은 어긋나는 것이
#   정상입니다. 체크포인트를 끈 모델(Normal_E1 · nocheckpoint)의 Predicate500 은
#   models/hardware_bram_nocheckpoint/sim/Makefile 을 쓰십시오.
#   bbht_bram_top(make top)은 어댑터 없이 Main IP 를 직접 물어 MODEL 과 무관하게
#   K3/H3-E4-M2 입니다.
#
# 갈래가 둘인 이유는 코어 자리에 무엇을 끼우느냐입니다. 통신 계층(wrapper·
# mmio·loader)은 두 갈래 모두 src/ 의 같은 파일이고, 계약 이름
# bbht_grover_core 를 뭅니다.
#
#   stub   자리 채우개(testbench/bbht_grover_core_stub.v). 탐색 없이 몇 초 만에
#          통신 계약만 봅니다
#   real   모델 어댑터(models/hardware_bram_<MODEL>/src/) + Main IP. 실제 탐색까지 돕니다
#
# 2026-09-13 전에는 보드에 구운 정본 통신 계층을 따로 두고 make final 로
# 돌렸습니다. 그 판은 태그 board-k3h3-e4-m2 에 있습니다.
#
# 빌드 디렉터리를 저장소 밖으로 빼는 이유가 있습니다. 이 저장소 경로에
# "중앙대학교 학부인턴" 처럼 공백이 들어 있는데, verilator 가 만들어 주는
# Makefile 을 GNU Make 가 공백 있는 디렉터리에서 실행하지 못합니다
# ("Unsupported: GNU Make cannot build in directories containing spaces").
# --Mdir 로 공백 없는 곳을 지정하면 그대로 돌아갑니다.

BUILD    ?= /tmp/sjs_build
TOP       = tb_bbht_rvx
SIM       = $(BUILD)/sim_tb

SRC_DIR   = ../src
TB_DIR    = ../testbench
CSR_DIR   = ../../software/contract/generated

MODEL    ?= K3H3_E4_M2
MODEL_DIR = ../models/hardware_bram_$(MODEL)
ADAPTER   = $(MODEL_DIR)/src/bbht_grover_core_adapter.v
# 모델 열 개. 폴더 이름에서 hardware_bram_ 을 뗀 것입니다.
MODELS    = $(patsubst ../models/hardware_bram_%/src/bbht_grover_core_adapter.v,%,\
              $(sort $(wildcard ../models/hardware_bram_*/src/bbht_grover_core_adapter.v)))

# Main IP 중 합성 경로에 들어가는 열입니다. glob 을 쓰면 policy OOC
# 전용인 grover_policy_ooc_top.v 와 grover_policy_impl_wrapper.v 까지 딸려 와
# 최상위가 셋이 됩니다.
CORE_FILES = bbht_grover_main_ip.v \
             grover_arithmetic.v grover_bbht.v grover_checkpoint.v \
             grover_iteration.v grover_loader.v grover_measurement.v \
             grover_memories.v grover_policy.v grover_status.v
CORE_SRCS  = $(addprefix $(SRC_DIR)/,$(CORE_FILES))

COMM_LAYER = $(SRC_DIR)/bbht_rvx_wrapper.v $(SRC_DIR)/bbht_grover_mmio.v \
             $(SRC_DIR)/bbht_ahb_loader.v

SRCS = $(TB_DIR)/tb_bbht_rvx.v \
       $(COMM_LAYER) \
       $(TB_DIR)/bbht_grover_core_stub.v \
       $(TB_DIR)/ahb_sram_model.v

VFLAGS = -Wno-fatal -Wno-DECLFILENAME -I$(CSR_DIR) -I$(SRC_DIR) -I$(TB_DIR)

# 실물 코어가 낀 갈래는 탐색 한 번이 수십만 사이클이라 TB 의 폴링 상한과
# 워치독을 크게 열어 두어야 합니다.
CORE_DEFS = -DGUARD_POLLS=3000000 -DSIM_TIMEOUT_NS=4000_000_000

# Main IP 소스가 원래 내는 경고들입니다. 보드 정본과 같은 코드를 유지하려고
# 고치지 않으므로
# 기본 경고집합으로 두고 실제 오류(폭 불일치, 미해결 참조)만 잡습니다.
FROZEN_WNO = -Wno-DECLFILENAME -Wno-WIDTHEXPAND -Wno-WIDTHTRUNC \
             -Wno-LATCH -Wno-UNOPTFLAT -Wno-CMPCONST

.PHONY: all regress driver lint csr ports clean \
        ports-real lint-real regress-real driver-real real \
        top lint-top model-check ports-models lint-models

all: ports regress driver

# 통신 계층에 Main IP 를 어댑터로 끼운 갈래. 스텁보다 훨씬 오래 걸립니다.
real: ports-real lint-real regress-real driver-real

# CSR 헤더가 정본과 어긋나면 먼저 멈춥니다. 생성 헤더를 손으로 고쳐 놓고
# 회귀만 통과시키는 일을 막으려는 것입니다.
csr:
	@python3 ../../software/contract/gen_csr.py --check

# PJK 인수인계 §3.3/§3.4 포트 계약과 RTL 이 어긋나지 않았는지.
#   ports        스텁을 대조 (통신 계층만 볼 때)
#   ports-real   어댑터를 대조 (통신 계층에 Main IP 가 물린 상태)
ports:
	@python3 ../../software/contract/check_ports.py stub

ports-real: model-check
	@python3 ../../software/contract/check_ports.py real $(MODEL)

# MODEL 철자가 틀리면 verilator 가 "파일 없음" 으로 길게 죽기 전에 멈춥니다.
model-check:
	@test -f $(ADAPTER) || { echo "모델이 없습니다: $(MODEL) (있는 것: $(MODELS))"; exit 1; }

# 모델 열 개 전부. 어댑터를 새로 만들거나 고친 뒤 돌립니다.
ports-models:
	@for m in $(MODELS); do printf '%-14s ' $$m; \
	     python3 ../../software/contract/check_ports.py real $$m > /tmp/sjs_ports_$$m.log 2>&1 \
	     && tail -1 /tmp/sjs_ports_$$m.log \
	     || { echo "포트 계약 실패"; cat /tmp/sjs_ports_$$m.log; exit 1; }; done

lint-models: csr
	@for m in $(MODELS); do printf '%-14s ' $$m; \
	     verilator --lint-only $(FROZEN_WNO) -I$(CSR_DIR) -I$(SRC_DIR) \
	          $(COMM_LAYER) ../models/hardware_bram_$$m/src/bbht_grover_core_adapter.v \
	          $(CORE_SRCS) --top-module bbht_rvx_wrapper > /tmp/sjs_lint_$$m.log 2>&1 \
	     && echo "lint 통과" || { echo "lint 실패 (/tmp/sjs_lint_$$m.log)"; exit 1; }; done

regress: csr ports
	@mkdir -p $(BUILD)
	verilator --binary --timing $(VFLAGS) $(SRCS) --top-module $(TOP) \
	          --Mdir $(BUILD) -o sim_tb
	@$(SIM)

# 드라이버(bbht_grover_driver.c)를 그대로 컴파일해 RTL 에 붙입니다.
# 오프셋 어긋남, 폴링 순서, 열거 FIFO drain 을 여기서 잡습니다.
driver: csr ports
	@./run_driver_test.sh

# 합성 대상 RTL 만 봅니다. 테스트벤치와 모델은 뺍니다.
lint: csr ports
	verilator --lint-only -Wall -Wno-DECLFILENAME -Wno-UNUSEDSIGNAL \
	          -I$(CSR_DIR) -I$(SRC_DIR) -I$(TB_DIR) \
	          $(COMM_LAYER) $(TB_DIR)/bbht_grover_core_stub.v \
	          --top-module bbht_rvx_wrapper
	@echo "lint 통과"

clean:
	rm -rf $(BUILD) /tmp/sjs_build_real_* $(TOP_BUILD) \
	       /tmp/sjs_drv /tmp/sjs_drv_real_* /tmp/sjs_lint_*.log /tmp/sjs_ports_*.log

#---------------------------------------------------------------------
# 통신 계층 + 어댑터 + Main IP
#
# 모델 어댑터(models/hardware_bram_<모델>/src/bbht_grover_core_adapter.v)
# 가 모듈 이름(bbht_grover_main_ip -> bbht_grover_core)과 리셋 이름(rstn ->
# rstnn)만 맞춰 주고, 나머지 61신호는 1:1 입니다.
#---------------------------------------------------------------------
REAL_SRCS  = $(TB_DIR)/tb_bbht_rvx.v $(COMM_LAYER) \
             $(ADAPTER) \
             $(CORE_SRCS) $(TB_DIR)/ahb_sram_model.v

REAL_FLAGS = -Wno-fatal -Wno-DECLFILENAME -I$(CSR_DIR) -I$(SRC_DIR) \
             -I$(TB_DIR) $(CORE_DEFS)

REAL_BUILD = /tmp/sjs_build_real_$(MODEL)

regress-real: csr ports-real
	@mkdir -p $(REAL_BUILD)
	verilator --binary --timing $(REAL_FLAGS) $(REAL_SRCS) --top-module $(TOP) \
	          --Mdir $(REAL_BUILD) -o sim_real
	@$(REAL_BUILD)/sim_real

driver-real: csr ports-real
	@CORE=real ADAPTER=$(ADAPTER) BUILD=/tmp/sjs_drv_real_$(MODEL) ./run_driver_test.sh

lint-real: csr ports-real
	verilator --lint-only $(FROZEN_WNO) \
	          -I$(CSR_DIR) -I$(SRC_DIR) -I$(TB_DIR) \
	          $(COMM_LAYER) $(ADAPTER) \
	          $(CORE_SRCS) --top-module bbht_rvx_wrapper
	@echo "lint 통과 (통신 계층 + $(MODEL) 어댑터 + Main IP)"

#---------------------------------------------------------------------
# 최상단 회귀
#
# src/bbht_bram_top.v 는 통신 계층(mmio, loader)에 Main IP 를
# 어댑터 없이 바로 문 최상단입니다. hardware_dram 의 bbht_dram_top 과
# 짝이고, 호스트가 하는 순서 그대로(설정 -> DMA -> COMMAND -> STATUS 폴링
# -> 결과 읽기) 돌립니다. 확인 항목 H1~H15 는 TB 머리말에 있습니다.
#
# tb_bbht_rvx(T1~T10)와 겹치는 것도 있지만 이쪽은 Q14 전체(16,384개)를
# 적재하고, 같은 설정을 NORMAL_SINGLE 과 CKPT_SINGLE 로 한 번씩 돌려
# 궤적이 같은지 TB 안에서 판정합니다.
#---------------------------------------------------------------------
TOP_RTL   = $(SRC_DIR)/bbht_bram_top.v $(SRC_DIR)/bbht_grover_mmio.v \
            $(SRC_DIR)/bbht_ahb_loader.v $(CORE_SRCS)
TOP_SRCS  = $(TB_DIR)/tb_bbht_bram_top.v $(TB_DIR)/ahb_sram_model.v $(TOP_RTL)
TOP_FLAGS = -Wno-fatal -Wno-DECLFILENAME -I$(CSR_DIR) -I$(SRC_DIR) \
            -I$(SRC_DIR) -I$(TB_DIR)
TOP_BUILD = /tmp/sjs_build_top

lint-top: csr
	verilator --lint-only $(FROZEN_WNO) \
	          -I$(CSR_DIR) -I$(SRC_DIR) \
	          $(TOP_RTL) --top-module bbht_bram_top
	@echo "lint 통과 (최상단 bbht_bram_top)"

top: lint-top
	@mkdir -p $(TOP_BUILD)
	@verilator --binary --timing $(TOP_FLAGS) $(TOP_SRCS) \
	          --top-module tb_bbht_bram_top --Mdir $(TOP_BUILD) -o sim \
	          > $(TOP_BUILD)/build.log 2>&1 \
	          || { tail -30 $(TOP_BUILD)/build.log; exit 1; }
	@$(TOP_BUILD)/sim | tee $(TOP_BUILD)/top.log
	@grep -q '^PASS' $(TOP_BUILD)/top.log || { echo "top 실패"; exit 1; }

#---------------------------------------------------------------------
# 250쌍 벤치 -- 같은 워크로드를 RTL 로 돌려 궤적 불변량을 봅니다
#
#   make bench250              통신 계층 + 어댑터 + Main IP 를 드라이버로 연속 실행
#
# 같은 시드로 Normal 과 체크포인트 갈래를 돌려 trial_count 와 L_BBHT 가
# 일치하는지 보는 paired 방식입니다. 이 둘은 checkpoint 를 켜든 끄든 같아야
# 합니다 -- checkpoint 는 psi 를 어떻게 계산하느냐만 바꾸지 탐색 궤적을
# 바꾸지 않습니다.
#
# result_index 만 보면 안 됩니다. BBHT 가 후보를 술어로 자가 검증하므로
# 진폭이 깨져도 답은 맞게 나옵니다. 2026-09-06 에 융합 시도의 소유권 결함
# 두 건이 정확히 이 방식으로만 드러났습니다.
#
# 사이클 수를 보드와 맞대 볼 때는 대상을 확인하십시오. 이 벤치는 5타겟 ×
# 시드 50 (250쌍) 이고, 2026-09-07 보드 실측과 6단계 ablation 은 5타겟 ×
# 시드 100 (500워크로드) 입니다. 시드 로스터가 다르므로 총합은 직접 비교
# 대상이 아닙니다 (results/2026-09-08_publication_6stage/ 참조).
#---------------------------------------------------------------------
BENCH_CORE   = real_$(MODEL)
BENCH_BUILD  = /tmp/sjs_bench_$(BENCH_CORE)
BENCH_WL     = /tmp/sjs_bench_wl
BENCH_OUT   ?= $(BENCH_BUILD)/bench250_$(BENCH_CORE).csv
BENCH_DEFS   = -DBBHT_HOST_TEST -DBBHT_NO_PRINTF -DBBHT_TIMEOUT=200000000

BENCH_COMM   = $(SRC_DIR)/bbht_rvx_wrapper.v $(SRC_DIR)/bbht_grover_mmio.v \
               $(SRC_DIR)/bbht_ahb_loader.v \
               $(ADAPTER)

.PHONY: bench250 bench250-wl

bench250-wl:
	@python3 ../../software/rtl_vectors/tools/dump_bench_workload.py --seeds 50 --out $(BENCH_WL)

bench250: csr model-check bench250-wl
	@rm -rf $(BENCH_BUILD); mkdir -p $(BENCH_BUILD)/src
	@cp $(TB_DIR)/tb_bench250.cpp $(BENCH_COMM) $(CORE_SRCS) $(BENCH_BUILD)/src/
	@cp $(SRC_DIR)/grover_param.vh $(BENCH_BUILD)/src/
	@cp $(CSR_DIR)/bbht_grover_csr.vh $(CSR_DIR)/bbht_grover_regs.h $(BENCH_BUILD)/src/
	@cp ../firmware/bbht_grover_driver.c ../firmware/bbht_grover_driver.h $(BENCH_BUILD)/src/
	@gcc -c -O2 $(BENCH_DEFS) -I$(BENCH_BUILD)/src \
	     $(BENCH_BUILD)/src/bbht_grover_driver.c -o $(BENCH_BUILD)/driver.o
	@verilator --cc --exe --build -Wno-fatal -Wno-DECLFILENAME \
	     --Mdir $(BENCH_BUILD)/obj \
	     -CFLAGS "$(BENCH_DEFS) -I$(BENCH_BUILD)/src -O2" \
	     -LDFLAGS "$(BENCH_BUILD)/driver.o" -I$(BENCH_BUILD)/src \
	     $(foreach f,$(notdir $(BENCH_COMM) $(CORE_SRCS)),$(BENCH_BUILD)/src/$(f)) \
	     --top-module bbht_rvx_wrapper $(BENCH_BUILD)/src/tb_bench250.cpp \
	     -o bench > $(BENCH_BUILD)/build.log 2>&1 \
	     || { tail -20 $(BENCH_BUILD)/build.log; exit 1; }
	@echo "250쌍 실행 중 ($(BENCH_CORE)). 20분쯤 걸립니다."
	@WL_DIR=$(BENCH_WL) $(BENCH_BUILD)/obj/bench > $(BENCH_OUT)
	@python3 bench250_report.py $(BENCH_OUT)

#---------------------------------------------------------------------
# 500 워크로드 벤치 -- 보드 500런·6단계 ablation 과 같은 워크로드
#
#   make bench500              통신 계층 + 어댑터 + Main IP 를 드라이버로 연속 실행
#
# 250쌍 벤치와 하는 일은 같고 시드 로스터만 100쌍입니다 (5타겟 x 100시드).
# 따로 둔 이유는 두 가지입니다.
#
#   1. 250쌍 하네스가 이미 낸 근거(results/2026-09-10_bench250_final_core/)를
#      건드리지 않으려고. tb_bench250.cpp 는 시드 배열이 50 으로 고정입니다
#   2. 500개를 한 프로세스에서 연달아 돌아야 보드 앱과 실행 순서가 같습니다.
#      50개씩 두 번 나눠 돌면 체크포인트 준비 비용을 두 번 내게 됩니다
#
# 이 벤치의 비교 상대는 둘입니다. 둘 다 같은 500 워크로드입니다.
#
#   results/2026-09-08_publication_6stage/          RTL 사이클 축 (iverilog)
#     의 K3/H3-E4-M2 단계 -- MODEL 기본값과 같은 구성
#   models/hardware_bram_K3H3_E4_M2/vivado/.../2026-09-08_k3h3_e4_m2_board_500run/
#                                                   보드 실경과 시간 축
#
# 250쌍보다 두 배 걸립니다. 40분쯤 잡으십시오.
#---------------------------------------------------------------------
BENCH500_BUILD = /tmp/sjs_bench500_$(BENCH_CORE)
BENCH500_WL    = /tmp/sjs_bench500_wl
BENCH500_OUT  ?= $(BENCH500_BUILD)/bench500_$(BENCH_CORE).csv

.PHONY: bench500 bench500-wl

bench500-wl:
	@python3 ../../software/rtl_vectors/tools/dump_bench_workload.py --seeds 100 --out $(BENCH500_WL)

bench500: csr model-check bench500-wl
	@rm -rf $(BENCH500_BUILD); mkdir -p $(BENCH500_BUILD)/src
	@cp $(TB_DIR)/tb_bench500.cpp $(BENCH_COMM) $(CORE_SRCS) $(BENCH500_BUILD)/src/
	@cp $(SRC_DIR)/grover_param.vh $(BENCH500_BUILD)/src/
	@cp $(CSR_DIR)/bbht_grover_csr.vh $(CSR_DIR)/bbht_grover_regs.h $(BENCH500_BUILD)/src/
	@cp ../firmware/bbht_grover_driver.c ../firmware/bbht_grover_driver.h $(BENCH500_BUILD)/src/
	@gcc -c -O2 $(BENCH_DEFS) -I$(BENCH500_BUILD)/src \
	     $(BENCH500_BUILD)/src/bbht_grover_driver.c -o $(BENCH500_BUILD)/driver.o
	@verilator --cc --exe --build -Wno-fatal -Wno-DECLFILENAME \
	     --Mdir $(BENCH500_BUILD)/obj \
	     -CFLAGS "$(BENCH_DEFS) -I$(BENCH500_BUILD)/src -O2" \
	     -LDFLAGS "$(BENCH500_BUILD)/driver.o" -I$(BENCH500_BUILD)/src \
	     $(foreach f,$(notdir $(BENCH_COMM) $(CORE_SRCS)),$(BENCH500_BUILD)/src/$(f)) \
	     --top-module bbht_rvx_wrapper $(BENCH500_BUILD)/src/tb_bench500.cpp \
	     -o bench > $(BENCH500_BUILD)/build.log 2>&1 \
	     || { tail -20 $(BENCH500_BUILD)/build.log; exit 1; }
	@echo "500 워크로드 실행 중 ($(BENCH_CORE)). 40분쯤 걸립니다."
	@WL_DIR=$(BENCH500_WL) $(BENCH500_BUILD)/obj/bench > $(BENCH500_OUT)
	@python3 bench500_report.py $(BENCH500_OUT)

#---------------------------------------------------------------------
# 네 술어 x 500 워크로드 -- Predicate500
#
#   make predicate500          LT / GT / EQ / RANGE 각각 M 다섯 개 x 시드 100쌍을
#                              Normal 과 체크포인트로 돌려 SW 기준모델과 맞댑니다
#
# bench500 은 EQ 하나뿐이라 나머지 세 술어의 비교기 경로가 실측 규모로 검증된
# 적이 없어서 둡니다. 자극과 기댓값은 software/ 쪽에서 만듭니다.
#
#   software/experiments/predicate500_benchmark/run_predicate500_golden.py
#       -> expected/predicate500_expected.csv (기준모델 기댓값 2,000행)
#   software/rtl_vectors/tools/dump_predicate500_workload.py
#       -> $(PRED500_WL)/ (데이터셋 20개와 술어별 목록)
#
# 술어 넷을 프로세스 넷으로 나눠 동시에 돌립니다. 논리 궤적과 물리 반복은
# 실행 이력과 무관하므로 나눠 돌려도 대조 결과는 같습니다. 체크포인트
# 사이클만 목록마다 memo 청소를 한 번씩 더 냅니다 (3,279 사이클, 기술문서 11장 11.5절).
# 한 목록에 40분쯤, 넷을 동시에 돌리면 전체도 40분~1시간입니다.
#---------------------------------------------------------------------
PRED500_BUILD = /tmp/sjs_pred500_$(BENCH_CORE)
PRED500_WL    = /tmp/sjs_pred500_wl
PRED500_PREDS ?= LT GT EQ RANGE

.PHONY: predicate500 predicate500-wl predicate500-build

predicate500-wl:
	@python3 ../../software/rtl_vectors/tools/dump_predicate500_workload.py --out $(PRED500_WL)

predicate500-build: csr model-check
	@rm -rf $(PRED500_BUILD); mkdir -p $(PRED500_BUILD)/src
	@cp $(TB_DIR)/tb_predicate500.cpp $(BENCH_COMM) $(CORE_SRCS) $(PRED500_BUILD)/src/
	@cp $(SRC_DIR)/grover_param.vh $(PRED500_BUILD)/src/
	@cp $(CSR_DIR)/bbht_grover_csr.vh $(CSR_DIR)/bbht_grover_regs.h $(PRED500_BUILD)/src/
	@cp ../firmware/bbht_grover_driver.c ../firmware/bbht_grover_driver.h $(PRED500_BUILD)/src/
	@gcc -c -O2 $(BENCH_DEFS) -I$(PRED500_BUILD)/src \
	     $(PRED500_BUILD)/src/bbht_grover_driver.c -o $(PRED500_BUILD)/driver.o
	@verilator --cc --exe --build -j 4 -Wno-fatal -Wno-DECLFILENAME \
	     --Mdir $(PRED500_BUILD)/obj \
	     -CFLAGS "$(BENCH_DEFS) -I$(PRED500_BUILD)/src -O2" \
	     -LDFLAGS "$(PRED500_BUILD)/driver.o" -I$(PRED500_BUILD)/src \
	     $(foreach f,$(notdir $(BENCH_COMM) $(CORE_SRCS)),$(PRED500_BUILD)/src/$(f)) \
	     --top-module bbht_rvx_wrapper $(PRED500_BUILD)/src/tb_predicate500.cpp \
	     -o bench > $(PRED500_BUILD)/build.log 2>&1 \
	     || { tail -20 $(PRED500_BUILD)/build.log; exit 1; }

predicate500: predicate500-build predicate500-wl
	@echo "Predicate500 실행 중 ($(PRED500_PREDS) 동시). 40분~1시간 걸립니다."
	@pids=""; for p in $(PRED500_PREDS); do \
	     WL_DIR=$(PRED500_WL) WL_LIST=$(PRED500_WL)/workloads_$$p.txt \
	         $(PRED500_BUILD)/obj/bench > $(PRED500_BUILD)/pred_$$p.csv \
	         2> $(PRED500_BUILD)/pred_$$p.log & pids="$$pids $$!"; \
	 done; rc=0; for pid in $$pids; do wait $$pid || rc=1; done; exit $$rc
	@python3 predicate500_report.py --branch bram \
	     $(foreach p,$(PRED500_PREDS),$(PRED500_BUILD)/pred_$(p).csv) \
	     | tee $(PRED500_BUILD)/report.txt

#---------------------------------------------------------------------
# 콘솔 GEN 생성기 대 SW 생성기
#
#   make console-gen           firmware/bbht_console/src/bbht_dataset_gen.h 를
#                              호스트 gcc 로 컴파일해 Predicate500 데이터셋 20개의
#                              FNV-1a 와 정답 수를 기댓값 CSV 와 맞댑니다 (몇 초)
#---------------------------------------------------------------------
CONSOLE_GEN_BUILD = /tmp/sjs_console_gen
PRED500_DATASETS  = ../../software/experiments/predicate500_benchmark/expected/predicate500_datasets.csv

.PHONY: console-gen

console-gen: csr
	@mkdir -p $(CONSOLE_GEN_BUILD)
	@gcc -O2 -Wall -Wno-unused-function -DBBHT_HOST_TEST -DBBHT_NO_PRINTF \
	     -I$(CSR_DIR) -I../firmware -I../firmware/bbht_console/src \
	     $(TB_DIR)/tb_console_gen.c ../firmware/bbht_grover_driver.c \
	     -o $(CONSOLE_GEN_BUILD)/gen
	@$(CONSOLE_GEN_BUILD)/gen "$(PRED500_DATASETS)"

#---------------------------------------------------------------------
# SoC 시뮬 bbht_console 스크립트의 verilator 짝
#
#   make console-seq           콘솔 스크립트와 같은 순서(리셋 -> 적재 -> NORMAL ->
#                              체크포인트 두 번 -> ENUM)로 같은 RTL 을 드라이버로
#                              두드립니다. 빌드 포함 30초쯤
#
# RVX SoC 시뮬에서 bbht_console 을 돌린 트랜스크립트는 soc_console_check.py 가
# 이 CSV 와 명령 하나하나 맞댑니다.
#
#   python3 soc_console_check.py <qtsim.log> --ref $(CONSOLE_SEQ_OUT)
#
# 따로 둔 이유는 체크포인트 탐색의 사이클이 실행 이력에 달려 있기 때문입니다.
# 리셋 뒤 첫 탐색은 정책 memo 를 지우느라 3,279 사이클이 더 들고, 그다음도
# 직전 탐색에 따라 달라집니다. 그래서 콘솔 스크립트의 사이클은 보드 500런
# 행과 직접 맞댈 수 없고, 같은 순서로 돈 이 결과와 맞대야 합니다
# (testbench/tb_console_seq.cpp 머리말).
#---------------------------------------------------------------------
CONSOLE_SEQ_BUILD = /tmp/sjs_console_seq
CONSOLE_SEQ_OUT  ?= $(CONSOLE_SEQ_BUILD)/console_seq.csv

.PHONY: console-seq

console-seq: csr model-check bench500-wl
	@rm -rf $(CONSOLE_SEQ_BUILD); mkdir -p $(CONSOLE_SEQ_BUILD)/src
	@cp $(TB_DIR)/tb_console_seq.cpp $(BENCH_COMM) $(CORE_SRCS) $(CONSOLE_SEQ_BUILD)/src/
	@cp $(SRC_DIR)/grover_param.vh $(CONSOLE_SEQ_BUILD)/src/
	@cp $(CSR_DIR)/bbht_grover_csr.vh $(CSR_DIR)/bbht_grover_regs.h $(CONSOLE_SEQ_BUILD)/src/
	@cp ../firmware/bbht_grover_driver.c ../firmware/bbht_grover_driver.h $(CONSOLE_SEQ_BUILD)/src/
	@gcc -c -O2 $(BENCH_DEFS) -I$(CONSOLE_SEQ_BUILD)/src \
	     $(CONSOLE_SEQ_BUILD)/src/bbht_grover_driver.c -o $(CONSOLE_SEQ_BUILD)/driver.o
	@verilator --cc --exe --build -Wno-fatal -Wno-DECLFILENAME \
	     --Mdir $(CONSOLE_SEQ_BUILD)/obj \
	     -CFLAGS "$(BENCH_DEFS) -I$(CONSOLE_SEQ_BUILD)/src -O2" \
	     -LDFLAGS "$(CONSOLE_SEQ_BUILD)/driver.o" -I$(CONSOLE_SEQ_BUILD)/src \
	     $(foreach f,$(notdir $(BENCH_COMM) $(CORE_SRCS)),$(CONSOLE_SEQ_BUILD)/src/$(f)) \
	     --top-module bbht_rvx_wrapper $(CONSOLE_SEQ_BUILD)/src/tb_console_seq.cpp \
	     -o bench > $(CONSOLE_SEQ_BUILD)/build.log 2>&1 \
	     || { tail -20 $(CONSOLE_SEQ_BUILD)/build.log; exit 1; }
	@WL_DIR=$(BENCH500_WL) $(CONSOLE_SEQ_BUILD)/obj/bench > $(CONSOLE_SEQ_OUT)
	@cat $(CONSOLE_SEQ_OUT)
