# 통신 계층 회귀. verilator 로 빌드하고 돌립니다.
#
#   make        회귀 실행
#   make lint   lint 만
#   make clean
#
# 빌드 디렉터리를 저장소 밖으로 빼는 이유가 있습니다. 이 저장소 경로에
# "중앙대학교 학부인턴" 처럼 공백이 들어 있는데, verilator 가 만들어 주는
# Makefile 을 GNU Make 가 공백 있는 디렉터리에서 실행하지 못합니다
# ("Unsupported: GNU Make cannot build in directories containing spaces").
# --Mdir 로 공백 없는 곳을 지정하면 그대로 돌아갑니다.

BUILD    ?= /tmp/sjs_build
TOP       = tb_bbht_rvx
SIM       = $(BUILD)/sim_tb

RTL_DIR   = ../src
TB_DIR    = ../testbench
CSR_DIR   = ../../software/csr/generated

SRCS = $(TB_DIR)/tb_bbht_rvx.v \
       $(RTL_DIR)/bbht_rvx_wrapper.v \
       $(RTL_DIR)/bbht_grover_mmio.v \
       $(RTL_DIR)/bbht_ahb_loader.v \
       $(TB_DIR)/bbht_grover_core_stub.v \
       $(TB_DIR)/ahb_sram_model.v

VFLAGS = -Wno-fatal -Wno-DECLFILENAME -I$(CSR_DIR) -I$(RTL_DIR) -I$(TB_DIR)

.PHONY: all regress driver lint csr ports clean \
        ports-real lint-real regress-real driver-real real \
        ports-v3 lint-v3 regress-v3 driver-v3 v3

all: ports regress driver

# 실물 Main IP(src_v2) 를 어댑터로 끼운 갈래. 스텁 갈래보다 훨씬 오래 걸립니다.
real: ports-real lint-real regress-real driver-real

# PASS2 융합판(src_v3). real 과 같은 검사를 src_v3 으로 돌립니다.
# 사이클까지 보려면 bench250 을 쓰십시오 -- 궤적 결함은 27 트라이얼
# 회귀로는 안 드러납니다.
v3: ports-v3 lint-v3 regress-v3 driver-v3

# CSR 헤더가 정본과 어긋나면 먼저 멈춥니다. 생성 헤더를 손으로 고쳐 놓고
# 회귀만 통과시키는 일을 막으려는 것입니다.
csr:
	@python3 ../../software/csr/gen_csr.py --check

# PJK 인수인계 §3.3/§3.4 포트 계약과 RTL 이 어긋나지 않았는지.
#   ports       스텁을 대조 (통신 계층만 볼 때)
#   ports-real  어댑터를 대조 (실물 Main IP 가 물린 상태)
ports:
	@python3 ../../software/contract/check_ports.py stub

ports-real:
	@python3 ../../software/contract/check_ports.py real

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
	          -I$(CSR_DIR) -I$(RTL_DIR) -I$(TB_DIR) \
	          $(RTL_DIR)/bbht_rvx_wrapper.v \
	          $(RTL_DIR)/bbht_grover_mmio.v \
	          $(RTL_DIR)/bbht_ahb_loader.v \
	          $(TB_DIR)/bbht_grover_core_stub.v \
	          --top-module bbht_rvx_wrapper
	@echo "lint 통과"

clean:
	rm -rf $(BUILD) $(V2_BUILD) /tmp/sjs_drv /tmp/sjs_drv_real

#---------------------------------------------------------------------
# 실물 Main IP 갈래
#
# src_v2 는 PJK 최종 소스라 손대지 않습니다. src/bbht_grover_core_adapter.v
# 가 모듈 이름과 리셋 이름만 맞춰 주고, 나머지 61신호는 1:1 입니다.
#
# 스텁은 탐색이 101 사이클이지만 실물은 수십만 사이클이라 TB 의 폴링
# 상한과 워치독을 크게 열어 두어야 합니다.
#---------------------------------------------------------------------
V2_DIR   = ../src_v2
V2_CORE  = $(V2_DIR)/lpsoc_bbht_grover_main_ip.v \
           $(V2_DIR)/grover_arithmetic.v $(V2_DIR)/grover_bbht.v \
           $(V2_DIR)/grover_checkpoint.v $(V2_DIR)/grover_iteration.v \
           $(V2_DIR)/grover_loader.v $(V2_DIR)/grover_measurement.v \
           $(V2_DIR)/grover_memories.v $(V2_DIR)/grover_policy.v \
           $(V2_DIR)/grover_status.v

V2_SRCS  = $(TB_DIR)/tb_bbht_rvx.v \
           $(RTL_DIR)/bbht_rvx_wrapper.v $(RTL_DIR)/bbht_grover_mmio.v \
           $(RTL_DIR)/bbht_ahb_loader.v $(RTL_DIR)/bbht_grover_core_adapter.v \
           $(V2_CORE) $(TB_DIR)/ahb_sram_model.v

V2_FLAGS = -Wno-fatal -Wno-DECLFILENAME -I$(CSR_DIR) -I$(V2_DIR) -I$(TB_DIR) \
           -DGUARD_POLLS=3000000 -DSIM_TIMEOUT_NS=4000_000_000

V2_BUILD = /tmp/sjs_build_v2

regress-real: csr ports-real
	@mkdir -p $(V2_BUILD)
	verilator --binary --timing $(V2_FLAGS) $(V2_SRCS) --top-module $(TOP) \
	          --Mdir $(V2_BUILD) -o sim_v2
	@$(V2_BUILD)/sim_v2

driver-real: csr ports-real
	@CORE=real BUILD=/tmp/sjs_drv_real ./run_driver_test.sh

# 스텁 갈래의 lint 와 달리 -Wall 을 쓰지 않습니다. src_v2 는 freeze 대상이라
# 고칠 수 없는데 -Wall 이 74건을 올려 회귀가 멈춥니다. 기본 경고집합으로
# 두어 실제 오류(폭 불일치, 미해결 참조)만 잡습니다. 아래 넷은 frozen 소스가
# 원래 내는 것이라 눌러 둡니다.
lint-real: csr ports-real
	verilator --lint-only -Wno-DECLFILENAME \
	          -Wno-WIDTHEXPAND -Wno-WIDTHTRUNC -Wno-LATCH -Wno-UNOPTFLAT \
	          -Wno-CMPCONST \
	          -I$(CSR_DIR) -I$(V2_DIR) -I$(TB_DIR) \
	          $(RTL_DIR)/bbht_rvx_wrapper.v $(RTL_DIR)/bbht_grover_mmio.v \
	          $(RTL_DIR)/bbht_ahb_loader.v $(RTL_DIR)/bbht_grover_core_adapter.v \
	          $(V2_CORE) --top-module bbht_rvx_wrapper
	@echo "lint 통과 (실물)"

#---------------------------------------------------------------------
# 250쌍 벤치 -- 보드 실측과 같은 워크로드를 RTL 로 재현
#
#   make bench250            src_v2 (융합 없음). 보드와 0.00% 일치가 기대값
#   make bench250 CORE=v3    src_v3 (PASS2 융합)
#   make bench250-check      두 갈래를 다 돌리고 궤적 불변량까지 검사
#
# 보드 벤치와 같은 paired 방식입니다. 같은 시드로 Normal 과 K4 를 돌려
# trial_count 와 L_BBHT 가 일치하는지 봅니다. 이 둘은 checkpoint 를 켜든 끄든
# 같아야 합니다 -- checkpoint 는 psi 를 어떻게 계산하느냐만 바꾸지 탐색 궤적을
# 바꾸지 않습니다.
#
# result_index 만 보면 안 됩니다. BBHT 가 후보를 술어로 자가 검증하므로
# 진폭이 깨져도 답은 맞게 나옵니다. 2026-09-06 에 PASS2 융합의 소유권 결함
# 두 건이 정확히 이 방식으로만 드러났습니다.
#---------------------------------------------------------------------
BENCH_CORE  ?= $(if $(filter v3,$(CORE)),v3,v2)
BENCH_BUILD  = /tmp/sjs_bench_$(BENCH_CORE)
BENCH_WL     = /tmp/sjs_bench_wl
BENCH_SRCDIR = ../src_$(BENCH_CORE)
BENCH_OUT   ?= $(BENCH_BUILD)/bench250_$(BENCH_CORE).csv
BENCH_DEFS   = -DBBHT_HOST_TEST -DBBHT_NO_PRINTF -DBBHT_TIMEOUT=200000000

# 합성 경로에 들어가는 코어 파일만 적습니다. glob 을 쓰면 타이밍 증명용
# wrapper 와 OOC top 까지 딸려 와 최상위가 둘이 됩니다.
BENCH_FILES  = lpsoc_bbht_grover_main_ip.v \
               grover_arithmetic.v grover_bbht.v grover_checkpoint.v \
               grover_iteration.v grover_loader.v grover_measurement.v \
               grover_memories.v grover_policy.v grover_status.v

.PHONY: bench250 bench250-wl bench250-check

bench250-wl:
	@python3 ../../software/golden/tools/dump_bench250_workload.py --out $(BENCH_WL)

bench250: csr bench250-wl
	@rm -rf $(BENCH_BUILD); mkdir -p $(BENCH_BUILD)/src
	@cp tb_bench250.cpp $(RTL_DIR)/bbht_*.v $(BENCH_BUILD)/src/
	@cp $(BENCH_SRCDIR)/grover_param.vh $(BENCH_BUILD)/src/
	@for f in $(BENCH_FILES); do cp $(BENCH_SRCDIR)/$$f $(BENCH_BUILD)/src/; done
	@cp $(CSR_DIR)/bbht_grover_csr.vh $(CSR_DIR)/bbht_grover_regs.h $(BENCH_BUILD)/src/
	@cp ../firmware/bbht_grover_driver.c ../firmware/bbht_grover_driver.h $(BENCH_BUILD)/src/
	@gcc -c -O2 $(BENCH_DEFS) -I$(BENCH_BUILD)/src \
	     $(BENCH_BUILD)/src/bbht_grover_driver.c -o $(BENCH_BUILD)/driver.o
	@verilator --cc --exe --build -Wno-fatal -Wno-DECLFILENAME \
	     --Mdir $(BENCH_BUILD)/obj \
	     -CFLAGS "$(BENCH_DEFS) -I$(BENCH_BUILD)/src -O2" \
	     -LDFLAGS "$(BENCH_BUILD)/driver.o" -I$(BENCH_BUILD)/src \
	     $(BENCH_BUILD)/src/bbht_rvx_wrapper.v $(BENCH_BUILD)/src/bbht_grover_mmio.v \
	     $(BENCH_BUILD)/src/bbht_ahb_loader.v \
	     $(BENCH_BUILD)/src/bbht_grover_core_adapter.v \
	     $(foreach f,$(BENCH_FILES),$(BENCH_BUILD)/src/$(f)) \
	     --top-module bbht_rvx_wrapper $(BENCH_BUILD)/src/tb_bench250.cpp \
	     -o bench > $(BENCH_BUILD)/build.log 2>&1 \
	     || { tail -20 $(BENCH_BUILD)/build.log; exit 1; }
	@echo "250쌍 실행 중 (src_$(BENCH_CORE)). 20분쯤 걸립니다."
	@WL_DIR=$(BENCH_WL) $(BENCH_BUILD)/obj/bench > $(BENCH_OUT)
	@python3 bench250_report.py $(BENCH_OUT)

bench250-check:
	@$(MAKE) bench250 CORE=real BENCH_OUT=/tmp/sjs_bench250_v2.csv
	@$(MAKE) bench250 CORE=v3   BENCH_OUT=/tmp/sjs_bench250_v3.csv
	@python3 bench250_report.py /tmp/sjs_bench250_v2.csv /tmp/sjs_bench250_v3.csv

#---------------------------------------------------------------------
# PASS2 융합 갈래 (src_v3 + bbht_grover_core_adapter_v3.v)
#---------------------------------------------------------------------
V3_DIR   = ../src_v3
V3_CORE  = $(V3_DIR)/lpsoc_bbht_grover_main_ip.v \
           $(V3_DIR)/grover_arithmetic.v $(V3_DIR)/grover_bbht.v \
           $(V3_DIR)/grover_checkpoint.v $(V3_DIR)/grover_iteration.v \
           $(V3_DIR)/grover_loader.v $(V3_DIR)/grover_measurement.v \
           $(V3_DIR)/grover_memories.v $(V3_DIR)/grover_policy.v \
           $(V3_DIR)/grover_status.v

V3_SRCS  = $(TB_DIR)/tb_bbht_rvx.v \
           $(RTL_DIR)/bbht_rvx_wrapper.v $(RTL_DIR)/bbht_grover_mmio.v \
           $(RTL_DIR)/bbht_ahb_loader.v $(RTL_DIR)/bbht_grover_core_adapter_v3.v \
           $(V3_CORE) $(TB_DIR)/ahb_sram_model.v

V3_FLAGS = -Wno-fatal -Wno-DECLFILENAME -I$(CSR_DIR) -I$(V3_DIR) -I$(TB_DIR) \
           -DGUARD_POLLS=3000000 -DSIM_TIMEOUT_NS=4000_000_000

V3_BUILD = /tmp/sjs_build_v3

ports-v3:
	@python3 ../../software/contract/check_ports.py v3

regress-v3: csr ports-v3
	@mkdir -p $(V3_BUILD)
	verilator --binary --timing $(V3_FLAGS) $(V3_SRCS) --top-module $(TOP) \
	          --Mdir $(V3_BUILD) -o sim_v3
	@$(V3_BUILD)/sim_v3

driver-v3: csr ports-v3
	@CORE=v3 BUILD=/tmp/sjs_drv_v3 ./run_driver_test.sh

lint-v3: csr ports-v3
	verilator --lint-only -Wno-DECLFILENAME \
	          -Wno-WIDTHEXPAND -Wno-WIDTHTRUNC -Wno-LATCH -Wno-UNOPTFLAT \
	          -Wno-CMPCONST \
	          -I$(CSR_DIR) -I$(V3_DIR) -I$(TB_DIR) \
	          $(RTL_DIR)/bbht_rvx_wrapper.v $(RTL_DIR)/bbht_grover_mmio.v \
	          $(RTL_DIR)/bbht_ahb_loader.v \
	          $(RTL_DIR)/bbht_grover_core_adapter_v3.v \
	          $(V3_CORE) --top-module bbht_rvx_wrapper
	@echo "lint 통과 (v3)"
