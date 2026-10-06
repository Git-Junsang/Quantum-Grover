#!/usr/bin/env python3
"""
bbht_grover_csr.json -> C 헤더 + Verilog 헤더 + Python 상수 + 기술문서 13장 생성기.

PJK 인수인계 §4.2 "CSR 정의를 RTL/C app 여러 곳에 중복하지 않도록 canonical
register specification 또는 공통 generated header 체계를 정리" 에 대한 답입니다.

지금 어긋나 있는 세 곳을 하나로 모읍니다.
  - 옛 펌웨어 헤더 grover_regs.h : 8바이트 간격 옛 제안안 (폐기)
  - hardware/src/grover_mmio.v            : 저장소 설계 문서의 옛 초안
  - PJK 벤치마크 앱 main.c                : 실제 sign-off 맵을 앱마다 복사

사용법:
    python3 gen_csr.py            # generated/ 갱신
    python3 gen_csr.py --check    # 갱신 없이 최신인지만 확인 (CI 용, 다르면 종료코드 1)
"""

import json
import glob
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
SPEC_PATH = os.path.join(HERE, "bbht_grover_csr.json")
OUT_DIR = os.path.join(HERE, "generated")
DOC_DIR = os.path.join(HERE, "..", "..", "documents", "design_references")

BANNER = "이 파일은 gen_csr.py 가 bbht_grover_csr.json 에서 생성했습니다. 직접 고치지 마십시오."


def load_spec():
    with open(SPEC_PATH, encoding="utf-8") as f:
        return json.load(f)


def bit_range(bits):
    """'3:2' -> (3, 2),  '0' -> (0, 0)"""
    if ":" in bits:
        hi, lo = bits.split(":")
        return int(hi), int(lo)
    v = int(bits)
    return v, v


def mask_of(hi, lo):
    return ((1 << (hi - lo + 1)) - 1) << lo


# --------------------------------------------------------------------------
# C 헤더
# --------------------------------------------------------------------------
def gen_c(spec):
    L = []
    a = L.append

    a("/*")
    a(" * bbht_grover_regs.h -- BBHT/Grover CSR 레지스터 정의")
    a(" *")
    a(" * %s" % BANNER)
    a(" *")
    a(" * 정본 버전 %s (%s)" % (spec["version"], spec["date"]))
    a(" */")
    a("#ifndef BBHT_GROVER_REGS_H")
    a("#define BBHT_GROVER_REGS_H")
    a("")
    a("/*")
    a(" * base address 는 RVX 가 플랫폼에서 생성한 매크로를 씁니다.")
    a(" * 숫자를 직접 박으면 플랫폼 XML 이 바뀔 때 조용히 엉뚱한 주소를 두드립니다.")
    a(" * (현재 생성값 %s -- 참고용이고 코드에서 쓰지 마십시오)" % spec["base_value"])
    a(" *")
    a(" * BBHT_HOST_TEST 를 정의하면 CSR 접근이 함수 호출로 바뀝니다. 드라이버를")
    a(" * 보드가 아니라 verilator 모델에 붙여 회귀를 돌리기 위한 갈래이고,")
    a(" * 펌웨어 빌드에는 영향이 없습니다.")
    a(" */")
    a("#ifdef BBHT_HOST_TEST")
    a("extern unsigned int bbht_host_rd(unsigned int off);")
    a("extern void         bbht_host_wr(unsigned int off, unsigned int val);")
    a("#define BBHT_CSR_BASE       0u")
    a("#define bbht_rd(off)        bbht_host_rd(off)")
    a("#define bbht_wr(off, val)   bbht_host_wr((off), (unsigned int)(val))")
    a("#else")
    a("#include \"platform_info.h\"")
    a("#define BBHT_CSR_BASE       %s" % spec["base_macro"])
    a("#define BBHT_REG(off)       (*(volatile unsigned int *)(BBHT_CSR_BASE + (off)))")
    a("#define bbht_rd(off)        BBHT_REG(off)")
    a("#define bbht_wr(off, val)   do { BBHT_REG(off) = (unsigned int)(val); } while (0)")
    a("#endif")
    a("")
    a("#define BBHT_CSR_SIZE       %s" % spec["memorymap_size"])
    a("#define BBHT_CSR_STRIDE     %d" % spec["stride"])
    a("")

    ss = spec["search_space"]
    a("/* 탐색 공간과 시스템 상수 */")
    a("#define BBHT_Q_BITS         %d" % ss["q_bits"])
    a("#define BBHT_N_ENTRIES      %du" % ss["n_entries"])
    a("#define BBHT_RESULT_BITS    %d" % ss["result_index_bits"])
    a("#define BBHT_FIFO_DEPTH     %du" % ss["result_fifo_depth"])
    a("#define BBHT_ACCEL_CLK_HZ   %du" % ss["accel_clk_hz"])
    a("/* 호스트 회귀는 자기 버퍼 주소를 쓰므로 덮어쓸 수 있게 둡니다. */")
    a("#ifndef BBHT_SRAM_BASE")
    a("#define BBHT_SRAM_BASE      %su" % ss["sram_base"])
    a("#endif")
    a("#ifndef BBHT_SRAM_LAST")
    a("#define BBHT_SRAM_LAST      %su" % ss["sram_last"])
    a("#endif")
    a("")

    a("/* 레지스터 오프셋 */")
    for r in spec["registers"]:
        a("#define BBHT_%-26s %su   /* %-4s %s */"
          % (r["name"], r["offset"], r["access"], r["desc"].split(".")[0]))
    a("")


    a("/* STATUS 비트 */")
    for b in spec["status_bits"]:
        a("#define BBHT_ST_%-20s (1u << %-2d)  /* %s */"
          % (b["name"].upper(), b["bit"], b["desc"]))
    a("")
    a("/* 종료 사유 판별에 쓰는 묶음. amp_overflow 는 진단용이라 뺐습니다 -- 이것이")
    a(" * 서 있어도 결과는 유효할 수 있습니다(PJK 벤치마크 앱과 같은 취급). */")
    fatal = ["config_error", "zero_weight_error", "load_error"]
    a("#define BBHT_ST_FATAL_MASK  (%s)"
      % " | \\\n                             ".join("BBHT_ST_%s" % n.upper() for n in fatal))
    limit = ["shot_limit", "budget_limit"]
    a("#define BBHT_ST_LIMIT_MASK  (%s)"
      % " | ".join("BBHT_ST_%s" % n.upper() for n in limit))
    a("")

    a("/* DMA_STATUS 비트 */")
    for b in spec["dma_status_bits"]:
        a("#define BBHT_DMA_%-19s (1u << %-2d)  /* %s */"
          % (b["name"].upper(), b["bit"], b["desc"]))
    a("")

    a("/* CONTROL / ENUM_CFG 필드 */")
    for r in spec["registers"]:
        for f in r.get("fields", []):
            hi, lo = bit_range(f["bits"])
            a("#define BBHT_%s_%s_SHIFT %s%d"
              % (r["name"], f["name"].upper(), " " * max(1, 14 - len(r["name"]) - len(f["name"])), lo))
            a("#define BBHT_%s_%s_MASK  %s0x%08Xu"
              % (r["name"], f["name"].upper(), " " * max(1, 14 - len(r["name"]) - len(f["name"])), mask_of(hi, lo)))
    a("")

    a("/* 술어 */")
    for p in spec["predicate_modes"]:
        a("#define BBHT_PRED_%-8s %d   /* %s */" % (p["name"], p["value"], p["desc"]))
    a("")

    a("/* CONTROL 레지스터 조립 */")
    a("#define BBHT_CONTROL_WORD(auto_shot, burst, pred) \\")
    a("    ((((unsigned int)(auto_shot) & 1u) << 0) | \\")
    a("     (((unsigned int)(burst)     & 1u) << 1) | \\")
    a("     (((unsigned int)(pred)      & 3u) << 2))")
    a("")
    a("/* ENUM_CFG 레지스터 조립 */")
    a("#define BBHT_ENUM_CFG_WORD(enable, fail_limit) \\")
    a("    ((((unsigned int)(enable)     &  1u) << 0) | \\")
    a("     (((unsigned int)(fail_limit) & 15u) << 4))")
    a("")

    a("/* 권장 운용 모드 (auto_shot, burst_enable, enum_enable) */")
    for m in spec["run_modes"]:
        a("/*   %-14s auto=%d burst=%d enum=%d  %s */"
          % (m["name"], m["auto_shot"], m["burst_enable"], m["enum_enable"], m["desc"]))
    a("")

    a("#endif /* BBHT_GROVER_REGS_H */")
    return "\n".join(L) + "\n"


# --------------------------------------------------------------------------
# Verilog 헤더
# --------------------------------------------------------------------------
def gen_v(spec):
    L = []
    a = L.append

    a("//=====================================================================")
    a("// bbht_grover_csr.vh -- BBHT/Grover CSR 주소와 비트 정의 (RTL 쪽)")
    a("//")
    a("// %s" % BANNER)
    a("//")
    a("// 정본 버전 %s (%s)" % (spec["version"], spec["date"]))
    a("//")
    a("// 주소는 워드 인덱스가 아니라 바이트 오프셋입니다. mmio 는 paddr 의")
    a("// 하위 비트에서 워드 인덱스를 뽑아 쓰므로 CSR_IDX_ 쪽을 씁니다.")
    a("//=====================================================================")
    a("`ifndef BBHT_GROVER_CSR_VH")
    a("`define BBHT_GROVER_CSR_VH")
    a("")

    stride = spec["stride"]
    idx_bits = max(int(r["offset"], 16) // stride for r in spec["registers"]).bit_length()

    a("`define BBHT_CSR_STRIDE     %d" % stride)
    a("`define BBHT_CSR_IDX_BITS   %d" % idx_bits)
    a("`define BBHT_CSR_NUM_REG    %d" % (max(int(r["offset"], 16) for r in spec["registers"]) // stride + 1))
    a("")

    ss = spec["search_space"]
    a("// 탐색 공간")
    a("`define BBHT_Q_BITS         %d" % ss["q_bits"])
    a("`define BBHT_N_ENTRIES      %d" % ss["n_entries"])
    a("`define BBHT_DATA_W         %d" % ss["data_word_bits"])
    a("`define BBHT_RESULT_W       %d" % ss["result_index_bits"])
    a("`define BBHT_FIFO_CNT_W     %d" % (spec["search_space"]["result_fifo_depth"].bit_length()))
    a("")

    a("// 워드 인덱스 (paddr[%d:%d])" % (idx_bits + 1, 2))
    for r in spec["registers"]:
        idx = int(r["offset"], 16) // stride
        a("`define CSR_IDX_%-26s %d'd%-3d   // %s %s"
          % (r["name"], idx_bits, idx, r["offset"], r["access"]))
    a("")

    a("// STATUS 비트 위치")
    for b in spec["status_bits"]:
        a("`define BBHT_ST_%-20s %d" % (b["name"].upper(), b["bit"]))
    a("")

    a("// DMA_STATUS 비트 위치")
    for b in spec["dma_status_bits"]:
        a("`define BBHT_DMA_%-19s %d" % (b["name"].upper(), b["bit"]))
    a("")

    a("// 술어")
    for p in spec["predicate_modes"]:
        a("`define BBHT_PRED_%-8s 2'd%d" % (p["name"], p["value"]))
    a("")

    a("`endif")
    return "\n".join(L) + "\n"


# --------------------------------------------------------------------------
# Python 상수 (호스트 CLI 가 import)
# --------------------------------------------------------------------------
def gen_py(spec):
    L = []
    a = L.append
    a('"""bbht_grover_csr.py -- 호스트 쪽 CSR 상수.')
    a("")
    a(BANNER)
    a("")
    a("정본 버전 %s (%s)" % (spec["version"], spec["date"]))
    a('"""')
    a("")
    a("BASE = %s" % spec["base_value"])
    a("STRIDE = %d" % spec["stride"])
    a("")
    a("REG = {")
    for r in spec["registers"]:
        a("    %-28s (%s, %r)," % ('"%s":' % r["name"], r["offset"], r["access"]))
    a("}")
    a("")
    a("STATUS_BITS = [")
    for b in spec["status_bits"]:
        a("    (%2d, %-20s %r)," % (b["bit"], '"%s",' % b["name"], b["desc"]))
    a("]")
    a("")
    a("DMA_STATUS_BITS = [")
    for b in spec["dma_status_bits"]:
        a("    (%2d, %-20s %r)," % (b["bit"], '"%s",' % b["name"], b["desc"]))
    a("]")
    a("")
    a("PREDICATE = {")
    for p in spec["predicate_modes"]:
        a("    %-10s %d," % ('"%s":' % p["name"], p["value"]))
    a("}")
    a("")
    a("RUN_MODES = {")
    for m in spec["run_modes"]:
        a("    %-18s dict(auto_shot=%d, burst_enable=%d, enum_enable=%d),"
          % ('"%s":' % m["name"], m["auto_shot"], m["burst_enable"], m["enum_enable"]))
    a("}")
    a("")
    ss = spec["search_space"]
    a("Q_BITS = %d" % ss["q_bits"])
    a("N_ENTRIES = %d" % ss["n_entries"])
    a("ACCEL_CLK_HZ = %d" % ss["accel_clk_hz"])
    a("SRAM_BASE = %s" % ss["sram_base"])
    a("SRAM_LAST = %s" % ss["sram_last"])
    return "\n".join(L) + "\n"


# --------------------------------------------------------------------------
# 문서 (documents/design_references/13_CSR_레지스터와_실행_모드.md)
#
# 기술문서 13장을 통째로 만듭니다. 표를 손으로 관리하면 반드시 코드와 어긋나므로
# 정본에서 같이 뽑고, 표 사이의 설명 문장도 이 템플릿에 둡니다. 13장의 문장을
# 고치려면 이 함수를 고치고 python3 gen_csr.py 를 돌리십시오.
# --------------------------------------------------------------------------
def gen_doc(spec):
    L = []
    a = L.append
    ss = spec["search_space"]

    a("# 13장. CSR 레지스터와 실행 모드")
    a("")
    a("> [← 12장 Main IP 포트 계약](12_Main_IP_포트_계약.md) · [문서 지도](00_문서_지도.md)"
      " · [14장 호스트 인터페이스와 UART 프로토콜 →](14_호스트_인터페이스와_UART_프로토콜.md)")
    a("")
    a("> 이 장은 `software/contract/gen_csr.py` 가 CSR 정본"
      " [`bbht_grover_csr.json`](../../software/contract/bbht_grover_csr.json) 에서 생성합니다.")
    a("> 손으로 고치면 다음 생성에서 덮어써집니다. 값은 JSON 을, 문장은 `gen_csr.py` 의")
    a("> `gen_doc()` 를 고친 뒤 `python3 software/contract/gen_csr.py` 를 돌리십시오.")
    a(">")
    a("> 출처: PJK `팀원_Handoff_SW_통신_v0.9.8` §1.4 / §1.5. 정본 버전 %s (%s)"
      % (spec["version"], spec["date"]))
    a("")
    a("---")
    a("")
    a("호스트 펌웨어가 가속기를 부리는 창구는 APB 레지스터 %d개입니다. CSR 계약은 v0.9.8 이후"
      % len(spec["registers"]))
    a("바뀌지 않았고, 보드에 구운 두 통신 계층 판의 오프셋 표도 전부 일치합니다. 레지스터가")
    a("Main IP 포트와 어떻게 이어지는지는 [12장](12_Main_IP_포트_계약.md), 호스트 명령이 어느")
    a("레지스터를 두드리는지는 [14장](14_호스트_인터페이스와_UART_프로토콜.md)에 있습니다.")
    a("")
    a("---")
    a("")
    a("## 13.1 CSR 접근 규격")
    a("")
    a("| 항목 | 값 |")
    a("|---|---|")
    a("| base address 매크로 | `%s` |" % spec["base_macro"])
    a("| 현재 생성값 | `%s` (이 환경 `make syn` 실측) |" % spec["base_value"])
    a("| 메모리맵 크기 | `%s` |" % spec["memorymap_size"])
    a("| 레지스터 간격 | %d바이트 |" % spec["stride"])
    a("| 데이터 폭 | %d비트 |" % spec["data_width"])
    a("| 버스 | APB3 슬레이브. `pready` 상수 1, 대기 상태 없음 |")
    a("")
    a("정렬되지 않은 접근과 미할당 주소는 `pslverr` 로 떨어집니다.")
    a("")
    a("C 코드에서는 숫자를 박지 말고 생성된 매크로를 씁니다. 플랫폼 XML 이 바뀌면 주소가")
    a("옮겨가고, 박아 둔 숫자는 조용히 엉뚱한 곳을 두드립니다.")
    a("")
    a("---")
    a("")
    a("## 13.2 탐색 공간과 클럭")
    a("")
    a("| 항목 | 값 |")
    a("|---|---|")
    a("| 유효 큐비트 | Q = %d |" % ss["q_bits"])
    a("| 탐색 공간 | N = %s |" % format(ss["n_entries"], ","))
    a("| 데이터 워드 | %d비트 signed |" % ss["data_word_bits"])
    a("| 결과 인덱스 | %d비트 |" % ss["result_index_bits"])
    a("| 결과 FIFO | %d비트 × %d칸 |" % (ss["result_index_bits"], ss["result_fifo_depth"]))
    a("| 가속기 클럭 | %s MHz. `CYCLE_COUNT` 의 기준이라 `us = cycles / %d` |"
      % (ss["accel_clk_hz"] // 1000000, ss["accel_clk_hz"] // 1000000))
    a("| SoC 클럭 | %s MHz. UART 보율의 기준 |" % (ss["system_clk_hz"] // 1000000))
    a("| 시스템 SRAM | `%s` ~ `%s` |" % (ss["sram_base"], ss["sram_last"]))
    a("")
    a("---")
    a("")
    a("## 13.3 레지스터 접근 유형")
    a("")
    a("| 표기 | 뜻 |")
    a("|---|---|")
    a("| `RW` | 설정. 저장되고 값이 IP 로 상시 나갑니다 |")
    a("| `W1P` | 명령. 저장 공간이 없고 쓰면 1사이클 펄스만 나갑니다. 읽으면 0. 쓰는 데이터는 무시되고 쓰는 행위 자체가 명령입니다 |")
    a("| `RO` | 상태. IP 가 내보내는 와이어를 읽기 응답에 실어 보냅니다 |")
    a("| `RPOP` | 읽기 완료가 곧 pop. 부작용이 있는 유일한 읽기입니다 |")
    a("")
    a("`RPOP` 은 `FIFO_DATA` 하나뿐입니다. 인덱스 0 이 정상 결과일 수 있으므로 값 0 을 비었다는")
    a("뜻으로 읽으면 안 되고, `FIFO_COUNT` 나 `STATUS.fifo_empty` 로 확인합니다.")
    a("")
    a("---")
    a("")
    a("## 13.4 레지스터 맵")
    a("")
    a("| 오프셋 | 이름 | 접근 | 폭 | 뜻 |")
    a("|--:|---|:-:|--:|---|")
    for r in spec["registers"]:
        a("| `%s` | `%s` | %s | %d | %s |"
          % (r["offset"], r["name"], r["access"], r["width"], r["desc"]))
    a("")
    a("`L_BBHT` 는 체크포인트 사용 여부와 관계없이 유지되는 알고리즘 지표이고, `ACTUAL_ITER` 는")
    a("체크포인트가 줄이는 실제 연산량입니다. 둘을 구분해야 합니다([15장](15_동작_과정과_사이클_구성.md)).")
    a("`0x064` 부터의 정책 텔레메트리로 [11장](11_체크포인트와_정책_엔진.md)의 정책 엔진을 밖에서")
    a("관찰할 수 있습니다. `POLICY_MAX_LATENCY` 가 3,352 로 튀면 리셋 뒤 memo 청소가 일어난")
    a("실행입니다.")
    a("")
    a("### 비트 필드가 있는 레지스터")
    a("")
    for r in spec["registers"]:
        if not r.get("fields"):
            continue
        a("`%s` (`%s`)" % (r["name"], r["offset"]))
        a("")
        a("| 비트 | 이름 | 뜻 |")
        a("|:-:|---|---|")
        for f in r["fields"]:
            a("| `%s` | `%s` | %s |" % (f["bits"], f["name"], f["desc"]))
        a("")
    a("---")
    a("")
    a("## 13.5 `STATUS` (`0x024`)")
    a("")
    a("| 비트 | 이름 | 뜻 |")
    a("|--:|---|---|")
    for b in spec["status_bits"]:
        a("| %d | `%s` | %s |" % (b["bit"], b["name"], b["desc"]))
    a("")
    a("자주 보게 되는 값입니다.")
    a("")
    a("| 값 | 뜻 |")
    a("|---|---|")
    a("| `0x080c` | 완료 + 결과 유효 + FIFO 빔. 정상 Single |")
    a("| `0x0404` | 완료 + 열거 종료, FIFO 에 결과 남음. 아직 뽑아야 함 |")
    a("| `0x0c04` | 완료 + 열거 종료 + FIFO 빔. 다 뽑았음 |")
    a("| `0x0844` | 완료 + 예산 도달 + FIFO 빔. 못 찾고 끝남 |")
    a("")
    a("`done_sticky` 를 지우는 것은 `COMMAND` 쓰기뿐입니다. `STATUS` 를 읽거나 설정을 바꿔도")
    a("지워지지 않습니다. `search_busy` 는 따로 나오지 않고 `busy & ~load_busy` 로 유도합니다.")
    a("")
    a("---")
    a("")
    a("## 13.6 `DMA_STATUS` (`0x060`)")
    a("")
    a("| 비트 | 이름 | 뜻 |")
    a("|--:|---|---|")
    for b in spec["dma_status_bits"]:
        a("| %d | `%s` | %s |" % (b["bit"], b["name"], b["desc"]))
    a("")
    a("`0x00000080` 이면 완료만 선 정상 상태입니다. 검사 시점과 이유는")
    a("[7장 7.3절](07_통신_계층.md#73-loader-의-사전-검사)에 있습니다.")
    a("")
    a("---")
    a("")
    a("## 13.7 술어와 실행 모드")
    a("")
    a("| 값 | 이름 | 조건 |")
    a("|--:|---|---|")
    for pm in spec["predicate_modes"]:
        a("| %d | `%s` | %s |" % (pm["value"], pm["name"], pm["desc"]))
    a("")
    a("`RANGE` 는 열린구간입니다. 경계값 자체는 정답이 아닙니다.")
    a("")
    a("실행 모드는 별도 레지스터가 아니라 세 비트의 조합입니다.")
    a("")
    a("| 이름 | `auto_shot` | `burst_enable` | `enum_enable` | 설명 |")
    a("|---|:-:|:-:|:-:|---|")
    for m in spec["run_modes"]:
        a("| `%s` | %d | %d | %d | %s |"
          % (m["name"], m["auto_shot"], m["burst_enable"], m["enum_enable"], m["desc"]))
    a("")
    a("`checkpoint_auto_enable = burst_enable && auto_shot` 이므로 수동 모드(`auto_shot=0`)에서는")
    a("체크포인트가 걸리지 않습니다([7장 7.1절](07_통신_계층.md#71-wrapper-의-제어-로직)).")
    a("체크포인트 없는 판과 DRAM 갈래는 `burst_enable` 을 무시하고 NORMAL 로 돕니다.")
    a("")
    a("### 모드 이름에 K · H 를 넣지 않는 이유")
    a("")
    a("실행 모드 이름은 2026-09-10 에 `K4H8_*` 에서 `CKPT_*` 로 바꿨습니다. K · H · E · M 은 전부")
    a("RTL 빌드에 컴파일되는 값이라 이름에 값을 넣으면 빌드가 바뀔 때마다 이름이 틀려집니다. 실제로")
    a("K4/H8 에서 K4/H4 를 거쳐 지금은 K3/H3 입니다.")
    a("")
    a("`bbht_paper_bench` 의 `CONTROL_K4H8_EQ` · `MODE_K4H8` 은 그대로 두었습니다. 그 파일은 보드")
    a("ELF 를 낸 소스와 sha256 이 같아야 합니다. 소프트웨어 기준모델은 CSR 모드 이름 대신 정책")
    a("이름으로 부릅니다([4장 4.2절](04_소프트웨어_기준모델과_정답_벡터.md#42-세-계층의-기준-모델)).")
    a("")
    a("---")
    a("")
    a("## 13.8 생성 파이프라인")
    a("")
    a("정본 JSON 하나에서 넷을 생성합니다. 생성물은 손으로 고치지 않습니다.")
    a("")
    a("| 생성물 | 쓰는 곳 |")
    a("|---|---|")
    a("| `software/contract/generated/bbht_grover_csr.vh` | RTL (`bbht_grover_mmio.v` 등 네 곳) |")
    a("| `software/contract/generated/bbht_grover_regs.h` | 펌웨어 C |")
    a("| `software/contract/generated/bbht_grover_csr.py` | 호스트 CLI |")
    a("| `documents/design_references/13_CSR_레지스터와_실행_모드.md` | 이 장 |")
    a("")
    a("같은 숫자를 들고 있으면서 생성 대상이 아닌 곳이 둘 더 있습니다.")
    a("")
    a("| 곳 | 생성 대상이 아닌 이유 |")
    a("|---|---|")
    a("| `software/models/common/final_hardware_contract.py` | CSR 과 다른 축인 정책 이름을 같이 담습니다 |")
    a("| `hardware_bram/firmware/bbht_paper_bench/src/main.c` | 보드 ELF 소스라 한 글자도 못 고칩니다 |")
    a("")
    a("`gen_csr.py --check` 가 그 둘을 읽기만 하고 정본과 대조합니다(main.c 는 이름을 줄여 쓴")
    a("것이 있어 오프셋 기준으로 봅니다). 셋째 검사는 방향이 반대로, 생성 헤더를 우회해 RTL 안에")
    a("CSR 값을 다시 박는 것을 막습니다.")
    a("")
    a("```bash")
    a("python3 software/contract/gen_csr.py          # 갱신")
    a("python3 software/contract/gen_csr.py --check  # 갱신 없이 확인만 (CI 용)")
    a("```")
    a("")
    a("체크포인트 판 `sim/Makefile` 은 모든 타깃에서 `--check` 를, 체크포인트 없는 판은 생성을 먼저")
    a("돌리므로 생성 헤더를 손으로 고쳐 놓고 회귀만 통과시키는 일이 생기지 않습니다(DRAM 갈래는 생성")
    a("헤더를 include 만 합니다). CSR 정의가 옛 펌웨어 헤더(8바이트 간격")
    a("제안안) · 옛 설계안 mmio · proof app 마다의 복사본 세 곳에 따로 있다가 어긋난 적이 있어서 이")
    a("구조를 만들었습니다.")
    return "\n".join(L) + "\n"


# --------------------------------------------------------------------------
# 교차대조 -- 생성하지 않지만 같은 숫자를 들고 있는 곳들
#
# CSR 맵은 생성물 넷 말고도 두 군데에 더 있습니다. 둘 다 생성 대상으로 삼을 수
# 없어서(이유는 아래) 읽기만 하고 정본과 대조합니다.
#
#   - software/models/common/final_hardware_contract.py
#       CSR 맵 외에 정책 이름(K3H3_* / K4H4_*)을 같이 담습니다. 그 이름은 CSR
#       모드 이름(CKPT_*)과 다른 축이라, 생성 대상으로 바꾸면 정책 이름이
#       사라집니다. 그래서 손으로 쓰되 오프셋만 여기서 대조합니다.
#   - hardware_bram/firmware/bbht_paper_bench/src/main.c
#       보드 ELF 를 낸 소스라 sha256 이 같아야 합니다. 한 글자도 못 고치므로
#       정의된 것만 부분집합으로 대조합니다.
#
# 세 번째 검사는 방향이 반대입니다. 생성 헤더를 우회해 RTL 안에 값을 다시
# 박아 두는 일을 막습니다.
# --------------------------------------------------------------------------
REPO = os.path.join(HERE, "..", "..")

CONTRACT_PY = os.path.join(REPO, "software", "models", "common",
                           "final_hardware_contract.py")
PAPER_BENCH_C = os.path.join(REPO, "hardware_bram", "firmware",
                             "bbht_paper_bench", "src", "main.c")
# hardware_bram 은 공용 src/ 와 모델마다의 src/(어댑터) 전부를 봅니다.
RTL_DIRS = ([os.path.join(REPO, "hardware_bram", "src")]
            + sorted(glob.glob(os.path.join(REPO, "hardware_bram", "models", "*", "src")))
            + [os.path.join(REPO, "hardware_dram", "src")])


def _spec_offsets(spec):
    return {r["name"]: int(r["offset"], 16) for r in spec["registers"]}


def _parse_py_dict(text, varname):
    """`VARNAME = {` 부터 짝 맞는 `}` 까지를 리터럴로 읽습니다."""
    m = re.search(r"^%s\s*=\s*\{" % re.escape(varname), text, re.M)
    if not m:
        return None
    depth, i = 0, m.end() - 1
    while i < len(text):
        if text[i] == "{":
            depth += 1
        elif text[i] == "}":
            depth -= 1
            if depth == 0:
                break
        i += 1
    body = text[m.end() - 1:i + 1]
    # 주석을 지우고 ast 로 읽습니다. 값이 전부 정수 리터럴이라 이걸로 충분합니다.
    import ast
    return ast.literal_eval(re.sub(r"#[^\n]*", "", body))


def check_contract_py(spec):
    """(a) 소프트웨어 기준모델의 CSR 맵이 정본과 같은가."""
    name = "final_hardware_contract.py"
    if not os.path.exists(CONTRACT_PY):
        return ["%s 를 못 찾았습니다 (%s)" % (name, CONTRACT_PY)]

    text = open(CONTRACT_PY, encoding="utf-8").read()
    bad = []

    offsets = _parse_py_dict(text, "CSR_OFFSETS")
    if offsets is None:
        bad.append("%s 에 CSR_OFFSETS 가 없습니다" % name)
    else:
        want = _spec_offsets(spec)
        for reg, off in sorted(want.items()):
            if reg not in offsets:
                bad.append("%s 에 %s 가 없습니다" % (name, reg))
            elif offsets[reg] != off:
                bad.append("%s 의 %s = 0x%03X, 정본은 0x%03X"
                           % (name, reg, offsets[reg], off))
        for reg in sorted(set(offsets) - set(want)):
            bad.append("%s 의 %s 는 정본에 없습니다" % (name, reg))

    for var, key in (("STATUS_BITS", "status_bits"),
                     ("DMA_STATUS_BITS", "dma_status_bits")):
        got = _parse_py_dict(text, var)
        if got is None:
            bad.append("%s 에 %s 가 없습니다" % (name, var))
            continue
        # 기준모델은 이름 -> 비트번호 방향입니다 (정본 JSON 은 목록).
        want = {b["name"]: b["bit"] for b in spec[key]}
        if got != want:
            for bit_name in sorted(set(want) | set(got)):
                if want.get(bit_name) != got.get(bit_name):
                    bad.append("%s 의 %s[%s] = %r, 정본은 %r"
                               % (name, var, bit_name, got.get(bit_name), want.get(bit_name)))
    return bad


def check_paper_bench(spec):
    """(b) 보드 ELF 를 낸 앱의 자체 복사본.

    이 파일은 한 글자도 못 고칩니다 -- 보드에 구운 ELF 의 소스와 sha256 이 같아야
    하기 때문입니다. 그래서 **오프셋 기준**으로 봅니다. 이름은 앱 쪽이 줄여 쓴
    것이 여럿이라(CSR_POLICY_CYCLES = POLICY_CYCLES_TOTAL 등) 이름으로 맞대면
    고칠 수 없는 차이가 매번 걸립니다.

    잡는 것은 둘입니다.
      - 정본에 없는 오프셋을 쓰고 있는가 (맵이 밀렸다는 뜻)
      - 정본과 같은 이름을 쓰면서 오프셋이 다른가 (더 위험한 어긋남)
    """
    name = "bbht_paper_bench/src/main.c"
    if not os.path.exists(PAPER_BENCH_C):
        return ["%s 를 못 찾았습니다" % name]

    text = open(PAPER_BENCH_C, encoding="utf-8").read()
    by_name = _spec_offsets(spec)
    by_offset = {off: reg for reg, off in by_name.items()}
    bad = []
    for reg, off in re.findall(r"^#define\s+CSR_(\w+)\s+0x([0-9A-Fa-f]+)", text, re.M):
        got = int(off, 16)
        if reg in by_name:
            if by_name[reg] != got:
                bad.append("%s 의 CSR_%s = 0x%03X, 정본은 0x%03X"
                           % (name, reg, got, by_name[reg]))
        elif got not in by_offset:
            bad.append("%s 의 CSR_%s = 0x%03X 는 정본에 없는 오프셋입니다"
                       % (name, reg, got))
    return bad


def check_rtl_no_redefine():
    """(c) 생성 헤더를 우회해 RTL 안에 값을 다시 박지 않았는가."""
    bad = []
    pat = re.compile(r"^\s*`define\s+(CSR_IDX_\w+|BBHT_ST_\w+|BBHT_CSR_\w+|BBHT_DMA_\w+)")
    for d in RTL_DIRS:
        if not os.path.isdir(d):
            continue
        for fn in sorted(os.listdir(d)):
            if not fn.endswith((".v", ".vh")):
                continue
            # 생성 헤더 자신은 당연히 define 합니다.
            if fn == "bbht_grover_csr.vh":
                continue
            p = os.path.join(d, fn)
            for i, line in enumerate(open(p, encoding="utf-8", errors="replace"), 1):
                m = pat.match(line)
                if m:
                    bad.append("%s:%d 가 %s 를 직접 define 합니다 -- 생성 헤더를 include 하십시오"
                               % (os.path.relpath(p, REPO), i, m.group(1)))
    return bad


def run_crosschecks(spec):
    """셋을 다 돌리고 어긋난 것만 돌려줍니다."""
    results = [
        ("final_hardware_contract.py", check_contract_py(spec)),
        ("bbht_paper_bench/src/main.c", check_paper_bench(spec)),
        ("RTL 재정의 없음", check_rtl_no_redefine()),
    ]
    bad = []
    for label, problems in results:
        if problems:
            print("어긋남 %s" % label)
            for p in problems:
                print("       %s" % p)
            bad.extend(problems)
        else:
            print("일치  %s" % label)
    return bad


# --------------------------------------------------------------------------
def main():
    check_only = "--check" in sys.argv
    spec = load_spec()

    outputs = {
        os.path.join(OUT_DIR, "bbht_grover_regs.h"): gen_c(spec),
        os.path.join(OUT_DIR, "bbht_grover_csr.vh"): gen_v(spec),
        os.path.join(OUT_DIR, "bbht_grover_csr.py"): gen_py(spec),
        os.path.join(DOC_DIR, "13_CSR_레지스터와_실행_모드.md"): gen_doc(spec),
    }

    os.makedirs(OUT_DIR, exist_ok=True)
    stale = []

    for path, text in outputs.items():
        name = os.path.basename(path)
        old = None
        if os.path.exists(path):
            with open(path, encoding="utf-8") as f:
                old = f.read()
        if old == text:
            print("최신  %s" % name)
            continue
        stale.append(name)
        if check_only:
            print("어긋남 %s" % name)
        else:
            with open(path, "w", encoding="utf-8") as f:
                f.write(text)
            print("생성  %s" % name)

    # 오프셋이 겹치거나 stride 를 벗어나지 않는지 확인합니다.
    seen = {}
    for r in spec["registers"]:
        off = int(r["offset"], 16)
        if off % spec["stride"]:
            print("오류: %s 오프셋 %s 가 %d바이트 정렬이 아닙니다"
                  % (r["name"], r["offset"], spec["stride"]))
            return 2
        if off in seen:
            print("오류: 오프셋 %s 가 %s 와 %s 에 중복" % (r["offset"], seen[off], r["name"]))
            return 2
        seen[off] = r["name"]

    # 생성하지 않지만 같은 숫자를 들고 있는 곳들. 갱신 모드에서도 돌립니다 --
    # 손으로 관리하는 쪽이 어긋난 것은 생성으로 고쳐지지 않기 때문입니다.
    print("")
    crosscheck_bad = run_crosschecks(spec)

    if stale and check_only:
        print("\ngenerated/ 가 정본과 다릅니다. python3 gen_csr.py 를 돌리십시오.")
    if crosscheck_bad:
        print("\n손으로 관리하는 쪽이 정본과 어긋났습니다. 위 목록을 보고 맞추십시오.")
    if crosscheck_bad or (stale and check_only):
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
