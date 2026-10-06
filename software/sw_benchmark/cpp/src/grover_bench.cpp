// grover_bench.cpp : benchmark runner for every C++ model (Common500 and Predicate500).
//
//   model A1  --engine sw  --policy normal            CPP_SW_BEST_NORMAL_F64/F32  (main SW baseline)
//   model A2  --engine sw  --policy allj|k3h3|k4h4    CPP_SW_BEST_<POLICY>_F64/F32
//   model B   --engine rtl --policy normal|k3h3|k4h4|allj   CPP_RTL_EXACT_<POLICY>
//
// Options:
//
//   --engine rtl|sw        rtl = RTL-identical Q1.22 (model B), sw = SW best (model A)
//   --policy normal|k4h4|k3h3|allj
//   --prec f64|f32         (sw engine only)
//   --threads T            members of the SpinTeam inside one Grover iteration (latency mode,
//                          the SW counterpart of RTL E4; sw and rtl engines)
//   --workers W            workloads run concurrently (throughput mode)
//   --reps R               timed repetitions per workload after 1 warm-up (default 5)
//   --inputs DIR           software/experiments/common500_benchmark/inputs (seed roster + datasets/)
//   --targets 1,4,16,64,256  --seeds K (first K roster pairs)
//   --pred LT|GT|EQ|RANGE --a A --b B --datasets DIR
//                          Predicate500 datasets (DIR/dataset_<PRED>_target_<M>.bin,
//                          tools/make_predicate500_datasets.py); default = Common500 EQ 12345
//   --session              allj only: keep the state library across the seeds of a
//                          dataset (DRAM build behaviour); 1 pass, no warm-up
//   --out results.csv  --summary summary.json  --trace attempts.jsonl
//
// Timing tiers (all steady_clock ns):
//   compute_ns : Grover iterations only (oracle + diffusion)
//   search_ns  : search() call: j draws, iterations, policy, measurement
//   prep_ns    : dataset file read + oracle mask build (once per dataset)
//   e2e_ns     : prep_ns + search_ns  (workload-level load; amortized form in summary)
#include <pthread.h>
#include <sched.h>

#include <atomic>
#include <exception>

#include <cstring>
#include <iostream>
#include <map>
#include <thread>

#include "q14_contract.hpp"
#include "core_rtl_exact.hpp"
#include "core_sw_float.hpp"
#include "bbht_search.hpp"

using namespace grover;

struct Options {
    std::string engine = "sw", policy = "normal", prec = "f64", inputs, out = "results.csv",
                summary = "summary.json", trace, pred, datasets;
    int a = 12345, b = 0;
    bool session = false;
    std::vector<int> targets{1, 4, 16, 64, 256};
    int seeds = 100, reps = 5, threads = 1, workers = 1, shot_cap = DEFAULT_SHOT_CAP;
};

static std::vector<int> parse_list(const std::string& s) {
    std::vector<int> v;
    std::stringstream ss(s);
    std::string x;
    while (std::getline(ss, x, ',')) if (!x.empty()) v.push_back(std::stoi(x));
    return v;
}

static Options parse_args(int argc, char** argv) {
    Options o;
    for (int i = 1; i < argc; ++i) {
        std::string a = argv[i];
        auto next = [&]() -> std::string {
            if (i + 1 >= argc) throw std::invalid_argument("missing value for " + a);
            return argv[++i];
        };
        if (a == "--engine") o.engine = next();
        else if (a == "--policy") o.policy = next();
        else if (a == "--prec") o.prec = next();
        else if (a == "--inputs") o.inputs = next();
        else if (a == "--out") o.out = next();
        else if (a == "--summary") o.summary = next();
        else if (a == "--trace") o.trace = next();
        else if (a == "--targets") o.targets = parse_list(next());
        else if (a == "--seeds") o.seeds = std::stoi(next());
        else if (a == "--reps") o.reps = std::stoi(next());
        else if (a == "--threads") o.threads = std::stoi(next());
        else if (a == "--workers") o.workers = std::stoi(next());
        else if (a == "--shot-cap") o.shot_cap = std::stoi(next());
        else if (a == "--pred") o.pred = next();
        else if (a == "--a") o.a = std::stoi(next());
        else if (a == "--b") o.b = std::stoi(next());
        else if (a == "--datasets") o.datasets = next();
        else if (a == "--session") o.session = true;
        else throw std::invalid_argument("unknown option " + a);
    }
    if (o.inputs.empty()) throw std::invalid_argument("--inputs is required");
    if (!o.pred.empty() && o.datasets.empty()) throw std::invalid_argument("--pred needs --datasets");
    if (o.session && (o.policy != "allj" || o.workers != 1))
        throw std::invalid_argument("--session needs --policy allj and --workers 1");
    if (o.session) o.reps = 1;
    if (o.engine != "rtl" && o.engine != "sw") throw std::invalid_argument("--engine rtl|sw");
    if (o.threads > 1 && o.workers > 1) throw std::invalid_argument("use either --threads (latency) or --workers (throughput)");
    if (o.workers > 1 && !detail::kProcessCpus.empty() && size_t(o.workers) > detail::kProcessCpus.size())
        throw std::invalid_argument("--workers " + std::to_string(o.workers) + " needs that many CPUs; only " +
                                    std::to_string(detail::kProcessCpus.size()) + " are available");
    if (o.threads > 1 && !detail::kProcessCpus.empty() && size_t(o.threads) > detail::kProcessCpus.size())
        throw std::invalid_argument("--threads " + std::to_string(o.threads) + " needs that many CPUs; only " +
                                    std::to_string(detail::kProcessCpus.size()) + " are available");
    return o;
}

// ------------------------------------------------------------- energy (RAPL)
struct Rapl {
    std::string path = "/sys/class/powercap/intel-rapl:0/energy_uj";
    std::string range_path = "/sys/class/powercap/intel-rapl:0/max_energy_range_uj";
    bool ok = false;
    uint64_t range = 0;
    Rapl() {
        std::ifstream f(path);
        uint64_t v;
        ok = bool(f >> v);
        std::ifstream r(range_path);
        if (!(r >> range)) range = 0;
    }
    uint64_t read() const { std::ifstream f(path); uint64_t v = 0; f >> v; return v; }
    double delta_j(uint64_t a, uint64_t b) const {
        uint64_t d = b >= a ? b - a : (range ? range - a + b : 0);
        return double(d) * 1e-6;
    }
};

// ------------------------------------------------------------------- rows
struct Row {
    int target_count, seed_index;
    uint32_t seed_j, seed_meas;
    SearchResult res;
    int64_t search_med, search_min, compute_med, prep_ns;
    std::vector<int64_t> search_all;
};

static int64_t median(std::vector<int64_t> v) {
    std::sort(v.begin(), v.end());
    return v.empty() ? 0 : v[v.size() / 2];
}

template <class Core, class... Args>
static void run_dataset(const Options& o, int M, const std::vector<SeedPair>& roster, std::vector<Row>& rows,
                        std::ofstream* trace, Args&&... core_args) {
    std::string path = o.inputs + "/datasets/dataset_target_" + std::to_string(M) + ".bin";
    OracleConfig oc;   // EQ 12345, DATA_COUNT = N (official Common500 contract)
    if (!o.pred.empty()) {   // Predicate500
        path = o.datasets + "/dataset_" + o.pred + "_target_" + std::to_string(M) + ".bin";
        oc.predicate = parse_predicate(o.pred);
        oc.threshold_a = o.a;
        oc.threshold_b = o.b;
    }

    // prep tier: read the dataset and build the oracle mask. Median of at least
    // 5 samples: the value is copied to all 100 workloads of the dataset, so one
    // noisy sample would otherwise be multiplied by 100.
    std::vector<int64_t> preps;
    std::vector<uint8_t> mask;
    for (int k = 0; k < std::max(5, o.reps); ++k) {
        int64_t t0 = now_ns();
        auto data = load_dataset(path);
        mask = build_target_mask(data, oc);
        preps.push_back(now_ns() - t0);
    }
    int targets = 0;
    for (auto m : mask) targets += m;
    if (targets != M) throw std::runtime_error("mask target count mismatch for M=" + std::to_string(M));
    int64_t prep = median(preps);
    Policy pol = parse_policy(o.policy);
    size_t base = rows.size();
    int nseeds = std::min<int>(o.seeds, int(roster.size()));
    rows.resize(base + nseeds);

    // One search per seed. Throughput mode (--workers W): W threads, each with its
    // own engine, pull seeds from a shared counter; thread w is pinned to the w-th
    // CPU of the process mask (read at program start). No OpenMP runtime is used,
    // so nothing pins the process behind our back.
    std::atomic<int> next_seed{0};
    auto worker = [&](int w) {
        if (o.workers > 1 && !detail::kProcessCpus.empty()) {
            cpu_set_t one;
            CPU_ZERO(&one);
            CPU_SET(detail::kProcessCpus[size_t(w) % detail::kProcessCpus.size()], &one);
            pthread_setaffinity_np(pthread_self(), sizeof(one), &one);
        }
        Engine<Core> eng(pol, mask, core_args...);
        for (int s; (s = next_seed.fetch_add(1)) < nseeds;) {
            const SeedPair& sp = roster[s];
            Row row{};
            row.target_count = M; row.seed_index = sp.index; row.seed_j = sp.seed_j; row.seed_meas = sp.seed_meas;
            if (!o.session) eng.search(sp.seed_j, sp.seed_meas, o.shot_cap, false);   // warm-up
            std::vector<int64_t> st, ct;
            for (int k = 0; k < o.reps; ++k) {
                int64_t t0 = now_ns();
                SearchResult r = eng.search(sp.seed_j, sp.seed_meas, o.shot_cap, trace != nullptr && k == 0,
                                            o.session && s > 0);
                int64_t dt = now_ns() - t0;
                st.push_back(dt);
                ct.push_back(r.compute_ns);
                if (k == 0) row.res = std::move(r);
            }
            row.search_all = st;
            row.search_med = median(st);
            row.search_min = *std::min_element(st.begin(), st.end());
            row.compute_med = median(ct);
            row.prep_ns = prep;
            rows[base + s] = std::move(row);
        }
    };
    if (o.workers <= 1) {
        worker(0);
    } else {
        std::vector<std::thread> pool;
        std::vector<std::exception_ptr> errors(size_t(o.workers));
        for (int w = 0; w < o.workers; ++w)
            pool.emplace_back([&, w] {
                try { worker(w); } catch (...) { errors[size_t(w)] = std::current_exception(); }
            });
        for (auto& t : pool) t.join();
        for (auto& e : errors) if (e) std::rethrow_exception(e);
    }
    if (trace) {
        for (int s = 0; s < nseeds; ++s) {
            const Row& row = rows[base + s];
            *trace << "{\"predicate\":\"" << (o.pred.empty() ? "EQ" : o.pred) << "\",\"target_count\":" << M << ",\"seed_index\":" << row.seed_index << ",\"attempts\":[";
            for (size_t i = 0; i < row.res.attempts.size(); ++i) {
                const Attempt& a = row.res.attempts[i];
                *trace << (i ? "," : "") << "[" << a.requested_j << "," << a.source_j << "," << a.physical << ","
                       << a.threshold << "," << a.result_index << "," << (a.success ? 1 : 0) << "]";
            }
            *trace << "]}\n";
        }
    }
}

static std::string cpu_model() {
    std::ifstream f("/proc/cpuinfo");
    std::string line;
    while (std::getline(f, line))
        if (line.rfind("model name", 0) == 0) return line.substr(line.find(':') + 2);
    return "unknown";
}

static std::string json_escape(const std::string& s) {
    std::string o;
    for (char c : s) { if (c == '"' || c == '\\') o.push_back('\\'); o.push_back(c); }
    return o;
}

int main(int argc, char** argv) {
    try {
        Options o = parse_args(argc, argv);
        auto roster = load_seed_roster(o.inputs + "/official_board_seed_roster.h");
        std::unique_ptr<std::ofstream> trace;
        if (!o.trace.empty()) trace.reset(new std::ofstream(o.trace));
        std::vector<Row> rows;
        Rapl rapl;
        std::string backend;
        if (o.engine == "rtl") backend = std::string("CPP_RTL_EXACT_") + o.policy;
        else backend = std::string("CPP_SW_BEST_") + o.policy + "_" + o.prec;
        if (o.session) backend += "_session";
        for (auto& c : backend) c = char(std::toupper(c));

        uint64_t e0 = rapl.ok ? rapl.read() : 0;
        int64_t wall0 = now_ns();
        for (int M : o.targets) {
            if (o.engine == "rtl") run_dataset<RtlCore>(o, M, roster, rows, trace.get(), o.threads);
            else if (o.prec == "f32") run_dataset<FloatCore<float>>(o, M, roster, rows, trace.get(), o.threads);
            else run_dataset<FloatCore<double>>(o, M, roster, rows, trace.get(), o.threads);
        }
        int64_t wall = now_ns() - wall0;
        uint64_t e1 = rapl.ok ? rapl.read() : 0;

        std::ofstream csv(o.out);
        csv << "predicate,threshold_a,threshold_b,target_count,seed_index,seed_j,seed_meas,backend,policy,precision,threads,workers,reps,success,"
               "termination_reason,result_index,trial_count,L_BBHT,actual_grover_iterations,compute_ns,search_ns,"
               "search_ns_min,prep_ns,e2e_ns\n";
        char buf[32];
        std::map<int, std::array<int64_t, 3>> perM;   // search, compute, e2e sums
        int successes = 0;
        long trials = 0, L = 0, phys = 0;
        for (const Row& r : rows) {
            csv << (o.pred.empty() ? "EQ" : o.pred) << "," << o.a << "," << o.b << ","
                << r.target_count << "," << r.seed_index << ",";
            std::snprintf(buf, sizeof buf, "0x%08x,0x%08x", r.seed_j, r.seed_meas);
            csv << buf << "," << backend << "," << o.policy << "," << (o.engine == "rtl" ? "q1.22" : o.prec) << ","
                << o.threads << "," << o.workers << "," << o.reps << "," << int(r.res.success) << ","
                << termination_name(r.res.termination) << ",";
            if (r.res.success) csv << r.res.result_index;
            csv << "," << r.res.trial_count << "," << r.res.L_BBHT << "," << r.res.physical_iterations << ","
                << r.compute_med << "," << r.search_med << "," << r.search_min << "," << r.prep_ns << ","
                << (r.prep_ns + r.search_med) << "\n";
            auto& acc = perM[r.target_count];
            acc[0] += r.search_med; acc[1] += r.compute_med; acc[2] += r.prep_ns + r.search_med;
            successes += r.res.success; trials += r.res.trial_count; L += r.res.L_BBHT; phys += r.res.physical_iterations;
        }

        std::ofstream js(o.summary);
        js << "{\n  \"backend\": \"" << backend << "\",\n  \"engine\": \"" << o.engine << "\",\n  \"policy\": \"" << o.policy
           << "\",\n  \"precision\": \"" << (o.engine == "rtl" ? "q1.22" : o.prec) << "\",\n  \"threads\": " << o.threads
           << ",\n  \"workers\": " << o.workers << ",\n  \"reps\": " << o.reps << ",\n  \"workloads\": " << rows.size()
           << ",\n  \"success\": " << successes << ",\n  \"trials\": " << trials << ",\n  \"L_BBHT\": " << L
           << ",\n  \"physical_iterations\": " << phys << ",\n  \"campaign_wall_ns\": " << wall
           << ",\n  \"campaign_wall_note\": \"warm-up + reps + prep for all workloads\",\n  \"throughput_searches_per_s\": " << (double(rows.size()) * (o.reps + 1) / (wall / 1e9)) << ",\n  \"per_target\": {";
        bool first = true;
        int64_t ts = 0, tc = 0, te = 0;
        for (auto& [M, acc] : perM) {
            js << (first ? "" : ",") << "\n    \"" << M << "\": {\"search_ns_sum\": " << acc[0] << ", \"compute_ns_sum\": "
               << acc[1] << ", \"e2e_ns_sum\": " << acc[2] << "}";
            first = false; ts += acc[0]; tc += acc[1]; te += acc[2];
        }
        int64_t prep_amortized = 0;
        for (auto& [M, acc] : perM) { (void)acc; for (const Row& r : rows) if (r.target_count == M) { prep_amortized += r.prep_ns; break; } }
        js << "\n  },\n  \"search_ns_sum\": " << ts << ",\n  \"compute_ns_sum\": " << tc << ",\n  \"e2e_ns_sum_per_workload_load\": " << te
           << ",\n  \"e2e_ns_sum_load_once_per_dataset\": " << (ts + prep_amortized);
        if (rapl.ok) js << ",\n  \"rapl_package_energy_j\": " << rapl.delta_j(e0, e1);
        else js << ",\n  \"rapl_package_energy_j\": null";
        js << ",\n  \"environment\": {\"cpu\": \"" << json_escape(cpu_model()) << "\", \"hardware_threads\": "
           << std::thread::hardware_concurrency() << ", \"compiler\": \"" << json_escape(__VERSION__) << "\", \"flags\": \""
#ifdef BUILD_FLAGS
           << json_escape(BUILD_FLAGS)
#endif
           << "\", \"process_cpus\": " << detail::kProcessCpus.size() << "}\n}\n";

        std::fprintf(stderr, "%s: success %d/%zu trials %ld L %ld phys %ld search_sum %.3f ms compute_sum %.3f ms wall %.3f s%s\n",
                     backend.c_str(), successes, rows.size(), trials, L, phys, ts / 1e6, tc / 1e6, wall / 1e9,
                     rapl.ok ? "" : " (RAPL unavailable)");
        return 0;
    } catch (const std::exception& e) {
        std::fprintf(stderr, "error: %s\n", e.what());
        return 2;
    }
}
