#!/usr/bin/env bash
# run_all.sh : the whole paper campaign in one command.
#
#   bash run_all.sh                          # everything, sw_benchmark/results/<host>_<date>/
#   WORKLOAD=predicate500 SKIP_QISKIT=1 bash run_all.sh
#
# Stages
#   1. build + environment record
#   2. verification   C++ RTL-exact model vs team golden model vs FPGA boards, vectors, oracles
#   3. timing         every model, 1 core and multi-core, on Predicate500 (main) and Common500
#   4. cross-checks   NumPy / Qiskit runs vs the C++ float model of the same policy
#   5. report         <OUT>/<workload>/report/report.md
#
# Reads the team code and data in place (software/models, software/experiments, software/rtl_vectors)
# and never writes outside sw_benchmark/. Options (environment variables):
#   WORKLOAD=predicate500|common500|both   default both
#   OUT=dir                                default results/<host>_<YYYYmmdd_HHMM>
#   CORE=N                                 CPU for single-core runs; must be one this process may
#                                          use (default: the 2nd allowed CPU). On a hybrid CPU
#                                          pick the fastest core type you have (P-core if any).
#   REPS=5                                 C++ timed repetitions per workload (NumPy 3, Qiskit 1)
#   SKIP_QISKIT=1                          skip Qiskit (single-threaded Predicate500 takes hours)
#   QISKIT_SEEDS=K                         Qiskit on the first K seed pairs only (default 100)
#   BASELINE_POLICIES="normal allj k3h3"   NumPy / Qiskit policies (k4h4 also available)
#   GOLDEN_POLICIES="normal k3h3 allj"     team golden model policies (k4h4 also available)
#   SKIP_GOLDEN=1                          skip timing the team golden model
#   ENERGY=1                               wrap timing runs in `perf stat -e power/energy-pkg/`
#
# Multi-core: latency mode runs 2, 4, 8, <physical cores>, <logical CPUs> threads; throughput
# mode runs <physical cores> and <logical CPUs> workers (one run if there is no SMT).
# Qiskit multi-thread runs use all logical CPUs.
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
WORKLOAD=${WORKLOAD:-both}
NPROC=$(nproc)                                    # logical CPUs (hyper-threads included)
# CPUs this process may run on (container cpuset / taskset), e.g. "12 13 ... 19"
ALLOWED=$(python3 -c "import os; print(' '.join(map(str, sorted(os.sched_getaffinity(0)))))")
# physical cores among the allowed CPUs (hyper-thread siblings share a core id)
PHYS=$({ lscpu -p=CPU,Core,Socket 2>/dev/null || true; } | awk -F, -v list="$ALLOWED" \
    'BEGIN { n = split(list, a, " "); for (i = 1; i <= n; i++) ok[a[i]] = 1 }
     !/^#/ && ($1 in ok) { print $2 "," $3 }' | sort -u | wc -l)
[ "${PHYS:-0}" -ge 1 ] && [ "$PHYS" -le "$NPROC" ] || PHYS=$NPROC
FULL_COUNTS=$(printf "%s\n" "$PHYS" "$NPROC" | sort -n -u)   # "all physical" and "all logical"
if [ -z "${CORE:-}" ]; then
    set -- $ALLOWED
    CORE=${2:-$1}
elif ! printf " %s " $ALLOWED | grep -q " $CORE "; then
    echo "CORE=$CORE is not available here; allowed CPUs: $ALLOWED" >&2
    exit 1
fi
set --
CORE_MHZ=$(lscpu -e=CPU,MAXMHZ 2>/dev/null | awk -v c="$CORE" '$1 == c {print $2}')
REPS=${REPS:-5}
QISKIT_SEEDS=${QISKIT_SEEDS:-100}
BASELINE_POLICIES=${BASELINE_POLICIES:-"normal allj k3h3"}
GOLDEN_POLICIES=${GOLDEN_POLICIES:-"normal k3h3 allj"}
OUT=${OUT:-$HERE/results/$(hostname)_$(date +%Y%m%d_%H%M)}
mkdir -p "$OUT/energy"

SOFTWARE=$(cd "$HERE/.." && pwd)                   # team SW tree (read only)
C500="$SOFTWARE/experiments/common500_benchmark/inputs"   # team: seed roster + Common500 datasets
P500="$HERE/data/predicate500_datasets"            # sw_benchmark: Predicate500 datasets
BENCH="$HERE/build/grover_bench"
NUMPY="python3 $HERE/baselines/numpy_baseline.py"
QISKIT="python3 $HERE/baselines/qiskit_baseline.py"
GOLDEN="python3 $HERE/baselines/golden_baseline.py"
TOOLS="$HERE/tools"
export OPENBLAS_NUM_THREADS=1 MKL_NUM_THREADS=1   # NumPy single-threaded; C++ pins its own threads
export PYTHONDONTWRITEBYTECODE=1   # never write __pycache__ into the team folders

declare -A PA=([LT]=-16384 [GT]=16383 [EQ]=12345 [RANGE]=-4096)   # Predicate500 thresholds
declare -A PB=([LT]=0 [GT]=0 [EQ]=0 [RANGE]=4096)
PREDS="LT GT EQ RANGE"

energy() {   # energy <label> <command...>
    local label=$1; shift
    if [ "${ENERGY:-0}" = 1 ]; then
        perf stat -a -e power/energy-pkg/ -x, -o "$OUT/energy/$label.txt" "$@"
    else
        "$@"
    fi
}

# ============================================================ 1. build, environment
echo "== 1. build"
make -C "$HERE" -s
{
    echo "host: $(hostname)"; echo "cpu: $(grep -m1 'model name' /proc/cpuinfo | cut -d: -f2)"
    echo "nproc (logical CPUs): $NPROC"; echo "physical cores: $PHYS"; echo "kernel: $(uname -r)"; echo "compiler: $(${CXX:-g++} --version | head -1)"
    echo "python: $(python3 --version)"
    python3 -c "import numpy,qiskit,qiskit_aer;print('numpy',numpy.__version__,'qiskit',qiskit.__version__,'aer',qiskit_aer.__version__)" 2>/dev/null || true
    echo "governor: $(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null || echo n/a)"
    echo "allowed CPUs: $ALLOWED"
    echo "single-core runs pinned to CPU $CORE (max MHz ${CORE_MHZ:-n/a}); C++ reps $REPS"
    echo "virtualization: $(systemd-detect-virt 2>/dev/null || echo n/a)"
    lscpu -e=CPU,CORE,ONLINE,MAXMHZ 2>/dev/null || true
} > "$OUT/environment.txt"
ENV_NOTE="$(grep -m1 'model name' /proc/cpuinfo | cut -d: -f2 | xargs), $PHYS physical cores / $NPROC logical CPUs; single-core runs pinned to CPU $CORE (max ${CORE_MHZ:-?} MHz)"

# ============================================================ 2. verification
V="$OUT/verification"; mkdir -p "$V/runs"
echo "== 2. verification"
python3 "$TOOLS/make_predicate500_datasets.py" --out "$V/predicate500_datasets_regenerated" | tee "$V/predicate500_datasets.txt"
cmp -s <(cat "$V"/predicate500_datasets_regenerated/*.bin) <(cat "$P500"/*.bin) \
    && echo "bundled data/predicate500_datasets identical to the regenerated files" | tee -a "$V/predicate500_datasets.txt"
python3 "$TOOLS/verify_cpp_rtl_vectors.py" | tee "$V/cpp_rtl_vectors.txt"
python3 "$TOOLS/verify_cpp_oracles.py" | tee "$V/cpp_oracles.txt"
for pr in $PREDS; do
    args=(--inputs "$C500" --pred $pr --a ${PA[$pr]} --b ${PB[$pr]} --datasets "$P500" --reps 1)
    for p in normal k3h3 allj; do
        "$BENCH" --engine rtl --policy $p "${args[@]}" --out "$V/runs/rtl_${pr}_$p.csv" --summary "$V/runs/rtl_${pr}_$p.json"
    done
    "$BENCH" --engine rtl --policy allj --session "${args[@]}" --out "$V/runs/rtl_${pr}_session.csv" --summary "$V/runs/rtl_${pr}_session.json"
done
python3 "$TOOLS/verify_cpp_rtl_vs_golden_predicate500.py" --runs "$V/runs" | tee "$V/cpp_rtl_vs_golden_predicate500.txt"
for p in normal k4h4 k3h3; do
    "$BENCH" --engine rtl --policy $p --inputs "$C500" --reps 1 --out "$V/runs/rtl_$p.csv" --summary "$V/runs/rtl_$p.json" \
        --trace "$V/runs/rtl_$p.jsonl"
done
python3 "$TOOLS/verify_cpp_rtl_vs_golden_common500.py" --runs "$V/runs" | tee "$V/cpp_rtl_vs_golden_common500.txt"

# ============================================================ 3-5. timing per workload
# run <workload> <label> <command...>
#   predicate500: runs the command once per predicate, adding --pred/--a/--b/--datasets
#   common500   : runs it once
#   writes <R>/<label>[_<PRED>].csv/.json
run() {
    local wl=$1 label=$2; shift 2
    if [ "$wl" = predicate500 ]; then
        for pr in $PREDS; do
            energy "${wl}_${label}_$pr" "$@" --inputs "$C500" --pred $pr --a ${PA[$pr]} --b ${PB[$pr]} \
                --datasets "$P500" --out "$R/${label}_$pr.csv" --summary "$R/${label}_$pr.json"
        done
    else
        energy "${wl}_${label}" "$@" --inputs "$C500" --out "$R/$label.csv" --summary "$R/$label.json"
    fi
}

campaign() {   # campaign <workload>
    local wl=$1
    W="$OUT/$wl"; R="$W/runs"; mkdir -p "$R"
    echo "== 3. $wl: single core (core $CORE)"
    for prec in f64 f32; do
        for p in normal allj k3h3 k4h4; do
            run $wl "cpp_sw_${p}_${prec}_1c" taskset -c "$CORE" "$BENCH" --engine sw --policy $p --prec $prec --reps "$REPS"
        done
    done
    for p in normal k3h3 allj; do
        run $wl "cpp_rtl_${p}_1c" taskset -c "$CORE" "$BENCH" --engine rtl --policy $p --reps "$REPS"
    done
    for p in $BASELINE_POLICIES; do
        run $wl "numpy_${p}_1c" taskset -c "$CORE" $NUMPY --policy $p --reps 3
        if [ "${SKIP_QISKIT:-0}" != 1 ]; then
            run $wl "qiskit_${p}_1t" taskset -c "$CORE" $QISKIT --policy $p --threads 1 --reps 1 --seeds "$QISKIT_SEEDS"
        fi
    done
    if [ "${SKIP_GOLDEN:-0}" != 1 ]; then
        for p in $GOLDEN_POLICIES; do
            run $wl "golden_${p}_1c" taskset -c "$CORE" $GOLDEN --policy $p --reps 1
        done
    fi

    echo "== 3. $wl: multi-core latency (threads inside one Grover iteration)"
    for t in $(printf "%s\n" 2 4 8 "$PHYS" "$NPROC" | sort -n -u); do
        [ "$t" -le "$NPROC" ] || continue
        for prec in f64 f32; do
            run $wl "cpp_sw_normal_${prec}_T$t" "$BENCH" --engine sw --policy normal --prec $prec --threads "$t" --reps "$REPS"
        done
    done
    if [ "$NPROC" -ge 4 ]; then
        # SW counterpart of the board's K3/H3-E4-M2: K3H3 policy, one iteration split over
        # 4 cores (E4), hierarchical sampler (M2; the default sampler of every C++ core).
        echo "== 3. $wl: K3H3-E4-M2 counterpart (4 cores per search)"
        for prec in f64 f32; do
            run $wl "cpp_sw_k3h3_${prec}_T4" "$BENCH" --engine sw --policy k3h3 --prec $prec --threads 4 --reps "$REPS"
        done
        for p in normal k3h3; do
            run $wl "cpp_rtl_${p}_T4" "$BENCH" --engine rtl --policy $p --threads 4 --reps "$REPS"
        done
    fi
    if [ "${SKIP_QISKIT:-0}" != 1 ]; then
        for p in $BASELINE_POLICIES; do
            run $wl "qiskit_${p}_T$NPROC" $QISKIT --policy $p --threads "$NPROC" --reps 1 --seeds "$QISKIT_SEEDS"
        done
    fi

    for w in $FULL_COUNTS; do
        [ "$w" -ge 2 ] || continue
        echo "== 3. $wl: multi-core throughput ($w workloads in parallel)"
        for prec in f64 f32; do
            for p in normal allj; do
                run $wl "cpp_sw_${p}_${prec}_W$w" "$BENCH" --engine sw --policy $p --prec $prec --workers "$w" --reps "$REPS"
            done
        done
        run $wl "cpp_rtl_normal_W$w" "$BENCH" --engine rtl --policy normal --workers "$w" --reps "$REPS"
        for p in $BASELINE_POLICIES; do
            run $wl "numpy_${p}_W$w" $NUMPY --policy $p --workers "$w" --reps 3
        done
        if [ "${SKIP_GOLDEN:-0}" != 1 ]; then
            for p in $GOLDEN_POLICIES; do
                run $wl "golden_${p}_W$w" $GOLDEN --policy $p --workers "$w" --reps 1
            done
        fi
    done

    echo "== 4. $wl: cross-checks (same policy => same result per workload)"
    : > "$W/verify_baselines_vs_cpp.txt"
    check() { python3 "$TOOLS/verify_baselines_vs_cpp.py" --ref "$R"/$1*.csv --cpp "$R"/$2*.csv | tee -a "$W/verify_baselines_vs_cpp.txt"; }
    for p in $BASELINE_POLICIES; do                         # float family: NumPy / Qiskit = C++ float
        check "numpy_${p}_1c" "cpp_sw_${p}_f64_1c"
        [ "${SKIP_QISKIT:-0}" = 1 ] || check "qiskit_${p}_1t" "cpp_sw_${p}_f64_1c"
    done
    if [ "${SKIP_GOLDEN:-0}" != 1 ]; then                   # RTL family: golden = C++ RTL-exact (bit-exact)
        for p in $GOLDEN_POLICIES; do
            case $p in normal|k3h3|allj) check "golden_${p}_1c" "cpp_rtl_${p}_1c" ;; esac
        done
    fi
    for w in $FULL_COUNTS; do                                # throughput runs = 1-core runs
        [ "$w" -ge 2 ] || continue
        for p in $BASELINE_POLICIES; do check "numpy_${p}_W$w" "numpy_${p}_1c"; done
        if [ "${SKIP_GOLDEN:-0}" != 1 ]; then
            for p in $GOLDEN_POLICIES; do check "golden_${p}_W$w" "golden_${p}_1c"; done
        fi
    done

    if [ "$NPROC" -ge 4 ]; then
        echo "== 4. $wl: 4-core runs = 1-core runs (RTL-exact: bit-exact; float: same trajectory)"
        for k in cpp_rtl_normal cpp_rtl_k3h3 cpp_sw_k3h3_f64 cpp_sw_k3h3_f32; do
            check "${k}_T4" "${k}_1c"
        done
    fi

    echo "== 5. $wl: report"
    python3 "$TOOLS/summarize_results.py" --workload $wl --runs "$R" --out-dir "$W/report" --env-note "$ENV_NOTE"
}

if [ "$WORKLOAD" = predicate500 ] || [ "$WORKLOAD" = both ]; then campaign predicate500; fi
if [ "$WORKLOAD" = common500 ] || [ "$WORKLOAD" = both ]; then campaign common500; fi
echo "done: $OUT"
