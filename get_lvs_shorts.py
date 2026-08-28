#!/usr/bin/env python3
"""
# Copyright (c) 2026 Syed Shakir Iqbal (Xwhiteroom)
# SPDX-License-Identifier: MIT


Summarize a Calibre-style LVS shorts report (lvs.sum.shorts).
Produces a 5-level summary:
  Level 0 - By Net-pair          : per net-pair total/unique counts, a per-layer shorts breakdown, and start/end net coordinates
  Level 1 - Overall              : total short count, unique (net-pair,layer) count, layers involved
  Level 2 - By Layer             : per layer total/unique counts and which net-pairs occur on it
  Level 3 - By Layer > Net-pair  : per (layer, net-pair) total/unique counts, with the two shorted nets and their coordinates reported as start/end
  Level 4 - By Net               : start/end nets merged into one unique-net table, with shorts count, coordinate, and layers per net
Each SHORT violation is printed 4x in the report (plain, "BY CELL","BY LAYER (X)", "BY CELL BY LAYER (X)").
This script reads only the plain and "BY LAYER (X)" header lines (skipping the "BY CELL" duplicates) to avoid double counting.
Net coordinates are read from the "<net>" at (x, y) on layer "..." lines that follow each SHORT header.
Multiple report files can be summarized together with -f/--file (repeatable).
"""

import argparse
import csv
import re
import os
import sys
from collections import defaultdict
from tabulate import tabulate
HEADER_RE = re.compile(r'^SHORT (\d+)\.\s+(.+?) - (.+?) in (\S+)(?: BY LAYER \(([^)]+)\))?$')
SHORTED_TEXT_COUNT_RE = re.compile(r'^\s*(\d+)\s+Shorted texts:')
SHORTED_TEXT_RE = re.compile(r'^"([^"]+)"\s+at\s+\(([^,]+),\s*([^)]+)\)')
DEFAULT_FILE = ("lvs.sum.shorts")

def read_shorted_text_coords(it, lookahead=5):
    """Consume lines from `it` (positioned right after a SHORT header line) to
    pull the (x, y) coordinate of each shorted net's text label. Returns a
    dict of {net_name: (x, y)}."""
    coords = {}
    for _ in range(lookahead):
        try:
            line = next(it)
        except StopIteration:
            return coords
        m = SHORTED_TEXT_COUNT_RE.match(line)
        if m:
            for _ in range(int(m.group(1))):
                try:
                    text_line = next(it)
                except StopIteration:
                    break
                tm = SHORTED_TEXT_RE.match(text_line)
                if tm:
                    name, x, y = tm.groups()
                    coords[name] = (float(x), float(y))
            return coords
    return coords

def parse(path, file_tag):
    """Parse one lvs.sum.shorts file. file_tag namespaces SHORT numbers so multiple reports can be merged without number collisions."""
    all_short_keys = set()
    plain_keys = set()
    layer_occurrences = []        # list of (key, layer, norm_pair, disp_pair, coords)
    with open(path, "r", errors="replace") as f:
        it = iter(f)
        for line in it:
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
                coords = read_shorted_text_coords(it)  # {net_name: (x, y)}
                layer_occurrences.append((key, layer, norm_pair, disp_pair, coords))
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
    pair_coords = {}  # norm_pair -> first-seen {net_name: (x, y)}
    for key, layer, norm_pair, _, coords in layer_occurrences:
        pair_layer_total[norm_pair][layer] += 1
        pair_layer_keys[norm_pair][layer].add(key)
        pair_coords.setdefault(norm_pair, coords)

    level0 = []
    for norm_pair, layer_counts in pair_layer_total.items():
        total = sum(layer_counts.values())
        uniq_keys = set()
        for s in pair_layer_keys[norm_pair].values():
            uniq_keys |= s
        breakdown = " ".join(f"{layer}:{cnt}" for layer, cnt in sorted(layer_counts.items()))
        repr_coords = pair_coords[norm_pair]
        level0.append({
            "pair": f"{norm_pair[0]}-{norm_pair[1]}",
            "start": norm_pair[0],
            "end": norm_pair[1],
            "start_coord": repr_coords.get(norm_pair[0]),
            "end_coord": repr_coords.get(norm_pair[1]),
            "total_count": total,
            "unique_count": len(uniq_keys),
            "layers": sorted(layer_counts.keys()),
            "layers_breakdown": breakdown,
        })
    level0.sort(key=lambda r: r["total_count"], reverse=True)

    # Level 1: overall
    layers = sorted({layer for _, layer, _, _, _ in layer_occurrences})
    uniq_pair_layer = {(norm_pair, layer) for _, layer, norm_pair, _, _ in layer_occurrences}

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
    for key, layer, norm_pair, _, _ in layer_occurrences:
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
    key_coords = {}
    for key, layer, norm_pair, disp_pair, coords in layer_occurrences:
        group_key = (layer, norm_pair)
        key_total[group_key] += 1
        key_shorts[group_key].add(key)
        key_display.setdefault(group_key, disp_pair)
        key_coords.setdefault(group_key, coords)

    level3 = []
    for layer in layers:
        for norm_pair in sorted(layer_pairs[layer]):
            group_key = (layer, norm_pair)
            start, end = key_display[group_key]
            repr_coords = key_coords[group_key]
            level3.append({
                "layer": layer,
                "start": start,
                "end": end,
                "start_coord": repr_coords.get(start),
                "end_coord": repr_coords.get(end),
                "total_count": key_total[group_key],
                "unique_count": len(key_shorts[group_key]),
            })

    # Level 4: by net (start and end merged into one unique-net table)
    net_count = defaultdict(int)
    net_layers = defaultdict(set)
    net_coord = {}
    for key, layer, norm_pair, disp_pair, coords in layer_occurrences:
        for net_name in disp_pair:
            net_count[net_name] += 1
            net_layers[net_name].add(layer)
            net_coord.setdefault(net_name, coords.get(net_name))

    level4 = []
    for net_name in net_count:
        level4.append({
            "net": net_name,
            "count": net_count[net_name],
            "coord": net_coord[net_name],
            "layers": sorted(net_layers[net_name]),
        })
    level4.sort(key=lambda r: r["count"], reverse=True)

    return level0, level1, level2, level3, level4

def fmt_coord(coord):
    return f"({coord[0]:.3f}, {coord[1]:.3f})" if coord else "-"

def print_report(level0, level1, level2, level3, level4, tablefmt="github", max_level=0):
    if max_level >= 0:
        print("LEVEL 0 - BY NET-PAIR")
        l0_rows = [
            [row["pair"], row["total_count"], row["unique_count"],
             fmt_coord(row["start_coord"]), fmt_coord(row["end_coord"]),
             row["layers_breakdown"]]
            for row in level0
        ]
        print(tabulate(l0_rows, headers=["Net-pair", "Total", "Uniq", "Start", "End",
                                          "Layers (layer:count)"], tablefmt=tablefmt))
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
            [row["layer"], fmt_coord(row["start_coord"]), fmt_coord(row["end_coord"]),
             row["total_count"], row["unique_count"]]
            for row in level3
        ]
        print(tabulate(l3_rows, headers=["Layer", "Start", "End", "Total", "Uniq"], tablefmt=tablefmt))
        print()

    # Level 4 always publishes, regardless of --max_level.
    print("LEVEL 4 - BY NET (start/end merged)")
    l4_rows = [
        [row["net"], row["count"], fmt_coord(row["coord"]), ", ".join(row["layers"])]
        for row in level4
    ]
    print(tabulate(l4_rows, headers=["Net", "Shorts (as start or end)", "Coord", "Layers"], tablefmt=tablefmt))

def write_level0_csv(level0, path):
    with open(path, "w", newline="") as f:
        w = csv.writer(f)
        w.writerow(["net_pair", "total_count", "unique_count", "start_net", "start_x", "start_y",
                    "end_net", "end_x", "end_y", "layers_breakdown"])
        for row in level0:
            sx, sy = row["start_coord"] or ("", "")
            ex, ey = row["end_coord"] or ("", "")
            w.writerow([row["pair"], row["total_count"], row["unique_count"], row["start"], sx, sy,
                        row["end"], ex, ey, row["layers_breakdown"]])

def write_level1_csv(level1, path):
    with open(path, "w", newline="") as f:
        w = csv.writer(f)
        w.writerow(["metric", "value"])
        w.writerow(["total_short_count", level1["total_count"]])
        w.writerow(["unique_net_pair_layer_count", level1["unique_count"]])
        w.writerow(["layers_involved", ", ".join(level1["layers"])])
        w.writerow(["shorts_without_layer_info", level1["shorts_without_layer_info"]])
        for abbrev_path, abbrev_from in level1["abbreviations"]:
            w.writerow([f"abbreviated_report:{abbrev_path}", f"only 'BY LAYER' blocks past SHORT {abbrev_from - 1}"])

def write_level2_csv(level2, path):
    with open(path, "w", newline="") as f:
        w = csv.writer(f)
        w.writerow(["layer", "total_count", "unique_count", "net_pairs"])
        for row in level2:
            pairs_str = ", ".join(f"{a}-{b}" for a, b in row["net_pairs"])
            w.writerow([row["layer"], row["total_count"], row["unique_count"], pairs_str])

def write_level3_csv(level3, path):
    with open(path, "w", newline="") as f:
        w = csv.writer(f)
        w.writerow(["layer", "start_net", "start_x", "start_y", "end_net", "end_x", "end_y",
                    "total_count", "unique_short_count"])
        for row in level3:
            sx, sy = row["start_coord"] or ("", "")
            ex, ey = row["end_coord"] or ("", "")
            w.writerow([row["layer"], row["start"], sx, sy, row["end"], ex, ey,
                        row["total_count"], row["unique_count"]])

def write_level4_csv(level4, path):
    with open(path, "w", newline="") as f:
        w = csv.writer(f)
        w.writerow(["net", "shorts_count", "x", "y", "layers"])
        for row in level4:
            x, y = row["coord"] or ("", "")
            w.writerow([row["net"], row["count"], x, y, ", ".join(row["layers"])])


def write_csvs(level0, level1, level2, level3, level4, csv_path):
    """Write one CSV per level, suffixing the given path with .levelN before the extension."""
    base, ext = os.path.splitext(csv_path)
    ext = ext or ".csv"
    out_paths = [f"{base}.level{n}{ext}" for n in range(5)]
    write_level0_csv(level0, out_paths[0])
    write_level1_csv(level1, out_paths[1])
    write_level2_csv(level2, out_paths[2])
    write_level3_csv(level3, out_paths[3])
    write_level4_csv(level4, out_paths[4])
    return out_paths


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("file", nargs="?", default=None, help="path to lvs.sum.shorts (positional, optional)")
    ap.add_argument("-f", "--file", dest="files", action="append", metavar="PATH", help="path to lvs.sum.shorts (repeatable, e.g. -f run1/lvs.sum.shorts -f run2/lvs.sum.shorts)")
    ap.add_argument("--csv", metavar="PATH", help="write all levels (0-4) to CSV, suffixing PATH with .level0..level4 before its extension")
    ap.add_argument("--tablefmt", default="github", help="tabulate table format (default: github)")
    ap.add_argument("--max_level", type=int, choices=[0, 1, 2, 3, 4], default=0, help="only print levels 0..max_level (Level 4, the by-net table, always prints regardless). Default: 0")
    args = ap.parse_args()

    paths = args.files if args.files else ([args.file] if args.file else [DEFAULT_FILE])
    [print("# MISSING - ", os.path.abspath(p)) for p in paths if not os.path.exists(p)]; paths = [p for p in paths if os.path.exists(p)]
    for p in paths:      print("# REPORTS - " , os.path.abspath(p))
    max_level = args.max_level

    all_short_keys, layer_occurrences, shorts_without_layer, abbreviations = parse_files(paths)
    print()
    level0, level1, level2, level3, level4 = build_summary(all_short_keys, layer_occurrences, shorts_without_layer, abbreviations)
    print_report(level0, level1, level2, level3, level4, tablefmt=args.tablefmt, max_level=max_level)

    if args.csv:
        out_paths = write_csvs(level0, level1, level2, level3, level4, args.csv)
        print("\n# WROTE CSVs - ")
        for p in out_paths:
            print(f"  {p}")

if __name__ == "__main__":
    sys.exit(main())
