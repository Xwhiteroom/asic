#!/usr/bin/env python3
"""
# Copyright (c) 2026 Syed Shakir Iqbal (Xwhiteroom)
# SPDX-License-Identifier: MIT

# Description  : Restore STA/Innovus Session.
"""
global my_version
my_version = "V3.0"
####################################################################################################################
import sys,glob,re,time,datetime,inspect,itertools,json,copy;#tqdm;#yaml
from   collections              import defaultdict
from   argparse                 import Namespace
from   operator                 import itemgetter
import argparse
import glob
import json
import os
import re
import textwrap
import random
tree = lambda: defaultdict(tree);
spacing_string = "\t\t                         ";
#-------------------------------------------------------------------------------------------------------------
# Global
#-------------------------------------------------------------------------------------------------------------
#   Format for exec summary
def get_exec_time(start,end):
     if end != 0 : xtime = round(end - start,0) ; duration = str(datetime.timedelta(seconds=xtime));
     return duration;
#-------------------------------------------------------------------------------------------------------------
#   Format for exec summary
def get_exec_sum(func_name,comment,start,end):
    duration = "--------"; Xtype = "Start";add = "";
    if end != 0 : duration = "%08.2f" %(end - start); Xtype = "Done "; add = "";
    my_message = "\t** Info::%20s:\t " %(func_name) + Xtype + "[" + duration + "s]  " + comment + add;
    return my_message;
#-------------------------------------------------------------------------------------------------------------
#   Report file mem in B/KB/MB/GB
def get_file_mem(file):
    size  = os.path.getsize(file);
    unit  = "B"
    if size < 1024:                    unit = "B" ; size = round(size,1)
    elif size < (1024*1024):           unit = "KB"; size = round(size/1024,1)
    elif size < (1024*1024*1024):      unit = "MB"; size = round(size/(1024*1024),1)
    elif size < (1024*1024*1024*1024): unit = "GB"; size = round(size/(1024*1024*1024),1)
    out = str(size) + " " + unit;
    return out
#-------------------------------------------------------------------------------------------------------------
def load_json(json_file):
    func_name = "<load_json>";
    comment   = "Loading JSON file " + json_file;
    step1_time = time.time();
    if not os.path.isfile(json_file):
      raise Exception('JSON file not found "%s"' % json_file)
    with open(json_file, 'r') as file_ptr: my_dictionary_temp = json.load(file_ptr);
    step2_time = time.time();xsum = get_exec_sum(func_name,comment,step1_time,step2_time);print(xsum);
    return my_dictionary_temp
#-------------------------------------------------------------------------------------------------------------
#   Object to JSON file
def write_json(data,json_file,formatx):
    func_name = "<write_json>";
    comment   = "Writing JSON file " + json_file ;
    step1_time = time.time();xsum = get_exec_sum(func_name,comment,step1_time,0);#Xprint(xsum);
    with open(json_file, "w") as f:
      if (formatx == "H"): f.write(json.dumps(data, sort_keys=True, indent=4, separators=(',', ': '))); #for pretty
      else               : f.write(json.dumps(data))
      f.close();
    comment = comment + " Size [" + get_file_mem(json_file) + "]";
    step2_time = time.time();xsum = get_exec_sum(func_name,comment,step1_time,step2_time);print(xsum);
#-------------------------------------------------------------------------------------------------------------
def glob_files(rpt_file_list):
  rpt_files = []
  for f in rpt_file_list:
    rpt_files += glob.glob(f)
  return rpt_files
#-------------------------------------------------------------------------------------------------------------
def parse_def_file(tup):
  func_name = "<parse_def_file>"
  '''
  Parse the def file and extract macros used
  '''
  f, tag, thread_no, fp_start, fp_end = tup
  fp = open_file(f, fp_start)
  line = fp.readline()

  macros = {}
  total  = {}
  while line:
    xline = re.sub("^\s+","",line)
    if '-' in xline and ('+ PLACED' in xline or '+ FIXED' in xline):
      ref_cell = xline.split(" ")[2]
      key = f'{tag}-{thread_no}-{ref_cell}'
      #key = f'{ref_cell}'
      macros[key] = ref_cell
      total[ref_cell] = ref_cell
    line = fp.readline()
  cells = len(list(total))
  info_string = "\t** Info::%20s:\t" % (func_name)
  #print(f'{info_string} Processed {cells} cells');
  #progress_multi["def_parse"]["count"] += 1
  #done   = 100 * progress_multi["def_parse"]["count"] /  progress_multi["def_parse"]["total"]
  #print("%02d" % (done),end=" ")
  return macros
#-------------------------------------------------------------------------------------------------------------
def parse_lef_file(tup):
  func_name = "<parse_lef_file>"
  '''
  Parse the lef file and extract macros used
  '''
  f, tag, thread_no, fp_start, fp_end = tup
  fp = open_file(f, fp_start)
  basex = os.path.basename(f)
  line = fp.readline()

  macros = {}
  macros["cell"] = dict()
  macros["tech"] = dict()

  total  = {}
  is_file_tech_lef = 0;
  while line:
    if 'MANUFACTURINGGRID' in line : is_file_tech_lef += 1
    if 'CLEARANCEMEASURE'  in line : is_file_tech_lef += 1
    if 'MACRO ' in line :
      #ref_cell = line.split(" ")[1]
      ref_cell = re.sub("\n","",line.split(" ")[1])
      key = f'{tag}-{thread_no}-{basex}-{ref_cell}'
      #key = f'{ref_cell}'
      macros["cell"][key] = ref_cell
      total[ref_cell] = basex
    line = fp.readline()
  cells = len(list(total))
  info_string = "\t** Info::%20s:\t" % (func_name)
  #print(f'{info_string} Processed {cells} cells in {f}');
  if is_file_tech_lef == 2: macros["tech"][f] =  is_file_tech_lef
  return macros
#-------------------------------------------------------------------------------------------------------------
def get_phydb_qc(run_dir,xargs):

  xfile_map                   = tree()
  xfile_map["file_tech_lefs"] = xargs.techlef
  xfile_map["file_dk_lefs"]   = xargs.dklef
  xfile_map["file_ip_lefs"]   = xargs.iplef
  xfile_map["file_miss_lefs"] = xargs.misslef
  xfile_map["file_ip_defs"]   = xargs.ipdef
  xfile_map["file_ip_mims"]   = xargs.mims

  os.system("touch %s/%s " % (run_dir,"PHY_DB_ENABLED"))
  for xid in xfile_map : os.system("touch %s/%s " % (run_dir,xid))
  for xid in xfile_map :
    if bool(os.path.exists(xfile_map[xid])):
      os.system("cat %s > %s/%s " % (xfile_map[xid],run_dir,xid))
    else :
      print("          - Warning : Missing PhyDB file %s --> %s !" % (xid,xfile_map[xid]))

  sta_tcl_header = textwrap.dedent(f"""

  ##---------------------------------------------------------------------------------------
  puts "** STA_GLB_INFO:: Adding File List [date]"
  ##---------------------------------------------------------------------------------------
  global xphy_db_set
  global xphy_db_list
  ##---------------------------------------------------------------------------------------

  """)

  for xid in xfile_map : sta_tcl_header += "  set xphy_db_set(%s)   %s/%s\n"  % (xid,run_dir,xid)

  return sta_tcl_header

#-------------------------------------------------------------------------------------------------------------
def get_phydb_proc():

  sta_tcl_header = """

  ##---------------------------------------------------------------------------------------
  puts "** STA_GLB_INFO:: Adding Global Procs To Support PhyDBIn For Slaves/Master [date]"
  ##---------------------------------------------------------------------------------------
  global xphy_db_set
  global xphy_db_list
  ##---------------------------------------------------------------------------------------
  proc print_stage {  red_blue comment } {
      if { $red_blue == "blue" } {
              puts [format "\\033\[34m%-100s %30s \\033\[0m" "$comment"  [date]]
      } else {
              puts [format "\\033\[31m%-100s %30s \\033\[0m" "$comment"  [date]]
      }
  }
  ##---------------------------------------------------------------------------------------
  proc pt_get_files_from_list { category xfiles } {
	set design_files  [list]
	set file_counter  0
	array unset uniq_files

	foreach flist $xfiles {
		set indata [open $flist ]
   		while {[gets $indata line]>=0} {
			if { [file exist $line] } {
				if { ![info exist uniq_files($line)] } {
					lappend  design_files $line
					set uniq_files($line) $line
					incr file_counter
				}
				if { [regexp "0000$" $file_counter] } {
					puts "                     - Valid Files $category = $file_counter"
				}
			} else {
				puts "** STA_GLB_WARN:: Missing $category File $line found in $flist"
			}
		}
	puts "** STA_GLB_INFO:: Found $category Files = $file_counter in $flist"
	close $indata
	}
	return $design_files
  }
  ##---------------------------------------------------------------------------------------
  proc pt_eco_phydb_read { file_tech_lefs file_dk_lefs file_ip_lefs file_miss_lefs file_ip_defs args} {

        pt_eco_phydb_in $file_tech_lefs $file_dk_lefs $file_ip_lefs $file_miss_lefs $file_ip_defs

	puts  "** STA_GLB_INFO:: Reading PhyDB using additional args=$args"
        # General Options
        reset_eco_options
        pt_clock_donttouch   true
        set_eco_options      -physical_enable_clock_data
        set_eco_options      -enable_pin_color_alignment_check
        set eco_strict_pin_name_equivalence true
        report_eco_options > [current_scenario].pre_phydb_eco_options.log
	puts  ""

        set use_tech_lefs   [pt_get_files_from_list TECH_LEF $file_tech_lefs]
	set use_dk_lefs     [pt_get_files_from_list DK_LEF   $file_dk_lefs]
	set use_ip_lefs     [pt_get_files_from_list IP_LEF   $file_ip_lefs]
	set use_miss_lefs   [pt_get_files_from_list MISS_LEF $file_miss_lefs]
	set use_ip_defs     [pt_get_files_from_list IP_DEF   $file_ip_defs]
        set cmd "set_eco_options -log_file ./\[current_scenario\].physical_lef_def.log -physical_lib_path \[concat \$use_dk_lefs \$use_ip_lefs\] -physical_design_path \[concat \$use_ip_defs\]  -allow_missing_lef \[concat \$use_miss_lefs\] $args"
	puts  ""
        puts  "                  <CMD> $cmd"
	puts  ""
	eval $cmd
        report_eco_options > [current_scenario].post_phydb_eco_options.log
	puts  ""
        check_eco
  }
  ##---------------------------------------------------------------------------------------
  proc pt_eco_phydb_in { file_tech_lefs file_dk_lefs file_ip_lefs file_miss_lefs file_ip_defs } {
  	global xphy_db_set xphy_db_list
	set xphy_db_set(file_tech_lefs) "$file_tech_lefs"
	set xphy_db_set(file_dk_lefs)   "$file_dk_lefs"
	set xphy_db_set(file_ip_lefs)   "$file_ip_lefs"
	set xphy_db_set(file_miss_lefs) "$file_miss_lefs"
	set xphy_db_set(file_ip_defs)   "$file_ip_defs"
	puts "** STA_GLB_INFO:: PhyDB Pointer Set As Below"
        #parray xphy_db_set
	foreach xfile [array names xphy_db_set] {
		set status [ catch { file  copy -force $xphy_db_set($xfile) . }]
		if { $status == "1" } {
			puts "                     - Failed to Copy File List $xfile -> $xphy_db_set($xfile)"

		} else {
			puts "                     - Locally Copied File List $xfile -> $xphy_db_set($xfile)"
		}
	}
	puts  ""
  }
  ##---------------------------------------------------------------------------------------
  proc pt_eco_phydb_prep { file_tech_lefs file_dk_lefs file_ip_lefs file_miss_lefs file_ip_defs } {
  	global xphy_db_set xphy_db_list
	set xphy_db_set(file_tech_lefs) "$file_tech_lefs"
	set xphy_db_set(file_dk_lefs)   "$file_dk_lefs"
	set xphy_db_set(file_ip_lefs)   "$file_ip_lefs"
	set xphy_db_set(file_miss_lefs) "$file_miss_lefs"
	set xphy_db_set(file_ip_defs)   "$file_ip_defs"
	puts "** STA_GLB_INFO:: PhyDB Pointer Set As Below"
        parray xphy_db_set
	foreach xfile [array names xphy_db_set] {
		set status [ catch { file  copy -force $xphy_db_set($xfile) . }]
		if { $status == "1" } {
			puts "** STA_GLB_WARN:: Failed to Copy File List $xfile -> $xphy_db_set($xfile)"
		} else {
			puts "** STA_GLB_INFO:: Locally Copied File List $xfile -> $xphy_db_set($xfile)"
		}
	}
        pt_eco_phydb_to_list
	puts ""

  }
  ##---------------------------------------------------------------------------------------
  proc pt_eco_phydb_to_list {} {
  	global xphy_db_set xphy_db_list
	set xphy_db_list  		[list]
	foreach xfile [array names xphy_db_set] {
		lappend xphy_db_list   "$xfile,$xphy_db_set($xfile)"
	}
  }
  ##---------------------------------------------------------------------------------------
  proc pt_help_phydb_in {} {

      puts "
            #==============================================================================================================
            # TECH + DK FILES
            #==============================================================================================================
            set xtrack h210
            #set xtrack h280
            set eco_kit_dir    \"[pwd]/eco_kit\"
            array unset xphy_db_set
            set xphy_db_set(file_tech_lefs) \"\$eco_kit_dir/tech/\$xtrack/tech.leflist\"
            set xphy_db_set(file_dk_lefs)   \"\$eco_kit_dir/dk/\$xtrack/dk.leflist\"
            set xphy_db_set(file_ip_lefs)   \"\$eco_kit_dir/ip/\$xtrack/ip.leflist\"
            set xphy_db_set(file_miss_lefs) \"\$eco_kit_dir/miss/\$xtrack/miss.leflist\"
            set xphy_db_set(file_ip_defs)   \"\$eco_kit_dir/ipdef/ip.deflist\"

            pt_eco_phydb_read  \$xphy_db_set(file_tech_lefs) \$xphy_db_set(file_dk_lefs) \$xphy_db_set(file_ip_lefs) \$xphy_db_set(file_miss_lefs) \$xphy_db_set(file_ip_defs)

        "
  }
  ##---------------------------------------------------------------------------------------
  proc pt_clock_donttouch { true_false} {
      puts "** STA_GLB_INFO:: Apply ClockNetwork as DontTouch=$true_false"
      set_dont_touch [get_clock_network_objects -type cell -include_clock_gating_network [get_clock *]] $true_false
      set_dont_touch [get_clock_network_objects -type net  -include_clock_gating_network [get_clock *]] $true_false
      set_dont_touch [get_clock_network_objects -type pin  -include_clock_gating_network [get_clock *]] $true_false
      set_dont_touch [get_clock_network_objects -type pin                                [get_clock *]] $true_false
  }
  ##---------------------------------------------------------------------------------------


  """
  return sta_tcl_header

#-------------------------------------------------------------------------------------------------------------
def get_dmsa_wrapper(session_list,cores,ram,tag,rundir,xargs):

  parse_session  = "[list \\\n"
  for x in session_list:
    if os.path.exists(x):
      parse_session += " %s \\\n" % (os.path.realpath(x))
  parse_session  += " ]"
  mims            = "\"" + xargs.mims + "\""
  dp_cmd          = re.sub('"','\\"',xargs.dp_cmd)
  sta_tcl_header = textwrap.dedent(f"""


  global CUSTOM_STA_ECO_SESSION CUSTOM_STA_ECO_CORE CUSTOM_STA_ECO_RAM CUSTOM_STA_ECO_TAG CUSTOM_STA_ECO_RUN CUSTOM_STA_ECO_MIM CUSTOM_STA_ECO_DP_CMD
  set CUSTOM_STA_ECO_DP_CMD  "{dp_cmd}"
  set CUSTOM_STA_ECO_SESSION {parse_session}
  set CUSTOM_STA_ECO_CORE    {cores}
  set CUSTOM_STA_ECO_RAM     {ram}
  set CUSTOM_STA_ECO_TAG     {tag}
  set CUSTOM_STA_ECO_RUN     {rundir}
  set CUSTOM_STA_ECO_MIM     {mims}

  """)

  sta_tcl_header += """

  ##---------------------------------------------------------------------------------------
  # Above Vars Are Flow Controllers
  #    -  CUSTOM_STA_ECO_DP_CMD
  #    -  CUSTOM_STA_ECO_SESSION
  #    -  CUSTOM_STA_ECO_CORE
  #    -  CUSTOM_STA_ECO_RAM
  #    -  CUSTOM_STA_ECO_TAG
  #    -  CUSTOM_STA_ECO_RUN
  #    -  CUSTOM_STA_ECO_MIM
  ##---------------------------------------------------------------------------------------
  puts "** STA_GLB_INFO:: Adding Global Procs [date]"
  ##---------------------------------------------------------------------------------------
  proc print_stage {  red_blue comment } {
      if { $red_blue == "blue" } {
              puts [format "\\033\[34m%-100s %30s \\033\[0m" "$comment"  [date]]
      } else {
              puts [format "\\033\[31m%-100s %30s \\033\[0m" "$comment"  [date]]
      }
  }
  ##---------------------------------------------------------------------------------------
  print_stage blue \"** STA_GLB_INFO:: Adding Global Procs\"
  ##---------------------------------------------------------------------------------------
  proc globalset { cmdx } {
      eval $cmdx
      remote_execute { eval $cmdx }
  }
  ##---------------------------------------------------------------------------------------
  proc file_to_list {filename} {
      set data [list]
      if { [file exist $filename] } {
         set f [open $filename ]
         set data [split [string trim [read $f]]]
         close $f
      }
         return $data
  }

  """

  sta_tcl_header += """

  ##---------------------------------------------------------------------------------------
  print_stage blue "** STA_GLB_INFO:: Adding DMSA Setting"
  ##---------------------------------------------------------------------------------------

  ## Enable Additional PT Vars
  set         eco_strict_pin_name_equivalence           true
  set         eco_physical_ignore_bad_site_rows         true
  set_app_var timing_enable_graph_based_refinement      true
  set_app_var timing_refinement_max_slack_threshold     0.0
  set_app_var eco_enable_mim                            true


  ## LSF Setup
  print_stage blue \"** STA_GLB_INFO:: Setting Up Slave LSF\"
  set multi_scenario_working_directory 	        $CUSTOM_STA_ECO_RUN
  set multi_scenario_merged_error_log 	        $CUSTOM_STA_ECO_RUN/error_log.log
  set multi_scenario_license_mode               core
  set num_sessions 			        [llength $CUSTOM_STA_ECO_SESSION]
  set report_default_significant_digits         3

  if { $CUSTOM_STA_ECO_RAM > 0 } {
    set_host_options -name PT_DMSA_LSF  -num_processes $num_sessions -max_cores $CUSTOM_STA_ECO_CORE -protocol custom -submit_command "$CUSTOM_STA_ECO_DP_CMD -J PT_DMSA_SLAVE_$CUSTOM_STA_ECO_TAG -- "
  } else {
    set_host_options -name PT_ECO_LOCAL -num_processes $num_sessions -max_cores $CUSTOM_STA_ECO_CORE
  }
  start_hosts
  report_host_usage -nosplit


  ##---------------------------------------------------------------------------------------
  print_stage blue \"** STA_GLB_INFO:: Building DMSA\"
  ##---------------------------------------------------------------------------------------

  ## BUILT DMSA
  set id 	0
  foreach session_dir $CUSTOM_STA_ECO_SESSION {
    if {![file isdirectory $session_dir]} {
       puts "      - session directory not exist"
       puts "      - $session_dir"
       return 0
    } else {
       set scn_name "[lindex [split $session_dir "/"] end-1].[lindex [split $session_dir "/"] end].[expr { int(100000 * rand()) }]"
       if { [regexp "save_session." $session_dir] } {  set scn_name [lindex [split $session_dir "/"] end  ] ; print_stage red "** STA_GLB_INFO:: Name $scn_name";}
       if { [regexp "session.pocvm" $session_dir] } {  set scn_name [lindex [split $session_dir "/"] end-1] ; print_stage red "** STA_GLB_INFO:: Name $scn_name";}
       regsub -all {.*save_session.} $scn_name {} scn_name
       regsub -all {.*sta.bb_gba.}   $scn_name {} scn_name
       regsub -all {.*sta.bb_sta.}   $scn_name {} scn_name
       regsub -all {.*sta.bb_pba.}   $scn_name {} scn_name
       regsub -all {\/} $scn_name {_}
       set     scn_name  [format "%s.%03d" $scn_name $id]
       puts "      - creating image using - $session_dir"
       puts "      - scenario = $scn_name"
       create_scenario -name $scn_name -image    ${session_dir}
    }
       incr id
  }

  ##---------------------------------------------------------------------------------------
  print_stage blue \"** STA_GLB_INFO:: Finalizing DMSA\"
  ##---------------------------------------------------------------------------------------

  ## Variable Export
  current_session  -all
  current_scenario -all

  set DMSA_VARS     [list ]
  set DMSA_VARS     [concat $DMSA_VARS [list CUSTOM_STA_ECO_SESSION  CUSTOM_STA_ECO_CORE  CUSTOM_STA_ECO_RAM  CUSTOM_STA_ECO_TAG  CUSTOM_STA_ECO_RUN  CUSTOM_STA_ECO_MIM] ]
  set_distributed_variable  $DMSA_VARS

  ## Root Dir Setup
  print_stage blue \"** STA_GLB_INFO:: CD to Target RunDir $CUSTOM_STA_ECO_RUN\"
  file mkdir $CUSTOM_STA_ECO_RUN
  cd         $CUSTOM_STA_ECO_RUN
  set MODE       DMSA
  set CORNER     DMSA
  set SCENARIO   $MODE.$CORNER

  ##---------------------------------------------------------------------------------------
  print_stage red \"** STA_GLB_INFO:: Adding ECO Tag/MIM Options\"
  ##---------------------------------------------------------------------------------------
  ## Enable ECO Options
  set CUSTOM_STA_ECO_PREFIX       "U_PTECOCUSTOM_[lindex [date] 1][lindex [date] 2]"
  set CUSTOM_STA_ECO_USED_MIMS    [file_to_list $CUSTOM_STA_ECO_MIM]

  if { $CUSTOM_STA_ECO_MIM != "" } {
    print_stage red \"** STA_GLB_INFO:: Adding MIM Setting CUSTOM_STA_ECO_USED_MIMS = $CUSTOM_STA_ECO_USED_MIMS\"
    set cmdx "
        remote_execute -verbose {
            set_eco_option -mim_group [file_to_list $CUSTOM_STA_ECO_MIM]
        }
    "
    eval $cmdx
  }
  print_stage red \"** STA_GLB_INFO:: CUSTOM_STA_ECO_PREFIX = $CUSTOM_STA_ECO_PREFIX\"
  set cmdx "
      remote_execute -verbose {
          set eco_strict_pin_name_equivalence                     true
          set eco_alternative_area_ratio_threshold                2
          set eco_instance_name_prefix                            $CUSTOM_STA_ECO_PREFIX
          set eco_net_name_prefix                                 $CUSTOM_STA_ECO_PREFIX
          set eco_insert_buffer_search_distance_in_site_rows      24
      }
  "
  eval $cmdx

  """
  return sta_tcl_header
#-------------------------------------------------------------------------------------------------------------
def get_session_data(session,xargs):

  # Defaults
  pt_version_from_session = "T-2022.03-SP5-1" ;
  my_design  = "UNKNOWN_TOP";
  pt_version = xargs.pt_shell
  binlookup  = xargs.binlookup
  xrandom    = random.randint(0,99999)
  date_stamp = datetime.datetime.now().strftime("%Y_%m_%d_%H_%M_%S")
  user_name  = os.environ.get('USER')
  base_name  = os.path.basename(session)

  run_tag    = "USER.%s.DATE.%s.RAND.%s.NAME.%s" % (user_name,date_stamp,xrandom,base_name)
  # Readme Parsing
  readme_file = glob.glob(session + "/README")
  if len(readme_file) > 0 :
    with open(readme_file[0]) as f:
      line = f.readline();
      while 'PrimeTime Version:' not in line: line = f.readline();
      line = f.readline(); pt_version_from_session = re.sub("^\s\+","",line).split()[0]
      while 'Current Design: ' not in line: line = f.readline();
      my_design = re.sub("^\s\+","",line).split()[2]


  # Bin Lookup
  pt_shell_file = "/cad/tools" + "/synopsys/primetime/" + pt_version_from_session + "/bin/pt_shell"
  pt_versions = list()
  print("Lookup Areas:",binlookup,"\nFile Pattern:",pt_shell_file)
  if binlookup != "":
    bin_lookup = 0
    for xlookup in binlookup.split(":") :
      path_name=  xlookup + pt_shell_file
      bin_file =  glob.glob(path_name)
      print("Lookup Areas:",binlookup,"\nFile Pattern:",pt_shell_file,"\nBin File Path:",path_name)
      if  len(bin_file):
        bin_lookup += 1
        pt_versions.append(bin_file)

  if len(pt_versions) < 1 : print("          - Warning : Session used a pt_shell version that  no longer exist! %s" % (pt_shell_file))
  else:                     pt_version = pt_versions[0]
  if len(pt_versions) > 1 : print("          - Warning : Session Found in multiple(%d) places but selected %s" % (len(pt_versions),pt_shell_file))

  # Cmd Parsing / Not Reliable
  cmd_file = glob.glob(session + "/cmd_log" + "Skipme")
  if len(cmd_file) > 0 :
    with open(cmd_file[0]) as f:
      line = f.readline();
      while 'primetime' not in line and 'admin/setup' not in line: line = f.readline();
      for x in line.split():
        if 'admin/setup' in x:
          file_path = re.sub("admin/setup/.synopsys_pt.setup","bin/pt_shell",x)
          if os.path.exists(file_path): pt_version = re.sub("admin/setup/.synopsys_pt.setup","bin/pt_shell",x)
          else:  print("          - Warning : Session used a pt_shell version that  no longer exist! %s" % (file_path))

  run_dir    = "%s/restore_pt/%s/%s/%s" % (xargs.logdir,my_design,pt_version_from_session,run_tag)
  return my_design,pt_version,pt_version_from_session,run_tag,run_dir
#-------------------------------------------------------------------------------------------------------------
def get_session_data_innovus(session,xargs):

  # Defaults
  inv_version_from_session = "22.13-e047_1" ;
  my_design  = "UNKNOWN_TOP";
  inv_version = xargs.innovus
  xrandom     = random.randint(0,99999)
  date_stamp = datetime.datetime.now().strftime("%Y_%m_%d_%H_%M_%S")
  user_name  = os.environ.get('USER')
  run_tag    = "USER.%s.DATE.%s.RAND.%s" % (user_name,date_stamp,xrandom)
  # Readme Parsing
  readme_file = glob.glob(session + "/*.globals")
  if len(readme_file) > 0 :
    with open(readme_file[0]) as f:
        for line in f:
            # ---- Design extraction race ----
            if my_design == "UNKNOWN_TOP":
                if line.strip().startswith("#  Design:"):
                    # Example: "#  Design:   sdm_emcpu_top"
                    match = re.search(r"#\s*Design:\s*(\S+)", line)
                    if match:
                        my_design = match.group(1)
                        print("          - Design Found :", my_design)

                elif "init_top_cell" in line:
                    tokens = re.sub(r'^[\s+]|[{}]', "", line).split()
                    if len(tokens) >= 3:
                        my_design = tokens[2]
                        print("          - Design Found :", my_design)

            # ---- DB version extraction ----
            if inv_version_from_session == xargs.innovus and "restore_db_version" in line:
                tokens = re.sub(r'^[\s+]|[{}]', "", line).split()
                if len(tokens) >= 3:
                    inv_version_from_session = tokens[2]
                    print("          - DB Found :", inv_version_from_session)

            # ---- break early if both found ----
            if my_design != "UNKNOWN_TOP" and inv_version_from_session != xargs.innovus:
                break

  # Cmd Parsing
  innovus_path    = inv_version
  innovus_path_db = "tools/cadence/innovus/%s/bin/innovus" % (inv_version_from_session)

  if os.path.exists(innovus_path_db): innovus_path = innovus_path_db ; inv_version=innovus_path_db;
  else:  print("          - Warning : Session used a innovus version that  no longer exist! %s" % (innovus_path_db))

  run_dir    = "%s/restore_innovus/%s/%s/%s" % (xargs.logdir,my_design,inv_version_from_session,run_tag)
  return my_design,inv_version,inv_version_from_session,run_tag,run_dir,innovus_path

#-------------------------------------------------------------------------------------------------------------
def main():
  func_name = "<load_me>";
  step1_time = time.time();#xsum = get_exec_sum(func_name,comment,step1_time,0);#Xprint(xsum);
  #if int(args.debug) > 0 : print('@id ' + str(idx), end='\r', flush=True)
  present_user = os.environ.get('USER')

  # Priviledge access
  plot = 0;
  if present_user == "sshakiriqbal": plot = 1

  parser = argparse.ArgumentParser(description='Restore Sessions Version=' + str(my_version) )
  parser.add_argument('sessions'   , nargs='+', help='session_dirs')
  # Compute
  parser.add_argument('--dp_cmd'   , default='nc run -jobproj braga.pd -Ix -I -wl -F -r "CORES/CNT_CORE SLOTS/1 RAM/CNT_RAM AZRESOURCEDISK#300000"', help='nc run -jobproj braga.pd -Ix -I -wl -F -r "CORES/CNT_CORE SLOTS/1 RAM/CNT_RAM  redhat8"')
  parser.add_argument('--core'     , default=8, help='Default 8 ')
  parser.add_argument('--ram'      , default=96000, help='Default 96000')
  # Run Control
  parser.add_argument('--dry'      , default=1, help='Default 1')
  parser.add_argument('--prefix'   , default="", help='Default ""')
  parser.add_argument('--merge'    , default=0, help='Default 0')
  # Tool Control
  parser.add_argument('--pt_shell' , default="pt_shell", help='Default pt_shell')
  parser.add_argument('--innovus'  , default="innovus", help='Default innovus')
  parser.add_argument('--notiming' , default=0, help='Default innovus no timing=0')
  parser.add_argument('--binlookup', default="", help='Default LookUp Area For Binary : seperated')
  # General Hoosk
  parser.add_argument('--script'   , default="", help='Default "", this script is sourced with a catch post restore session')
  parser.add_argument('--post_cmd' , default="pwd ; sleep 30", help='Default "", this cmd is run after exit of restore_session only in pt_shell so far')
  parser.add_argument('--logdir'   , default="./", help='Default ./')
  # PT ECO
  parser.add_argument('--dmsa'     , default=0, help='Default 0')
  parser.add_argument('--phy'      , default=0, help='Default 0')
  parser.add_argument('--techlef'  , default="", help='Default none')
  parser.add_argument('--dklef'    , default="", help='Default none')
  parser.add_argument('--iplef'    , default="", help='Default none')
  parser.add_argument('--ipdef'    , default="", help='Default none')
  parser.add_argument('--misslef'  , default="", help='Default none')
  parser.add_argument('--phyarg'   , default="", help='Default none')
  parser.add_argument('--mims'     , default="", help='Default none')

  args = parser.parse_args()

  # Configure Compute
  print("          - Informs : DP Compute ORG : ",args.dp_cmd)
  args.dp_cmd = re.sub("CNT_CORE",args.core,args.dp_cmd)
  args.dp_cmd = re.sub("CNT_RAM",args.ram,args.dp_cmd)
  print("          - Informs : DP Compute UPD : ",args.dp_cmd)
  print("          - Informs : Post Run CMD   : ",args.post_cmd)

  # Find Out The sessions Used
  my_sessions = glob_files(args.sessions)
  pt_version_from_session  = "T-2022.03-SP5-1" ;
  inv_version_from_session = "22.13-e047_1" ;

  my_design   = "UNKNOWN_TOP";
  pt_version  = "pt_shell"
  inv_version = "innovus"

  run_cmd_mrg  = "xfce4-terminal -H  --tab -T %s  " % ("DEF_SESSION")

  # Find Out The sessions Used is primetime/innovus:
  innovus_sessions   = []
  primetime_sessions = []
  for each_dir in my_sessions:
    if ".enc.dat" in each_dir or each_dir.endswith(".enc"):
      innovus_sessions.append(each_dir)
      print("          - Informs : Innovus   DB : ",each_dir)
    else:
      primetime_sessions.append(each_dir)
      print("          - Informs : Primetime DB : ",each_dir)


  if len(my_sessions) != 0 :
    # Innovus Loop
    if len(innovus_sessions) > 0 :
      run_cmd_mrg  = "xfce4-terminal -H  --tab -T %s  " % ("INNOVUS_SESSION")
      print("          - Warning : 1 or more sessions is type innovus please set --innovus version correctly , present ",args.innovus)
      print("          - GetHint : Run the same command with --dry 1 to get target innovus module load cmd !")
      print("          - Example : /cad/tools/cadence/innovus/25.11-y060_1/bin/innovus !")
      for session in innovus_sessions:
        if os.path.isdir(session):
          # Session Parsing
          print("          - Session %s" % (session))
          my_design,inv_version,inv_version_from_session,run_tag,run_dir,innovus_path = get_session_data_innovus(session,args)
          print("          - Design  : %s" % (my_design))
          print("          - Version : %s" % (inv_version))
          if args.prefix != "": run_tag = str(args.prefix) + "__" + run_tag
          run_tag = my_design + ".INV." + run_tag
          innovus_template = "win off; setMultiCpuUsage -localCpu %s ; restoreDesign %s %s; cd %s ; timeDesign -reportOnly ; " % (args.core,session,my_design,run_dir)
          if int(args.notiming):
            innovus_template = "win off; setMultiCpuUsage -localCpu %s ; restoreDesign -noTiming %s %s; cd %s ; " % (args.core,session,my_design,run_dir)
            print("          - Warning : DB Restored Via NoTiming")
            run_tag = my_design + ".INV_NO_TIM." + run_tag

          if args.script != "" : innovus_template += " catch { source %s } ; " % (args.script)
          # File Creation
          os.system("mkdir -p %s " % (run_dir))
          run_dir = os.path.abspath(run_dir)
          inv_tcl  = run_dir + "/innovus.tcl"
          inv_log  = run_dir + "/innovus.log"
          # Main CMD Creation
          fp = open(inv_tcl,"w+"); print(innovus_template,file=fp);fp.close();

          main_cmd    = "\n#module unload  tools/cadence/innovus ; module load  tools/cadence/innovus/%s" % (inv_version_from_session)
          main_cmd   += "\n"
          run_cmd     = "xterm -T %s -geometry 300x64 -e \"%s -wait 100 -log %s -files %s \" &" % (run_tag,inv_version,inv_log,inv_tcl)
          run_cmd_mrg += " --tab -T %s -e \"bash -c ' %s -output_log_file %s -f %s ; bash '\"" % (run_tag,inv_version,inv_log,inv_tcl)

          #run_cmd_lsf = "nc run -r CORES/%s RAM/%s -J LSF_%s -- %s " % (args.core,args.ram,run_tag,run_cmd)
          run_cmd_lsf = "%s -J LSF_%s -- %s " % (args.dp_cmd,run_tag,run_cmd)

          if int(args.ram) > 0  : main_cmd += run_cmd_lsf
          else                  : main_cmd += run_cmd
          if int(args.dry) == 1 : print("\n",main_cmd)
          else                  : os.system(main_cmd)


    # Primetime Loop
    if int(args.dmsa) == 0 :
      for session in primetime_sessions:
        run_cmd_mrg  = "xfce4-terminal -H  --tab -T %s  " % ("PT_SESSION")
        if os.path.isdir(session):
          # Session Parsing
          my_design,pt_version,pt_version_from_session,run_tag,run_dir = get_session_data(session,args)
          if args.prefix != "": run_tag = str(args.prefix) + "__" + run_tag
          run_tag = my_design + ".PT." + run_tag
          smsa_template = "set_host_options -max_cores %s ; set STA_SESSION %s  ; restore_session %s ; cd %s ; " % (args.core,session,session,run_dir)
          if args.script != "" : smsa_template += " catch { source %s } ; " % (args.script)
          # File Creation
          os.system("mkdir -p %s " % (run_dir))
          run_dir = os.path.abspath(run_dir)
          pt_tcl  = run_dir + "/pt.tcl"
          pt_log  = run_dir + "/pt.log"
          # Main CMD Creation
          fp = open(pt_tcl,"w+"); print(smsa_template,file=fp);fp.close();

          main_cmd    = "\n#module unload  tools/synopsys/primetime ; module load  tools/synopsys/primetime/%s" % (pt_version_from_session)
          main_cmd   += "\n"
          run_cmd     = "xterm -T %s -geometry 300x64 -e \"%s -output_log_file %s -f %s ; %s \" &" % (run_tag,pt_version,pt_log,pt_tcl,args.post_cmd)
          run_cmd_mrg += " --tab -T %s -e \"bash -c ' %s -output_log_file %s -f %s ; %s ;bash '\"" % (run_tag,pt_version,pt_log,pt_tcl,args.post_cmd)
          #run_cmd_lsf = "nc run -r CORES/%s RAM/%s -J LSF_%s -- %s " % (args.core,args.ram,run_tag,run_cmd)
          run_cmd_lsf = "%s -J LSF_%s -- %s " % (args.dp_cmd,run_tag,run_cmd)

          if int(args.merge) == 0:
            if int(args.ram) > 0  : main_cmd += run_cmd_lsf
            else                  : main_cmd += run_cmd
            if int(args.dry) == 1 : print("\n",main_cmd)
            else                  : os.system(main_cmd)
      if int(args.merge) == 1 :
            #run_cmd_lsf_mrg = "nc run -r CORES/%s RAM/%s -J LSF_%s -- %s &" % (args.core,args.ram,run_tag,run_cmd_mrg)
            run_cmd_lsf_mrg = "%s -J LSF_%s -- %s " % (args.dp_cmd,run_tag,run_cmd_mrg)
            if int(args.ram) > 0  : main_cmd += run_cmd_lsf_mrg
            else                  : main_cmd += run_cmd_mrg
            if int(args.dry) == 1 : print("\n",main_cmd)
            else                  : os.system(main_cmd)
    else:
      for session in primetime_sessions:
        if os.path.isdir(session):
          # Session Parsing
          my_design,pt_version,pt_version_from_session,run_tag,run_dir = get_session_data(session,args)
          if args.prefix != "": run_tag = str(args.prefix) + "__" + run_tag
          run_tag = my_design + ".PT." + run_tag
      # File Creation
      os.system("mkdir -p %s " % (run_dir)) ;
      run_dir = os.path.abspath(run_dir)
      pt_tcl = run_dir + "/pt_dmsa.tcl"
      pt_log = run_dir + "/pt_dmsa.log"
      pt_phy = run_dir + "/pt_phy.tcl"
      # Main CMD Creation
      dmsa_template = get_dmsa_wrapper(args.sessions,args.core,args.ram,run_tag,run_dir,args)
      if args.script != ""  : dmsa_template += "\n  catch { source %s } ; \n" % (args.script)
      # Prep Phy DB Input Dependency
      xphy_template = get_phydb_proc()
      dmsa_template += "  ##---------------------------------------------------------------------------------------\n"
      dmsa_template += "  print_stage blue \"** STA_GLB_INFO:: Start Importing Procs for PhyDB\" ; \n\n"
      dmsa_template += "  ##---------------------------------------------------------------------------------------\n"
      dmsa_template += "  source  %s ;   \n\n" % (pt_phy)
      dmsa_template += "  remote_execute  -verbose { source  %s } ; \n\n" % (pt_phy)

      if int(args.phy) == 1 :
        # Normal Import
        xphy_template += "  ##---------------------------------------------------------------------------------------\n"
        xphy_template += "  puts \"** STA_GLB_INFO:: Start Importing Procs for PhyDB\" ; \n"
        xphy_template += "  ##---------------------------------------------------------------------------------------\n"
        xphy_template += get_phydb_qc(run_dir,args)
        # For Callback
        dmsa_template += "  ##---------------------------------------------------------------------------------------\n"
        dmsa_template += "  print_stage blue \"** STA_GLB_INFO:: Starting With Physical DB read [date]\"\n"
        dmsa_template += "  ##---------------------------------------------------------------------------------------\n\n"
        dmsa_template += "  remote_execute -verbose { pt_eco_phydb_read  $xphy_db_set(file_tech_lefs) $xphy_db_set(file_dk_lefs) $xphy_db_set(file_ip_lefs) $xphy_db_set(file_miss_lefs) $xphy_db_set(file_ip_defs) %s } ;\n\n" % (args.phyarg)

      fp = open(pt_tcl,"w+"); print(dmsa_template,file=fp);fp.close();
      fp = open(pt_phy,"w+"); print(xphy_template,file=fp);fp.close();

      main_cmd    = "\n#module unload tools/synopsys/primetime ; module load tools/synopsys/primetime/%s" % (pt_version_from_session)
      main_cmd   += "\n"
      run_cmd     = "xterm -T DMSA_PHY%d_%s -geometry 300x64 -e \"%s -output_log_file %s -multi -f %s \" ; %s &" % (int(args.phy),run_tag,pt_version,pt_log,pt_tcl,args.post_cmd)
      #run_cmd_lsf = "nc run -r CORES/%s RAM/%s -J LSF_DMSA_PHY%d_%s -- %s " % (args.core,args.ram,int(args.phy),run_tag,run_cmd)
      run_cmd_lsf = "%s -J LSF_%s -- %s " % (args.dp_cmd,run_tag,run_cmd)

      if int(args.ram) > 0  : main_cmd += run_cmd_lsf
      else                  : main_cmd += run_cmd
      if int(args.dry) == 1 : print("\n",main_cmd) ;  os.system("rm -rf %s" % (run_dir))
      else                  : os.system(main_cmd)

  else:
    return "No Sessions Found!"
main()
