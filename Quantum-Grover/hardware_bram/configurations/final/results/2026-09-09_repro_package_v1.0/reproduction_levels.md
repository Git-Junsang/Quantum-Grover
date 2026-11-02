# Reproduction levels

| Level | Command | Output | Exactness expectation |
|---|---|---|---|
| R0 | `repro.sh check` | tool/environment inventory | informational |
| R1 | `repro.sh anchor` | 5 logs, 6 anchor cycle values | exact |
| R2 | `repro.sh publication` | 2500 logs + 6-stage summary | exact under same RTL/simulator semantics |
| R3 | `repro.sh kh` | 750 logs + K/H summary | exact |
| R4 | `repro.sh resource` | 5 synthesis report sets | exact resource table is tied to Vivado 2024.2 common-condition flow |
| R5 | `repro.sh standalone` | routed reports + bitstream | timing closure required; exact resources/timing may depend on Vivado version/strategy |
| R6 | `repro.sh rvx` | instructions | external RVX environment required |
