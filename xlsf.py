#!/usr/bin/env python3
"""
# Copyright (c) 2026 Syed Shakir Iqbal (Xwhiteroom)
# SPDX-License-Identifier: MIT
#
# Examples:
#   xlsf
#   xlsf --cores 8 --ram 64000
#   xlsf -- pt_shell -file run.tcl
#   xlsf --helper top
#   xlsf --helper "tail -f run.log"
#   xlsf --helper bin/xcmd
#   xlsf --terminal xterm
#   xlsf --dry
#
# Notes:
#   - No cmd => launch terminal.
#   - Cmd after '--' => run directly.
#   - Multiple --helper => multiple kitty tabs.
"""


import argparse
import os
import shlex
import subprocess
from datetime import datetime

p = argparse.ArgumentParser(description="LSF wrapper")
p.add_argument("--cores", "-n", type=int, default=1, help="LSF core count")
p.add_argument("--ram", type=int, default=10000, help="Memory in MB")
p.add_argument("--project", "-P", default="pt-impl", help="LSF project pt-impl/sb-impl")
p.add_argument("--queue", "-q", default="high", help="LSF queue")
p.add_argument("--type", "-t", default="RHEL8_64", help="LSF Resource Machine")
p.add_argument("--select", default="csbatch", help="LSF select constraint")
p.add_argument("--output", help="Override log file path")
p.add_argument("--logdir", default="~/trash", help="Log directory")
p.add_argument("--logprefix", default="xlsf_", help="Log filename prefix")
p.add_argument("--terminal", default="kitty",choices=["xterm", "kitty"], help="xterm/kitty/gnome(TBD)")
p.add_argument("--helper",action="append",default=[],help="Launch helper command in an additional kitty tab. Can be specified multiple times.")
p.add_argument("--dry", action="store_true", help="Print command, do not submit")
p.add_argument("cmd", nargs=argparse.REMAINDER, help="Command to run")

args = p.parse_args()
stamp = datetime.now().strftime("%Y%m%d")

if args.terminal == "gnome":
    title = f"XLSF_GT_{args.cores}x{args.ram // 1000}GB"
    term_cmd = f"gnome-terminal --title={title}"
elif args.terminal == "xterm":
    title = f"XLSF_XT_{args.cores}x{args.ram // 1000}GB"
    term_cmd = f"xterm -T {title}"
elif args.terminal == "kitty":
    title = f"XLSF_KT_{args.cores}x{args.ram // 1000}GB"
    #term_cmd = f"kitty --title={title}"
    term_cmd = f"kitty --title={title} -o allow_remote_control=yes"       
    if args.helper:
        session_file = f"/tmp/xlsf_{os.getpid()}.session"
        session_file = os.path.expanduser(f"{args.logdir}/{args.logprefix}{stamp}.{os.getpid()}.session")
        with open(session_file, "w") as f:
            f.write("new_tab Shell\n")
            f.write(f"launch {os.environ.get('SHELL', '/bin/bash')}\n\n")
            for helper in args.helper:
                helper_name = os.path.basename(shlex.split(helper)[0])
                f.write(f"new_tab {helper_name}\n")
                f.write(f"launch sh -c {shlex.quote(helper)}\n\n")
        term_cmd = (f"{term_cmd}" f" --session {session_file}")
else:
    raise ValueError(f"Unsupported terminal: {args.terminal}")


#if not args.cmd: p.error("No command specified. Use '-- <command>'")
if args.cmd:
    #cmd = (f"{term_cmd} "  f"-- bash -lc {shlex.quote(user_cmd)}")    
    cmd = " ".join(shlex.quote(x) for x in args.cmd)
else:
    cmd = term_cmd

logfile = (
    os.path.expanduser(args.output)
    if   args.output
    else os.path.expanduser(f"{args.logdir}/{args.logprefix}{stamp}.log")
)

bsub_cmd = [
    "lsf_bsub",
    "-o", logfile,
    "-n", str(args.cores),
    "-q", args.queue,
    "-P", args.project,
    "-J", title,    
    "-R",
    f"rusage[mem={args.ram}] order[cpuf:-maxmem:-mem] "
    f"select[(type=={args.type})&&({args.select})]",
    cmd,
]

if args.dry:
    print("<CMD> ", " ".join(shlex.quote(x) for x in bsub_cmd))    
else:
    print("<CMD> ", " ".join(shlex.quote(x) for x in bsub_cmd))    
    subprocess.run(bsub_cmd, check=True)

