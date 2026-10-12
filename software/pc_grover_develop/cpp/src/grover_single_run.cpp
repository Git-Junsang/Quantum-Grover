// grover_single_run.cpp : one dataset, one call. Used by tools/verify_cpp_oracles.py
// and tools/verify_cpp_rtl_vectors.py (not a benchmark).
//
//   grover_single_run mask   <data.bin> <PRED> <a> <b> <count>
//       -> prints the target indices (one line, space separated)
//   grover_single_run search <data.bin> <PRED> <a> <b> <count> <engine> <policy> <prec> <seed_j> <seed_meas>
//       -> prints "success result_index trial_count L_BBHT physical"
//   grover_single_run core   <data.bin> <PRED> <a> <b> <count> <j>
//       -> RTL core only: prints the 16384 final Q1.22 amplitudes (one per line)
#include <iostream>

#include "q14_contract.hpp"
#include "core_rtl_exact.hpp"
#include "core_sw_float.hpp"
#include "bbht_search.hpp"

using namespace grover;

int main(int argc, char** argv) {
    try {
        if (argc < 7) throw std::invalid_argument("usage: see header");
        std::string cmd = argv[1];
        auto data = load_dataset(argv[2]);
        OracleConfig oc;
        oc.predicate = parse_predicate(argv[3]);
        oc.threshold_a = std::stoi(argv[4]);
        oc.threshold_b = std::stoi(argv[5]);
        oc.data_count = std::stoi(argv[6]);
        auto mask = build_target_mask(data, oc);
        if (cmd == "mask") {
            bool first = true;
            for (int i = 0; i < N; ++i)
                if (mask[i]) { std::cout << (first ? "" : " ") << i; first = false; }
            std::cout << "\n";
            return 0;
        }
        if (cmd == "core") {
            int j = std::stoi(argv[7]);
            RtlCore core(mask);
            RtlCore::State st;
            core.reset_state(st);
            int64_t ns = 0;
            core.run(st, j, ns);
            for (int i = 0; i < N; ++i) std::cout << st.a[i] << "\n";
            return 0;
        }
        if (cmd == "search") {
            std::string engine = argv[7];
            Policy pol = parse_policy(argv[8]);
            std::string prec = argv[9];
            uint32_t sj = uint32_t(std::stoul(argv[10], nullptr, 0));
            uint32_t sm = uint32_t(std::stoul(argv[11], nullptr, 0));
            SearchResult r;
            if (engine == "rtl") { Engine<RtlCore> e(pol, mask); r = e.search(sj, sm); }
            else if (prec == "f32") { Engine<FloatCore<float>> e(pol, mask, 1); r = e.search(sj, sm); }
            else { Engine<FloatCore<double>> e(pol, mask, 1); r = e.search(sj, sm); }
            std::cout << int(r.success) << " " << r.result_index << " " << r.trial_count << " " << r.L_BBHT << " "
                      << r.physical_iterations << "\n";
            return 0;
        }
        throw std::invalid_argument("unknown command " + cmd);
    } catch (const std::exception& e) {
        std::cerr << "error: " << e.what() << "\n";
        return 2;
    }
}
