# hardware_dram 회귀. verilator 로 빌드하고 돌립니다.
#
#   make            ports lint store prep core top 을 순서대로
#   make store      grover_dram_amp_store 단위 (지연 0 / 백프레셔 두 벌)
#   make prep       grover_dram_prep_seq 단위 -- 체크포인트 K/H 를 대신하는 부분
#   make core       Main IP 통합 (통신 계층 없이 코어만)
#   make top        최상단 bbht_dram_top 회귀 -- 호스트 CSR 경로 + AHB 적재 +
#                   DRAM 포트까지 통째 (기본 지연 / 백프레셔 두 벌) 와
#                   core 로그와의 궤적 대조
#   make equiv      hardware_bram 과 궤적 대조 + 비용 비교 (손으로 고른 8케이스)
#   make bench250   250쌍 워크로드로 3자 대조
#                   (250 dram + 250 normal + 250 ckpt = 750 케이스, 3분쯤)
#   make lint       합성 대상 RTL 만 lint
#   make ports      PJK 인수인계 포트 계약 대조
#   make clean
#
# 빌드 디렉터리를 저장소 밖으로 빼는 이유는 hardware_bram/sim/Makefile 과
# 같습니다. 이 저장소 경로에 공백이 들어 있어서 verilator 가 만들어 주는
# Makefile 을 GNU Make 가 제자리에서 못 돌립니다. --Mdir 로 공백 없는 곳을
# 지정하면 그대로 돌아갑니다.
#
# 통신 계층 회귀는 top 타깃입니다. 대상은 ../src/bbht_dram_top.v 이고,
# 같은 폴더의 bbht_rvx_wrapper.v + 어댑터(계약판)가 아닙니다. 계약판은
# DRAM 포트를 안쪽에서 묶어 두어 복원이 필요한 탐색에서 멈추므로
# ports·lint 로 포트 계약만 지킵니다 (bbht_dram_top.v 머리말 참고).

BUILD    ?= /tmp/dram_build

# src 하나에 Main IP 코어(grover_*·lpsoc_*)와 통신 계층(bbht_*)이 같이
# 있습니다. 2026-09-11 에 src_v2 를 src 로 합쳤습니다.
RTL_DIR   = ../src
TB_DIR    = ../testbench
CSR_DIR   = ../../software/contract/generated
BRAM_SRC  = ../../hardware_bram/src
# AHB SRAM 모델은 hardware_bram 것을 그대로 씁니다. 통신 계층(mmio,
# loader)이 두 갈래에서 같은 파일이라 모델을 따로 둘 이유가 없습니다.
BRAM_TB   = ../../hardware_bram/testbench

# 합성 경로에 들어가는 코어 파일만 적습니다. glob 을 쓰면 안 됩니다.
# src 에는 최상위가 둘(bbht_dram_top, 계약판 bbht_rvx_wrapper) 들어 있어서
# glob 으로 모으면 타깃마다 엉뚱한 최상위와 통신 계층이 딸려 들어갑니다.
DRAM_CORE = $(RTL_DIR)/lpsoc_bbht_grover_main_ip.v \
            $(RTL_DIR)/grover_arithmetic.v \
            $(RTL_DIR)/grover_dram_random.v \
            $(RTL_DIR)/grover_dram_amp_store.v \
            $(RTL_DIR)/grover_dram_prep_seq.v \
            $(RTL_DIR)/grover_dram_queue.v \
            $(RTL_DIR)/grover_dram_shot_fsm.v \
            $(RTL_DIR)/grover_iteration.v \
            $(RTL_DIR)/grover_loader.v \
            $(RTL_DIR)/grover_measurement.v \
            $(RTL_DIR)/grover_memories.v \
            $(RTL_DIR)/grover_status.v

# equiv 대조용. hardware_bram 쪽은 읽기만 하고 절대 고치지 않습니다.
# 2026-09-09 부터 대조 상대가 보드 정본 K3/H3-E4-M2 입니다 (그전에는
# 지금은 없어진 hardware_bram/src_v2 의 K4/H4 였습니다).
BRAM_CORE = $(BRAM_SRC)/bbht_grover_main_ip.v \
            $(BRAM_SRC)/grover_arithmetic.v $(BRAM_SRC)/grover_bbht.v \
            $(BRAM_SRC)/grover_checkpoint.v $(BRAM_SRC)/grover_iteration.v \
            $(BRAM_SRC)/grover_loader.v $(BRAM_SRC)/grover_measurement.v \
            $(BRAM_SRC)/grover_memories.v $(BRAM_SRC)/grover_policy.v \
            $(BRAM_SRC)/grover_status.v

VFLAGS    = -Wno-fatal -Wno-DECLFILENAME -I$(RTL_DIR) -I$(TB_DIR)
BRAMFLAGS = -Wno-fatal -Wno-DECLFILENAME -I$(BRAM_SRC) -I$(TB_DIR)

# DRAM 지연 두 벌. 실물 MIG 지연을 알게 되면 SLOW 쪽 숫자만 바꾸면 됩니다.
FAST = -GWR_LAT=0 -GRD_LAT=1  -GBEAT_GAP=0 -GSTALL_EN=0
SLOW = -GWR_LAT=9 -GRD_LAT=31 -GBEAT_GAP=1 -GSTALL_EN=1

.PHONY: all regress ports lint store prep core top equiv clean

all: regress

regress: ports lint store prep core top

#---------------------------------------------------------------------
# 포트 계약. hardware_bram 과 같은 wrapper 19 + core 61 을 지켜야 합니다.
#---------------------------------------------------------------------
ports:
	@python3 ../../software/contract/check_ports.py dram

#---------------------------------------------------------------------
# 합성 대상만 lint. 테스트벤치와 DRAM 모델은 뺍니다.
#
# hardware_bram 의 lint-real 과 같은 이유로 -Wall 을 안 씁니다. 정본의
# 재사용 파일들이 원래 내는 폭 경고가 수십 건이라 회귀가 거기서 멈춥니다.
#---------------------------------------------------------------------
lint:
	@verilator --lint-only -Wno-DECLFILENAME \
	          -Wno-WIDTHEXPAND -Wno-WIDTHTRUNC -Wno-LATCH -Wno-UNOPTFLAT \
	          -Wno-CMPCONST \
	          -I$(CSR_DIR) -I$(RTL_DIR) -I$(TB_DIR) \
	          $(RTL_DIR)/bbht_rvx_wrapper.v $(RTL_DIR)/bbht_grover_mmio.v \
	          $(RTL_DIR)/bbht_ahb_loader.v $(RTL_DIR)/bbht_grover_core_adapter.v \
	          $(DRAM_CORE) --top-module bbht_rvx_wrapper
	@verilator --lint-only -Wno-DECLFILENAME \
	          -Wno-WIDTHEXPAND -Wno-WIDTHTRUNC -Wno-LATCH -Wno-UNOPTFLAT \
	          -Wno-CMPCONST \
	          -I$(CSR_DIR) -I$(RTL_DIR) \
	          $(TOP_RTL) --top-module bbht_dram_top
	@echo "lint 통과 (계약판 bbht_rvx_wrapper + 최상단 bbht_dram_top)"

#---------------------------------------------------------------------
# store/restore 단위. 지연 0 과 백프레셔 두 벌을 다 돌립니다.
#
# 두 벌이 필요한 이유: amp_store 의 STORE FSM 은 dram_wr_valid 를 든 채
# ready 를 기다리는 동안 amp_mem 의 읽기 출력이 유지된다는 전제로 짜여
# 있습니다. 지연 0 모델에서는 그 전제가 시험되지 않습니다.
#---------------------------------------------------------------------
STORE_SRCS = $(TB_DIR)/tb_dram_amp_store.v $(TB_DIR)/dram_burst_model.v \
             $(RTL_DIR)/grover_dram_amp_store.v $(RTL_DIR)/grover_memories.v

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
            $(RTL_DIR)/grover_dram_prep_seq.v $(RTL_DIR)/grover_dram_amp_store.v \
            $(RTL_DIR)/grover_dram_queue.v $(RTL_DIR)/grover_memories.v

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
# 세 벌(dram / bram Normal / bram 체크포인트)을 같은 자극으로 돌립니다.
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
	          --top-module tb_dram_core --Mdir $(BUILD)/core_ckpt -o sim \
	          > $(BUILD)/core_ckpt_build.log 2>&1 \
	          || { tail -30 $(BUILD)/core_ckpt_build.log; exit 1; }
	@$(BUILD)/core_ckpt/sim | tee $(BUILD)/core_ckpt.log
	@python3 equiv_report.py $(BUILD)/core_dram.log $(BUILD)/core_bram.log \
	                         $(BUILD)/core_ckpt.log

#---------------------------------------------------------------------
# 250쌍 벤치. equiv 의 손으로 고른 8케이스와 달리, 보드 실측이 실제로 쓴
# 워크로드(정답 개수 M in {1,4,16,64,256} x 시드 50쌍)를 그대로 돌려
# "DRAM 갈래가 정본 체크포인트를 이기냐 지냐"에 통계적으로 의미 있는 답을 냅니다.
#
# dram 은 한 번(250케이스), bram 은 CHECKPOINT_ENABLE=1 로 한 번만 빌드해
# burst_enable 을 케이스마다 0/1 로 바꿔 Normal/체크포인트를 같이 얻습니다
# (실물 칩이 런타임에 CSR 로 고르는 것과 같은 방식 -- tb_dram_bench250.v
# 헤더 참고).
#---------------------------------------------------------------------
WL_DIR = $(BUILD)/bench250_wl

BENCH_BRAM_SRC = $(BRAM_CORE)

bench250:
	@mkdir -p $(WL_DIR)
	python3 ../../software/rtl_vectors/tools/dump_bench_workload.py --seeds 50 --out $(WL_DIR)
	python3 bin_to_hex.py $(WL_DIR)
	@verilator --binary --timing $(VFLAGS) -DGD_DRAM_BRANCH \
	          -DGD_WL_DIR='"$(WL_DIR)"' -DGD_CSV_OUT='"$(BUILD)/bench250_dram.csv"' \
	          $(TB_DIR)/tb_dram_bench250.v $(TB_DIR)/dram_burst_model.v $(DRAM_CORE) \
	          --top-module tb_dram_bench250 --Mdir $(BUILD)/bench250_dram -o sim \
	          > $(BUILD)/bench250_dram_build.log 2>&1 \
	          || { tail -30 $(BUILD)/bench250_dram_build.log; exit 1; }
	$(BUILD)/bench250_dram/sim
	@verilator --binary --timing $(BRAMFLAGS) \
	          -DGD_WL_DIR='"$(WL_DIR)"' -DGD_CSV_OUT='"$(BUILD)/bench250_bram.csv"' \
	          $(TB_DIR)/tb_dram_bench250.v $(BENCH_BRAM_SRC) \
	          --top-module tb_dram_bench250 --Mdir $(BUILD)/bench250_bram -o sim \
	          > $(BUILD)/bench250_bram_build.log 2>&1 \
	          || { tail -30 $(BUILD)/bench250_bram_build.log; exit 1; }
	$(BUILD)/bench250_bram/sim
	python3 bench250_report.py $(BUILD)/bench250_dram.csv $(BUILD)/bench250_bram.csv

#---------------------------------------------------------------------
# 최상단 회귀. bbht_dram_top 에 APB 마스터(TB 태스크), AHB SRAM 모델,
# DRAM 모델을 붙여 호스트가 하는 순서 그대로(설정 -> DMA -> COMMAND ->
# STATUS 폴링 -> 결과 읽기) 돌립니다. 확인 항목 H1~H14 는 TB 머리말에
# 있습니다.
#
# 두 벌을 돌리는 이유는 store 타깃과 같습니다. 기본 지연(백프레셔 없음)
# 에서는 최상단 포트를 거친 valid/ready 핸드셰이크가 시험되지 않습니다.
#
# 끝으로 C1~C7 의 CASE 줄을 core 로그(tb_dram_core, 코어를 직접 흔든 것)와
# 맞댑니다. 궤적(valid/idx/trials/lbbht/cfgerr/shotlim/budlim)이 같아야
# "통신 계층을 거쳐도 같은 계산" 입니다. 궤적은 DRAM 지연과 무관하므로
# 백프레셔 판 로그도 같은 core 로그와 맞댑니다.
#
# 비용 표는 판정에 안 씁니다. 다만 기본 지연 판에서는 C1~C7 의 반복 수와
# 사이클까지 케이스마다 core 와 똑같이 나옵니다 (2026-09-11 확인). top TB
# 가 C1 직전에 재적재로 DRAM 표를 비우고 core TB 와 같은 순서로 돌리기
# 때문입니다. 이 숫자가 갈라지기 시작하면 TB 순서를 바꿨거나 통신 계층이
# Main IP 에 뭔가 다른 것을 넘기고 있는 것입니다. 백프레셔 판은 사이클만
# 늘어나는 것이 정상입니다.
#---------------------------------------------------------------------
TOP_RTL  = $(RTL_DIR)/bbht_dram_top.v $(RTL_DIR)/bbht_grover_mmio.v \
           $(RTL_DIR)/bbht_ahb_loader.v $(DRAM_CORE)
TOP_SRCS = $(TB_DIR)/tb_bbht_dram_top.v $(TB_DIR)/dram_burst_model.v \
           $(BRAM_TB)/ahb_sram_model.v $(TOP_RTL)
TOPFLAGS = -Wno-fatal -Wno-DECLFILENAME -I$(CSR_DIR) -I$(RTL_DIR) -I$(TB_DIR)

top: core
	@mkdir -p $(BUILD)
	@verilator --binary --timing $(TOPFLAGS) $(TOP_SRCS) \
	          --top-module tb_bbht_dram_top --Mdir $(BUILD)/top -o sim \
	          > $(BUILD)/top_build.log 2>&1 \
	          || { tail -30 $(BUILD)/top_build.log; exit 1; }
	@$(BUILD)/top/sim | tee $(BUILD)/top.log
	@grep -q '^PASS' $(BUILD)/top.log || { echo "top (기본 지연) 실패"; exit 1; }
	@verilator --binary --timing $(TOPFLAGS) $(SLOW) $(TOP_SRCS) \
	          --top-module tb_bbht_dram_top --Mdir $(BUILD)/top_slow -o sim \
	          > $(BUILD)/top_slow_build.log 2>&1 \
	          || { tail -30 $(BUILD)/top_slow_build.log; exit 1; }
	@$(BUILD)/top_slow/sim | tee $(BUILD)/top_slow.log
	@grep -q '^PASS' $(BUILD)/top_slow.log || { echo "top (백프레셔) 실패"; exit 1; }
	@python3 equiv_report.py --names dram,top $(BUILD)/core_dram.log $(BUILD)/top.log
	@python3 equiv_report.py --names dram,top_slow $(BUILD)/core_dram.log $(BUILD)/top_slow.log

clean:
	rm -rf $(BUILD)

#---------------------------------------------------------------------
# 500 워크로드 벤치. 250쌍 벤치와 하는 일은 같고 시드 로스터만 100쌍입니다
# (M in {1,4,16,64,256} x 시드 100 = 500).
#
# 표본을 500 으로 올린 이유는 정본 근거와 자리를 맞추기 위해서입니다.
# 보드 실측(2026-09-08 500런)과 6단계 ablation 이 전부 이 500 워크로드를
# 쓰므로, 여기서 나온 dram 대 K3/H3-E4-M2 비교를 그 근거들과 같은 표본에서
# 말할 수 있습니다. 250쌍 벤치는 시드 로스터가 앞 50쌍이라 그렇게 못 합니다.
#
# 250쌍 쪽 파일은 건드리지 않았습니다. tb_dram_bench250.v 가 NSEED=50 으로
# 고정이라 500 은 tb_dram_bench500.v 로 따로 뒀습니다.
#---------------------------------------------------------------------
WL500_DIR = $(BUILD)/bench500_wl

# DRAM 지연을 고르는 스위치. dram 갈래의 비용은 전부 여기에 걸려 있으므로
# 결과를 인용할 때 어느 쪽으로 쟀는지 같이 적어야 합니다.
#
#   DLAT=model  TB 기본값 (WR_LAT=4 RD_LAT=12, 백프레셔 없음)
#   DLAT=fast   지연 0 에 가까운 상한 (WR_LAT=0 RD_LAT=1)
#   DLAT=slow   백프레셔까지 있는 하한 (WR_LAT=9 RD_LAT=31 BEAT_GAP=1)
#
# 물리 MIG 지연을 알게 되면 slow 쪽 숫자만 바꾸면 됩니다.
DLAT ?= model
ifeq ($(DLAT),slow)
DRAM_LAT = $(SLOW)
else ifeq ($(DLAT),fast)
DRAM_LAT = $(FAST)
else
DRAM_LAT =
endif

.PHONY: bench500

bench500:
	@mkdir -p $(WL500_DIR)
	python3 ../../software/rtl_vectors/tools/dump_bench_workload.py --seeds 100 --out $(WL500_DIR)
	python3 bin_to_hex.py $(WL500_DIR)
	@verilator --binary --timing $(VFLAGS) -DGD_DRAM_BRANCH $(DRAM_LAT) \
	          -DGD_WL_DIR='"$(WL500_DIR)"' -DGD_CSV_OUT='"$(BUILD)/bench500_dram_$(DLAT).csv"' \
	          $(TB_DIR)/tb_dram_bench500.v $(TB_DIR)/dram_burst_model.v $(DRAM_CORE) \
	          --top-module tb_dram_bench500 --Mdir $(BUILD)/bench500_dram_$(DLAT) -o sim \
	          > $(BUILD)/bench500_dram_build.log 2>&1 \
	          || { tail -30 $(BUILD)/bench500_dram_build.log; exit 1; }
	$(BUILD)/bench500_dram_$(DLAT)/sim
	@verilator --binary --timing $(BRAMFLAGS) \
	          -DGD_WL_DIR='"$(WL500_DIR)"' -DGD_CSV_OUT='"$(BUILD)/bench500_bram.csv"' \
	          $(TB_DIR)/tb_dram_bench500.v $(BENCH_BRAM_SRC) \
	          --top-module tb_dram_bench500 --Mdir $(BUILD)/bench500_bram -o sim \
	          > $(BUILD)/bench500_bram_build.log 2>&1 \
	          || { tail -30 $(BUILD)/bench500_bram_build.log; exit 1; }
	$(BUILD)/bench500_bram/sim
	python3 bench500_report.py $(BUILD)/bench500_dram_$(DLAT).csv $(BUILD)/bench500_bram.csv
