#!/usr/bin/env python3
"""
# Copyright (c) 2026 Syed Shakir Iqbal (Xwhiteroom)
# SPDX-License-Identifier: MIT

"""
"""Split a CSV into one XLSX workbook with one tab per unique value of a given column.

Example:
    ssi_csv_split2xlsx.py get_comp_drv.csv --column tile -o get_comp_drv.xlsx

Each unique value of --column becomes its own sheet (tab name = that value, sanitized
for Excel's sheet-name rules: max 31 chars, none of []:*?/\\ , deduped if two values
collapse to the same sanitized name). Rows with a missing/blank value in --column are
grouped into a sheet named "_blank_". Sheet order follows first appearance in the CSV.
"""
import os
import sys


def _reexec_under_sibling_venv():
    """If a '.venv' next to this script exists and we're not already running under it,
    re-exec under it -- so the pandas/openpyxl deps are available even if the caller ran
    `python3 ssi_csv_split2xlsx.py` or `./ssi_csv_split2xlsx.py` without sourcing
    .venv/bin/activate. No-op if the venv is missing, we're already running under it, or
    SSI_CSV_SPLIT2XLSX_NO_VENV is set.

    Detection uses sys.prefix rather than sys.executable: venv's bin/python3 is typically
    just a symlink to the system interpreter binary, so comparing realpath(sys.executable)
    would always match the system python and never re-exec."""
    if os.environ.get('SSI_CSV_SPLIT2XLSX_NO_VENV'):
        return
    venv_dir = os.path.join(os.path.dirname(os.path.realpath(__file__)), '.venv')
    venv_python = os.path.join(venv_dir, 'bin', 'python3')
    if not os.path.exists(venv_python):
        return
    if os.path.realpath(sys.prefix) == os.path.realpath(venv_dir):
        return
    os.execv(venv_python, [venv_python, os.path.realpath(__file__)] + sys.argv[1:])


_reexec_under_sibling_venv()

import argparse
import re
import pandas as pd

EXCEL_SHEET_MAX_LEN = 31
INVALID_SHEET_CHARS_RE = re.compile(r"[\[\]:*?/\\]")
BLANK_SHEET_NAME = "_blank_"


def sanitize_sheet_name(value, used_names):
    name = INVALID_SHEET_CHARS_RE.sub("_", str(value).strip()) or BLANK_SHEET_NAME
    name = name[:EXCEL_SHEET_MAX_LEN]
    base = name
    counter = 1
    while name in used_names:
        suffix = f"_{counter}"
        name = base[:EXCEL_SHEET_MAX_LEN - len(suffix)] + suffix
        counter += 1
    used_names.add(name)
    return name


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("csv_file", help="Input CSV file")
    ap.add_argument("-c", "--column", required=True, help="Column name to split rows by")
    ap.add_argument("-o", "--output", required=True, help="Output XLSX file")
    args = ap.parse_args()

    df = pd.read_csv(args.csv_file, dtype=str)
    if args.column not in df.columns:
        ap.error(f"column {args.column!r} not found; available columns: {', '.join(df.columns)}")

    blank_mask = df[args.column].isna() | (df[args.column].astype(str).str.strip() == "")
    values_in_order = []
    seen = set()
    for v in df.loc[~blank_mask, args.column]:
        if v not in seen:
            seen.add(v)
            values_in_order.append(v)

    used_names = set()
    with pd.ExcelWriter(args.output, engine="openpyxl") as writer:
        for value in values_in_order:
            group = df[df[args.column] == value]
            sheet_name = sanitize_sheet_name(value, used_names)
            print(f"{value!r} ({len(group)} rows) -> [{sheet_name}]")
            group.to_excel(writer, sheet_name=sheet_name, index=False)
        if blank_mask.any():
            group = df[blank_mask]
            sheet_name = sanitize_sheet_name(BLANK_SHEET_NAME, used_names)
            print(f"<blank> ({len(group)} rows) -> [{sheet_name}]")
            group.to_excel(writer, sheet_name=sheet_name, index=False)

    print(f"Created {args.output}")


if __name__ == "__main__":
    main()
