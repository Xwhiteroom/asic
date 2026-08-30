#!/usr/bin/env python3
"""
# Copyright (c) 2026 Syed Shakir Iqbal (Xwhiteroom)
# SPDX-License-Identifier: MIT

"""

import argparse
import csv
from pathlib import Path
from tabulate import tabulate

def csv_to_table(csv_file, tablefmt):
    with open(csv_file, newline="", encoding="utf-8") as f:
        rows = list(csv.reader(f))
    if not rows:
        return f"\n## {Path(csv_file).name}\n<empty>\n"
    headers = rows[0]
    data = rows[1:]
    table = tabulate(data,headers=headers,tablefmt=tablefmt,maxcolwidths=None,disable_numparse=True,)
    return f"\n## {Path(csv_file).name}\n{table}\n"


def main():
    parser = argparse.ArgumentParser(description="Render one or more CSV files using tabulate.")
    parser.add_argument("csv_files",nargs="+",help="CSV files to render",)
    parser.add_argument("-f","--format",default="github",help="Tabulate format (default: github)",)
    parser.add_argument("-o","--output",help="Write output to a file instead of stdout",)
    args = parser.parse_args()
    output = "\n".join(
        csv_to_table(csv_file, args.format)
        for csv_file in args.csv_files
    )

    if args.output:
        with open(args.output, "w", encoding="utf-8") as f:
            f.write(output)
    else:
        print(output)

if __name__ == "__main__":
    main()
