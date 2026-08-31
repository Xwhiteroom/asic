#!/usr/bin/env python3
"""
# Copyright (c) 2026 Syed Shakir Iqbal (Xwhiteroom)
# SPDX-License-Identifier: MIT

Cross-stage clock latency summary from PT 'report_clock_qor -type latency' reports.

Parses one or more latency.rpt(.gz) files -- typically the same tile at different flow
stages, e.g.:
    rpts/FxCts/latency.rpt.gz
    rpts/FxOptCts/latency.rpt.gz
    rpts/FxPixCts/latency.rpt.gz
    rpts/FxReRoute/latency.rpt.gz
    rpts/FxRoute/latency.rpt.gz

Each file's "Summary Table for Corner ..." section is parsed (the "Details Table" per-sink
breakdown is not) into one row per (Stage, Scenario, Clock). Stage is taken from the
immediate parent directory name (FxCts, FxOptCts, ...), so results from every input file
can be compared side by side. Scenario already encodes both the corner and mode (e.g.
'setup_tt0p75v100c_macroTypRC_typrc100c_FuncTT0p75vRcNom'), so Corner/Mode aren't repeated
as separate columns.

A clock with multiple un-merged user-defined skew groups reports '--' on its own row and one
indented sub-row per skew group in the source report; those sub-rows are never emitted as
their own output rows, but when the clock's own row is all '--', its numbers are synthesized
from those skew groups instead of being left blank (Max/GlobalSkew take the worst/max across
groups, Min the best/min, Median/StdDev a sinks-weighted average -- an approximation, flagged
via SkewGroups > 0 so it's distinguishable from a directly-reported value).

Output columns: Stage, Scenario, Clock, Sinks, SkewGroups, TarSkew, GlbSkew, TargetLat, MaxLat,
MinLat, MedLat, SigmaLat. SkewGroups is 0 when the row is a direct report value, or the number
of skew groups aggregated over when synthesized. A field that was '--' in the source report
(no value, and not recoverable from skew groups either) stays '--' in the output.
"""
import argparse
import csv
import gzip
import multiprocessing as mp
import os
import re
import sys
import time

SUMMARY_RE = re.compile(r'Summary Table for Corner\s+(\S+)\s*=')
DETAILS_RE = re.compile(r'Details Table for Corner\s+(\S+)\s*=')
MODE_RE = re.compile(r'^###\s*Mode:\s*(.+?),\s*Scenario:\s*(.+?)\s*$')
DASHES_RE = re.compile(r'^-{10,}\s*$')

# A new record (clock row, or an indented skew-group sub-row) starts when non-space content
# appears at or before this column. Genuine multi-line wrap continuations (numeric column
# overflow) start far deeper than this, typically column 50+.
INDENT_THRESHOLD = 30


def open_rpt(path):
    if path.endswith('.gz'):
        return gzip.open(path, 'rt', errors='replace')
    return open(path, 'r', errors='replace')


def stage_of(path):
    return path.rsplit('/', 2)[-2] if '/' in path else path


def to_float(s):
    return None if s in ('', '--') else float(s)


def to_int(s):
    return None if s in ('', '--') else int(s)


def extract_record(record_lines):
    """A record's lines, once concatenated end-to-end (each continuation line's own leading
    whitespace acts as the separator) and whitespace-split, yield exactly 10 tokens: Name,
    Attrs, Sinks, TargetSkew, GlobalSkew, TargetLatency, MaxLatency, MinLatency,
    MedianLatency, StdDev."""
    joined = ''.join(line.rstrip('\n') for line in record_lines)
    toks = joined.split()
    if len(toks) != 10:
        return None
    name, attrs, sinks, target_skew, global_skew, target_latency, max_latency, min_latency, median_latency, stddev = toks
    return {
        'name': name,
        'sinks': to_int(sinks),
        'target_skew': to_float(target_skew),
        'global_skew': to_float(global_skew),
        'target_latency': to_float(target_latency),
        'max_latency': to_float(max_latency),
        'min_latency': to_float(min_latency),
        'median_latency': to_float(median_latency),
        'stddev': to_float(stddev),
    }


def iter_mode_records(lines):
    """Walk lines already scoped to one corner's Summary Table, yielding (scenario,
    is_skew_group_child, record_lines) for every clock / skew-group row."""
    scenario = None
    active = False
    record_lines = []
    record_is_child = False

    def is_new_record(line):
        stripped = line.lstrip(' ')
        return bool(stripped) and (len(line) - len(stripped)) <= INDENT_THRESHOLD

    for line in lines:
        m = MODE_RE.match(line)
        if m:
            if active and record_lines:
                yield scenario, record_is_child, record_lines
            scenario = m.group(2)
            record_lines = []
            active = True
            continue
        if not active:
            continue
        if DASHES_RE.match(line):
            if record_lines:
                yield scenario, record_is_child, record_lines
            record_lines = []
            active = False
            continue
        if not line.strip():
            continue
        if is_new_record(line):
            if record_lines:
                yield scenario, record_is_child, record_lines
            record_lines = [line]
            record_is_child = line[0] == ' '
        else:
            record_lines.append(line)
    if active and record_lines:
        yield scenario, record_is_child, record_lines


def parse_latency_file(path):
    """Yield one dict per (Scenario, Clock) row in every Summary Table in this file,
    skipping skew-group sub-rows. Returns (rows, ncorners)."""
    stage = stage_of(path)
    with open_rpt(path) as fh:
        lines = fh.readlines()

    markers = []
    for i, line in enumerate(lines):
        m = SUMMARY_RE.search(line)
        if m:
            markers.append((i, 'summary', m.group(1)))
            continue
        m = DETAILS_RE.search(line)
        if m:
            markers.append((i, 'details', m.group(1)))
    markers.sort()

    rows = []
    ncorners = 0
    for j, (idx, kind, corner) in enumerate(markers):
        if kind != 'summary':
            continue
        ncorners += 1
        region_end = markers[j + 1][0] if j + 1 < len(markers) else len(lines)
        region = lines[idx + 1:region_end]

        parent = None
        children = []

        def finalize():
            if parent is None:
                return
            row = merge_skew_groups(parent, children)
            row.update(stage=stage, scenario=parent_scenario, clock=parent['name'])
            rows.append(row)

        parent_scenario = None
        for scenario, is_child, record_lines in iter_mode_records(region):
            rec = extract_record(record_lines)
            if rec is None:
                sys.stderr.write(f"WARNING: {path}: corner={corner} unparsed record "
                                  f"(field count mismatch): {record_lines[0].strip()[:60]!r}\n")
                continue
            if is_child:
                children.append(rec)
                continue
            finalize()
            parent, parent_scenario, children = rec, scenario, []
        finalize()
    return rows, ncorners


def merge_skew_groups(parent, children):
    """A clock with un-merged skew groups reports '--' on its own row and one real row per
    skew group (dropped from output otherwise). When that happens, synthesize the clock's
    missing numbers from its skew groups instead of leaving them blank: Max/Global-skew take
    the worst (max) across groups, Min the best (min), Median/StdDev a sinks-weighted average
    (an approximation, since these aren't simply combinable). TargetSkew/TargetLatency are
    left alone -- they're genuinely not defined pre-merge, in the parent or any child.
    Adds 'skew_groups' = how many child groups contributed (0 if the parent's own numbers
    were used as-is)."""
    row = dict(parent)
    row['skew_groups'] = 0
    if row['max_latency'] is not None or not children:
        return row

    def wavg(field):
        num = den = 0.0
        for c in children:
            if c[field] is not None and c['sinks']:
                num += c[field] * c['sinks']
                den += c['sinks']
        return (num / den) if den else None

    def best(field, pick):
        vals = [c[field] for c in children if c[field] is not None]
        return pick(vals) if vals else None

    row['global_skew'] = best('global_skew', max)
    row['max_latency'] = best('max_latency', max)
    row['min_latency'] = best('min_latency', min)
    row['median_latency'] = wavg('median_latency')
    row['stddev'] = wavg('stddev')
    row['skew_groups'] = len(children)
    return row


COLUMNS = ['Stage', 'Scenario', 'Clock', 'Sinks', 'SkewGroups', 'TarSkew', 'GlbSkew', 'TargetLat',
           'MaxLat', 'MinLat', 'MedLat', 'SigmaLat']


def fmt_num(x, precision):
    return '--' if x is None else f"{x:.{precision}f}"


def fmt_int(x):
    return '--' if x is None else str(x)


def write_rows(rows, out, precision, delimiter=','):
    writer = csv.writer(out, delimiter=delimiter, lineterminator='\n')
    writer.writerow(COLUMNS)
    for r in rows:
        writer.writerow([
            r['stage'], r['scenario'], r['clock'], fmt_int(r['sinks']), r['skew_groups'],
            fmt_num(r['target_skew'], precision), fmt_num(r['global_skew'], precision),
            fmt_num(r['target_latency'], precision), fmt_num(r['max_latency'], precision),
            fmt_num(r['min_latency'], precision), fmt_num(r['median_latency'], precision),
            fmt_num(r['stddev'], precision),
        ])


PIVOT_MISSING = '- / - / - / -'


def build_pivot(rows, stage_columns, precision):
    """(Clock, Scenario) rows x Stage columns, each cell 'MaxLat / MinLat / MedLat / GlbSkew'
    for that stage (PIVOT_MISSING if that clock/scenario has no row for that stage)."""
    groups = {}
    for r in rows:
        groups.setdefault((r['clock'], r['scenario']), {})[r['stage']] = r
    pivot_rows = []
    for (clock, scenario), by_stage in sorted(groups.items()):
        cells = []
        for stage in stage_columns:
            r = by_stage.get(stage)
            if r is None:
                cells.append(PIVOT_MISSING)
            else:
                cells.append(f"{fmt_num(r['max_latency'], precision)} / "
                              f"{fmt_num(r['min_latency'], precision)} / "
                              f"{fmt_num(r['median_latency'], precision)} / "
                              f"{fmt_num(r['global_skew'], precision)}")
        pivot_rows.append((clock, scenario, cells))
    return pivot_rows


def pivot_table(pivot_rows, stage_columns):
    headers = ['Clock', 'Scenario'] + stage_columns
    table = [[clock, scenario, *cells] for clock, scenario, cells in pivot_rows]
    return headers, table


PIVOT_LEGEND = 'MaxLat / MinLat / MedLat / GlbSkew'


def print_pivot(pivot_rows, stage_columns, out=sys.stderr):
    _, table = pivot_table(pivot_rows, stage_columns)
    headers = ['Clock', 'Scenario'] + [f"{s}\n({PIVOT_LEGEND})" for s in stage_columns]
    try:
        from tabulate import tabulate
        text = tabulate(table, headers=headers, tablefmt='psql')
    except ImportError:
        all_rows = [headers] + table
        widths = [max(len(str(row[i])) for row in all_rows) for i in range(len(headers))]
        line = lambda row: '  '.join(str(v).ljust(w) for v, w in zip(row, widths))
        text = '\n'.join([line(headers), line(['-' * w for w in widths])] + [line(r) for r in table])
    out.write(text + '\n')


def write_pivot_csv(pivot_rows, stage_columns, out_path):
    headers, table = pivot_table(pivot_rows, stage_columns)
    with open(out_path, 'w', newline='') as fh:
        writer = csv.writer(fh, lineterminator='\n')
        writer.writerow(headers)
        writer.writerows(table)


def _worker(path):
    t0 = time.time()
    rows, ncorners = parse_latency_file(path)
    return path, rows, ncorners, time.time() - t0


def run_pool(paths, jobs):
    jobs = max(1, min(jobs, len(paths)))
    if jobs == 1:
        for path in paths:
            yield _worker(path)
        return
    with mp.Pool(processes=jobs) as pool:
        for result in pool.imap_unordered(_worker, paths):
            yield result


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('rpts', nargs='+', help='latency.rpt(.gz) files, one per stage')
    ap.add_argument('--format', choices=['csv', 'tsv'], default='csv', help='output delimiter (default: csv)')
    ap.add_argument('--stage-order', help='comma-separated stage names controlling row order '
                                           '(default: order of appearance on the command line)')
    ap.add_argument('--significant', type=int, default=3, metavar='N',
                     help="decimal places for TarSkew/GlbSkew/TargetLat/MaxLat/MinLat/MedLat/SigmaLat "
                          "(printf '%%.Nf' style; default: 3)")
    ap.add_argument('--filter', metavar='REGEX',
                     help="regex (re.search) on Clock name restricting which clocks appear in the "
                          "printed pivot table; the CSVs (main and .pivot.csv) always keep every clock")
    ap.add_argument('-j', '--jobs', type=int, default=None,
                     help='parallel worker processes, one report file per worker (default: cpu count, capped at file count)')
    ap.add_argument('-o', '--out', default='-', help='output file (default: stdout)')
    args = ap.parse_args()

    filter_re = None
    if args.filter:
        try:
            filter_re = re.compile(args.filter)
        except re.error as e:
            ap.error(f"--filter is not a valid regex: {args.filter!r} ({e})")

    total = len(args.rpts)
    jobs = args.jobs if args.jobs is not None else min(total, os.cpu_count() or 1)
    delimiter = ',' if args.format == 'csv' else '\t'

    if args.stage_order:
        stage_rank = {s.strip(): i for i, s in enumerate(args.stage_order.split(','))}
    else:
        stage_rank = {}
        for path in args.rpts:
            s = stage_of(path)
            if s not in stage_rank:
                stage_rank[s] = len(stage_rank)

    rows = []
    for done, (path, file_rows, ncorners, elapsed) in enumerate(run_pool(args.rpts, jobs), 1):
        sys.stderr.write(f"[{done}/{total}] parsed {stage_of(path)} "
                          f"({elapsed:.2f}s, {ncorners} corners, {len(file_rows)} clock rows)\n")
        sys.stderr.flush()
        rows.extend(file_rows)

    rows.sort(key=lambda r: (r['scenario'], r['clock'], stage_rank.get(r['stage'], len(stage_rank))))

    out = sys.stdout if args.out == '-' else open(args.out, 'w', newline='')
    write_rows(rows, out, args.significant, delimiter=delimiter)
    if out is not sys.stdout:
        out.close()
        sys.stderr.write(f"\nWrote {len(rows)} rows: {os.path.abspath(args.out)}\n")

    stage_columns = sorted(stage_rank, key=stage_rank.get)
    pivot_rows = build_pivot(rows, stage_columns, args.significant)
    printed_rows = pivot_rows
    if filter_re is not None:
        printed_rows = [pr for pr in pivot_rows if filter_re.search(pr[0])]
        sys.stderr.write(f"\n--filter {args.filter!r} matched {len(printed_rows)}/{len(pivot_rows)} "
                          f"(Clock, Scenario) rows for the printed table\n")
    sys.stderr.write("\nMaxLat / MinLat / MedLat / GlbSkew by Stage (rows = Clock, Scenario):\n")
    print_pivot(printed_rows, stage_columns)

    if args.out == '-':
        sys.stderr.write("\nNote: skipping pivot .csv dump since -o is stdout; pass -o FILE to also get one.\n")
    else:
        pivot_path = f"{os.path.splitext(args.out)[0]}.pivot.csv"
        write_pivot_csv(pivot_rows, stage_columns, pivot_path)
        sys.stderr.write(f"Wrote pivot table: {os.path.abspath(pivot_path)}\n")


if __name__ == '__main__':
    main()
