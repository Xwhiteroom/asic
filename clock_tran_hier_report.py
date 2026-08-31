#!/usr/bin/env python3
# Copyright (c) 2026 Syed Shakir Iqbal (Xwhiteroom)
# SPDX-License-Identifier: MIT
#
#---------------------------------------------------------------------------------------------
"""Hierarchical clock-transition-violation report, rolled up by driver tile, across corners.

Parses one or more PT "Common Report Format: Clock Transition" reports
(clock_trans.rpt / clock_trans.rpt.gz), groups every violating net by its
*driver* instance (mapped to a "tile" name via a user-supplied regex map),
and reports -- per tile, per corner -- how many sinks are affected and what
the worst (most negative slack) offending sink looked like. Tile names may
encode a hierarchy with '/' (e.g. "CORE/CT/DAISYCHAIN") and will be rolled
up accordingly.

Mapping file format (CSV, first match wins, '#' comments allowed):
    regex_pattern,tile_name
    ^core[0-9]+/ct0e/,CORE/CT0E
    ^core[0-9]+/,CORE/OTHER
    ^c3x_lid_chnl_l/,LID/CHNL_L
    ^c3x_lid_dftio/,LID/DFTIO

The regex is matched (re.search) against the full Driver instance+pin path
as it appears in the report, e.g.:
    core9/ct0e/ct0e_SLM/ct/ct_daisychnl_mustw0rk/.../ZN
"""
import argparse
import csv
import functools
import gzip
import multiprocessing as mp
import os
import re
import sys
import time
from collections import Counter, defaultdict

NET_RE = re.compile(r'^Net:\s+(\S+)')
SLACK_RE = re.compile(r'^\s*Slack:\s+(-?[\d.]+)')
VALUE_RE = re.compile(r'^\s*Value:\s+(-?[\d.]+)')
LIMIT_RE = re.compile(r'^\s*Limit:\s+(-?[\d.]+)')
CLOCK_RE = re.compile(r'^\s*Clock:\s+(\S+)')
DRIVER_RE = re.compile(r'^\s*Driver:\s+(\S+)\s+\(([^)]*)\)')
SINK_RE = re.compile(r'^\s*Sink:\s+(\S+)\s+\(([^)]*)\)')
TRANS_RE = re.compile(r'^\s*Trans:\s+(-?[\d.]+)')
PHYS_RE = re.compile(r'^\s*Physical Coordinates:\s+(-?[\d.]+)\s+(-?[\d.]+)')
END_RE = re.compile(r'^\s*;\s*$')


def open_rpt(path):
    if path.endswith('.gz'):
        return gzip.open(path, 'rt', errors='replace')
    return open(path, 'r', errors='replace')


def corner_of(path):
    return path.rsplit('/', 2)[-2] if '/' in path else path


def load_mapping(path):
    rules = []
    with open(path, newline='') as fh:
        for row in csv.reader(fh):
            if not row:
                continue
            first = row[0].strip()
            if not first or first.startswith('#'):
                continue
            if len(row) < 2 or not row[1].strip():
                raise ValueError(f"Bad mapping line (need 'pattern,tile_name'): {row}")
            rules.append((re.compile(row[0].strip()), row[1].strip()))
    return rules


def map_tile(driver_path, rules, unmapped_counter, unmapped_label):
    for rx, tile in rules:
        if rx.search(driver_path):
            return tile
    unmapped_counter[driver_path.split('/', 1)[0]] += 1
    return unmapped_label


def parse_blocks(fh):
    """Yield finished violation blocks: dicts with net/clock/limit/driver_path/sinks."""
    block = None
    state = None  # 'driver' or 'sink'
    cur_sink = None
    for line in fh:
        m = NET_RE.match(line)
        if m:
            block = {'net': m.group(1), 'sinks': []}
            state = None
            cur_sink = None
            continue
        if block is None:
            continue
        m = SLACK_RE.match(line)
        if m:
            block['slack'] = float(m.group(1))
            continue
        m = VALUE_RE.match(line)
        if m:
            block['value'] = float(m.group(1))
            continue
        m = LIMIT_RE.match(line)
        if m:
            block['limit'] = float(m.group(1))
            continue
        m = CLOCK_RE.match(line)
        if m:
            block['clock'] = m.group(1)
            continue
        m = DRIVER_RE.match(line)
        if m:
            block['driver_path'] = m.group(1)
            block['driver_cell'] = m.group(2)
            state = 'driver'
            continue
        m = SINK_RE.match(line)
        if m:
            cur_sink = {'path': m.group(1), 'cell': m.group(2)}
            block['sinks'].append(cur_sink)
            state = 'sink'
            continue
        m = TRANS_RE.match(line)
        if m:
            if state == 'sink' and cur_sink is not None:
                cur_sink['trans'] = float(m.group(1))
            elif state == 'driver':
                block['driver_trans'] = float(m.group(1))
            continue
        m = PHYS_RE.match(line)
        if m:
            x, y = float(m.group(1)), float(m.group(2))
            if state == 'sink' and cur_sink is not None:
                cur_sink['x'], cur_sink['y'] = x, y
            elif state == 'driver':
                block['driver_x'], block['driver_y'] = x, y
            continue
        if END_RE.match(line):
            if 'driver_path' in block:
                yield block
            block = None
            state = None
            cur_sink = None
            continue
        # ignore everything else (comments, physical coordinates, banners, ...)


def new_stat():
    return {'count': 0, 'worst_slack': None, 'worst_clock': None, 'worst_trans': None,
            'worst_limit': None, 'worst_net': None, 'worst_driver': None, 'worst_sink': None}


def merge_stat(dst, src):
    dst['count'] += src['count']
    if src['worst_slack'] is not None and (dst['worst_slack'] is None or src['worst_slack'] < dst['worst_slack']):
        for k in ('worst_slack', 'worst_clock', 'worst_trans', 'worst_limit', 'worst_net', 'worst_driver', 'worst_sink'):
            dst[k] = src[k]


def process_file(path, rules, count_mode, tile_corner_stats, unmapped_counter, unmapped_label):
    corner = corner_of(path)
    nblocks = 0
    with open_rpt(path) as fh:
        for block in parse_blocks(fh):
            nblocks += 1
            limit = block.get('limit')
            if limit is None:
                continue
            tile = map_tile(block['driver_path'], rules, unmapped_counter, unmapped_label)
            for sink in block['sinks']:
                trans = sink.get('trans')
                if trans is None:
                    continue
                violating = trans > limit
                if count_mode == 'violating' and not violating:
                    continue
                slack = limit - trans
                stat = tile_corner_stats[tile][corner]
                stat['count'] += 1
                if stat['worst_slack'] is None or slack < stat['worst_slack']:
                    stat.update(
                        worst_slack=slack, worst_clock=block.get('clock'), worst_trans=trans,
                        worst_limit=limit, worst_net=block['net'], worst_driver=block['driver_path'],
                        worst_sink=sink['path'],
                    )
    return nblocks


def build_tree(tile_corner_stats):
    root = {'children': {}, 'own_corners': defaultdict(new_stat)}
    for tile, corners in tile_corner_stats.items():
        node = root
        for part in tile.split('/'):
            node = node['children'].setdefault(part, {'children': {}, 'own_corners': defaultdict(new_stat)})
        for corner, stat in corners.items():
            merge_stat(node['own_corners'][corner], stat)
    return root


def rollup(node):
    agg = defaultdict(new_stat)
    for corner, stat in node['own_corners'].items():
        merge_stat(agg[corner], stat)
    for child in node['children'].values():
        child_agg = rollup(child)
        for corner, stat in child_agg.items():
            merge_stat(agg[corner], stat)
    node['rollup_corners'] = agg
    return agg


def total_count(node):
    return sum(s['count'] for s in node['rollup_corners'].values())


def fmt_stat(stat):
    return (f"count={stat['count']:<5d} worst_slack={stat['worst_slack']:.3f}  "
            f"clock={stat['worst_clock']}  trans={stat['worst_trans']:.3f}/{stat['worst_limit']:.3f}  "
            f"net={stat['worst_net']}  sink={stat['worst_sink']}")


def print_node(node, name, depth, out, corner_order):
    if total_count(node) == 0:
        return
    indent = '  ' * depth
    out.write(f"{indent}{name}  [TOTAL count={total_count(node)}]\n")

    overall_worst_corner, overall_worst = None, None
    for corner, stat in node['rollup_corners'].items():
        if stat['worst_slack'] is not None and (overall_worst is None or stat['worst_slack'] < overall_worst['worst_slack']):
            overall_worst, overall_worst_corner = stat, corner
    if overall_worst is not None:
        out.write(f"{indent}  WORST (any corner={overall_worst_corner}): {fmt_stat(overall_worst)}\n")

    for corner in corner_order:
        stat = node['rollup_corners'].get(corner)
        if stat and stat['count']:
            out.write(f"{indent}  [{corner}] {fmt_stat(stat)}\n")

    children = sorted(node['children'].items(), key=lambda kv: -total_count(kv[1]))
    for child_name, child in children:
        print_node(child, child_name, depth + 1, out, corner_order)


TABLE_COLUMNS = [
    'Hier', 'StartModule', 'EndModule', 'WNS', 'WNS_N', 'TNS', 'CNS', 'Required', 'Actual',
    'Corner', 'Clock', 'PS_MM', 'Netlength', 'DTran', 'LTran', 'Net', 'DriverPin', 'DriverCell', 'DriverX', 'DriverY',
    'LoadPin', 'LoadCell', 'LoadCount', 'LoadX', 'LoadY', 'Category',
]


def round_sig(x, sig):
    """Round x to sig significant figures. No-op if x or sig is None, or x == 0."""
    if x is None or sig is None or x == 0:
        return x
    import math
    digits = sig - int(math.floor(math.log10(abs(x)))) - 1
    return round(x, digits)


def fmt_val(x, sig=None):
    """Trim trailing zeros off a ps value, e.g. 52.000000 -> '52', 1958.652710 -> '1958.65271'.
    Pass sig to first round to that many significant figures."""
    if x is None:
        return ''
    x = round_sig(x, sig)
    s = f"{x:.6f}".rstrip('0').rstrip('.')
    return s if s else '0'


def fmt_coord(x):
    if x is None:
        return ''
    return f"{x:.2f}"


def fmt_ps_mm(x):
    """PS_MM is undefined at zero Netlength (see compute_derived) -> report as NA."""
    return 'NA' if x is None else fmt_val(x)


def tile_of(pin, rules, unmapped_counter, unmapped_label):
    """A single pin's tile: 'TOP_FLAT' with no mapping file, else the first regex match (or unmapped_label)."""
    if rules is None:
        return 'TOP_FLAT'
    return map_tile(pin, rules, unmapped_counter, unmapped_label)


def combine_hier(start_module, end_module):
    """Single tile if start and end are the same, 'start.end' if they differ."""
    return start_module if start_module == end_module else f"{start_module}.{end_module}"


def hier_of(driver_pin, sink_pin, rules, unmapped_counter, unmapped_label):
    """StartModule/EndModule (each pin's tile) plus the combined Hier
    ('single' tile if they're equal, 'start.end' if they differ)."""
    start_module = tile_of(driver_pin, rules, unmapped_counter, unmapped_label)
    end_module = tile_of(sink_pin, rules, unmapped_counter, unmapped_label)
    hier = combine_hier(start_module, end_module)
    return start_module, end_module, hier


def compute_derived(row):
    """Fill in WNS_N, Netlength and PS_MM from the raw fields already on the row."""
    limit, slack = row['limit'], row['slack']
    row['wns_n'] = (slack / limit) if (limit not in (None, 0) and slack is not None) else None

    dx, dy, sx, sy = row['driver_x'], row['driver_y'], row['sink_x'], row['sink_y']
    netlength = abs(dx - sx) + abs(dy - sy) if None not in (dx, dy, sx, sy) else None
    row['netlength'] = netlength

    dtran, ltran = row['driver_trans'], row['sink_trans']
    if netlength not in (None, 0) and dtran is not None and ltran is not None:
        row['ps_mm'] = (dtran - ltran) / netlength
    else:
        row['ps_mm'] = None
    return row


def parse_clk_vt(s):
    """Compile the 'allowed clock VT' regex for --clk-vt (tested against DriverCell)."""
    if not s:
        return None
    try:
        return re.compile(s)
    except re.error as e:
        raise ValueError(f"--clk-vt is not a valid regex: {s!r} ({e})")


def parse_netlen_thresholds(s):
    """'30,75,150' -> [short_max, med_max, long_max], strictly ascending."""
    if not s:
        return None
    vals = [float(tok.strip()) for tok in s.split(',')]
    if len(vals) != 3:
        raise ValueError(f"--netlen-thresholds needs exactly 3 ascending values (short,med,long): {s!r}")
    if not (vals[0] < vals[1] < vals[2]):
        raise ValueError(f"--netlen-thresholds must be strictly ascending: {vals}")
    return vals


def parse_drivermap(s):
    """'#Label1:regex1,#Label2:regex2' -> [(label, compiled_regex), ...], tested against DriverPin."""
    if not s:
        return []
    pairs = []
    for entry in s.split(','):
        entry = entry.strip()
        if not entry:
            continue
        if ':' not in entry:
            raise ValueError(f"--drivermap entries must be 'label:regex': {entry!r}")
        label, pattern = entry.split(':', 1)
        try:
            pairs.append((label.strip(), re.compile(pattern.strip())))
        except re.error as e:
            raise ValueError(f"--drivermap regex is not valid: {pattern!r} ({e})")
    return pairs


def category_of(row, clk_vt_re, netlen_thresholds, drivermap_rules):
    """Semicolon-joined auto-analysis flags for triage: clock-VT mismatch, netlength bucket,
    and any --drivermap pattern matching DriverPin. Empty string if nothing fires."""
    labels = []

    if clk_vt_re is not None:
        cell = row.get('driver_cell') or ''
        if not clk_vt_re.search(cell):
            labels.append('#NonClkVT')

    if netlen_thresholds is not None:
        nl = row.get('netlength')
        if nl is not None:
            t_short, t_med, t_long = netlen_thresholds
            if nl > t_long:
                labels.append(f'#VeryLongNet{fmt_val(t_long)}>um')
            elif nl < t_short:
                labels.append(f'#ShortNet<{fmt_val(t_short)}um')
            elif nl < t_med:
                labels.append(f'#MedNet<{fmt_val(t_med)}um')
            else:
                labels.append(f'#LongNet<{fmt_val(t_long)}um')

    if drivermap_rules:
        name = row.get('driver_pin') or ''
        for label, rx in drivermap_rules:
            if rx.search(name):
                labels.append(label)

    return ';'.join(labels)


def parse_table_rows(path, rules, unmapped_label, clk_vt_re=None, netlen_thresholds=None, drivermap_rules=None):
    """Parse one report file into table rows. Returns (rows, nblocks, unmapped_counter).

    Each row is one (Net, Clock, Corner) violation, so TNS/CNS are trivially WNS/1 here;
    they only become real aggregates once rows are collapsed per-Net (see dedup_worst_per_net)."""
    corner = corner_of(path)
    rows = []
    nblocks = 0
    unmapped_counter = Counter()
    with open_rpt(path) as fh:
        for block in parse_blocks(fh):
            nblocks += 1
            limit = block.get('limit')
            if limit is None or not block['sinks']:
                continue
            worst_sink = max(block['sinks'], key=lambda s: s.get('trans', float('-inf')))
            driver_pin = block.get('driver_path')
            sink_pin = worst_sink.get('path')
            slack = block.get('slack')
            start_module, end_module, hier = hier_of(
                driver_pin, sink_pin, rules, unmapped_counter, unmapped_label)
            row = {
                'corner': corner,
                'clock': block.get('clock'),
                'net': block.get('net'),
                'hier': hier,
                'start_module': start_module,
                'end_module': end_module,
                'limit': limit,
                'actual_trans': block.get('value', worst_sink.get('trans')),
                'slack': slack,
                'tns': slack,
                'cns': 1,
                'driver_pin': driver_pin,
                'driver_cell': block.get('driver_cell'),
                'driver_trans': block.get('driver_trans'),
                'driver_x': block.get('driver_x'),
                'driver_y': block.get('driver_y'),
                'sink_pin': sink_pin,
                'sink_cell': worst_sink.get('cell'),
                'sink_trans': worst_sink.get('trans'),
                'sink_x': worst_sink.get('x'),
                'sink_y': worst_sink.get('y'),
                'num_sinks': len(block['sinks']),
            }
            compute_derived(row)
            row['category'] = category_of(row, clk_vt_re, netlen_thresholds, drivermap_rules)
            rows.append(row)
    return rows, nblocks, unmapped_counter


def sort_rows_by_slack(rows):
    """Worst (most negative) slack first."""
    return sorted(rows, key=lambda r: (r['slack'] if r['slack'] is not None else float('inf')))


def dedup_worst_per_net(sorted_rows):
    """Collapse rows to one per Net (across all Corner/Clock combinations).

    The kept row's Corner/Clock/driver/sink/etc. columns are those of the single worst
    (net, corner, clock) combination; TNS/CNS are recomputed as the sum/count of WNS
    across *every* (corner, clock) combination that violated on this net."""
    groups = defaultdict(list)
    for r in sorted_rows:
        groups[r['net']].append(r)

    uniq = []
    for group in groups.values():
        worst = min(group, key=lambda r: (r['slack'] if r['slack'] is not None else float('inf')))
        merged = dict(worst)
        merged['tns'] = sum(r['slack'] for r in group if r['slack'] is not None)
        merged['cns'] = len(group)
        uniq.append(merged)
    return sort_rows_by_slack(uniq)


def write_rows(writer, rows, significant=None):
    writer.writerow(TABLE_COLUMNS)
    for r in rows:
        writer.writerow([
            r['hier'], r['start_module'], r['end_module'],
            fmt_val(r['slack'], significant), fmt_val(r['wns_n'], significant),
            fmt_val(r['tns'], significant), r['cns'],
            fmt_val(r['limit']), fmt_val(r['actual_trans']), r['corner'], r['clock'],
            fmt_ps_mm(r['ps_mm']), fmt_val(r['netlength']), fmt_val(r['driver_trans']), fmt_val(r['sink_trans']),
            r['net'], r['driver_pin'], r['driver_cell'], fmt_coord(r['driver_x']), fmt_coord(r['driver_y']),
            r['sink_pin'], r['sink_cell'], r['num_sinks'], fmt_coord(r['sink_x']), fmt_coord(r['sink_y']),
            r['category'],
        ])


def write_table(sorted_rows, out, top=None, delimiter='\t', significant=None):
    if top is not None:
        sorted_rows = sorted_rows[:top]
    writer = csv.writer(out, delimiter=delimiter, lineterminator='\n')
    write_rows(writer, sorted_rows, significant)


def uniq_out_path(out_path):
    """Same prefix as out_path, with any extension replaced by '.uniq.csv'."""
    root, _ext = os.path.splitext(out_path)
    return f"{root}.uniq.csv"


def write_uniq_table(uniq_rows, out_path, significant=None):
    with open(out_path, 'w', newline='') as fh:
        writer = csv.writer(fh, delimiter=',', lineterminator='\n')
        write_rows(writer, uniq_rows, significant)


def sanitize_for_filename(s):
    return re.sub(r'[^A-Za-z0-9._-]', '_', s)


def write_grouped_triage(uniq_rows, out_path, key_field, dir_suffix, significant=None):
    """Split the worst-per-net rows into one CSV per distinct value of key_field.
    Written under '<out_path prefix><dir_suffix>/<sanitized key>.csv'. Returns (dir, {key: path})."""
    root, _ext = os.path.splitext(out_path)
    triage_dir = f"{root}{dir_suffix}"
    os.makedirs(triage_dir, exist_ok=True)
    groups = defaultdict(list)
    for r in uniq_rows:
        groups[r[key_field]].append(r)
    written = {}
    for key, group in groups.items():
        fpath = os.path.join(triage_dir, sanitize_for_filename(key) + '.csv')
        with open(fpath, 'w', newline='') as fh:
            writer = csv.writer(fh, delimiter=',', lineterminator='\n')
            write_rows(writer, group, significant)  # already worst-first, since uniq_rows is sorted
        written[key] = fpath
    return triage_dir, written


def write_hier_triage(uniq_rows, out_path, significant=None):
    """One CSV per exact Hier value (e.g. 'LID/MSFLL.LID/CHNL_L'), for hierarchy triage."""
    return write_grouped_triage(uniq_rows, out_path, 'hier', '.hier_triage', significant)


def parse_steps(s):
    """'0,-10,-25,-50,-100,-500,-1000,-inf' -> [0.0,-10.0,...,-inf]; each adjacent pair (hi, lo)
    defines a half-open bucket (lo, hi]. Must be strictly descending."""
    steps = [float(tok.strip()) for tok in s.split(',')]
    if len(steps) < 2:
        raise ValueError('--steps needs at least two thresholds')
    if any(steps[i] <= steps[i + 1] for i in range(len(steps) - 1)):
        raise ValueError(f'--steps must be strictly descending: {steps}')
    return steps


def fmt_step(x):
    if x == float('-inf'):
        return '-inf'
    if x == float('inf'):
        return 'inf'
    return fmt_val(x)


def step_labels(steps):
    return [f"{fmt_step(steps[i])}~{fmt_step(steps[i + 1])}" for i in range(len(steps) - 1)]


def bucket_index(slack, steps):
    """Index of the bucket (lo, hi] containing slack, clamped into range for out-of-band values."""
    if slack is None:
        return None
    for i in range(len(steps) - 1):
        hi, lo = steps[i], steps[i + 1]
        if lo < slack <= hi:
            return i
    return 0 if slack > steps[0] else len(steps) - 2


def histogram(rows, steps):
    counts = [0] * (len(steps) - 1)
    for r in rows:
        i = bucket_index(r['slack'], steps)
        if i is not None:
            counts[i] += 1
    return counts


GROUP_BY_FIELDS = {
    'hier': ('hier', 'Hier'),
    'startmodule': ('start_module', 'StartModule'),
    'endmodule': ('end_module', 'EndModule'),
    'category': ('category', 'Category'),
}


def parse_group_by(s):
    """'end_module,category' -> ['endmodule', 'category'], validated against GROUP_BY_FIELDS."""
    fields = []
    for tok in s.split(','):
        key = tok.strip().lower().replace('_', '').replace('-', '')
        if not key:
            continue
        if key not in GROUP_BY_FIELDS:
            raise ValueError(f"--group-by field not recognized: {tok!r} "
                              f"(choices: hier, startmodule, endmodule, category)")
        fields.append(key)
    if not fields:
        raise ValueError("--group-by needs at least one field")
    return fields


SORT_METRIC_FIELDS = {'wns', 'tns', 'cns', 'corner'}


def parse_sort_by(s, group_by):
    """'-cns,wns' -> [('cns', True), ('wns', False)]. Field must be 'wns'/'tns'/'cns'/'corner'
    or one of the active --group-by fields. Leading '-' means descending."""
    valid = SORT_METRIC_FIELDS | set(group_by)
    spec = []
    for tok in s.split(','):
        tok = tok.strip()
        if not tok:
            continue
        desc = tok.startswith('-')
        key = (tok[1:] if desc else tok).strip().lower().replace('_', '').replace('-', '')
        if key not in valid:
            raise ValueError(f"--sort-by field not recognized: {tok!r} (choices: {', '.join(sorted(valid))})")
        spec.append((key, desc))
    if not spec:
        raise ValueError("--sort-by needs at least one field")
    return spec


def sort_key_value(row, field):
    if field in ('wns', 'tns'):
        v = row[field]
        return v if v is not None else float('inf')
    if field == 'cns':
        return row['cns']
    if field == 'corner':
        return row['corner']
    return row['keys'][GROUP_BY_FIELDS[field][0]]


def sort_summary(summary, sort_by, group_by):
    """Stable multi-pass sort: apply passes from least to most significant so earlier
    (higher-priority) keys win; always ends with the full group-by key tuple as a final
    deterministic tie-break, appended only if not already covered by sort_by."""
    covered = {f for f, _ in sort_by}
    passes = list(sort_by) + [(k, False) for k in group_by if k not in covered]
    for field, desc in reversed(passes):
        summary.sort(key=lambda r: sort_key_value(r, field), reverse=desc)
    return summary


def hier_summary(uniq_rows, steps, group_by, sort_by):
    """Rollup over the worst-per-net rows, grouped by the given --group-by fields: worst WNS,
    summed TNS/CNS, the Corner of the worst-WNS net, and a slack histogram across --steps.
    Sorted per --sort-by, with the group-by key tuple as a final deterministic tie-break."""
    row_fields = [GROUP_BY_FIELDS[k][0] for k in group_by]
    groups = defaultdict(list)
    for r in uniq_rows:
        groups[tuple(r[f] for f in row_fields)].append(r)
    summary = []
    for key, group in groups.items():
        worst = min(group, key=lambda r: (r['slack'] if r['slack'] is not None else float('inf')))
        summary.append({
            'keys': dict(zip(row_fields, key)),
            'wns': worst['slack'],
            'tns': sum(r['tns'] for r in group if r['tns'] is not None),
            'cns': sum(r['cns'] for r in group),
            'corner': worst['corner'],
            'hist': histogram(group, steps),
        })
    return sort_summary(summary, sort_by, group_by)


def print_hier_summary(summary, steps, group_by, significant=None, out=sys.stderr):
    row_fields = [GROUP_BY_FIELDS[k][0] for k in group_by]
    display_names = [GROUP_BY_FIELDS[k][1] for k in group_by]
    headers = display_names + ['WNS', 'TNS', 'CNS', 'Corner'] + step_labels(steps)
    table = [[*(s['keys'][f] for f in row_fields),
              fmt_val(s['wns'], significant), fmt_val(s['tns'], significant), s['cns'], s['corner'],
              *[c if c else '-' for c in s['hist']]]
             for s in summary]
    try:
        from tabulate import tabulate
        text = tabulate(table, headers=headers, tablefmt='psql')
    except ImportError:
        rows = [headers] + [[str(c) for c in row] for row in table]
        widths = [max(len(row[i]) for row in rows) for i in range(len(headers))]
        line = lambda row: '  '.join(str(v).ljust(w) for v, w in zip(row, widths))
        text = '\n'.join([line(headers), line(['-' * w for w in widths])] + [line(r) for r in table])
    out.write(text + '\n')


def _worker_table(rules, unmapped_label, clk_vt_re, netlen_thresholds, drivermap_rules, path):
    t0 = time.time()
    rows, nblocks, unmapped_counter = parse_table_rows(
        path, rules, unmapped_label, clk_vt_re, netlen_thresholds, drivermap_rules)
    return path, rows, nblocks, unmapped_counter, time.time() - t0


def _worker_tree(rules, count_mode, unmapped_label, path):
    t0 = time.time()
    local_stats = defaultdict(lambda: defaultdict(new_stat))
    local_unmapped = Counter()
    nblocks = process_file(path, rules, count_mode, local_stats, local_unmapped, unmapped_label)
    plain_stats = {tile: dict(corners) for tile, corners in local_stats.items()}
    return path, plain_stats, local_unmapped, nblocks, time.time() - t0


def report_progress(done, total, path, nblocks, elapsed, extra=''):
    sys.stderr.write(f"[{done}/{total}] parsed {corner_of(path)} "
                      f"({elapsed:.2f}s, {nblocks} net blocks{extra})\n")
    sys.stderr.flush()


def run_pool(worker, paths, jobs):
    jobs = max(1, min(jobs, len(paths)))
    if jobs == 1:
        for path in paths:
            yield worker(path)
        return
    with mp.Pool(processes=jobs) as pool:
        for result in pool.imap_unordered(worker, paths):
            yield result


def print_unmapped_warning(unmapped_counter, unmapped_label):
    if not unmapped_counter:
        return
    sys.stderr.write("\nWARNING: pins with no mapping rule match (top-level instance : occurrence count):\n")
    for top, n in unmapped_counter.most_common(20):
        sys.stderr.write(f"  {top}: {n}\n")
    sys.stderr.write("Extend --mapping to cover these if they should not fall under "
                      f"'{unmapped_label}'.\n")


def main():
    epilog = (
        "notes (tsv/csv format):\n"
        "  Hier/StartModule/EndModule: StartModule/EndModule are the Driver/Load pins' tiles from\n"
        "  --mapping (or TOP_FLAT with none). Hier combines them ('single' tile if equal, 'start.end' if not).\n"
        "  Category: semicolon-joined auto-analysis flags from --clk-vt/--netlen-thresholds/--drivermap.\n"
        "  --group-by controls only the printed summary table -- pick any of hier, start_module,\n"
        "  end_module, category (comma-separated, default 'start_module,category').\n"
        "  With -o FILE, in addition to the main table this also writes:\n"
        "    FILE.uniq.csv                worst-slack-per-net table\n"
        "    FILE.hier_triage/<Hier>.csv  one file per exact Hier value\n"
    )
    ap = argparse.ArgumentParser(description=__doc__, epilog=epilog,
                                  formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('rpts', nargs='+', help='clock_trans.rpt(.gz) files, one per corner')
    ap.add_argument('--format', choices=['tree', 'tsv', 'csv'], default='tree',
                     help="'tree': hierarchical tile rollup (needs --mapping); "
                          "'tsv'/'csv': flat ranked per-net-violation table, worst slack first, "
                          "tab- or comma-delimited")
    ap.add_argument('--mapping', help='CSV file of regex_pattern,tile_name (first match wins); '
                                       'required for --format tree, optional for tsv/csv (adds a Hier column; '
                                       'omit it and Hier is always TOP_FLAT)')
    ap.add_argument('--unmapped-label', default='TOP_FLAT', help='tile name used for drivers/sinks matching no mapping rule')
    ap.add_argument('--count-mode', choices=['violating', 'all'], default='violating',
                     help="'violating': only count sinks whose Trans exceeds the net's Limit (default); "
                          "'all': count every listed sink under a violating net (tree format only)")
    ap.add_argument('--top', type=int, default=None, help='tsv/csv format only: keep only the N worst rows')
    ap.add_argument('--steps', default='-0,-10,-25,-50,-100,-500,-1000,-inf',
                     help='tsv/csv format only: comma-separated, strictly descending slack (ps) thresholds; '
                          'each adjacent pair becomes a histogram bucket in the summary table')
    ap.add_argument('--group-by', default='start_module,category', metavar='FIELD,...',
                     help="tsv/csv format only: comma-separated fields to group the printed summary table "
                          "by, from {hier, start_module, end_module, category} (default: 'start_module,category')")
    ap.add_argument('--sort-by', default='wns', metavar='FIELD,...',
                     help="tsv/csv format only: comma-separated columns to sort the printed summary table by, "
                          "from {wns, tns, cns, corner} plus whatever --group-by fields are active; prefix a "
                          "field with '-' for descending (default: 'wns', i.e. worst slack first). The active "
                          "--group-by fields are always appended as a final tie-break for determinism")
    ap.add_argument('--significant', type=int, default=None,
                     help='tsv/csv format only: round WNS/WNS_N/TNS to N significant figures in the CSVs and '
                          'the per-Hier summary table (default: no rounding, full trimmed precision)')
    ap.add_argument('--clk-vt', default='ULVT$', metavar='REGEX',
                     help="tsv/csv format only: regex (re.search) of DriverCell suffixes considered proper "
                          "clock VT; cells NOT matching are flagged '#NonClkVT' in Category (default: 'ULVT$'; "
                          "pass '' to disable)")
    ap.add_argument('--netlen-thresholds', default='30,75,150', metavar='SHORT,MED,LONG',
                     help="tsv/csv format only: 3 ascending Netlength thresholds classifying each row into "
                          "#ShortNet/#MedNet/#LongNet/#VeryLongNet in Category (default: '30,75,150'; "
                          "pass '' to disable). NOTE: Netlength is Manhattan distance in whatever raw units "
                          "the report's Physical Coordinates use (often DB units, not microns) -- the "
                          "30/75/150 default assumes microns and will need rescaling to your DBU/micron "
                          "ratio, e.g. --netlen-thresholds 60000,150000,300000")
    ap.add_argument('--drivermap', default='#NonCtsBuilt:/Fx,#CreditCell:FE_FEEDX,#SCCTS:SSCTS_',
                     metavar='LABEL:REGEX,...',
                     help="tsv/csv format only: comma-separated 'label:regex' pairs (re.search on DriverPin); "
                          "every matching label is appended to Category (default: "
                          "'#NonCtsBuilt:/Fx,#CreditCell:FE_FEEDX,#SCCTS:SSCTS_'; pass '' to disable)")
    ap.add_argument('-j', '--jobs', type=int, default=None,
                     help='parallel worker processes, one report file per worker (default: cpu count, capped at file count)')
    ap.add_argument('-o', '--out', default='-', help='output file (default: stdout)')
    args = ap.parse_args()

    total = len(args.rpts)
    if args.jobs is None:
        args.jobs = min(total, os.cpu_count() or 1)
    if args.format in ('tsv', 'csv'):
        try:
            steps = parse_steps(args.steps)
            group_by = parse_group_by(args.group_by)
            sort_by = parse_sort_by(args.sort_by, group_by)
            clk_vt_re = parse_clk_vt(args.clk_vt)
            netlen_thresholds = parse_netlen_thresholds(args.netlen_thresholds)
            drivermap_rules = parse_drivermap(args.drivermap)
        except ValueError as e:
            ap.error(str(e))

    out = sys.stdout if args.out == '-' else open(args.out, 'w', newline='')

    if args.format in ('tsv', 'csv'):
        delimiter = '\t' if args.format == 'tsv' else ','
        rules = load_mapping(args.mapping) if args.mapping else None
        unmapped_counter = Counter()
        rows = []
        worker = functools.partial(_worker_table, rules, args.unmapped_label,
                                    clk_vt_re, netlen_thresholds, drivermap_rules)
        for done, (path, file_rows, nblocks, local_unmapped, elapsed) in enumerate(
                run_pool(worker, args.rpts, args.jobs), 1):
            report_progress(done, total, path, nblocks, elapsed, extra=f", {len(file_rows)} violation rows")
            rows.extend(file_rows)
            unmapped_counter.update(local_unmapped)
        sorted_rows = sort_rows_by_slack(rows)
        write_table(sorted_rows, out, top=args.top, delimiter=delimiter, significant=args.significant)
        if out is not sys.stdout:
            out.close()

        output_files = []
        if args.out != '-':
            output_files.append(('main table', os.path.abspath(args.out), len(sorted_rows)))

        uniq_rows = dedup_worst_per_net(sorted_rows)
        if args.out == '-':
            sys.stderr.write("Note: skipping .uniq.csv / hier-triage output since -o is stdout; "
                              "pass -o FILE to also get them.\n")
        else:
            uniq_path = uniq_out_path(args.out)
            write_uniq_table(uniq_rows, uniq_path, significant=args.significant)
            output_files.append(('worst-per-net', os.path.abspath(uniq_path), len(uniq_rows)))

            triage_dir, written = write_hier_triage(uniq_rows, args.out, significant=args.significant)
            hier_counts = Counter(r['hier'] for r in uniq_rows)
            for hier, fpath in sorted(written.items()):
                output_files.append((f"hier-triage[{hier}]", os.path.abspath(fpath), hier_counts[hier]))

        sys.stderr.write("\nOutput files:\n")
        for label, fpath, nrows in output_files:
            sys.stderr.write(f"  [{label}] {fpath} ({nrows} rows)\n")

        sort_desc = ', '.join(f"-{f}" if d else f for f, d in sort_by)
        sys.stderr.write(f"\nSummary grouped by {', '.join(group_by)}, sorted by {sort_desc}:\n")
        print_hier_summary(hier_summary(uniq_rows, steps, group_by, sort_by), steps, group_by,
                            significant=args.significant)

        print_unmapped_warning(unmapped_counter, args.unmapped_label)
        return

    if not args.mapping:
        ap.error('--mapping is required for --format tree')

    rules = load_mapping(args.mapping)
    tile_corner_stats = defaultdict(lambda: defaultdict(new_stat))
    unmapped_counter = Counter()
    corner_order = []
    for path in args.rpts:
        corner = corner_of(path)
        if corner not in corner_order:
            corner_order.append(corner)

    worker = functools.partial(_worker_tree, rules, args.count_mode, args.unmapped_label)
    for done, (path, plain_stats, local_unmapped, nblocks, elapsed) in enumerate(
            run_pool(worker, args.rpts, args.jobs), 1):
        nviol = sum(stat['count'] for corners in plain_stats.values() for stat in corners.values())
        report_progress(done, total, path, nblocks, elapsed, extra=f", {nviol} violation sinks")
        for tile, corners in plain_stats.items():
            for c, stat in corners.items():
                merge_stat(tile_corner_stats[tile][c], stat)
        unmapped_counter.update(local_unmapped)

    root = build_tree(tile_corner_stats)
    rollup(root)

    out.write(f"# Hierarchical clock transition report across {len(corner_order)} corner(s): {', '.join(corner_order)}\n")
    out.write(f"# count-mode={args.count_mode}\n\n")
    children = sorted(root['children'].items(), key=lambda kv: -total_count(kv[1]))
    for name, child in children:
        print_node(child, name, 0, out, corner_order)
    if out is not sys.stdout:
        out.close()
        sys.stderr.write(f"\nOutput files:\n  [tree] {os.path.abspath(args.out)}\n")

    print_unmapped_warning(unmapped_counter, args.unmapped_label)


if __name__ == '__main__':
    main()
