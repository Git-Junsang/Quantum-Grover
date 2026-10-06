# Builds the C++ models into build/:
#   build/grover_bench       benchmark runner (models A1, A2, B)
#   build/grover_single_run  single-dataset driver for the verification tools
CXX ?= g++
CXXFLAGS ?= -O3 -march=native -std=c++17 -fopenmp-simd -pthread -Wall -Wextra
# -fopenmp-simd: only the `#pragma omp simd` vectorization hints; no OpenMP runtime
# (threads are our own, see cpp/include/spin_team.hpp and grover_bench.cpp).
FLAGS_STR := $(CXX) $(CXXFLAGS)
BIN := build/grover_bench build/grover_single_run

all: $(BIN)

build/%: cpp/src/%.cpp cpp/include/*.hpp
	@mkdir -p build
	$(CXX) $(CXXFLAGS) -DBUILD_FLAGS='"$(FLAGS_STR)"' -Icpp/include $< -o $@

clean:
	rm -rf build
.PHONY: all clean
