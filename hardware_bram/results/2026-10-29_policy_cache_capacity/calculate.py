#!/usr/bin/env python3
"""Calculate declared generic-policy storage for the Main-IP connection.

This is a capacity audit, not a simulation or synthesis result. The candidate
array reserves a worst-case upper bound at every search depth. Unused depths,
unique-action shortcuts, RAM aspect ratios, and physical port implementation
are deliberately not translated into a synthesized RAM count.
"""
from __future__ import annotations

import csv
import hashlib
import json
import math
from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.colors import LogNorm
from matplotlib.patches import Rectangle


OUT = Path(__file__).resolve().parent
ROOT = OUT.parents[2]
POLICY = ROOT / "hardware_bram/src/grover_policy_parameterized.sv"
MAIN = ROOT / "hardware_bram/src/bbht_grover_main_ip.v"
RESOURCE = ROOT / "hardware_bram/results/2026-10-29_engine_sweep/resource_model.json"


def main() -> None:
    policy_source = POLICY.read_text()
    main_source = MAIN.read_text()
    # Guard the particular declarations audited by this calculation. A source
    # change should require reviewing the method rather than silently reusing it.
    for declaration in (
        "WORD_W=U+CW+11",
        "CACHE_N=cache_bound(U-1,K-1)",
        "cache[0:(H+1)*CACHE_N-1]",
        "MEMO_ADDR_W=12",
        "EPOCH_W=16",
        "memo_depth[0:MEM_SIZE-1]",
    ):
        assert declaration in policy_source, declaration
    assert "CKPT_COUNT_W=(CHECKPOINT_CAPACITY>4)?$clog2(CHECKPOINT_CAPACITY+1):3" in main_source
    assert ".COUNT_W(CKPT_COUNT_W)" in main_source

    tiles = json.loads(RESOURCE.read_text())["available"]["bram"]
    tile_bits = 36 * 1024
    device_bits = int(tiles * tile_bits)
    rows = []
    image_values = []
    for capacity in range(1, 11):
        image_row = []
        for lookahead in range(1, 11):
            # Main IP retains at least four physical slots and a three-bit
            # count. The standalone solver's default count width can differ
            # for capacities below four; use the integrated connection here.
            count_width = max(4, capacity).bit_length()
            universe = capacity + lookahead + 1
            entry_bits = universe + count_width + 11
            per_frame = sum(
                math.comb(capacity + lookahead, size)
                for size in range(capacity)
            )
            frames = lookahead + 1
            entries = frames * per_frame
            cache_bits = entries * entry_bits
            # Epoch, full set tag, request depth and exact cost. This excludes
            # DFS registers, the lower-bound pipeline and memory port logic.
            memo_bits = 4096 * (16 + universe + 4 + 11)
            rows.append({
                "k": capacity,
                "h": lookahead,
                "count_width_bits": count_width,
                "candidate_entry_bits": entry_bits,
                "candidate_entries_per_frame": per_frame,
                "declared_frames": frames,
                "candidate_entries": entries,
                "candidate_bits": cache_bits,
                "candidate_kib": cache_bits / 8192,
                "candidate_bram36_capacity_min": math.ceil(cache_bits / tile_bits),
                "candidate_exceeds_device_bram_capacity": cache_bits > device_bits,
                "memo_bits": memo_bits,
                "memo_kib": memo_bits / 8192,
                "cache_and_memo_kib": (cache_bits + memo_bits) / 8192,
            })
            image_row.append(cache_bits / 8192)
        image_values.append(image_row)

    with (OUT / "capacity.csv").open("w", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)
    with (OUT / "candidate_kib.csv").open("w", newline="") as stream:
        writer = csv.writer(stream)
        writer.writerow(["checkpoint_capacity / lookahead", *range(1, 11)])
        for capacity, values in enumerate(image_values, 1):
            writer.writerow([capacity, *(f"{value:.6f}" for value in values)])

    metadata = {
        "scope": "Main-IP-connected generic solver declarations; not synthesis or necessary minimum storage",
        "range": {"k": [1, 10], "h": [1, 10]},
        "memo_address_bits": 12,
        "memo_epoch_bits": 16,
        "direct_dependence_on_iteration_or_square_engines": False,
        "device_bram36_tiles": tiles,
        "device_bram_kib": device_bits / 8192,
        "assumptions": [
            "Generic solver is selected, including force_generic where applicable.",
            "Physical RAM usage also depends on banking, ports and aspect ratios.",
            "Unique-action and unused-depth synthesis pruning is not estimated.",
            "Memo, amplitude, dataset, SoC and all other state are excluded from the candidate heatmap.",
            "Default memo table capacity and tag widths are held fixed.",
        ],
        "sha256": {
            str(path.relative_to(ROOT)): hashlib.sha256(path.read_bytes()).hexdigest()
            for path in (POLICY, MAIN, RESOURCE)
        },
        "rows": len(rows),
    }
    (OUT / "method.json").write_text(json.dumps(metadata, indent=2) + "\n")

    fig, ax = plt.subplots(figsize=(12.4, 10.6))
    fig.subplots_adjust(left=0.11, right=0.94, bottom=0.11, top=0.87)
    norm = LogNorm(vmin=min(map(min, image_values)), vmax=max(map(max, image_values)))
    colors = plt.get_cmap("YlGnBu")
    mesh = ax.imshow(image_values, origin="lower", norm=norm, cmap=colors)
    for row in rows:
        x, y = row["h"] - 1, row["k"] - 1
        value = row["candidate_kib"]
        label = f"{value:.3f}" if value < 1 else f"{value:,.1f}"
        r, g, b, _ = colors(norm(value))
        color = "white" if 0.299 * r + 0.587 * g + 0.114 * b < 0.52 else "#132634"
        ax.text(x, y, label, ha="center", va="center", fontsize=9, color=color)
        if row["candidate_exceeds_device_bram_capacity"]:
            ax.add_patch(Rectangle((x - 0.47, y - 0.47), 0.94, 0.94,
                                   fill=False, edgecolor="#db2828", linewidth=2))
    ax.set_xticks(range(10), range(1, 11))
    ax.set_yticks(range(10), range(1, 11))
    ax.set_xlabel("Lookahead-Shots")
    ax.set_ylabel("Checkpoint-Capacity")
    ax.set_title("Generic policy candidate cache: declared capacity (KiB)\n"
                 "Main-IP count width; independent of iteration / square engine counts\n"
                 f"Red border: cache alone exceeds all 200T BRAM ({device_bits / 8192:,.1f} KiB)",
                 fontsize=12, pad=16)
    fig.colorbar(mesh, ax=ax, label="Declared candidate cache (KiB; logarithmic color scale)", shrink=0.82)
    fig.text(0.02, 0.025,
             "Capacity audit only. Excludes memo and datapath memories; unmarked cells do not establish fit. "
             "Not a synthesized RAM count.", fontsize=9)
    fig.savefig(OUT / "candidate_cache_heatmap.png", dpi=170)
    fig.savefig(OUT / "candidate_cache_heatmap.svg")
    plt.close(fig)
    print(f"Calculated {len(rows)} configurations; device BRAM {device_bits / 8192:,.1f} KiB")


if __name__ == "__main__":
    main()
