# 양자 에뮬레이터 레퍼런스 논문 목록

## 수집 방법

OpenAlex API로 보유 논문 15편을 시드 삼아 인용 그래프를 2-hop 양방향(시드가 인용한 논문 + 시드를 인용한 논문)으로 확장하고, FPGA·양자 에뮬레이션 키워드 14개로 추가 스윕했습니다. 후보 **2,824편**을 모아 제목 기준 관련도 필터로 **137편**을 남겼고, 그중 **26편**의 PDF를 `5. 추가 수집 (OpenAlex)/`에 받아뒀습니다.

> 각 논문의 분류와 관련도는 **제목·서지정보만으로 판단**한 것입니다. 본문을 읽고 검증하지 않았으므로, 실제 내용은 직접 확인이 필요합니다.

범례 — `✅` 기존 보유 · `⬇️` PDF 다운로드 완료 · `★` Grover 관련


## A. Grover 직접 관련 (9편)

| | 연도 | 인용 | 제목 | 출처 | DOI |
|---|---|---|---|---|---|
| ★ | 2023 | 9 | Practical Quantum Search by Variational Quantum Eigensolver on Noisy Intermediate-Scale Quantum |  | [10.1109/csci62032.2023.00071](https://doi.org/10.1109/csci62032.2023.00071) |
| ★ | 2017 | 7 | Parallel simulation of Shor's and Grover's algorithms in the distributed geometric machine |  | [10.1109/fskd.2017.8393304](https://doi.org/10.1109/fskd.2017.8393304) |
| ★ | 2020 | 4 | Modifying quantum Grover’s algorithm for dynamic multi-pattern search on reconfigurable hardwar | Journal of Computational Elect | [10.1007/s10825-020-01489-3](https://doi.org/10.1007/s10825-020-01489-3) |
| ⬇️★ | 2020 | 4 | Modelling of Grover’s quantum search algorithms: implementations of Simple quantum simulators o | System Analysis in Science and | [10.37005/2071-9612-2020-3-65-128](https://doi.org/10.37005/2071-9612-2020-3-65-128) |
| ★ | 2017 | 4 | Efficient In-Situ Quantum Computing Simulation of Shor's and Grover's Algorithms |  | [10.1109/sbac-padw.2017.19](https://doi.org/10.1109/sbac-padw.2017.19) |
| ★ | 2022 | 3 | FPGA Based Resource Efficient Simulation and Emulation Of Grover’s Search Algorithm | 2022 IEEE 19th India Council I | [10.1109/indicon56171.2022.10040039](https://doi.org/10.1109/indicon56171.2022.10040039) |
| ✅★ | 2025 | 2 | Feasibility and Limitations of Generalized Grover Search Algorithm-Based Quantum Asymmetric Cry | Electronics | [10.3390/electronics14193821](https://doi.org/10.3390/electronics14193821) |
| ✅★ | 2024 | 2 | Developing a Grover's quantum algorithm emulator on standalone FPGAs: optimization and implemen | AIMS Mathematics | [10.3934/math.20241493](https://doi.org/10.3934/math.20241493) |
| ★ | 2019 | 2 | A solution to implement Grover quantum computation algorithm using the binary representation of |  | [10.1109/ecai46879.2019.9042138](https://doi.org/10.1109/ecai46879.2019.9042138) |

## B. FPGA 양자 에뮬레이터 아키텍처 (핵심) (67편)

| | 연도 | 인용 | 제목 | 출처 | DOI |
|---|---|---|---|---|---|
|  | 2023 | 1032 | Logical quantum processor based on reconfigurable atom arrays | Nature | [10.1038/s41586-023-06927-3](https://doi.org/10.1038/s41586-023-06927-3) |
|  | 2021 | 101 | Reconfigurable Quantum Local Area Network Over Deployed Fiber | PRX Quantum | [10.1103/prxquantum.2.040304](https://doi.org/10.1103/prxquantum.2.040304) |
|  | 2004 | 73 | FPGA emulation of quantum circuits |  | [10.1109/iccd.2004.1347938](https://doi.org/10.1109/iccd.2004.1347938) |
| ⬇️ | 2018 | 63 | Reconfigurable optical implementation of quantum complex networks | New Journal of Physics | [10.1088/1367-2630/aabc77](https://doi.org/10.1088/1367-2630/aabc77) |
| ⬇️ | 2019 | 44 | An FPGA-Based Hardware Platform for the Control of Spin-Based Quantum Systems | IEEE Transactions on Instrumen | [10.1109/tim.2019.2910921](https://doi.org/10.1109/tim.2019.2910921) |
|  | 2008 | 43 | FPGA-Based Circuit Model Emulation of Quantum Algorithms |  | [10.1109/isvlsi.2008.43](https://doi.org/10.1109/isvlsi.2008.43) |
|  | 2016 | 38 | An FPGA-Based Quantum Computing Emulation Framework Based on Serial-Parallel Architecture | International Journal of Recon | [10.1155/2016/5718124](https://doi.org/10.1155/2016/5718124) |
| ⬇️ | 2018 | 34 | An FPGA-based real quantum computer emulator | Journal of Computational Elect | [10.1007/s10825-018-1287-5](https://doi.org/10.1007/s10825-018-1287-5) |
|  | 2019 | 31 | Scaling reconfigurable emulation of quantum algorithms at high precision and high throughput | Quantum Engineering | [10.1002/que2.19](https://doi.org/10.1002/que2.19) |
|  | 2021 | 30 | FPGA-Accelerated Quantum Computing Emulation and Quantum Key Distillation | IEEE Micro | [10.1109/mm.2021.3085431](https://doi.org/10.1109/mm.2021.3085431) |
| ✅ | 2023 | 28 | Towards Complete and Scalable Emulation of Quantum Algorithms on High-Performance Reconfigurabl | IEEE Transactions on Computers | [10.1109/tc.2023.3248276](https://doi.org/10.1109/tc.2023.3248276) |
|  | 2020 | 28 | Emulation of high-performance correlation-based quantum clustering algorithm for two-dimensiona | Quantum Information Processing | [10.1007/s11128-020-02683-9](https://doi.org/10.1007/s11128-020-02683-9) |
| ⬇️ | 2018 | 26 | A dynamically reconfigurable logic cell: from artificial neural networks to quantum-dot cellula | Applied Nanoscience | [10.1007/s13204-018-0653-8](https://doi.org/10.1007/s13204-018-0653-8) |
|  | 2004 | 25 | FPGA-based high-speed emulator of quantum computing |  | [10.1109/fpt.2003.1275727](https://doi.org/10.1109/fpt.2003.1275727) |
|  | 2017 | 20 | FPGA quantum computing emulator using high level design tools |  | [10.23919/sase-case.2017.8115369](https://doi.org/10.23919/sase-case.2017.8115369) |
| ⬇️ | 2023 | 19 | Quantum AI simulator using a hybrid CPU–FPGA approach | Scientific Reports | [10.1038/s41598-023-34600-2](https://doi.org/10.1038/s41598-023-34600-2) |
|  | 2002 | 17 | Evolving Quantum Circuits and an FPGA-based Quantum Computing Emulator | PDXScholar  (Portland State Un | — |
| ⬇️ | 2009 | 13 | A space-efficient quantum computer simulator suitable for high-speed FPGA implementation | Proceedings of SPIE, the Inter | [10.1117/12.817924](https://doi.org/10.1117/12.817924) |
|  | 2021 | 12 | An FPGA-based hardware abstraction of quantum computing systems | Journal of Computational Elect | [10.1007/s10825-021-01765-w](https://doi.org/10.1007/s10825-021-01765-w) |
|  | 2022 | 11 | Quantum Circuit Simulator based on FPGA | 2022 13th International Confer | [10.1109/ictc55196.2022.9952408](https://doi.org/10.1109/ictc55196.2022.9952408) |
| ⬇️ | 2018 | 9 | FPGA-based Digital Quantum Coprocessor | Advances in Cyber-Physical Sys | [10.23939/acps2018.02.067](https://doi.org/10.23939/acps2018.02.067) |
|  | 2020 | 8 | FPGA Based Digital Quantum Computer Verification |  | [10.1109/dessert50317.2020.9125077](https://doi.org/10.1109/dessert50317.2020.9125077) |
|  | 2019 | 8 | Dimension Reduction Using Quantum Wavelet Transform on a High-Performance Reconfigurable Comput | International Journal of Recon | [10.1155/2019/1949121](https://doi.org/10.1155/2019/1949121) |
|  | 2019 | 8 | Towards Lattice Quantum Chromodynamics on FPGA devices | Computer Physics Communication | [10.1016/j.cpc.2019.107029](https://doi.org/10.1016/j.cpc.2019.107029) |
| ⬇️ | 2024 | 6 | Project and Implementation of a Quantum Logic Gate Emulator on FPGA Using a Model-Based Design  | IEEE Access | [10.1109/access.2024.3377458](https://doi.org/10.1109/access.2024.3377458) |
|  | 2023 | 6 | Q2Logic: A Coarse-Grained FPGA Overlay targeting Schrödinger Quantum Circuit Simulations |  | [10.1109/ipdpsw59300.2023.00078](https://doi.org/10.1109/ipdpsw59300.2023.00078) |
|  | 2025 | 5 | A Reconfigurable Framework for Hybrid Quantum–Classical Computing | Algorithms | [10.3390/a18050271](https://doi.org/10.3390/a18050271) |
|  | 2022 | 5 | A Performance Optimization of Quantum Computing Simulation using FPGA | 2022 19th International Confer | [10.1109/ecti-con54298.2022.9795571](https://doi.org/10.1109/ecti-con54298.2022.9795571) |
|  | 2013 | 5 | Quantum FPGA architecture design |  | [10.1109/fpt.2013.6718386](https://doi.org/10.1109/fpt.2013.6718386) |
|  | 2024 | 4 | Qu-Trefoil: Large-Scale Quantum Circuit Simulator Working on FPGA With SATA Storages | IEEE Transactions on Computers | [10.1109/tc.2024.3521546](https://doi.org/10.1109/tc.2024.3521546) |
|  | 2024 | 4 | A data compressor for FPGA-based state vector quantum simulators |  | [10.1145/3665283.3665293](https://doi.org/10.1145/3665283.3665293) |
|  | 2024 | 4 | QHLS: An HLS Framework to Convert High-Level Descriptions to Quantum Circuits | IEEE Transactions on Computer- | [10.1109/tcad.2024.3391699](https://doi.org/10.1109/tcad.2024.3391699) |
|  | 2021 | 4 | QubiC: An Open-Source FPGA-Based Control and Measurement System for Superconducting Quantum Inf | IEEE Transactions on Quantum E | [10.1109/tqe.2021.3116540](https://doi.org/10.1109/tqe.2021.3116540) |
|  | 2024 | 3 | Quantum Optimization for FPGA-Placement |  | [10.1109/qce60285.2024.00080](https://doi.org/10.1109/qce60285.2024.00080) |
|  | 2023 | 3 | FPGA-based Deterministic and Low-Latency Control for Distributed Quantum Computing |  | [10.1109/infocomwkshps57453.2023.10226129](https://doi.org/10.1109/infocomwkshps57453.2023.10226129) |
|  | 2021 | 3 | New FPGA design solution using quantum computation concepts |  | [10.1109/siitme53254.2021.9663653](https://doi.org/10.1109/siitme53254.2021.9663653) |
|  | 2019 | 3 | Principles of Digital Quantum Coprocessor Based on a FPGA, which Operates under the Control of  |  | [10.1109/acitt.2019.8779932](https://doi.org/10.1109/acitt.2019.8779932) |
|  | 2025 | 2 | A Novel Data Representation Towards Efficient FPGA-based Quantum Computer Simulation |  | [10.1109/ismvl64713.2025.00031](https://doi.org/10.1109/ismvl64713.2025.00031) |
|  | 2025 | 2 | An FPGA-based Emulation Process for Dynamic Quantum Circuits |  | [10.1109/isqed65160.2025.11014465](https://doi.org/10.1109/isqed65160.2025.11014465) |
|  | 2022 | 2 | HLS Implementation of Quantum Shor’s Algorithm Using Matrix Pruning | 2022 Second International Conf | [10.1109/icaect54875.2022.9807860](https://doi.org/10.1109/icaect54875.2022.9807860) |
|  | 2021 | 2 | An Emulation of Quantum Error-Correction on an FPGA device |  | [10.1109/fpl53798.2021.00025](https://doi.org/10.1109/fpl53798.2021.00025) |
|  | 2019 | 2 | FPGA BASED K QUBIT DIGITAL QUANTUM COPROCESSOR | ELECTRICAL AND COMPUTER SYSTEM | [10.15276/eltecs.31.107.2019.10](https://doi.org/10.15276/eltecs.31.107.2019.10) |
| ⬇️ | 2026 | 1 | FPGA Based Quantum Circuit Simulator: Processing 30 Qubit Systems | Research Square | [10.21203/rs.3.rs-8581344/v1](https://doi.org/10.21203/rs.3.rs-8581344/v1) |
|  | 2025 | 1 | AEQUAM: Accelerating Quantum Algorithm Validation Through FPGA-Based Emulation | IEEE Access | [10.1109/access.2025.3589746](https://doi.org/10.1109/access.2025.3589746) |
|  | 2024 | 1 | A Table Look-Up Based Quantum Simulation Accelerator on an FPGA |  | [10.1109/icfpt64416.2024.11113474](https://doi.org/10.1109/icfpt64416.2024.11113474) |
|  | 2024 | 1 | Re-structuring CNN using quantum layer executed on FPGA hardware for classifying 2-D data |  | [10.1109/icdv61346.2024.10617085](https://doi.org/10.1109/icdv61346.2024.10617085) |
|  | 2023 | 1 | Enormous-Scale Quantum State Vector Calculation with FPGA-accelerated SATA storages |  | [10.1109/icfpt59805.2023.00049](https://doi.org/10.1109/icfpt59805.2023.00049) |
| ⬇️ | 2021 | 1 | FPGA Based Hardware Abstraction of Quantum Computing System | Research Square | [10.21203/rs.3.rs-467244/v1](https://doi.org/10.21203/rs.3.rs-467244/v1) |
|  | 2018 | 1 | An FPGA-based quantum circuit emulation framework using heisenberg representation | International Journal of Quant | [10.1142/s0219749918500521](https://doi.org/10.1142/s0219749918500521) |
|  | 2026 | 0 | Scalable Quantum Circuit Simulation via Circuit Cutting and FPGA Acceleration |  | [10.1145/3806645.3816155](https://doi.org/10.1145/3806645.3816155) |
|  | 2026 | 0 | Quantum Gate Simulation and Acceleration on FPGA | Lecture notes in electrical en | [10.1007/978-981-96-8690-2_18](https://doi.org/10.1007/978-981-96-8690-2_18) |
|  | 2026 | 0 | Testing an FPGA-based quantum bit emulator as a random number generator | Opto-Electronics Review | [10.24425/opelre.2026.157819](https://doi.org/10.24425/opelre.2026.157819) |
| ⬇️ | 2026 | 0 | FPGA-Based Emulation Framework for Two-Qubit Quantum Computation: Design, Implementation, and V |  | [10.17504/protocols.io.dm6gp4bqpgzp/v1](https://doi.org/10.17504/protocols.io.dm6gp4bqpgzp/v1) |
|  | 2026 | 0 | FPGA Acceleration of Quantum Circuit Primitives: Fixed-Point Microcoded Design and CPU Comparis |  | [10.1109/icecte69292.2026.11429464](https://doi.org/10.1109/icecte69292.2026.11429464) |
| ✅⬇️ | 2025 | 0 | Standalone FPGA-Based QAOA Emulator for Weighted-MaxCut on Embedded Devices | arXiv (Cornell University) | [10.48550/arxiv.2502.11316](https://doi.org/10.48550/arxiv.2502.11316) |
|  | 2025 | 0 | Evaluating Cost-Effective Reconfigurable Hardware for Quantum Simulation | Communications in computer and | [10.1007/978-3-031-85884-0_5](https://doi.org/10.1007/978-3-031-85884-0_5) |
|  | 2025 | 0 | Optical control system for quantum bit emulator based on green laser, AOM modulators and FPGA t | Opto-Electronics Review | [10.24425/opelre.2025.157332](https://doi.org/10.24425/opelre.2025.157332) |
|  | 2025 | 0 | FPGA acceleration of tensor network computing for quantum spin models | Review of Scientific Instrumen | [10.1063/5.0239473](https://doi.org/10.1063/5.0239473) |
|  | 2025 | 0 | Design and FPGA-Based Implementation of a Quantum-Inspired Single-Qubit Circuit |  | [10.1109/elexcom67950.2025.11451321](https://doi.org/10.1109/elexcom67950.2025.11451321) |
|  | 2025 | 0 | FPGA Implemented Quantum Approximate Optimization Algorithm for MaxCut Acceleration |  | [10.1109/icfpt67023.2025.00049](https://doi.org/10.1109/icfpt67023.2025.00049) |
| ⬇️ | 2024 | 0 | A Scalable FPGA Architecture for Quantum Computing Simulation | arXiv (Cornell University) | [10.48550/arxiv.2407.06415](https://doi.org/10.48550/arxiv.2407.06415) |
|  | 2024 | 0 | FPGA-Based Real-Time Processing for Optical Quantum Measurement and Control |  | [10.1109/itnec60942.2024.10733136](https://doi.org/10.1109/itnec60942.2024.10733136) |
| ⬇️ | 2024 | 0 | A Physical Model of Quantum Bit Behavior Based on a Programmable FPGA Integrated Circuit | Computer Science | [10.7494/csci.2023.25.4.6289](https://doi.org/10.7494/csci.2023.25.4.6289) |
| ⬇️ | 2021 | 0 | A design of FPGA framework for quantum computing simulation |  | [10.58837/chula.the.2021.110](https://doi.org/10.58837/chula.the.2021.110) |
|  | 2021 | 0 | Emulating a Quantum Computer with an FPGA | Bulletin of the American Physi | — |
|  | 2013 | 0 | A Co-processor architecture for simulation of quantum algorithms on FPGA | LA Referencia (Red Federada de | — |
|  | 2008 | 0 | A reconfigurable accelerator for quantum computations |  | [10.1109/fpl.2008.4630024](https://doi.org/10.1109/fpl.2008.4630024) |

## C. QFT / 기타 알고리즘 FPGA 에뮬레이션 (5편)

| | 연도 | 인용 | 제목 | 출처 | DOI |
|---|---|---|---|---|---|
|  | 2015 | 17 | An Accurate FPGA-Based Hardware Emulation on Quantum Fourier Transform |  | — |
|  | 2019 | 6 | Efficient FPGA Emulation of Quantum Fourier Transform |  | [10.1109/cstic.2019.8755730](https://doi.org/10.1109/cstic.2019.8755730) |
|  | 2014 | 6 | FPGA-based quantum circuit emulation: A case study on Quantum Fourier transform |  | [10.1109/isicir.2014.7029495](https://doi.org/10.1109/isicir.2014.7029495) |
|  | 2019 | 3 | Implementation and Analysis of Quantum Fourier Transform Gates Over FPGA Framework |  | [10.1109/meco.2019.8760171](https://doi.org/10.1109/meco.2019.8760171) |
|  | 2022 | 1 | Hierarchical IP Core Generator for Quantum Fourier Transform Implementation in FPGA | 2022 IEEE 17th International C | [10.1109/csit56902.2022.10000438](https://doi.org/10.1109/csit56902.2022.10000438) |

## D. QEC · 노이즈 · 암호 FPGA (10편)

| | 연도 | 인용 | 제목 | 출처 | DOI |
|---|---|---|---|---|---|
|  | 2020 | 58 | High-Speed Post-Processing in Continuous-Variable Quantum Key Distribution Based on FPGA Implem | Journal of Lightwave Technolog | [10.1109/jlt.2020.2985408](https://doi.org/10.1109/jlt.2020.2985408) |
|  | 2022 | 25 | FPGA Implementation of Compact Hardware Accelerators for Ring-Binary-LWE-based Post-quantum Cry | ACM Transactions on Reconfigur | [10.1145/3569457](https://doi.org/10.1145/3569457) |
|  | 2025 | 7 | Ascon on FPGA: Post-Quantum Safe Authenticated Encryption with Replay Protection for IoT | Electronics | [10.3390/electronics14132668](https://doi.org/10.3390/electronics14132668) |
|  | 2024 | 7 | Compact and Low-Latency FPGA-Based Number Theoretic Transform Architecture for CRYSTALS Kyber P | Information | [10.3390/info15070400](https://doi.org/10.3390/info15070400) |
|  | 2022 | 4 | FPGA-Based Implementation of Multidimensional Reconciliation Encoding in Quantum Key Distributi | Entropy | [10.3390/e25010080](https://doi.org/10.3390/e25010080) |
|  | 2025 | 3 | HySecure: FPGA-Based Hybrid Post-Quantum and Classical Cryptography Platform for End-to-End IoT | Electronics | [10.3390/electronics14193908](https://doi.org/10.3390/electronics14193908) |
| ⬇️ | 2023 | 2 | Scalable Quantum Error Correction for Surface Codes using FPGA | arXiv (Cornell University) | [10.48550/arxiv.2301.08419](https://doi.org/10.48550/arxiv.2301.08419) |
|  | 2022 | 2 | Design Exploration and Code Optimizations for FPGA-Based Post-Quantum Cryptography using High-L |  | [10.36227/techrxiv.19404413.v1](https://doi.org/10.36227/techrxiv.19404413.v1) |
|  | 2015 | 2 | FPGA-Based Emulation of a Synchronous Phase-Coded Quantum Cryptography System | Computación y Sistemas | [10.13053/cys-19-1-1549](https://doi.org/10.13053/cys-19-1-1549) |
|  | 2024 | 0 | FPGA-Based Quantum Emulator for Surface Code |  | [10.1109/ictc62082.2024.10827261](https://doi.org/10.1109/ictc62082.2024.10827261) |

## E. GPU / HPC 시뮬레이터 (16편)

| | 연도 | 인용 | 제목 | 출처 | DOI |
|---|---|---|---|---|---|
| ⬇️ | 2016 | 59 | High Performance Emulation of Quantum Circuits |  | [10.1109/sc.2016.73](https://doi.org/10.1109/sc.2016.73) |
|  | 2020 | 38 | Density Matrix Quantum Circuit Simulation via the BSP Machine on Modern GPU Clusters |  | [10.1109/sc41405.2020.00017](https://doi.org/10.1109/sc41405.2020.00017) |
|  | 2014 | 35 | GPU-aware distributed quantum simulation |  | [10.1145/2554850.2554892](https://doi.org/10.1145/2554850.2554892) |
|  | 2015 | 29 | Quantum Computer Simulation on Multi-GPU Incorporating Data Locality | Lecture notes in computer scie | [10.1007/978-3-319-27119-4_17](https://doi.org/10.1007/978-3-319-27119-4_17) |
|  | 2022 | 18 | Q-GPU: A Recipe of Optimizations for Quantum Circuit Simulation Using GPUs |  | [10.1109/hpca53966.2022.00059](https://doi.org/10.1109/hpca53966.2022.00059) |
|  | 2011 | 13 | Parallel quantum computer simulation on the GPU |  | — |
|  | 2023 | 11 | Communication Optimizations for State-vector Quantum Simulator on CPU+GPU Clusters |  | [10.1145/3605573.3605631](https://doi.org/10.1145/3605573.3605631) |
|  | 2017 | 7 | Quantum Computer Simulation on GPU Cluster Incorporating Data Locality | Lecture notes in computer scie | [10.1007/978-3-319-68505-2_8](https://doi.org/10.1007/978-3-319-68505-2_8) |
|  | 2007 | 7 | Simulation of quantum gates on a novel GPU architecture |  | — |
|  | 2024 | 6 | Performance analysis and modeling for quantum computing simulation on distributed GPU platforms | Quantum Information Processing | [10.1007/s11128-024-04580-x](https://doi.org/10.1007/s11128-024-04580-x) |
|  | 2019 | 4 | Improving in situ GPU simulation of quantum computing in the D-GM environment | The International Journal of H | [10.1177/1094342018823251](https://doi.org/10.1177/1094342018823251) |
|  | 2025 | 2 | Quantum Emulators: CPU, single GPU and multiple GPUs performance comparison | Procedia Computer Science | [10.1016/j.procs.2025.08.248](https://doi.org/10.1016/j.procs.2025.08.248) |
|  | 2014 | 2 | Preliminary performance evaluations of the determinant quantum Monte Carlo simulations for mult | International Journal of Compu | [10.1504/ijcse.2014.058695](https://doi.org/10.1504/ijcse.2014.058695) |
|  | 2022 | 1 | dgQuEST: Accelerating Large Scale Quantum Circuit Simulation through Hybrid CPU-GPU Memory Hier | Lecture notes in computer scie | [10.1007/978-3-030-93571-9_2](https://doi.org/10.1007/978-3-030-93571-9_2) |
|  | 2026 | 0 | quEStab: Towards Scalable Quantum Circuit Simulation on Multi-GPU using an Extended Stabilizer  |  | [10.1145/3797905.3816723](https://doi.org/10.1145/3797905.3816723) |
|  | 2023 | 0 | ScalaQC: a scalability optimization framework for full-state quantum simulation on CPU+GPU hete | CCF Transactions on High Perfo | [10.1007/s42514-023-00145-z](https://doi.org/10.1007/s42514-023-00145-z) |

## F. 기타 하드웨어·에뮬레이션 (30편)

| | 연도 | 인용 | 제목 | 출처 | DOI |
|---|---|---|---|---|---|
| ⬇️ | 2019 | 158 | A flexible high-performance simulator for verifying and benchmarking quantum circuits implement | npj Quantum Information | [10.1038/s41534-019-0196-1](https://doi.org/10.1038/s41534-019-0196-1) |
|  | 2021 | 131 | <tt>Qibo</tt> : a framework for quantum simulation with hardware acceleration | Quantum Science and Technology | [10.1088/2058-9565/ac39f5](https://doi.org/10.1088/2058-9565/ac39f5) |
|  | 2020 | 25 | Griffiths-McCoy singularity on the diluted Chimera graph: Monte Carlo simulations and experimen | Physical review. A/Physical re | [10.1103/physreva.102.042403](https://doi.org/10.1103/physreva.102.042403) |
| ⬇️ | 2022 | 19 | Investigating hardware acceleration for simulation of CFD quantum circuits | Frontiers in Mechanical Engine | [10.3389/fmech.2022.925637](https://doi.org/10.3389/fmech.2022.925637) |
|  | 2003 | 19 | 16-Qubit Quantum-Computing Emulation Based on High-Speed Hardware Architecture | Japanese Journal of Applied Ph | [10.1143/jjap.42.2182](https://doi.org/10.1143/jjap.42.2182) |
|  | 2020 | 13 | Efficient Computation Techniques and Hardware Architectures for Unitary Transformations in Supp | Journal of Signal Processing S | [10.1007/s11265-020-01569-4](https://doi.org/10.1007/s11265-020-01569-4) |
|  | 2018 | 9 | Towards Higher Scalability of Quantum Hardware Emulation Using Efficient Resource Scheduling |  | [10.1109/icrc.2018.8638610](https://doi.org/10.1109/icrc.2018.8638610) |
|  | 2015 | 9 | Efficient emulation of quantum circuits on classical hardware |  | [10.1109/lascas.2015.7250404](https://doi.org/10.1109/lascas.2015.7250404) |
|  | 2011 | 9 | Hardware emulation of Quantum Fourier Transform |  | [10.1109/lascas.2011.5750269](https://doi.org/10.1109/lascas.2011.5750269) |
| ⬇️ | 2025 | 7 | Simulation of Quantum Computers: Review and Acceleration Opportunities | ACM Transactions on Quantum Co | [10.1145/3762672](https://doi.org/10.1145/3762672) |
|  | 2025 | 5 | Accelerating two-dimensional electronic spectroscopy simulations with a probe qubit protocol | Physical Review Research | [10.1103/physrevresearch.7.023130](https://doi.org/10.1103/physrevresearch.7.023130) |
| ⬇️ | 2016 | 5 | SIMULATION OF QUANTUM COMPUTING USING HARDWARE CORES | Polythematic Online Scientific | [10.21515/1990-4665-123-037](https://doi.org/10.21515/1990-4665-123-037) |
|  | 2024 | 4 | Parallel quantum computing simulations via quantum accelerator platform virtualization | Future Generation Computer Sys | [10.1016/j.future.2024.06.007](https://doi.org/10.1016/j.future.2024.06.007) |
|  | 2009 | 4 | On using FPGAS to accelerate the emulation of quantum computing |  | [10.1109/ccece.2009.5090115](https://doi.org/10.1109/ccece.2009.5090115) |
|  | 2003 | 4 | QCE: A Simulator for Quantum Computer Hardware | University of Groningen resear | — |
|  | 2025 | 3 | Accelerating Simulation of Quantum Circuits under Noise via Computational Reuse |  | [10.1145/3695053.3730992](https://doi.org/10.1145/3695053.3730992) |
|  | 2020 | 3 | A hardware architecture for the Walsh–Hadamard transform toward fast simulation of quantum algo | CCF Transactions on High Perfo | [10.1007/s42514-020-00028-7](https://doi.org/10.1007/s42514-020-00028-7) |
|  | 2024 | 2 | Theoretical Analysis of the Memory-Efficient Matrix Storage Method for Quantum Emulation Accele |  | [10.1109/mcsoc64144.2024.00067](https://doi.org/10.1109/mcsoc64144.2024.00067) |
| ⬇️ | 2024 | 2 | Simulation of Quantum Computers: Review and Acceleration Opportunities | arXiv (Cornell University) | [10.48550/arxiv.2410.12660](https://doi.org/10.48550/arxiv.2410.12660) |
|  | 2019 | 2 | Improving Emulation of Quantum Algorithms using Space-Efficient Hardware Architectures |  | [10.1109/asap.2019.000-1](https://doi.org/10.1109/asap.2019.000-1) |
|  | 2014 | 2 | The hardware implementation of a quantum computation system emulator |  | [10.1109/ae.2014.7011682](https://doi.org/10.1109/ae.2014.7011682) |
|  | 2026 | 1 | Advancing Full-Stack Acceleration for SchröDinger-Style Quantum Simulation |  | [10.1109/hpca68181.2026.11408466](https://doi.org/10.1109/hpca68181.2026.11408466) |
|  | 2025 | 1 | QEA: An Accelerator for Quantum Circuit Simulation with Resources Efficiency and Flexibility |  | [10.1109/icdv66179.2025.11135229](https://doi.org/10.1109/icdv66179.2025.11135229) |
| ⬇️ | 2024 | 1 | AMARETTO: Enabling Efficient Quantum Algorithm Emulation on Low-Tier FPGAs |  | [10.1109/icecs61496.2024.10848965](https://doi.org/10.1109/icecs61496.2024.10848965) |
| ⬇️ | 2021 | 1 | Fast quantum circuit simulation using hardware accelerated general purpose libraries | arXiv (Cornell University) | [10.48550/arxiv.2106.13995](https://doi.org/10.48550/arxiv.2106.13995) |
| ⬇️ | 2021 | 1 | Fast quantum circuit simulation using hardware accelerated general purpose libraries |  | [10.1109/isvlsi51109.2021.00086](https://doi.org/10.1109/isvlsi51109.2021.00086) |
| ⬇️ | 2026 | 0 | Accelerated Quantum Algorithm Prototyping: Modular Simulation and Noise Modelling with CUDA Sup | Journal of Advances in Informa | [10.12720/jait.17.6.1188-1210](https://doi.org/10.12720/jait.17.6.1188-1210) |
| ⬇️ | 2024 | 0 | Theoretical Analysis of the Efficient-Memory Matrix Storage Method for Quantum Emulation Accele | arXiv (Cornell University) | [10.48550/arxiv.2410.11146](https://doi.org/10.48550/arxiv.2410.11146) |
|  | 2014 | 0 | Emulación en hardware de circuitos cuánticos basados en compuertas Toffoli Hardware emulation o |  | — |
|  | 2014 | 0 | Hardware emulation of quantum circuits based on Toffoli gates | Revista Facultad de Ingeniería | [10.17533/udea.redin.19660](https://doi.org/10.17533/udea.redin.19660) |