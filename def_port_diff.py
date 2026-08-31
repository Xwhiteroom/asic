#!/bin/env python3
# Copyright (c) 2026 Syed Shakir Iqbal (Xwhiteroom)
# SPDX-License-Identifier: MIT
#-------------------------------------------------------------------------------
"""
Compare top-level PINS between two DEF files (plain or .gz) and report, as
top-level ("level 1") categories:

  - removed : ports present in --ref, gone in --tar
  - added   : ports present in --tar, not in --ref
  - common_moved : ports present in both, whose placed (x, y) differs

Each port entry includes its location (in microns) and which edge of the
DIEAREA boundary it sits on (LEFT/RIGHT/TOP/BOTTOM for the overall bounding
box, or NOTCH_V/NOTCH_H for an internal polygon edge when DIEAREA is a
non-rectangular polygon, as it is here).

Usage:
  def_port_diff.py --ref REF.def[.gz] --tar TAR.def[.gz] \
      [--out-dir DIR] [--out-prefix PREFIX] [--tol MICRONS]

Outputs (default dir ".", default prefix "def_port_diff"), created if
DIR doesn't exist yet:
  DIR/<prefix>.json           full structured data (all three categories)
  DIR/<prefix>_removed.csv
  DIR/<prefix>_added.csv
  DIR/<prefix>_common_moved.csv
and a summary printed to stdout.
"""

import argparse
import csv
import gzip
import json
import os
import re
import sys


PIN_HEADER_RE = re.compile(r'^\s*-\s+(\S+)')
NET_RE = re.compile(r'\+\s*NET\s+(\S+)')
DIRECTION_RE = re.compile(r'\+\s*DIRECTION\s+(\S+)')
LAYER_RE = re.compile(r'\+\s*LAYER\s+(\S+)')
PLACE_RE = re.compile(
    r'\+\s*(FIXED|PLACED|COVER)\s*\(\s*(-?\d+)\s+(-?\d+)\s*\)\s+(\S+)\s*;'
)
POINT_RE = re.compile(r'\(\s*(-?\d+)\s+(-?\d+)\s*\)')
UNITS_RE = re.compile(r'^UNITS\s+DISTANCE\s+MICRONS\s+(\d+)\s*;')


def opener(path):
    return gzip.open(path, 'rt') if path.endswith('.gz') else open(path, 'r')


def parse_pin_record(text):
    m = PIN_HEADER_RE.search(text)
    if not m:
        return None
    name = m.group(1)

    net_m = NET_RE.search(text)
    dir_m = DIRECTION_RE.search(text)
    layer_m = LAYER_RE.search(text)
    place_m = PLACE_RE.search(text)

    pin = {
        'name': name,
        'net': net_m.group(1) if net_m else '',
        'direction': dir_m.group(1) if dir_m else '',
        'layer': layer_m.group(1) if layer_m else '',
        'x': None,
        'y': None,
        'orient': '',
        'placed_type': '',
    }
    if place_m:
        pin['placed_type'] = place_m.group(1)
        pin['x'] = int(place_m.group(2))
        pin['y'] = int(place_m.group(3))
        pin['orient'] = place_m.group(4)
    return pin


def parse_def(path):
    """Return (units_per_micron, dieaea_points, {pin_name: pin_dict})."""
    units_per_micron = 1000
    diearea_pts = []
    pins = {}

    with opener(path) as f:
        in_pins = False
        record_lines = []
        for line in f:
            if not in_pins:
                u_m = UNITS_RE.match(line)
                if u_m:
                    units_per_micron = int(u_m.group(1))
                    continue
                if line.startswith('DIEAREA'):
                    diearea_pts = [(int(x), int(y)) for x, y in POINT_RE.findall(line)]
                    continue
                if line.startswith('PINS'):
                    in_pins = True
                    continue
                continue

            # in_pins == True
            if line.startswith('END PINS'):
                break

            record_lines.append(line.rstrip('\n'))
            if line.rstrip().endswith(';'):
                pin = parse_pin_record('\n'.join(record_lines))
                record_lines = []
                if pin:
                    pins[pin['name']] = pin

    return units_per_micron, diearea_pts, pins


def build_edges(diearea_pts):
    """Consecutive-vertex segments, closing the polygon back to point 0."""
    n = len(diearea_pts)
    edges = []
    for i in range(n):
        p1 = diearea_pts[i]
        p2 = diearea_pts[(i + 1) % n]
        edges.append((p1, p2))
    return edges


def classify_edge(x, y, edges, bbox):
    """Return (label, distance_in_def_units) for the CLOSEST DIEAREA edge
    segment -- ports commonly sit inset from the exact boundary line (pin
    shape geometry, routing margin), so exact coincidence is too strict;
    nearest-edge-with-distance degrades gracefully instead of going UNKNOWN."""
    min_x, min_y, max_x, max_y = bbox
    best_label = 'UNKNOWN'
    best_dist = None
    for (x1, y1), (x2, y2) in edges:
        if x1 == x2:  # vertical segment
            seg_min_y, seg_max_y = min(y1, y2), max(y1, y2)
            clamped_y = min(max(y, seg_min_y), seg_max_y)
            dist = ((x - x1) ** 2 + (y - clamped_y) ** 2) ** 0.5
            label = 'LEFT' if x1 == min_x else ('RIGHT' if x1 == max_x else 'NOTCH_V')
        elif y1 == y2:  # horizontal segment
            seg_min_x, seg_max_x = min(x1, x2), max(x1, x2)
            clamped_x = min(max(x, seg_min_x), seg_max_x)
            dist = ((x - clamped_x) ** 2 + (y - y1) ** 2) ** 0.5
            label = 'BOTTOM' if y1 == min_y else ('TOP' if y1 == max_y else 'NOTCH_H')
        else:
            continue  # non-orthogonal segment; not expected for this flow

        if best_dist is None or dist < best_dist:
            best_dist = dist
            best_label = label
    return best_label, best_dist


def bbox_of(points):
    xs = [p[0] for p in points]
    ys = [p[1] for p in points]
    return min(xs), min(ys), max(xs), max(ys)


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                  formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--ref', required=True, help='reference DEF (.def or .def.gz)')
    ap.add_argument('--tar', required=True, help='target DEF (.def or .def.gz)')
    ap.add_argument('--out-dir', default='.', help='directory to write outputs into (created if missing)')
    ap.add_argument('--out-prefix', default='def_port_diff', help='output file basename prefix')
    ap.add_argument('--tol', type=float, default=0.0,
                    help='minimum move distance in microns to report a common port as moved (default 0)')
    args = ap.parse_args()

    print('Parsing ref: %s' % args.ref, file=sys.stderr)
    ref_upm, ref_diearea, ref_pins = parse_def(args.ref)
    print('Parsing tar: %s' % args.tar, file=sys.stderr)
    tar_upm, tar_diearea, tar_pins = parse_def(args.tar)

    # Edge classification is done against the ref DEF's DIEAREA; if tar's
    # differs (shouldn't, normally, for the same tile) fall back to tar's
    # own for tar-only (added) ports.
    ref_edges = build_edges(ref_diearea) if ref_diearea else []
    ref_bbox = bbox_of(ref_diearea) if ref_diearea else (0, 0, 0, 0)
    tar_edges = build_edges(tar_diearea) if tar_diearea else ref_edges
    tar_bbox = bbox_of(tar_diearea) if tar_diearea else ref_bbox

    def um(v, upm):
        return v / float(upm) if v is not None else None

    ref_names = set(ref_pins.keys())
    tar_names = set(tar_pins.keys())

    removed_names = sorted(ref_names - tar_names)
    added_names = sorted(tar_names - ref_names)
    common_names = sorted(ref_names & tar_names)

    removed = []
    for name in removed_names:
        p = ref_pins[name]
        if p['x'] is not None:
            edge, edge_dist = classify_edge(p['x'], p['y'], ref_edges, ref_bbox)
            edge_dist_um = um(edge_dist, ref_upm)
        else:
            edge, edge_dist_um = 'UNPLACED', None
        removed.append({
            'name': name, 'net': p['net'], 'direction': p['direction'],
            'x_um': um(p['x'], ref_upm), 'y_um': um(p['y'], ref_upm),
            'orient': p['orient'], 'edge': edge, 'edge_dist_um': edge_dist_um,
        })

    added = []
    for name in added_names:
        p = tar_pins[name]
        if p['x'] is not None:
            edge, edge_dist = classify_edge(p['x'], p['y'], tar_edges, tar_bbox)
            edge_dist_um = um(edge_dist, tar_upm)
        else:
            edge, edge_dist_um = 'UNPLACED', None
        added.append({
            'name': name, 'net': p['net'], 'direction': p['direction'],
            'x_um': um(p['x'], tar_upm), 'y_um': um(p['y'], tar_upm),
            'orient': p['orient'], 'edge': edge, 'edge_dist_um': edge_dist_um,
        })

    common_moved = []
    for name in common_names:
        rp = ref_pins[name]
        tp = tar_pins[name]
        if rp['x'] is None or tp['x'] is None:
            continue
        rx_um, ry_um = um(rp['x'], ref_upm), um(rp['y'], ref_upm)
        tx_um, ty_um = um(tp['x'], tar_upm), um(tp['y'], tar_upm)
        dx = tx_um - rx_um
        dy = ty_um - ry_um
        if abs(dx) <= args.tol and abs(dy) <= args.tol:
            continue
        ref_edge, ref_edge_dist = classify_edge(rp['x'], rp['y'], ref_edges, ref_bbox)
        tar_edge, tar_edge_dist = classify_edge(tp['x'], tp['y'], tar_edges, tar_bbox)
        common_moved.append({
            'name': name, 'net': rp['net'], 'direction': rp['direction'],
            'ref_x_um': rx_um, 'ref_y_um': ry_um,
            'tar_x_um': tx_um, 'tar_y_um': ty_um,
            'dx_um': dx, 'dy_um': dy,
            'ref_edge': ref_edge, 'ref_edge_dist_um': um(ref_edge_dist, ref_upm),
            'tar_edge': tar_edge, 'tar_edge_dist_um': um(tar_edge_dist, tar_upm),
        })

    summary = {
        'ref_file': args.ref, 'tar_file': args.tar,
        'ref_pin_count': len(ref_names), 'tar_pin_count': len(tar_names),
        'common_count': len(common_names),
        'removed_count': len(removed), 'added_count': len(added),
        'common_moved_count': len(common_moved),
    }

    result = {
        'summary': summary,
        'removed': removed,
        'added': added,
        'common_moved': common_moved,
    }

    os.makedirs(args.out_dir, exist_ok=True)
    out_prefix = os.path.join(args.out_dir, args.out_prefix)

    json_path = out_prefix + '.json'
    with open(json_path, 'w') as f:
        json.dump(result, f, indent=2)

    def write_csv(path, rows, fieldnames):
        with open(path, 'w', newline='') as f:
            w = csv.DictWriter(f, fieldnames=fieldnames)
            w.writeheader()
            for r in rows:
                w.writerow(r)

    removed_csv = out_prefix + '_removed.csv'
    added_csv = out_prefix + '_added.csv'
    moved_csv = out_prefix + '_common_moved.csv'

    write_csv(removed_csv, removed,
              ['name', 'net', 'direction', 'x_um', 'y_um', 'orient', 'edge', 'edge_dist_um'])
    write_csv(added_csv, added,
              ['name', 'net', 'direction', 'x_um', 'y_um', 'orient', 'edge', 'edge_dist_um'])
    write_csv(moved_csv, common_moved,
              ['name', 'net', 'direction', 'ref_x_um', 'ref_y_um', 'tar_x_um', 'tar_y_um',
               'dx_um', 'dy_um', 'ref_edge', 'ref_edge_dist_um', 'tar_edge', 'tar_edge_dist_um'])

    print('')
    print('=== DEF port diff summary ===')
    for k, v in summary.items():
        print('%-18s: %s' % (k, v))
    print('')
    print('JSON:         %s' % json_path)
    print('removed CSV:  %s' % removed_csv)
    print('added CSV:    %s' % added_csv)
    print('moved CSV:    %s' % moved_csv)


if __name__ == '__main__':
    main()
