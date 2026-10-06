## RVX application makefile
ifdef RVX_MINI_HOME
	include ${RVX_MINI_HOME}/rvx_config.mh
else
	include ${RVX_DEVKIT_HOME}/rvx_config.mh
endif

TEMPLATE_FILE = ${RVX_ENV}/makefile/Makefile.app.template
include ${RVX_UTIL_HOME}/template_makefile.mh

PLATFORM_DIR = $(call absolute_path,${CURDIR}/../..)
PLATFORM_NAME = $(notdir ${PLATFORM_DIR})

APP_NAME = $(notdir ${CURDIR})

TARGET_IMP_CLASS ?= vp
BUILD_MODE ?= release

ENGINE_WS=${PLATFORM_DIR}/..
ENGINE_TARGET=app
ENGINE_USER_CMD_LIST=build clean
ENGINE_USER_CMD_ADV_LIST=
ENGINE_SYSTEM_CMD_LIST=run debugger.start debugger.stop debug path build_dir compile_list compile compile_incremental wifi_config aix_config local_ssw wifi_ssw aix_ssw
ENGINE_PARA= -p ${PLATFORM_NAME} -a ${APP_NAME} -tic ${TARGET_IMP_CLASS} -bm ${BUILD_MODE}
GUI_CMD_PARA_LIST=build:TARGET_IMP_CLASS
include ${RVX_ENV}/engine/rvx_make2engine.mh

FPGA_LIST = $(shell ${PYTHON3_CMD} ${RVX_UTIL_HOME}/os_util.py dir_list ${ENGINE_WS}/../imp_class_info )
IMP_LIST = vp rtl ${FPGA_LIST}

${IMP_LIST}:
	@make --no-print-directory build TARGET_IMP_CLASS=$@ BUILD_MODE=$(BUILD_MODE)

test:
	@make build TARGET_IMP_CLASS=vp BUILD_MODE=release
	@cd vp.release; make run
