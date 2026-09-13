# 통신 계층 회귀. verilator 로 빌드하고 돌립니다.
#
#   make        스텁 갈래 회귀 (몇 초)
#   make real   우리 통신 계층 + 어댑터 + 정본 Main IP
#   make final  보드 정본 통째 (src/ 만으로)
#   make top    최상단 bbht_bram_top 회귀 (Q14 전체 적재, NORMAL/CKPT 짝,
#               열거까지. 빌드 포함 1분 30초쯤)
#   make lint   lint 만
#   make bench250 / bench500
#               250쌍 / 500 워크로드 궤적 벤치 (20분 / 40분쯤)
#   make anchor | publication | kh
#               6단계 ablation 과 K/H 단독 실험 재현. iverilog 로 돕니다 (맨 아래 절)
#   make clean
#
# 갈래가 셋인 이유는 통신 계층이 두 벌이기 때문입니다.
#
#   src/        2026-09-07 보드에 구워진 정본. wrapper 가 어댑터 없이
#               bbht_grover_main_ip 를 K3/H3-E4-M2 로 직접 뭅니다. freeze 대상
#   src_comm/   우리가 쓴 통신 계층. CSR 정본에서 생성한 헤더를 include 하고
#               계약 이름 bbht_grover_core 를 물어서, 자리 채우개로 바꿔 끼우면
#               탐색 없이 몇 초 만에 통신 계약만 볼 수 있습니다
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
COMM_DIR  = ../src_comm
TB_DIR    = ../testbench
CSR_DIR   = ../../software/csr/generated

# 정본 Main IP 중 합성 경로에 들어가는 열입니다. glob 을 쓰면 policy OOC
# 전용인 grover_policy_ooc_top.v 와 grover_policy_impl_wrapper.v 까지 딸려 와
# 최상위가 셋이 됩니다.
CORE_FILES = bbht_grover_main_ip.v \
             grover_arithmetic.v grover_bbht.v grover_checkpoint.v \
             grover_iteration.v grover_loader.v grover_measurement.v \
             grover_memories.v grover_policy.v grover_status.v
CORE_SRCS  = $(addprefix $(SRC_DIR)/,$(CORE_FILES))

COMM_LAYER = $(COMM_DIR)/bbht_rvx_wrapper.v $(COMM_DIR)/bbht_grover_mmio.v \
             $(COMM_DIR)/bbht_ahb_loader.v

SRCS = $(TB_DIR)/tb_bbht_rvx.v \
       $(COMM_LAYER) \
       $(TB_DIR)/bbht_grover_core_stub.v \
       $(TB_DIR)/ahb_sram_model.v

VFLAGS = -Wno-fatal -Wno-DECLFILENAME -I$(CSR_DIR) -I$(COMM_DIR) -I$(TB_DIR)

# 실물 코어가 낀 갈래는 탐색 한 번이 수십만 사이클이라 TB 의 폴링 상한과
# 워치독을 크게 열어 두어야 합니다.
CORE_DEFS = -DGUARD_POLLS=3000000 -DSIM_TIMEOUT_NS=4000_000_000

# 정본 소스가 원래 내는 경고들입니다. freeze 대상이라 고칠 수 없으므로
# 기본 경고집합으로 두고 실제 오류(폭 불일치, 미해결 참조)만 잡습니다.
FROZEN_WNO = -Wno-DECLFILENAME -Wno-WIDTHEXPAND -Wno-WIDTHTRUNC \
             -Wno-LATCH -Wno-UNOPTFLAT -Wno-CMPCONST

.PHONY: all regress driver lint csr ports clean \
        ports-real lint-real regress-real driver-real real \
        ports-final lint-final regress-final driver-final final \
        top lint-top

all: ports regress driver

# 우리 통신 계층에 정본 Main IP 를 어댑터로 끼운 갈래. 스텁보다 훨씬 오래 걸립니다.
real: ports-real lint-real regress-real driver-real

# 보드에 구워진 정본만으로 같은 검사를 돌립니다. 어댑터도 우리 mmio 도 끼지
# 않으므로, 실패하면 정본 자체와 TB 기대가 어긋난 것입니다.
final: ports-final lint-final regress-final driver-final

# CSR 헤더가 정본과 어긋나면 먼저 멈춥니다. 생성 헤더를 손으로 고쳐 놓고
# 회귀만 통과시키는 일을 막으려는 것입니다.
csr:
	@python3 ../../software/csr/gen_csr.py --check

# PJK 인수인계 §3.3/§3.4 포트 계약과 RTL 이 어긋나지 않았는지.
#   ports        스텁을 대조 (통신 계층만 볼 때)
#   ports-real   어댑터를 대조 (우리 통신 계층에 정본 코어가 물린 상태)
#   ports-final  정본 wrapper 와 Main IP 를 직접 대조
ports:
	@python3 ../../software/contract/check_ports.py stub

ports-real:
	@python3 ../../software/contract/check_ports.py real

ports-final:
	@python3 ../../software/contract/check_ports.py final

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
	          -I$(CSR_DIR) -I$(COMM_DIR) -I$(TB_DIR) \
	          $(COMM_LAYER) $(TB_DIR)/bbht_grover_core_stub.v \
	          --top-module bbht_rvx_wrapper
	@echo "lint 통과"

clean:
	rm -rf $(BUILD) $(REAL_BUILD) $(FINAL_BUILD) $(TOP_BUILD) \
	       /tmp/sjs_drv /tmp/sjs_drv_real /tmp/sjs_drv_final \
	       /tmp/sjs_publication /tmp/sjs_kh

#---------------------------------------------------------------------
# 우리 통신 계층 + 정본 Main IP
#
# src/ 는 freeze 대상이라 손대지 않습니다. src_comm/bbht_grover_core_adapter.v
# 가 모듈 이름(bbht_grover_main_ip -> bbht_grover_core)과 리셋 이름(rstn ->
# rstnn)만 맞춰 주고, 나머지 61신호는 1:1 입니다.
#---------------------------------------------------------------------
REAL_SRCS  = $(TB_DIR)/tb_bbht_rvx.v $(COMM_LAYER) \
             $(COMM_DIR)/bbht_grover_core_adapter.v \
             $(CORE_SRCS) $(TB_DIR)/ahb_sram_model.v

REAL_FLAGS = -Wno-fatal -Wno-DECLFILENAME -I$(CSR_DIR) -I$(SRC_DIR) \
             -I$(COMM_DIR) -I$(TB_DIR) $(CORE_DEFS)

REAL_BUILD = /tmp/sjs_build_real

regress-real: csr ports-real
	@mkdir -p $(REAL_BUILD)
	verilator --binary --timing $(REAL_FLAGS) $(REAL_SRCS) --top-module $(TOP) \
	          --Mdir $(REAL_BUILD) -o sim_real
	@$(REAL_BUILD)/sim_real

driver-real: csr ports-real
	@CORE=real BUILD=/tmp/sjs_drv_real ./run_driver_test.sh

lint-real: csr ports-real
	verilator --lint-only $(FROZEN_WNO) \
	          -I$(CSR_DIR) -I$(SRC_DIR) -I$(COMM_DIR) -I$(TB_DIR) \
	          $(COMM_LAYER) $(COMM_DIR)/bbht_grover_core_adapter.v \
	          $(CORE_SRCS) --top-module bbht_rvx_wrapper
	@echo "lint 통과 (우리 통신 계층 + 정본 코어)"

#---------------------------------------------------------------------
# 보드 정본 통째
#
# src/ 안의 wrapper·mmio·loader 를 그대로 씁니다. 우리 TB 는 wrapper 에
# 파라미터를 넘기지 않으므로 두 갈래에 그대로 물립니다.
#---------------------------------------------------------------------
FINAL_SRCS  = $(TB_DIR)/tb_bbht_rvx.v \
              $(SRC_DIR)/bbht_rvx_wrapper.v $(SRC_DIR)/bbht_grover_mmio.v \
              $(SRC_DIR)/bbht_ahb_loader.v \
              $(CORE_SRCS) $(TB_DIR)/ahb_sram_model.v

FINAL_FLAGS = -Wno-fatal -Wno-DECLFILENAME -I$(CSR_DIR) -I$(SRC_DIR) \
              -I$(TB_DIR) $(CORE_DEFS)

FINAL_BUILD = /tmp/sjs_build_final

regress-final: csr ports-final
	@mkdir -p $(FINAL_BUILD)
	verilator --binary --timing $(FINAL_FLAGS) $(FINAL_SRCS) --top-module $(TOP) \
	          --Mdir $(FINAL_BUILD) -o sim_final
	@$(FINAL_BUILD)/sim_final

driver-final: csr ports-final
	@CORE=final BUILD=/tmp/sjs_drv_final ./run_driver_test.sh

lint-final: csr ports-final
	verilator --lint-only $(FROZEN_WNO) -I$(SRC_DIR) \
	          $(SRC_DIR)/bbht_rvx_wrapper.v $(SRC_DIR)/bbht_grover_mmio.v \
	          $(SRC_DIR)/bbht_ahb_loader.v $(CORE_SRCS) \
	          --top-module bbht_rvx_wrapper
	@echo "lint 통과 (정본)"

#---------------------------------------------------------------------
# 최상단 회귀
#
# src_comm/bbht_bram_top.v 는 우리 통신 계층(mmio, loader)에 정본 Main IP
# 를 어댑터 없이 바로 문 최상단입니다. hardware_dram 의 bbht_dram_top 과
# 짝이고, 호스트가 하는 순서 그대로(설정 -> DMA -> COMMAND -> STATUS 폴링
# -> 결과 읽기) 돌립니다. 확인 항목 H1~H15 는 TB 머리말에 있습니다.
#
# tb_bbht_rvx(T1~T10)와 겹치는 것도 있지만 이쪽은 Q14 전체(16,384개)를
# 적재하고, 같은 설정을 NORMAL_SINGLE 과 CKPT_SINGLE 로 한 번씩 돌려
# 궤적이 같은지 TB 안에서 판정합니다.
#---------------------------------------------------------------------
TOP_RTL   = $(COMM_DIR)/bbht_bram_top.v $(COMM_DIR)/bbht_grover_mmio.v \
            $(COMM_DIR)/bbht_ahb_loader.v $(CORE_SRCS)
TOP_SRCS  = $(TB_DIR)/tb_bbht_bram_top.v $(TB_DIR)/ahb_sram_model.v $(TOP_RTL)
TOP_FLAGS = -Wno-fatal -Wno-DECLFILENAME -I$(CSR_DIR) -I$(SRC_DIR) \
            -I$(COMM_DIR) -I$(TB_DIR)
TOP_BUILD = /tmp/sjs_build_top

lint-top: csr
	verilator --lint-only $(FROZEN_WNO) \
	          -I$(CSR_DIR) -I$(SRC_DIR) -I$(COMM_DIR) \
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
#   make bench250              정본 통신 계층 + 정본 코어
#   make bench250 CORE=real    우리 통신 계층 + 어댑터 + 정본 코어
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
BENCH_CORE  ?= $(if $(filter real,$(CORE)),real,final)
BENCH_BUILD  = /tmp/sjs_bench_$(BENCH_CORE)
BENCH_WL     = /tmp/sjs_bench_wl
BENCH_OUT   ?= $(BENCH_BUILD)/bench250_$(BENCH_CORE).csv
BENCH_DEFS   = -DBBHT_HOST_TEST -DBBHT_NO_PRINTF -DBBHT_TIMEOUT=200000000

ifeq ($(BENCH_CORE),real)
BENCH_COMM   = $(COMM_DIR)/bbht_rvx_wrapper.v $(COMM_DIR)/bbht_grover_mmio.v \
               $(COMM_DIR)/bbht_ahb_loader.v \
               $(COMM_DIR)/bbht_grover_core_adapter.v
else
BENCH_COMM   = $(SRC_DIR)/bbht_rvx_wrapper.v $(SRC_DIR)/bbht_grover_mmio.v \
               $(SRC_DIR)/bbht_ahb_loader.v
endif

.PHONY: bench250 bench250-wl bench250-check

bench250-wl:
	@python3 ../../software/golden/tools/dump_bench250_workload.py --out $(BENCH_WL)

bench250: csr bench250-wl
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

bench250-check:
	@$(MAKE) bench250 CORE=final BENCH_OUT=/tmp/sjs_bench250_final.csv
	@$(MAKE) bench250 CORE=real  BENCH_OUT=/tmp/sjs_bench250_real.csv
	@python3 bench250_report.py /tmp/sjs_bench250_final.csv /tmp/sjs_bench250_real.csv

#---------------------------------------------------------------------
# 500 워크로드 벤치 -- 보드 500런·6단계 ablation 과 같은 워크로드
#
#   make bench500              정본 통신 계층 + 정본 코어
#   make bench500 CORE=real    우리 통신 계층 + 어댑터 + 정본 코어
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
#     의 K3/H3-E4-M2 단계 -- 우리 src/ 와 같은 구성
#   vivado/.../2026-09-08_k3h3_e4_m2_board_500run/  보드 실경과 시간 축
#
# 250쌍보다 두 배 걸립니다. 40분쯤 잡으십시오.
#---------------------------------------------------------------------
BENCH500_BUILD = /tmp/sjs_bench500_$(BENCH_CORE)
BENCH500_WL    = /tmp/sjs_bench500_wl
BENCH500_OUT  ?= $(BENCH500_BUILD)/bench500_$(BENCH_CORE).csv

.PHONY: bench500 bench500-wl

bench500-wl:
	@python3 ../../software/golden/tools/dump_bench500_workload.py --out $(BENCH500_WL)

bench500: csr bench500-wl
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
# 6단계 ablation 과 K/H 단독 실험 재현
#
#   make anchor         타깃 256 · 시드 0 하나로 여섯 단계 사이클을 정확 대조 (5회)
#   make publication    500 워크로드 x 5구성 = 2,500회 + 집계. 총합이
#                       results/2026-09-08_publication_6stage/summary.csv 와 같아야 PASS
#   make kh             K/H 단독 E1, 250 워크로드 x 3구성 = 750회.
#                       results/2026-09-09_kh_isolated_e1/summary.csv 와 대조
#
#   JOBS=N 으로 병렬도를 정합니다 (기본 nproc).
#
# 재현 패키지 v1.0 의 러너(repro.sh anchor|publication|kh)를 옮겨 온 것입니다.
# 소스는 ../src_ablation/ -- 정본 src/ 에 MEAS_M1/M2 스위치를 더한 공통소스와
# 구성별 standalone top 8벌이라 src/ 와 모듈 이름이 겹쳐 폴더를 나눴습니다.
#
# 여기만 verilator 가 아니라 iverilog 입니다. 패키지 러너가 iverilog 를 썼고,
# 기대 사이클은 같은 시뮬레이터 의미론에서만 정확히 맞는다고 패키지가 적어
# 두었습니다 (results/2026-09-09_repro_package_v1.0/reproduction_levels.md).
# 로그는 /tmp/sjs_publication, /tmp/sjs_kh 에 쌓입니다.
#---------------------------------------------------------------------
JOBS ?= $(shell nproc)

.PHONY: anchor publication kh

anchor:
	python3 run_publication.py --anchor --jobs $(JOBS)

publication:
	python3 run_publication.py --full --jobs $(JOBS)

kh:
	python3 run_kh.py --jobs $(JOBS)
