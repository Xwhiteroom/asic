#!/usr/bin/env python3
"""
# Copyright (c) 2026 Syed Shakir Iqbal (Xwhiteroom)
# SPDX-License-Identifier: MIT

"""
import argparse
import glob
import json
import multiprocessing
import os
import re
import gzip
import pandas



def print_cur(cur_dict):
  for xattr in   cur_dict: print("%20s | %s" % (xattr,cur_dict[xattr]))


def load_json(f):
  if not os.path.isfile(f):
    raise Exception('JSON file not found "%s"' % f)
  with open(f) as fp:
    return json.load(fp)


def merge_json(a, b, key_set):
  req_list = [
      'check_href', 'mode', 'corner', 'bunch_id', 'start_pin', 'end_pin'
  ]
  merged_json = {}
  for key in key_set:
    if key in a:
      merged_json[key] = a[key]
    elif key in req_list:
      merged_json[key] = b[key]
    else:
      merged_json[key] = float('nan')
    if key in b:
      merged_json[key + '_released'] = b[key]
    else:
      merged_json[key + '_released'] = float('nan')
  return merged_json


def glob_files(rpt_file_list):
  rpt_files = []
  for f in rpt_file_list:
    rpt_files += glob.glob(f)
  return rpt_files


def read_next_lines(fp, num, line):
  for x in range(num):
    line = fp.readline()

  return line


def get_data(line_count, cur, fp, line, name, idx, skip):
  #line =  re.sub(" \* ", " ",line)
  cur[name] = line.split()[idx]
  #For debug:
  #xline = re.sub("\s+", ' ',line) ; xline = "";print(line_count,line_count+skip,"\t,",name,"=",cur[name]);
  return line_count+skip, read_next_lines(fp, skip, line)


def get_module(cell, project_tech):
  module_dict = project_tech['module_map']
  temp_dict   = dict();
  temp_dict[0] = 'TOP'
  for regex in module_dict:
    if re.search(regex, cell):
      temp_dict[len(regex)] = module_dict[regex]
  index = max(sorted(temp_dict))
  #print(cell,temp_dict[index])
  #return module_dict[regex]
  return temp_dict[index]


def get_x2x(start, end, project_tech):
  x2x = ''
  ref_dict = project_tech['ref_map']
  s_ref = 'MAC' ; e_ref = 'MAC';
  regexS = "XX"
  regexE = "XX"

  for regex in ref_dict:
    #if re.search(regex, start):
    if regex in  start:      s_ref = ref_dict[regex] ; regexS = regex
      #print(regex,start)
    #if re.search(regex, end):
    if  regex in  end:       e_ref = ref_dict[regex] ; regexE = regex
  #print( regexS, s_ref, regexE,e_ref)

  return '%s2%s' % (s_ref, e_ref)

def parse_rca_file(tup):
  f, tag, args, data_dict, project_tech = tup

  #with gzip.open(f,"rt") as fp:
  with open(f) as fp:
    paths = 0
    start = False
    line_cnt = 1
    prev_line = ''
    prev_prev_line = ''
    line = fp.readline()
    vio_group = str(args.check)
    while line:
      if start:
        if ('max_' in line or 'min_' in line  or '_pulse_width' in line) and len(line.split()) == 1 and "-" not in line:
          vio_group = line.split()[0];
          vio_group = re.sub("transition", 'tran', vio_group)
          vio_group = re.sub("capacitance", 'cap', vio_group)
          vio_group = re.sub("sequential_clock_min_period", 'mp_seq', vio_group)
          vio_group = re.sub("sequential_clock_pulse_width", 'mpw_seq', vio_group)
          vio_group = re.sub("clock_tree_pulse_width", 'mpw_cts', vio_group)

          #print(vio_group)

      if not start:
        if line_cnt > 100:
          break
        if 'Report' in line:
          start = True
      '''Process Path Detection'''
      if 'VIOLATED' in line:
        #line = re.sub(" (VIOLATED).", '', line)
        line = line.split(" (VIOLATE")[0]
        paths += 1
        key = '%s-%s' % (str(tag), str(paths))
        #print(line);
        if key not in data_dict:
          data_dict[key] = {}
        cur = data_dict[key];
        cur['report_file'] = f
        cur['vid'] = key
        cur['id'] = key
        cur['design'] = args.design
        cur['vcheck'] = args.check
        cur['check']  = args.check
        cur['mode'] = args.mode
        cur['corner'] = args.corner
        cur['line_start'] = line_cnt
        cur["brw_start"]  = '0.000'
        cur["brw_end"]    = '0.000'
        cur["brw_both"]   = '0.000'
        cur["buck_id"]      = ""
        cur["buck_cmt"]     = ""
        cur["slack_3T"]   = '0.000'
        cur["norm_slack_3T"]   = '0.000'
        cur["norm_delay"]   = '1.000'

        ''' Process Path Header'''
        # u_vcpu/u_cpu/u_l2_ctrl/SYN499070/A   0.3842   0.6650    -0.2808
        cur['end_pin']    = line.split()[0]
        cur['start_pin']  = line.split()[0]
        cur['buck_pat']   = line.split()[0]
        cur['required']   = line.split()[-3]
        cur['arrival']    = line.split()[-2]
        cur['slack']      = line.split()[-1]
        cur['group']      = vio_group
        cur['end_clk']    = "none"
        if 'mp_' in vio_group or 'mpw_' in vio_group :
            cur['end_clk']  = line.split("(")[1].split(")")[0] ;
            cur['end_clk']  = re.sub(" fall", ' F', cur['end_clk'])
            cur['end_clk']  = re.sub(" rise", ' R', cur['end_clk'])
        cur['hier']       = vio_group
        cur['x2x']        = vio_group


        cur['line_end']   = line_cnt;
        cur['arr_split']  = "Req:" + cur['required'] + " - Act:" + cur['arrival'] ;
        cur["norm_slack"] = cur["slack"]
        cur['end_module'] = get_module(cur['end_pin'], project_tech)
        cur['start_module'] = get_module(cur['start_pin'], project_tech)
        cur['travel'] = []
        cur['travel'].append(cur['start_module'])
        cur['travel'].append(cur['end_module'])
        cur['direction'] = '.'.join(cur['travel'])
        cur['buck_pat'] = re.sub("[0-9]+", '*', cur['buck_pat'])
        cur['buck_pat'] = re.sub(",", '*', cur['buck_pat'])
        cur['buck_pat'] = re.sub("\|", '->', cur['buck_pat'])
        cur['buck_pat'] = re.sub("\#", '->', cur['buck_pat'])
        if 'in2'  in cur['x2x'] :  cur['direction'] = str("IN." + cur['direction'])
        if '2out' in cur['x2x'] :  cur['direction'] = str(cur['direction'] + ".OUT")

      line = fp.readline();
      line_cnt+=1;
  print('Processed %s paths' % paths)
  print('Done parsing "%s"' % f)
  return data_dict



def parse_rpt_file(tup):
  f, tag, args, data_dict, project_tech = tup

  #with gzip.open(f,"rt") as fp:
  with open(f) as fp:

    paths = 0
    start = False
    line_cnt = 1
    prev_line = ''
    prev_prev_line = ''
    retDict = dict()
    # Shakir : Default MAPPING:
    retDict['design'] = args.design
    retDict['mode']   = args.mode
    retDict['corner'] = args.corner
    retDict['vcheck'] = args.check
    retDict['check']  = args.check
    if args.automap != "" :
      design_attr_data   = f.split("/")             ;    #hera_core.func.sspg_1p0000v_125c_rcmax.path.max.full.rpt
      design_attr        = design_attr_data[-1].split(".") ;    #hera_core.func.sspg_1p0000v_125c_rcmax.path.min_path.detail.rpt
      retDict['design']  = design_attr[0]
      retDict['mode']    = design_attr[1]
      retDict['corner']  = design_attr[2]
      retDict['check']   = "min"
      if "path.max" in design_attr_data[-1] or "max_path" in design_attr_data[-1]:  retDict['check']   = "max";
      retDict['vcheck']  = retDict['check']

    line = fp.readline()
    while line:
      #line =  re.sub(" \* ", " ",line)
      if not start:
        if line_cnt > 100:
          break
        if 'Report : timing' in line:
          start = True
      '''Process Path Detection'''
      if 'Startpoint:' in line:
        paths += 1
        key = '%s-%s' % (str(tag), str(paths))
        if key not in data_dict:
          data_dict[key] = {}
        cur = data_dict[key];
        cur['report_file'] = re.sub("whitechapel-asia","user",f);
        cur['vid'] = key
        cur['id'] = key
        cur['design'] = retDict['design'] ; #args.design
        cur['vcheck'] = retDict['vcheck'] ; #args.check
        cur['check']  = retDict['check']  ; #args.check
        cur['mode']   = retDict['mode']   ; #args.mode
        cur['corner'] = retDict['corner'] ; #args.corner
        cur['travel'] = []
        cur['crossing'] = []
        cur['crossing_dly'] = []
        cur['crpr_pin']   = 'none';
        cur["dly_in"]     = '0.000'
        cur["dly_out"]    = '0.000'
        cur["direction"]  = 'UNMAP'
        cur["hier"]       = 'intra'
        cur["x2x"]        = 'XX2XX'
        cur["arr_split"]  = 'NA'

        cur["brw_start"]  = '0.000'
        cur["brw_end"]    = '0.000'
        cur["brw_both"]   = '0.000'
        cur["diff_lat"]   = '0.000'
        cur["total_lat"]  = '0.000'
        cur["divg_ratio"] = '-99.0'
        cur["buck_id"]      = ""
        cur["buck_cmt"]     = ""
        cur["slack"]        = '-99.0'
        cur["norm_slack"]   = '-99.0'

        cur["slack_3T"]   = '0.000'
        cur["norm_slack_3T"]   = '0.000'
        cur['hier']         = 'intra'
        cur["net_arr"]      =  []
        cur["si_arr"]       =  []
        cur["si_nets"]      =  []
        cur["cell_arr"]     =  []
        cur["cell_pct"]     =  "0.0"
        cur["is_sync"]      =  '1'
        cur["comment"]      =  "NA"

        cur['line_start'] = line_cnt
        #print("#,",key,"#",line_cnt);

#  _   _                _            ____
# | | | | ___  __ _  __| | ___ _ __ |  _ \ __ _ _ __ ___  ___
# | |_| |/ _ \/ _` |/ _` |/ _ \ '__|| |_) / _` | '__/ __|/ _ \
# |  _  |  __/ (_| | (_| |  __/ |   |  __/ (_| | |  \__ \  __/
# |_| |_|\___|\__,_|\__,_|\___|_|___|_|   \__,_|_|  |___/\___|
#                              |_____|


        ''' Process Path Header'''
        line_cnt, line = get_data(line_cnt, cur, fp, line, 'start_cell', 1, 1)
        while 'Endpoint:' not in line : line_cnt +=1;line = fp.readline();

        #print(line_cnt,line);
        line_cnt, line = get_data(line_cnt, cur, fp, line, 'end_cell', 1, 1)
        if 'data to data' in line:    cur["is_sync"] = '0'
        cur['start_module'] = get_module(cur['start_cell'], project_tech)
        cur['end_module']   = get_module(cur['end_cell'], project_tech)
        cur['travel'].append(cur['start_module'])


        #print( cur['start_module'],cur['end_module'],cur['travel'])



        cur['crpr_pin'] = 'none';
        while 'Path Group:' not in line  and 'Last common pin:' not in line: line_cnt +=1;line = fp.readline()
        if 'Last common pin:' in line :
          line_cnt, line = get_data(line_cnt, cur, fp, line, 'crpr_pin', -1, 1)
        line_cnt, line = get_data(line_cnt, cur, fp, line, 'group', 2, 1)
        line_cnt, line = get_data(line_cnt, cur, fp, line, 'path', 2, 5)
        cur['vcheck'] = cur["path"]
        cur['check']  = cur["path"]

        #print("Header Parsed");print_cur(cur)

#  ____  _             _   ____       _       _       ____
# / ___|| |_ __ _ _ __| |_|  _ \ ___ (_)_ __ | |_    |  _ \ __ _ _ __ ___  ___
# \___ \| __/ _` | '__| __| |_) / _ \| | '_ \| __|   | |_) / _` | '__/ __|/ _ \
#  ___) | || (_| | |  | |_|  __/ (_) | | | | | |_    |  __/ (_| | |  \__ \  __/
# |____/ \__\__,_|_|   \__|_|   \___/|_|_| |_|\__|___|_|   \__,_|_|  |___/\___|
#                                               |_____|


        '''Process Path Arrival'''
        # Exception for in2out paths
        if " clock " not in line :
          cur['start_clk'] = 'none'
          cur['start_lat'] = '0.000'
        else:
          line_cnt, line = get_data(line_cnt, cur, fp, line, 'start_clk', 1, 1)
          if " * " in line or " H " in line : line =  re.sub(" \* | H ", " ",line)
          line_cnt, line = get_data(line_cnt, cur, fp, line, 'start_lat', -2, 1)
          try : cur['crossing_dly'].append(round(float(cur['start_lat']),3))
          except : a = 1 ;
          #print(cur['crossing_dly'],line,dict(cur),cur['start_lat'])

        # Exception for in2reg and in2out paths
        if "input external delay" in line:
          line_cnt, line = get_data(line_cnt, cur, fp, line, 'in_dly', -2, 1)
          line_cnt, line = get_data(line_cnt, cur, fp, line, 'start_pin', 0, 0)
          line_cnt, line = get_data(line_cnt, cur, fp, line, 'start_ref', 1, 1)
        else:
          line_cnt += 1;line = fp.readline();
          line_cnt, line = get_data(line_cnt, cur, fp, line, 'start_pin', 0, 0)
          line_cnt, line = get_data(line_cnt, cur, fp, line, 'start_ref', 1, 0)

        #print("Arrival Parsed");print_cur(cur)
#  ____       _       _           ____                         _
# |  _ \ ___ (_)_ __ | |_ ___    |  _ \ __ _ _ __ ___  ___  __| |
# | |_) / _ \| | '_ \| __/ __|   | |_) / _` | '__/ __|/ _ \/ _` |
# |  __/ (_) | | | | | |_\__ \   |  __/ (_| | |  \__ \  __/ (_| |
# |_|   \___/|_|_| |_|\__|___/___|_|   \__,_|_|  |___/\___|\__,_|
#                           |_____|


      '''Process Path Elements'''
      if '(net)' in prev_line :
        #print(prev_line,cur['net_arr'],round(float(line.split()[-4]),4),line_cnt)
        try : cur['net_arr'].append(round(float(line.split()[-4]),4))
        except : a = 1;
        #print(line_cnt,line)
        try:
          #print(line)
          if float(line.split()[-7]) != 0:
            if cur['path'] == 'max': cur['si_arr'].append(round(float(line.split()[-7]),4))
            else : cur['si_arr'].append(round(-1*float(line.split()[-7]),4))
            cur['si_nets'].append(  str(prev_line.split()[0] + "#" + str(round(float(line.split()[-7]),3)))  )
        except:
            a = 1;

      if '(net)' in line :
        try   : cur['cell_arr'].append(round(float(prev_line.split()[-4]),4))
        except: a = 1;#print("pre:  ",prev_line,"\npost: ",line);
      #print(line_cnt,line)

      #print("Points Parsed");
      #try : print_cur(cur); print(line)
      #except : print(line)
#   ____                   _                 ____                         _
#  / ___|_ __ ___  ___ ___(_)_ __   __ _    |  _ \ __ _ _ __ ___  ___  __| |
# | |   | '__/ _ \/ __/ __| | '_ \ / _` |   | |_) / _` | '__/ __|/ _ \/ _` |
# | |___| | | (_) \__ \__ \ | | | | (_| |   |  __/ (_| | |  \__ \  __/ (_| |
#  \____|_|  \___/|___/___/_|_| |_|\__, |___|_|   \__,_|_|  |___/\___|\__,_|
#                                  |___/_____|

      '''Process Path Arrival to Required Crossing'''
      if 'data arrival time' in line and 'data required time' not in prev_line:
        get_data(line_cnt, cur, fp, prev_line, 'end_pin', 0, 0)
        get_data(line_cnt, cur, fp, prev_line, 'end_ref', 1, 0)
        line_cnt, line = get_data(line_cnt, cur, fp, line, 'arrival', -1, 2)
        #print(line_cnt,"\n",cur,"\n",line)

        #print("Crossing Parsed");print_cur(cur)

#  _____           _             _       _       ____                         _
# | ____|_ __   __| |_ __   ___ (_)_ __ | |_    |  _ \ __ _ _ __ ___  ___  __| |
# |  _| | '_ \ / _` | '_ \ / _ \| | '_ \| __|   | |_) / _` | '__/ __|/ _ \/ _` |
# | |___| | | | (_| | |_) | (_) | | | | | |_    |  __/ (_| | |  \__ \  __/ (_| |
# |_____|_| |_|\__,_| .__/ \___/|_|_| |_|\__|___|_|   \__,_|_|  |___/\___|\__,_|
#                   |_|                    |_____|


        '''Process Path Required'''
        # Exception for in2out paths where out is not sequntial constrained
        if " clock " not in line :
          cur['end_clk'] = 'none'
          cur['end_lat'] = '0.000'
          cur['crpr']    = '0.000'
        else:
          line_cnt, line = get_data(line_cnt, cur, fp, line, 'end_clk', 1, 1)
          if " * " in line or " H " in line : line =  re.sub(" \* | H ", " ",line)
          line_cnt, line = get_data(line_cnt, cur, fp, line, 'end_lat', -2, 1)
          line_cnt, line = get_data(line_cnt, cur, fp, line, 'crpr', -2, 1)
        #print(line_cnt,line,cur)
        #print("Endpoint Parsed");print_cur(cur)

        # Exception for in2out paths
        if 'max_delay' in line:
          if " * " in line or " H " in line : line =  re.sub(" \* | H ", " ",line)
          line_cnt, line = get_data(line_cnt, cur, fp, line, 'lib_reqd', -2, 1)
          #print(line_cnt, cur['lib_reqd'])

          cur["is_sync"] = '0'
          if 'clock reconvergence pessimism' : prev_prev_line = prev_line ;prev_line = line; line_cnt, line = get_data(line_cnt, cur, fp, line, 'crpr', -2, 1)
        #print(line_cnt,line,cur["is_sync"])

        # Eception in case no uncertainty is added
        if 'uncertainty' in line:
           prev_prev_line = prev_line ;prev_line = line;line_cnt, line = get_data(line_cnt, cur, fp, line, 'margin', -2, 1)
        else:
          cur['margin'] = '0.000'
        #print(line,line_cnt,cur['margin'])
        # Eception in case no uncertainty is added
        if 'clock jitter' in line:
           old_margin = float(cur["margin"])
           prev_prev_line = prev_line ;prev_line = line;line_cnt, line = get_data(line_cnt, cur, fp, line, 'margin', -2, 1)
           cur['margin'] = str(round(float(cur['margin']) + old_margin,3))
        #print(line,line_cnt,cur['margin'])

        #print(line_cnt,line,cur['margin'],cur['end_cell'],cur['end_ref'])
        if 'setup time' in line or 'hold time' in line or 'recovery time' in line or 'removal time' in line:
          if " * " in line or " H " in line : line =  re.sub(" \* | H ", " ",line)
          line_cnt, line = get_data(line_cnt, cur, fp, line, 'lib_reqd', -2, 1);
          #print(line_cnt, cur['lib_reqd'])

        #print(line_cnt,line)

        # Exception for reg2out and in2out paths
        if 'output external delay' in line:
          line_cnt, line = get_data(line_cnt, cur, fp, line, 'out_dly', -2, 1)
          #print(line_cnt,line,cur)
        elif 'time burrowed from endpoint' in line:
          line_cnt, line = get_data(line_cnt, cur, fp, line, 'out_dly', -2, 1)
        # Skip Capture Path
        elif cur['end_cell'] not in line :
          while cur['end_cell'] not in line and 'data required time' not in line  :
            line_cnt +=1;line = fp.readline()
            if 'output external delay' in line:
              line_cnt, line = get_data(line_cnt, cur, fp, line, 'out_dly', -2, 1)
              cur['lib_reqd'] = "0.000"
              prev_prev_line = line;
              #print(line_cnt,line)
            #print(line_cnt,line)
          prev_line = line;
          line_cnt +=1;line = fp.readline()

          #print(line_cnt,line)
        #print(line_cnt,line,cur['margin'],cur['end_cell'],cur['end_ref'])
        #print(key,paths,line_cnt,line,prev_line)
        if '----------'  in line: prev_prev_line = prev_line ;prev_line = line;line_cnt +=1;line =fp.readline();#print(key,paths,line_cnt,line,prev_prev_line) ;

        if 'setup time' in line or 'hold time' in line or 'recovery time' in line or 'removal time' in line:
          if " * " in line or " H " in line : line =  re.sub(" \* | H ", " ",line)
          line_cnt, line = get_data(line_cnt, cur, fp, line, 'lib_reqd', -2, 1);
        #print(line_cnt,line)
          #print(line_cnt, cur['lib_reqd'])


      #print("Endpoint Parsed");print_cur(cur)
#  _____           _             ____                         _
# |  ___|__   ___ | |_ ___ _ __ |  _ \ __ _ _ __ ___  ___  __| |
# | |_ / _ \ / _ \| __/ _ \ '__|| |_) / _` | '__/ __|/ _ \/ _` |
# |  _| (_) | (_) | ||  __/ |   |  __/ (_| | |  \__ \  __/ (_| |
# |_|  \___/ \___/ \__\___|_|___|_|   \__,_|_|  |___/\___|\__,_|
#                          |_____|



      '''Process Path Footer'''
      if 'data required time' in line and 'data required time' not in prev_prev_line:
        if 'setup time' in prev_line or 'hold time' in prev_line or 'recovery time' in prev_line or 'removal time' in prev_line:
          #print(line_cnt)
          #line_cnt, line = get_data(line_cnt, cur, fp, prev_line, 'lib_reqd', -2, 0);
          if " * " in prev_line or " H " in prev_line : prev_line =  re.sub(" \* | H ", " ",prev_line)
          cur['lib_reqd'] = prev_line.split()[-2]
          #print(line_cnt, cur['lib_reqd'])

        #print(line_cnt,line)

      if 'data required time' in line and 'data required time' in prev_prev_line:
        line_cnt, line = get_data(line_cnt, cur, fp, line, 'required', -1, 3);
        #print(f,line_cnt,line,cur['required'])
        #print(key,paths,line_cnt,line)

        if 'statistical adjustment' in line:
          line_cnt, line = get_data(line_cnt, cur, fp, line, 'stat_adj', 2, 1)
          #print(f,line_cnt,line,cur['stat_adj'])

        if (cur["path"] == 'max' and args.check == 'max') and cur["is_sync"] == '1':
          line_cnt, line = get_data(line_cnt, cur, fp, line, 'slack', -1, 3)
          #print(f,line_cnt,line,cur['slack'],cur["path"],cur["is_sync"])

          if "normalization" in line:
            line_cnt, line = get_data(line_cnt, cur, fp, line, 'norm_delay', -1, 1)
            line_cnt, line = get_data(line_cnt, cur, fp, line, 'norm_slack', -1, 0)
          else:
            cur['norm_delay'] = '1.000'
            cur['norm_slack'] = cur['slack']
        else:
          line_cnt, line = get_data(line_cnt, cur, fp, line, 'slack', -1, 1)
          cur['norm_delay'] = '1.000'
          cur['norm_slack'] = cur['slack']
        #print(line_cnt,line)
        #print(key,line_cnt,line,cur['crossing_dly'])


      #print("Footer Parsed");print_cur(cur)

#  ____           _       ____
# |  _ \ ___  ___| |_    |  _ \ _ __ ___   ___ ___  ___ ___
# | |_) / _ \/ __| __|   | |_) | '__/ _ \ / __/ _ \/ __/ __|
# |  __/ (_) \__ \ |_    |  __/| | | (_) | (_|  __/\__ \__ \
# |_|   \___/|___/\__|___|_|   |_|  \___/ \___\___||___/___/
#                   |_____|


        cur['crossing_dly'].append(round(float(cur['arrival']) - sum(cur['crossing_dly']),3))

        cur['buck_pat'] = '|'.join(cur['crossing'])
        #print(line_cnt,line,cur['buck_pat'])

        if len(cur['travel']) == 1:
          cur['hier'] = 'intra'
          cur['buck_pat'] = cur['end_pin']
        elif len(cur['travel']) == 2:
          cur['hier'] = 'inter'
        elif len(cur['travel']) > 2:
          if cur['travel'][0] == cur['travel'][-1]:
            #cur['hier'] = 'loops%d' % len(cur['travel'])
            cur['hier'] = 'multi' ; #%d' % len(cur['travel']) - 2
          else:
            #cur['hier'] = 'fthru%d' % len(cur['travel'])
            cur['hier'] = 'multi' ;#%d' % len(cur['travel']) - 2
        cur['direction'] = '.'.join(cur['travel'])
        cur['thru_module'] = '.'.join(cur['travel'][1:-1])
        #travel_arr = list(map(str,cur['crossing_dly']))
        #travel_txt = ["CK"] + list(cur['travel']);
        if not bool(cur.get('lib_reqd')) : cur['lib_reqd'] = 99.9
        #cur['arr_split'] = ' '.join(map  (str,cur['crossing_dly']))
        cur['arr_split']  = ','.join([':'.join(x) for x in zip(["SCK"] + cur['travel'],map (str,cur['crossing_dly']) ) ])
        cur['arr_splitL'] = str(cur['arr_split'])
        cur['arr_splitC'] = "NA"
        cur['arr_splitW'] = "NA"
        try : 
          cur['arr_split']  += ",--," + "ECK:" + str(round(float(cur['end_lat']),3)) + ",CRP:" + str(round(float(cur['crpr']),3))
          cur['arr_splitC']  =  "ECK:" + str(round(float(cur['end_lat']),3)) + ",CRP:" + str(round(float(cur['crpr']),3))
        except: a = 1;
        try : 
          cur['arr_split']  += "," + "LIB:" + str(round(float(cur['lib_reqd']),3)) + ",--,UNC:" + str(round(float(cur['margin']),3)) + ",T:" +  str(round(float(cur['norm_delay']),3))
          cur['arr_splitC'] += "," + "LIB:" + str(round(float(cur['lib_reqd']),3)) 
          cur['arr_splitW']  = "UNC:" + str(round(float(cur['margin']),3)) + ",T:" +  str(round(float(cur['norm_delay']),3))
        except: a = 1;

        #print(travel_txt,travel_arr)
        cur['x2x'] = get_x2x(cur['start_ref'], cur['end_ref'], project_tech)
        #print(cur['start_ref'], cur['end_ref'],cur['x2x'])

        cur['buck_pat'] = re.sub("[0-9]+", '*', cur['buck_pat'])
        cur['buck_pat'] = re.sub(",", '*', cur['buck_pat'])
        cur['buck_pat'] = re.sub("\|", '->', cur['buck_pat'])
        cur['buck_pat'] = re.sub("\#", '->', cur['buck_pat'])
        cur['line_end'] = line_cnt
        if 'in2'  in cur['x2x'] :  cur['direction'] = str("IN." + cur['direction']) ; cur['hier'] = "extio"
        if '2out' in cur['x2x'] :  cur['direction'] = str(cur['direction'] + ".OUT") ; cur['hier'] = "extio"
        if int(args.debug) > 0 : print('@line ' + str(cur['line_end']) + "           paths@" + str(paths), end='\r', flush=True)
        try : cur['diff_lat'] = str(round(float(cur['end_lat']) -float(cur['start_lat']),3)) ;
        except :  a = 1
        try : cur['skew']     = str(round(float(cur['end_lat']) -float(cur['start_lat']) + float(cur['crpr']),3))
        except :  a = 1
        try : cur['skew_bin'] = str('SK_' + str("%0.2f" % float(cur['skew'])))
        except :  a = 1
        try :  cur['total_lat'] = str(round(float(cur['end_lat']) + float(cur['start_lat']),3))
        except :  a = 1
        if float(cur['total_lat']) > 0 :
          cur["divg_ratio"]  = str(round(100.00 *float(cur['diff_lat']) / float(cur['total_lat']),1))

        #print(line_cnt,line,cur);
        if not bool(cur.get('cell_arr')) or len(cur['cell_arr']) == 0 : cur['cell_arr'] = [0.000]
        if not bool(cur.get('net_arr')) or len(cur['net_arr'])  == 0 : cur['net_arr'] = [0.000]
        if not bool(cur.get('si_arr')) or len(cur['si_arr'])   == 0 : cur['si_arr'] = [0.000] ; cur['si_nets'] = ["none"]

        cur['si_dly']   = str(round(sum(cur['si_arr']),3))
        cur['cell_dly'] = str(round(sum(cur['cell_arr']),3))
        if cur['path'] == "max": cur['net_dly']  = str(round(sum(cur['net_arr']) - sum(cur['si_arr']) ,3))
        else:                    cur['net_dly']  = str(round(sum(cur['net_arr']) + sum(cur['si_arr']) ,3))
        try    :  cur["cell_pct"] =  str(round(100.00 *float(cur['cell_dly']) / (float(cur['cell_dly'])  + float(cur['net_dly']) + float(cur['si_dly'])) ,1))
        except :  a = 1 


        cur['si_cnt']   = str(len(cur['si_arr']))
        cur['cell_cnt'] = str(len(cur['cell_arr']))
        cur['net_cnt']  = str(len(cur['net_arr']))
        cur['si_max']   = str(max(cur['si_arr']))
        cur['cell_max'] = str(max(cur['cell_arr']))
        cur['net_max']  = str(max(cur['net_arr']))
        cur['si_min']   = str(min(cur['si_arr']))
        cur['cell_min'] = str(min(cur['cell_arr']))
        cur['net_min']  = str(min(cur['net_arr']))
        cur['si_worst'] = cur['si_nets'][cur['si_arr'].index(max(cur['si_arr']))]
        cur['si_top']   = cur['si_worst'].split("#")[0]
        cur['si_arr']   = ','.join(map  (str,cur['si_arr']))
        cur['cell_arr'] = ','.join(map  (str,cur['cell_arr']))
        cur['net_arr']  = ','.join(map  (str,cur['net_arr']))
        del cur['net_arr']
        del cur['si_arr']
        del cur['cell_arr']
        del cur['si_nets']
      #print("PostProcess Parsed");print_cur(cur)

        #print(line_cnt,line)
      if paths:
        #print(line_cnt,line)
        if '(' in line:
          cur_par = get_module(line.split()[0], project_tech)
          #print("XIFX0: ",key,line_cnt,cur['travel'],cur_par,cur['travel'][-1])
          if cur_par != cur['travel'][-1]:
          #if cur_par != cur['travel'][-1] and cur_par != 'TOP':

            cur['travel'].append(cur_par)
            #print(prev_prev_line,prev_line);
            #print(line_cnt,line,prev_prev_line,len(prev_prev_line.split()),prev_prev_line.split());
            if len(prev_prev_line.split()) == 0:
              #print("XIFX1: ",key,line_cnt,cur['travel'],cur_par)
              cur['crossing'].append('%s#%s' % (prev_line.split()[0],line.split()[0]))
              if cur['crossing_dly']:
                cur['crossing_dly'].append(round(float(prev_line.split()[-2]) - sum(cur['crossing_dly']),3))
              else:
                cur['crossing_dly'].append(round(float(prev_line.split()[-2]),3))
              #print("IF",line_cnt,cur['travel'],cur['crossing'],cur['crossing_dly'])

            else:
              #print("ELSE1: ",key,line_cnt,cur['travel'],cur_par)
              #print(line_cnt,"\nCUR:",line,"\nPRE:",prev_line,"\nPREPRE:",prev_prev_line);
              cur['crossing'].append('%s#%s' % (prev_prev_line.split()[0],line.split()[0]))
              if cur['crossing_dly']:
                try :  cur['crossing_dly'].append(round(float(prev_prev_line.split()[-2]) - sum(cur['crossing_dly']),3))
                except :
                  try:  cur['crossing_dly'].append(round(float(prev_line.split()[-2]) - sum(cur['crossing_dly']),3))
                  except: continue
              else:
                try: cur['crossing_dly'].append(round(float(prev_prev_line.split()[-2]),3))
                except: continue

              #print("EL",line_cnt,cur['travel'],cur['crossing'],cur['crossing_dly'])

      line_cnt += 1
      prev_prev_line = prev_line
      prev_line = line
      line = fp.readline()
  print('Processed %s paths' % paths)
  print('Done parsing "%s"' % f)
  print('Debug Mode:',args.debug);
  return data_dict


def main():
  parser = argparse.ArgumentParser(description='Parse primetime data - CPU custom')
  parser.add_argument('rpt_files', nargs='+',
                      help='report files from primetime')
  parser.add_argument('--design', default="whitechapel")
  parser.add_argument('--check', default="max")
  parser.add_argument('--mode', default="func")
  parser.add_argument('--corner', default="all_corner")
  parser.add_argument('--out', default='vios_out.json')
  parser.add_argument('--tech', required=True)
  parser.add_argument('--debug', default=0)
  parser.add_argument('--cellpin', default='')
  parser.add_argument('--threads', default=8)
  parser.add_argument('--autoslack', default='')
  parser.add_argument('--automap',   default='')

  args = parser.parse_args()

  # Get expanded primetime report files
  rpt_files = glob_files(args.rpt_files)

  data_dict = {}
  tag = 0
  input1 = list()
  results = list()
  temp_config  = load_json(args.tech)
  try    : project_tech  = temp_config["settings"]["default"]["tech"] ; print(" -- Config read through design config")
  except :
    try    :project_tech  = temp_config["tech"]                         ; print(" -- Config read through bob setup")
    except :project_tech  = temp_config                                 ; print(" -- Config read through project setup")

  # Assign Vio ID tracker
  #vio_db       = project_tech["scripts"]["vio_db"] + "/" + args.design + "_vio_db.json"
  #if args.vio_db != "" :  vio_db = args.vio_db
  for f in rpt_files:
    input1.append((os.path.abspath(f), tag, args, data_dict, project_tech))
    tag += 1
  with multiprocessing.Pool(int(args.threads)) as p:
    if args.check == "max" or args.check == "min":
      print("Doing Path Process")
      results = p.map(parse_rpt_file, input1)
    else :
      results = p.map(parse_rca_file, input1)
  for x in results:
    data_dict.update(x)


  # For Borrow Annotation
  cellpin_array = dict()
  for each in glob_files(args.rpt_files):
    cellpin_file = re.sub("path.max_path.detail.rpt","attr.cellpin.json",each)
    cellpin_file = re.sub("path.min_path.detail.rpt","attr.cellpin.json",cellpin_file)
    if os.path.exists(cellpin_file) : cellpin_array[each] = cellpin_file


  if args.cellpin != '' or ( args.autoslack != '' and len(cellpin_array) > 0 ):
    user_cellpin_data = dict();
    # Dict Given By User
    if args.cellpin != '':
      print("Doing Slack Annotation Process using user define nodeslack")
      user_cellpin_data = load_json(args.cellpin)

    # Dict Inferred By Path
    cellpin_data_multi = dict()
    use_autoslack = 0
    if args.autoslack != '' and len(cellpin_array) > 0:
      print("Doing Slack Annotation Process using automatic nodeslack")
      for each in cellpin_array:
        cellpin_data_multi[each] = load_json(cellpin_array[each])
        print(" -- Mapping ",os.path.basename(each),cellpin_array[each])
      use_autoslack = 1;

    ##
    print("Done path parsing, annotaitng 3T slack")

    cellpin_data = user_cellpin_data

    for idx in data_dict:
      if int(args.debug) > 0 : print('@id ' + str(idx), end='\r', flush=True)
      start_cell =   data_dict[idx]["start_cell"]
      end_cell   =   data_dict[idx]["end_cell"]
      xrpt_file  =   data_dict[idx]["report_file"]

      #if use_autoslack == 1:
      #  try   :  cellpin_data = cellpin_array[xrpt_file]
      #  except:  cellpin_data = user_cellpin_data
      #else                 : cellpin_data = user_cellpin_data
      if data_dict[idx]["path"] == "max" :
        try    : brw_start = str(cellpin_data[start_cell]["data"]["worse"]["max"])
        except : brw_start = "99.9"
        try    : brw_end   = str(cellpin_data[end_cell]["clock"]["worse"]["max"])
        except : brw_end   = "99.9"
      else:
        try    : brw_start = str(cellpin_data[start_cell]["data"]["worse"]["min"])
        except : brw_start = "99.9"
        try    : brw_end   = str(cellpin_data[end_cell]["clock"]["worse"]["min"])
        except : brw_end   = "99.9"
      try:     data_dict[idx]["brw_start"] = brw_start
      except : data_dict[idx]["brw_start"] = "99.9"
      try: data_dict[idx]["brw_end"]   = brw_end
      except : data_dict[idx]["brw_end"] = "99.9"
      if    data_dict[idx]["brw_end"] == "99.9"  and "ICG" in data_dict[idx]["x2x"] :  data_dict[idx]["brw_end"] = "0.000"
      try: data_dict[idx]["brw_both"]  = str(round(float(brw_end) + float(brw_start) ,3))
      except : data_dict[idx]["brw_both"] = "-99.9"
      try: data_dict[idx]["slack_3T"]  = str(round(float(data_dict[idx]["brw_both"]) + float(data_dict[idx]["slack"]),3))
      except : data_dict[idx]["slack_3T"] = "99.9"
      try: data_dict[idx]["norm_slack_3T"]  = str(round( float(data_dict[idx]["slack_3T"]) / float(data_dict[idx]["norm_delay"]) ,3))
      except : data_dict[idx]["norm_slack_3T"] = "99.9"
      vio_slack     = float(data_dict[idx]["slack"])
      push_margin   = float(data_dict[idx]["brw_end"])   + vio_slack
      pull_margin   = float(data_dict[idx]["brw_start"]) + vio_slack 
      skew_margin   = float(data_dict[idx]["slack_3T"])
      auto_comment = ""
      
      push = "PushEnd"
      pull = "PullStart"
      if data_dict[idx]["vcheck"] == "min" : pull = "PushStart" ; push = "PullEnd"
      if    push_margin  >=  0.00 : auto_comment += push + "2Fix"
      elif  pull_margin  >=  0.00 : auto_comment += pull + "2Fix"
      elif  skew_margin  >=  0.00 : auto_comment += "PullPush2Fix"
      else                        : auto_comment += "Critical"
      data_dict[idx]["buck_cmt"] = auto_comment
  with open(args.out, 'w') as fp:
    fp.write(json.dumps(data_dict, indent=4))


if __name__ == '__main__':
  main()


get_vios.py
Displaying get_vios.py.
