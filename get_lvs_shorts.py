#!/usr/bin/env python3
"""
# Copyright (c) 2026 Syed Shakir Iqbal (Xwhiteroom)
# SPDX-License-Identifier: MIT


Summarize a Calibre-style LVS shorts report (lvs.sum.shorts).
Produces a 4-level summary:
  Level 0 - By Net-pair          : per net-pair total/unique counts and a per-layer shorts breakdown
  Level 1 - Overall              : total short count, unique (net-pair,layer) count, layers involved
  Level 2 - By Layer             : per layer total/unique counts and which net-pairs occur on it
  Level 3 - By Layer > Net-pair  : per (layer, net-pair) total/unique counts, with the two shorted nets reported as start/end
Each SHORT violation is printed 4x in the report (plain, "BY CELL","BY LAYER (X)", "BY CELL BY LAYER (X)"). 
This script reads only the plain and "BY LAYER (X)" header lines (skipping the "BY CELL" duplicates) to avoid double counting.
Multiple report files can be summarized together with -f/--file (repeatable).
"""

import argparse
import csv
import re
import sys
from collections import defaultdict
from tabulate import tabulate
HEADER_RE = re.compile(r'^SHORT (\d+)\.\s+(.+?) - (.+?) in (\S+)(?: BY LAYER \(([^)]+)\))?$')
DEFAULT_FILE = ("lvs.sum.shorts")


def parse(path, file_tag):
    """Parse one lvs.sum.shorts file. file_tag namespaces SHORT numbers so multiple reports can be merged without number collisions."""
    all_short_keys = set()
    plain_keys = set()
    layer_occurrences = []        # list of (key, layer, norm_pair, disp_pair)
    with open(path, "r", errors="replace") as f:
        for line in f:
            if not line.startswith("SHORT "):
                continue
            line = line.rstrip("\n")
            if "BY CELL" in line:
                continue
            m = HEADER_RE.match(line)
            if not m:
                continue
            num_s, net1, net2, cell, layer = m.groups()
            key = (file_tag, int(num_s))
            all_short_keys.add(key)
            disp_pair = (net1, net2)
            norm_pair = tuple(sorted((net1, net2)))

            if layer:
                layer_occurrences.append((key, layer, norm_pair, disp_pair))
            else:
                plain_keys.add(key)

    seen_with_layer = {k for k, *_ in layer_occurrences}
    shorts_without_layer = all_short_keys - seen_with_layer

    # Diagnostic: Calibre abbreviates large reports - past some SHORT number the
    # plain/"BY CELL" geometry blocks stop being emitted and only "BY LAYER"
    # blocks continue. Surface that cutover so counts aren't mistaken for a
    # simple truncation/cutoff of the whole report.
    abbreviated_from = None
    plain_nums = {n for _, n in plain_keys}
    all_nums = {n for _, n in all_short_keys}
    if plain_nums and all_nums - plain_nums:
        max_plain = max(plain_nums)
        if max(all_nums) > max_plain:
            abbreviated_from = max_plain + 1

    return all_short_keys, layer_occurrences, shorts_without_layer, abbreviated_from


def parse_files(paths):
    all_short_keys = set()
    layer_occurrences = []
    shorts_without_layer = set()
    abbreviations = []  # list of (path, abbreviated_from)

    for path in paths:
        keys, occ, no_layer, abbrev_from = parse(path, file_tag=path)
        all_short_keys |= keys
        layer_occurrences.extend(occ)
        shorts_without_layer |= no_layer
        if abbrev_from:
            abbreviations.append((path, abbrev_from))

    return all_short_keys, layer_occurrences, shorts_without_layer, abbreviations


def build_summary(all_short_keys, layer_occurrences, shorts_without_layer, abbreviations):
    # Level 0: by net-pair, with a per-layer breakdown
    pair_layer_total = defaultdict(lambda: defaultdict(int))
    pair_layer_keys = defaultdict(lambda: defaultdict(set))
    for key, layer, norm_pair, _ in layer_occurrences:
        pair_layer_total[norm_pair][layer] += 1
        pair_layer_keys[norm_pair][layer].add(key)

    level0 = []
    for norm_pair, layer_counts in pair_layer_total.items():
        total = sum(layer_counts.values())
        uniq_keys = set()
        for s in pair_layer_keys[norm_pair].values():
            uniq_keys |= s
        breakdown = " ".join(f"{layer}:{cnt}" for layer, cnt in sorted(layer_counts.items()))
        level0.append({
            "pair": f"{norm_pair[0]}-{norm_pair[1]}",
            "total_count": total,
            "unique_count": len(uniq_keys),
            "layers": sorted(layer_counts.keys()),
            "layers_breakdown": breakdown,
        })
    level0.sort(key=lambda r: r["total_count"], reverse=True)

    # Level 1: overall
    layers = sorted({layer for _, layer, _, _ in layer_occurrences})
    uniq_pair_layer = {(norm_pair, layer) for _, layer, norm_pair, _ in layer_occurrences}

    level1 = {
        "total_count": len(all_short_keys),
        "unique_count": len(uniq_pair_layer),
        "layers": layers,
        "shorts_without_layer_info": len(shorts_without_layer),
        "abbreviations": abbreviations,
    }

    # Level 2: by layer
    layer_total = defaultdict(int)
    layer_pairs = defaultdict(set)
    for key, layer, norm_pair, _ in layer_occurrences:
        layer_total[layer] += 1
        layer_pairs[layer].add(norm_pair)

    level2 = []
    for layer in layers:
        level2.append({
            "layer": layer,
            "total_count": layer_total[layer],
            "unique_count": len(layer_pairs[layer]),
            "net_pairs": sorted(layer_pairs[layer]),
        })

    # Level 3: by layer > net-pair
    key_total = defaultdict(int)
    key_shorts = defaultdict(set)
    key_display = {}
    for key, layer, norm_pair, disp_pair in layer_occurrences:
        group_key = (layer, norm_pair)
        key_total[group_key] += 1
        key_shorts[group_key].add(key)
        key_display.setdefault(group_key, disp_pair)

    level3 = []
    for layer in layers:
        for norm_pair in sorted(layer_pairs[layer]):
            group_key = (layer, norm_pair)
            start, end = key_display[group_key]
            level3.append({
                "layer": layer,
                "start": start,
                "end": end,
                "total_count": key_total[group_key],
                "unique_count": len(key_shorts[group_key]),
            })

    return level0, level1, level2, level3


def print_report(level0, level1, level2, level3, tablefmt="github", max_level=0):
    if max_level >= 0:
        print("LEVEL 0 - BY NET-PAIR")
        l0_rows = [
            [row["pair"], row["total_count"], row["unique_count"], row["layers_breakdown"]]
            for row in level0
        ]
        print(tabulate(l0_rows, headers=["Net-pair", "Total", "Uniq", "Layers (layer:count)"], tablefmt=tablefmt))
        print()

    if max_level >= 1:
        print("LEVEL 1 - OVERALL SUMMARY")
        l1_rows = [
            ["Total short count", level1["total_count"]],
            ["Unique (net-pair, layer)", level1["unique_count"]],
            ["Layers involved", f"({len(level1['layers'])}) " + ", ".join(level1["layers"])],
        ]
        if level1["shorts_without_layer_info"]:
            l1_rows.append(["Shorts with no layer info", level1["shorts_without_layer_info"]])
        for path, abbrev_from in level1["abbreviations"]:
            l1_rows.append([
                f"Abbreviated report: {path}",
                f"only 'BY LAYER' blocks emitted past SHORT {abbrev_from - 1}; "
                f"counts above still include these",
            ])
        print(tabulate(l1_rows, headers=["Metric", "Value"], tablefmt=tablefmt))
        print()

    if max_level >= 2:
        print("LEVEL 2 - BY LAYER")
        l2_rows = [
            [row["layer"], row["total_count"], row["unique_count"],
             ", ".join(f"{a}-{b}" for a, b in row["net_pairs"])]
            for row in level2
        ]
        print(tabulate(l2_rows, headers=["Layer", "Total", "Uniq", "Net-pairs"], tablefmt=tablefmt))
        print()

    if max_level >= 3:
        print("LEVEL 3 - BY LAYER > NET-PAIR (start/end nets)")
        l3_rows = [
            [row["layer"], row["start"], row["end"], row["total_count"], row["unique_count"]]
            for row in level3
        ]
        print(tabulate(l3_rows, headers=["Layer", "Start", "End", "Total", "Uniq"], tablefmt=tablefmt))


def write_csv(level3, path):
    with open(path, "w", newline="") as f:
        w = csv.writer(f)
        w.writerow(["layer", "start_net", "end_net", "total_count", "unique_short_count"])
        for row in level3:
            w.writerow([row["layer"], row["start"], row["end"], row["total_count"], row["unique_count"]])


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("file", nargs="?", default=None, help="path to lvs.sum.shorts (positional, optional)")
    ap.add_argument("-f", "--file", dest="files", action="append", metavar="PATH", help="path to lvs.sum.shorts (repeatable, e.g. -f run1/lvs.sum.shorts -f run2/lvs.sum.shorts)")
    ap.add_argument("--csv", metavar="PATH", help="write level-3 (layer x net-pair) breakdown to CSV")
    ap.add_argument("--tablefmt", default="github", help="tabulate table format (default: github)")
    ap.add_argument("--max_level", type=int, choices=[0, 1, 2, 3, 4], default=0, help="only print levels 0..max_level (4 is treated as 3, the highest level). Default: 0")
    args = ap.parse_args()

    paths = args.files if args.files else ([args.file] if args.file else [DEFAULT_FILE])
    max_level = min(args.max_level, 3)

    all_short_keys, layer_occurrences, shorts_without_layer, abbreviations = parse_files(paths)
    level0, level1, level2, level3 = build_summary(all_short_keys, layer_occurrences, shorts_without_layer, abbreviations)
    print_report(level0, level1, level2, level3, tablefmt=args.tablefmt, max_level=max_level)

    if args.csv:
        write_csv(level3, args.csv)
        print(f"\nWrote level-3 breakdown to {args.csv}")


if __name__ == "__main__":
    sys.exit(main())
