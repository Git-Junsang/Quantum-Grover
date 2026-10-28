# Known optional additions / gaps

The package is usable now. The following may be added later without changing current authoritative results:

- Exact corrected historical checkpoint-DSE harness files, if recovered: `ckpt_core_tiebreak.py`, `tb_exp.py`, `agg_tb.py`. The package currently preserves the older DSE harness/results under `11_OPTIONAL_CHECKPOINT_DSE/legacy_input/`; do not infer that the old `ckpt_core.py` alone is the final corrected tie-break harness.
- A frozen RVX framework/repository snapshot is intentionally **not bundled**. RVX remains an external dependency.

No current publication RTL/resource/KH-isolated/standalone source is intentionally missing from this package.
