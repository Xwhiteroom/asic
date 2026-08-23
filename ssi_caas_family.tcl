# Copyright (c) 2026 Syed Shakir Iqbal (Xwhiteroom)
# SPDX-License-Identifier: MIT
#    ____                           _      _    _ _
#   / ___| ___ _ __   ___ _ __ __ _| |    / \  | (_) __ _ ___
#  | |  _ / _ \ '_ \ / _ \ '__/ _` | |   / _ \ | | |/ _` / __|
#  | |_| |  __/ | | |  __/ | | (_| | |  / ___ \| | | (_| \__ \
#   \____|\___|_| |_|\___|_|  \__,_|_| /_/   \_\_|_|\__,_|___/
#
#
# Global
global CAAS_TOOL CAAS_TOOL_PLATFORM CAAS_SCRIPT CORNER
# Alias : Report Hacks
alias xrt	                             ssi_sta_caas_xreport_timing
alias xrte	                             ssi_sta_caas_xreport_timing -delay min
set CAAS_SCRIPT                              [file normalize [info script]]

#    ____                           _   ____
#   / ___| ___ _ __   ___ _ __ __ _| | |  _ \ _ __ ___   ___ ___
#  | |  _ / _ \ '_ \ / _ \ '__/ _` | | | |_) | '__/ _ \ / __/ __|
#  | |_| |  __/ | | |  __/ | | (_| | | |  __/| | | (_) | (__\__ \
#   \____|\___|_| |_|\___|_|  \__,_|_| |_|   |_|  \___/ \___|___/
#
#

proc ssi_sta_caas_get_tool_version {} {
# Proc : Report Tool Type : ssi_sta_caas_get_tool_version
    global synopsys_root
    global CAAS_TOOL CAAS_TOOL_PLATFORM CAAS_DEFINE_PROC_ARGS
    global CORNER MODE
    set CAAS_TOOL nan
    set CAAS_TOOL_PLATFORM snps
    if { [info exist synopsys_root] } {
        if       {  [regexp "primetime|pt_shell|prime"                          $synopsys_root] } { set CAAS_TOOL ptx
        } elseif {  [regexp "fusion_compiler"                                   $synopsys_root] } { set CAAS_TOOL fcx
        } elseif { ![regexp "fusion_compiler|pt_shell|primetime|pt_shell|prime" $synopsys_root] } { set CAAS_TOOL nan
        }
        set CAAS_TOOL_PLATFORM snps
    } else {
        set CAAS_TOOL_PLATFORM cdns
        set CAAS_TOOL inv ; # PlaceHolder
    }

    if { ![info exist CORNER] } { set CORNER "CORNER_ALL" }
    if { ![info exist MODE]   } { set MODE     "MODE_ALL" }
    return $CAAS_TOOL
}


# Call Back to Tool Version Fetch
ssi_sta_caas_get_tool_version
puts [format "<STA::CAAS::PROC> TOOL  %-50s"   "$CAAS_TOOL_PLATFORM / $CAAS_TOOL"]
if { $CAAS_TOOL_PLATFORM == "snps" } {
    alias CAAS_DEFINE_PROC_ARGS         define_proc_attributes
} else {
    alias CAAS_DEFINE_PROC_ARGS         define_proc_arguments
}

#   _____ _           _                  _             _ _ _
#  |_   _(_)_ __ ___ (_)_ __   __ _     / \  _   _  __| (_) |_
#    | | | | '_ ` _ \| | '_ \ / _` |   / _ \| | | |/ _` | | __|
#    | | | | | | | | | | | | | (_| |  / ___ \ |_| | (_| | | |_
#    |_| |_|_| |_| |_|_|_| |_|\__, | /_/   \_\__,_|\__,_|_|\__|
#                             |___/
#


proc ssi_sta_caas_get_tool_attr {attribute tool} {
# Proc : Report Tool Type : ssi_sta_caas_get_tool_attr
    array unset tool_map

    set   snps  net_resistance_max;                   set  cdns  resistance_max;                       set  tool_map($cdns.cdns)  $snps;  set  tool_map($snps.snps)  $cdns;
    set   snps  ba_resistance_max;                    set  cdns  resistance_max;                       set  tool_map($cdns.cdns)  $snps;  set  tool_map($snps.snps)  $cdns;
    set   snps  applied_derate;                       set  cdns  total_derate;                         set  tool_map($cdns.cdns)  $snps;  set  tool_map($snps.snps)  $cdns;
    set   snps  scenario_name;                        set  cdns  view_name;                            set  tool_map($cdns.cdns)  $snps;  set  tool_map($snps.snps)  $cdns;
    set   snps  startpoint;                           set  cdns  launching_point;                      set  tool_map($cdns.cdns)  $snps;  set  tool_map($snps.snps)  $cdns;
    set   snps  endpoint;                             set  cdns  capturing_point;                      set  tool_map($cdns.cdns)  $snps;  set  tool_map($snps.snps)  $cdns;
    set   snps  startpoint_clock;                     set  cdns  launching_clock;                      set  tool_map($cdns.cdns)  $snps;  set  tool_map($snps.snps)  $cdns;
    set   snps  endpoint_clock;                       set  cdns  capturing_clock;                      set  tool_map($cdns.cdns)  $snps;  set  tool_map($snps.snps)  $cdns;
    set   snps  master_pin;                           set  cdns  master_source;                        set  tool_map($cdns.cdns)  $snps;  set  tool_map($snps.snps)  $cdns;
    set   snps  crpr_common_point;                    set  cdns  cppr_branch_point;                    set  tool_map($cdns.cdns)  $snps;  set  tool_map($snps.snps)  $cdns;
    set   snps  launch_clock_paths;                   set  cdns  launch_clock_path;                    set  tool_map($cdns.cdns)  $snps;  set  tool_map($snps.snps)  $cdns;
    set   snps  capture_clock_paths;                  set  cdns  capture_clock_path;                   set  tool_map($cdns.cdns)  $snps;  set  tool_map($snps.snps)  $cdns;
    set   snps  points;                               set  cdns  timing_points;                        set  tool_map($cdns.cdns)  $snps;  set  tool_map($snps.snps)  $cdns;
    set   snps  points.object;                        set  cdns  timing_points.object;                 set  tool_map($cdns.cdns)  $snps;  set  tool_map($snps.snps)  $cdns;
    set   snps  path_type;                            set  cdns  path_type;                            set  tool_map($cdns.cdns)  $snps;  set  tool_map($snps.snps)  $cdns;
    set   snps  slack;                                set  cdns  slack;                                set  tool_map($cdns.cdns)  $snps;  set  tool_map($snps.snps)  $cdns;
    set   snps  normalized_delay;                     set  cdns  phase_shift;                          set  tool_map($cdns.cdns)  $snps;  set  tool_map($snps.snps)  $cdns;
    #set   snps  normalized_slack;                     set  cdns  slack;                                set  tool_map($cdns.cdns)  $snps;  set  tool_map($snps.snps)  $cdns;
    set   snps  period;                               set  cdns  period;                               set  tool_map($cdns.cdns)  $snps;  set  tool_map($snps.snps)  $cdns;
    set   snps  max_slack;                            set  cdns  max_slack;                            set  tool_map($cdns.cdns)  $snps;  set  tool_map($snps.snps)  $cdns;
    set   snps  min_slack;                            set  cdns  min_slack;                            set  tool_map($cdns.cdns)  $snps;  set  tool_map($snps.snps)  $cdns;
    set   snps  common_path_pessimism;                set  cdns  cppr_adjustment;                      set  tool_map($cdns.cdns)  $snps;  set  tool_map($snps.snps)  $cdns;
    set   snps  startpoint_clock_latency;             set  cdns  launching_clock_latency;              set  tool_map($cdns.cdns)  $snps;  set  tool_map($snps.snps)  $cdns;
    set   snps  endpoint_clock_latency;               set  cdns  capturing_clock_latency;              set  tool_map($cdns.cdns)  $snps;  set  tool_map($snps.snps)  $cdns;
    set   snps  launching_clock_source_arrival_time;  set  cdns  capturing_clock_source_arrival_time;  set  tool_map($cdns.cdns)  $snps;  set  tool_map($snps.snps)  $cdns;
    set   snps  startpoint_clock_open_edge_type;      set  cdns  launching_clock_open_edge_type;       set  tool_map($cdns.cdns)  $snps;  set  tool_map($snps.snps)  $cdns;
    set   snps  endpoint_clock_open_edge_type;        set  cdns  capturing_clock_open_edge_type;       set  tool_map($cdns.cdns)  $snps;  set  tool_map($snps.snps)  $cdns;
    set   snps  arrival_window;                       set  cdns  arrival_window;                       set  tool_map($cdns.cdns)  $snps;  set  tool_map($snps.snps)  $cdns;
    set   snps  arrival;                              set  cdns  arrival;                              set  tool_map($cdns.cdns)  $snps;  set  tool_map($snps.snps)  $cdns;
    set   snps  required;                             set  cdns  required_time;                        set  tool_map($cdns.cdns)  $snps;  set  tool_map($snps.snps)  $cdns;
    set   snps  endpoint_hold_time_value;             set  cdns  hold;                                 set  tool_map($cdns.cdns)  $snps;  set  tool_map($snps.snps)  $cdns;
    set   snps  endpoint_setup_time_value;            set  cdns  setup;                                set  tool_map($cdns.cdns)  $snps;  set  tool_map($snps.snps)  $cdns;
    set   snps  endpoint_removal_time_value;          set  cdns  removal;                              set  tool_map($cdns.cdns)  $snps;  set  tool_map($snps.snps)  $cdns;
    set   snps  endpoint_recovery_time_value;         set  cdns  recovery;                             set  tool_map($cdns.cdns)  $snps;  set  tool_map($snps.snps)  $cdns;
    set   snps  clock_uncertainty;                    set  cdns  clock_uncertainty;                    set  tool_map($cdns.cdns)  $snps;  set  tool_map($snps.snps)  $cdns;
    set   snps  exception_delay;                      set  cdns  check_delay;                          set  tool_map($cdns.cdns)  $snps;  set  tool_map($snps.snps)  $cdns;
    set   snps  startpoint_clock_open_edge_value;     set  cdns  launching_clock_open_edge_time;       set  tool_map($cdns.cdns)  $snps;  set  tool_map($snps.snps)  $cdns;
    set   snps  endpoint_clock_open_edge_value;       set  cdns  capturing_clock_open_edge_time;       set  tool_map($cdns.cdns)  $snps;  set  tool_map($snps.snps)  $cdns;
    set   snps  sources;                              set  cdns  sources;                              set  tool_map($cdns.cdns)  $snps;  set  tool_map($snps.snps)  $cdns;
    #set  snps  ;                                     set  cdns  ;                                     set  tool_map($cdns.cdns)  $snps;  set  tool_map($snps.snps)  $cdns;

    # FC to PT Override Make PT Appear Like CDNS Tool And MAp Attribute Accordingly
    set sub_tool [ssi_sta_caas_get_tool_version]

    if { $sub_tool == "fcx" } {
        set  ptx_attr  annotated_delay_delta;        set  fcx_attr delta_delay;                        set  tool_map($ptx_attr.cdns)    $fcx_attr
        set  ptx_attr  ba_resistance_max;            set  fcx_attr ba_resistance_max;                  set  tool_map($ptx_attr.cdns)    $fcx_attr
        #set  ptx_attr  applied_derate;               set  fcx_attr variation_arrival;                  set  tool_map($ptx_attr.cdns)    $fcx_attr
    }

    if { [info exist tool_map($attribute.$tool)] } {
        set attributex $tool_map($attribute.$tool)
    } else {
        set attributex $attribute
    }
    #puts "Testing Line 114@ssi_sta_caas_get_tool_attr: attr=$attribute->$attributex / tool:$tool / sub_tool:$sub_tool"
    return $attributex
}

proc ssi_sta_caas_get_path_attr { path tool attribute } {
    global CAAS_TOOL CAAS_TOOL_PLATFORM CAAS_DEFINE_PROC_ARGS
    set attr_cdns [ssi_sta_caas_get_tool_attr $attribute snps]
    set attr_snps [ssi_sta_caas_get_tool_attr $attribute cdns]

    if { $CAAS_TOOL_PLATFORM == "snps" } {
        set eval_false [ catch { set object [get_attribute -quiet $path $attr_snps] } ]
    } else {
        set eval_false [ catch { set object [get_property  -quiet $path $attr_cdns] } ]
    }

    if { $eval_false } {
        return "Error Incorrect Path Attr Mapping for attribute=$attribute tool=$tool , cdns=$attr_cdns | snps=$attr_snps"
    } else {
        return $object
    }

    #set eval_snps_false [ catch { set object [get_attr -quiet $path $attr_snps] }]
    # Snps Fails
    #puts "Testing Line 128@ssi_sta_caas_get_path_attr: $attr_cdns (CDNS) --> $attr_snps (SNPS) --> $tool --> $attribute" ; puts "eval_snps_false=$eval_snps_false/object=$object"
    if { $eval_snps_false } {
        set eval_cdns_false [ catch { set object [get_property -quiet $path $attr_cdns] }]
        # Cdns Fails
        if { $eval_cdns_false } {
            return "Error Incorrect Path Attr Mapping for attribute=$attribute tool=$tool , cdns=$attr_cdns | snps=$attr_snps"
        } else {
           #puts "Returning CDNS Object : $attr_cdns"
           return $object
        }
    } else {
        #puts "Returning SNPS Object : $attr_snps"
        return $object
    }
}

##------------------------------------------------------------------
## ProcNameStart  : ssi_sta_caas_get_timing_paths
## ProcArguments  : ssi_sta_caas_get_timing_paths args
## ProcDependency : ssi_sta_caas_get_timing_paths
## ProcInfluence  : 2
## ProcRenamed    : 0
##------------------------------------------------------------------
proc  ssi_sta_caas_get_timing_paths args {
    set rpt_string      "$args"
    regsub -all {\{|\}} $rpt_string "" rpt_string
    set rpt_string1      "set path_collection \[get_timing_paths -path_type full_clock_expanded $rpt_string\]"
    set rpt_string2      "set path_collection \[report_timing    -path_type full_clock_expanded -collection $rpt_string\]"
    puts "**INFO: <CMD> ssi_sta_caas_get_timing_paths $rpt_string"
    # Synopsys
    set snps_eval_fail [catch { set path_collection [eval $rpt_string1] }]
    if { $snps_eval_fail } {
        set cdns_eval_fail [catch { set path_collection [eval $rpt_string2] }]
        if { $cdns_eval_fail } {
            return "Error Incorrect ReportTiming Command !"
        } else {
            return $path_collection
        }
    } else {
        return $path_collection

    }
}

proc ssi_sta_caas_timing_points_split {points start_after_pin end_after_pin tool debug} {
            set old_data [list 0,0,0]
            set arr_rc   0
            set arr_cell 0
            set arr_buf   0
            set arr_logic 0

            set stg_level 0
            set buf_level 0
            set logic_level 0
            set totalXY 0
	    set arr     0
            set totalsi 0
            set pathtrace ""
            set nodetrace [list "#Index,#Direction,#Delay,#Transition,#Xtlk,#Capacitance(Pin),#Capacitance(Net),#Resistance(Net),#Length(Net),#Cell,#Derate,#Node"]
            set start_offset [lindex [ssi_sta_caas_get_path_attr  $points $tool arrival] 0]
	    #set debug 1
	    set data_cache  "SP:$start_after_pin -> EP:$end_after_pin"
	    set data_real   ""
	    set pin_old     ""
	    set net_index   0
	    set arr_rel     0 ; # CDNS
            set dist_scale  1.000
            if { $tool == "cdns" }  { set dist_scale 1.000 } ; #CDNS
    	    #set cell_is_buf  [lsort -uniq [get_attr [get_lib_cells */* -filter "number_of_pins==2 && is_combinational==true" ] base_name]]

            set allow_first_repeater 1
            foreach_in_collection point $points {
	        set pin_obj    [ssi_sta_caas_get_path_attr $point $tool object ]
	        set pin        [get_object_name  $pin_obj ]
	        set pin_class  [ssi_sta_caas_get_path_attr $pin_obj $tool object_class ]
                set pdirection [ssi_sta_caas_get_path_attr $pin_obj $tool direction]
		set is_hier    [ssi_sta_caas_get_path_attr $pin_obj $tool is_hierarchical]
                set pin_cell   [get_cells -quiet -of_object $pin_obj]
                set ref_cell   [ssi_sta_caas_get_path_attr $pin_cell $tool ref_name]
                set is_buf_inv [sizeof_collection [get_lib_cells -quiet */$ref_cell -filter "number_of_pins==2 && is_combinational==true"]]

		if { $is_hier == "" || $is_hier == "true" } { continue;}
		# Incr Stage Data
	        set arr       [format "%.3f" [ssi_sta_caas_get_path_attr $point $tool arrival] ]
		set x_cor     "0"
		set y_cor     "0"
                catch { set x_cor     [format "%.1f" [expr [ssi_sta_caas_get_path_attr $pin_obj $tool x_coordinate]/$dist_scale] ]}
	        catch { set y_cor     [format "%.1f" [expr [ssi_sta_caas_get_path_attr $pin_obj $tool y_coordinate]/$dist_scale] ]}
	        set arr_si            [format "%.3f" [expr 0.000 + [ssi_sta_caas_get_path_attr $point $tool annotated_delay_delta] + 0.000 ]]
	        set totalsi           [format "%.3f" [expr $totalsi + $arr_si]]
	        #set slack             [format "%.3f" [expr 0.000 + [ssi_sta_caas_get_path_attr $point $tool slack] + 0.000 ]]
	        #set incremental       [format "%.3f" [expr 0.000 + [ssi_sta_caas_get_path_attr $point $tool incremental] + 0.000 ]]
	        set transition        [format "%.3f" [expr 0.000 + [ssi_sta_caas_get_path_attr $point $tool transition] + 0.000 ]]
	        set derate            [format "%.3f" [expr 0.000 + [ssi_sta_caas_get_path_attr $point $tool applied_derate] + 0.000 ]]

		# Trace Path
		if { $pdirection == "in" && $net_index > 0 } {
		  if { $is_buf_inv > 0  } {
                    #set pathtrace "$pathtrace -through_buf $pin"
                    incr buf_level
                    if { $allow_first_repeater } {
                         set pathtrace "$pathtrace -through $pin"
                         set allow_first_repeater 0
                     }
                    #puts "     -through $pin"
                  } else {
                    set pathtrace "$pathtrace -through $pin"
                    incr logic_level
                 }
		}
		#puts "$arr_si $pin"
                # Start
		if { $pin != $start_after_pin && $start_after_pin != "" } {
                        #set arr_rel $arr
                        #puts "New Arr_rel=$arr_rel | $pin"
	        	set old_data  [list $arr,$x_cor,$y_cor]
			continue
		} else {
			set data_real "SP:$start_after_pin ($arr)"
		        set start_after_pin ""
		}
		# Gen Clk Source Skip check
		if { $pin != $pin_old} {
	        	incr stg_level
			set pin_old $pin
		}

	        set arr_old   [lindex [split $old_data ","] 0]
	        set x_cor_old [lindex [split $old_data ","] 1]
	        set y_cor_old [lindex [split $old_data ","] 2]

	        set delta_x   0
	        set delta_y   0
	        set delta_arr 0
	        set distance  0
	        catch  { set delta_x   [format "%.1f" [expr   abs($x_cor - $x_cor_old)]] }
	        catch  { set delta_y   [format "%.1f" [expr   abs($y_cor - $y_cor_old)]] }
	        catch  { set delta_arr [expr   $arr   - $arr_old]        }
	        catch  { set distance  [format "%.1f" [expr   $delta_x + $delta_y]]     }
	        set totalXY [format "%.1f"     [expr $totalXY + $distance]]
	        if  { $pdirection == "in"} {
                    if { [regexp "cdns" $tool] } {
                        # Innovus Arr Offset Negative Fix"
		        if { $net_index == 0 } {
			    set arr_rc [format "%.3f" [expr  $arr_rc - $arr_si ] ] ;
                            set delta_arr 0.000
                            set arr_rel   $arr
                            #puts "arr_rel=$arr_rel | net_index=$net_index | pin=$pin"
		        } else {
                            set arr_rc   [format "%.3f" [expr  $arr_rc + $delta_arr - $arr_si ] ]
		        }
                    } else {
                        set arr_rc   [format "%.3f" [expr  $arr_rc + $delta_arr - $arr_si ] ]
                        #puts "     -- Debug arr_rc=$arr_rc + delta_arr=$delta_arr - arr_si=$arr_si start=$start_offset derate=$derate $x_cor,$y_cor| pin=$pin"

                    }
                } else {
                    set arr_cell [format "%.3f" [expr $arr_cell +  $delta_arr] ]
                    if { $is_buf_inv > 0 } {
                        set arr_buf   [format "%.3f" [expr $arr_buf +  $delta_arr] ]
                    } else {
                        set arr_logic [format "%.3f" [expr $arr_logic +  $delta_arr] ]

                    }
                }
	        set old_data  [list $arr,$x_cor,$y_cor]
                # End
		if { $pin == $end_after_pin && $end_after_pin != "" } {
		  set data_real "$data_real -> EP:$end_after_pin ($arr)" ; break ;
		}
		if { $debug} {
                	puts "     -- Debug $stg_level (XY=$totalXY) $arr $pin"
		}
		# Trace Node
		set net_data "$net_index"
                set net_length $distance
                incr net_index
		set net_obj   [get_nets -quiet [all_connected $pin]]
                set total_cap [ssi_sta_caas_get_path_attr $net_obj $tool total_capacitance_max]
                set net_cap   [ssi_sta_caas_get_path_attr $net_obj $tool wire_capacitance_max]
                set pin_cap   [expr 0.000 + $total_cap -$net_cap +0.000]
                set net_res   [ssi_sta_caas_get_path_attr $net_obj $tool net_resistance_max]
                if { $net_res == "" } {
                    set net_res   "NA"
                }

                #"#Index,#Direction,#Delay,#Transition,#Xtlk,#Capacitance(Pin),#Capacitance(Net),#Resistance(Net),#Length(Net),#Cell,#Derate,#Node"
		lappend nodetrace "$net_index,$pdirection,$delta_arr,$transition,$arr_si,$pin_cap,$net_cap,$net_res,$net_length,$ref_cell,$derate,$pin"
            }
	    set totalarr [expr $arr - $arr_rel]
	    if { $debug} {
	    	puts "  - Realx: $data_real  | $stg_level | $arr | $pin"
	    	puts "  - Cache: $data_cache | $stg_level | $arr | $pin\n\n"
                puts "  - Notes: RC=$arr_rc  | Cell=$arr_cell | Stage=$stg_level |Travel=$totalXY | Arr=$totalarr | Si=$totalsi"
                puts "  ----------------------------------------------------------\n"
                foreach x  $nodetrace { puts "$x"}
	    }
            #puts "pathtrace=$pathtrace"
	    set out [list $arr_rc $arr_cell $stg_level $totalXY $totalarr $totalsi $pathtrace $nodetrace $buf_level $logic_level $arr_buf $arr_logic $start_offset]
	    return $out
}

proc ssi_sta_caas_get_path_node_trace_list {nodetrace index_start filex idx slack} {
        # Node Data Details / Tool Agnostic
	#set nodetrace     [lindex $nodetrace_data 7]
        set j             $index_start
        set csv_list      [list "#File,#PathID,#GrossIndex,#Slack,[lindex $nodetrace 0]" ]
	foreach x [lrange $nodetrace 1 end] {
    		incr j
		set csv_data      "$filex,$idx,$j,$slack,$x"
		set nodeid       [lindex [split $x ","] end]
		lappend   csv_list $csv_data
	}
	return [list $csv_list $j]
}

proc ssi_sta_caas_path_id_map_loop {path idx pt_filex index_j tool} {
      global CORNER MODE CAAS_TOOL_PLATFORM
       # Import Global to Local Map
       set j    $index_j
       # Xreport Data Parsing
       #puts "\n\nData::: [get_attr $path slack]  | [get_attr $path endpoint.full_name] Pre  xreport_timing_var\n\n"
       #ssi_sta_caas_xreport_timing $path; #Debug
       redirect -variable xreport_timing_var {ssi_sta_caas_xreport_timing $path }  ; #ssi_sta_caas_xreport_timing
       #puts "\n\nData::: [get_attr $path slack]  | [get_attr $path endpoint.full_name] Post xreport_timing_var\n\n"
       redirect -file $pt_filex {puts $xreport_timing_var }
       # Summary Data
       set paths_data "$pt_filex,$idx,[lindex [split $xreport_timing_var "\n"] end-2 ]"
       set paths_head "#File,#PathID,[lindex [split $xreport_timing_var  "\n"] end-3 ]"
       # Node Data
       if { $CAAS_TOOL_PLATFORM == "snps" } {
            set slack          [get_attribute -quiet $path slack]
            set points         [ssi_sta_caas_get_path_attr $path  $tool points]
       } else {
            set slack          [get_property -quiet $path slack]
            set points         [get_property -quiet $path timing_points]
       }
       #puts "$idx,$slack"
       set return_point_data   [ssi_sta_caas_timing_points_split  $points "" "" $tool 0]
       set nodetrace           [lindex $return_point_data 7]
       #puts "$nodetrace"
       set nodecsv             [ssi_sta_caas_get_path_node_trace_list $nodetrace $j $pt_filex $idx $slack]
       set pt_node_data        [list]
       set csv_head            [lindex [lindex $nodecsv 0] 0]
       if { $j == 0 }          {lappend pt_node_data "$csv_head" ;}
       set j                   [lindex $nodecsv 1]
       foreach x [lrange [lindex $nodecsv 0] 1 end] {
         lappend pt_node_data  "$x"
         #puts "$x"
       }
       return [list $j $paths_head $paths_data $pt_node_data]
}

##------------------------------------------------------------------
## ProcNameStart  : ssi_sta_caas_xreport_timing
## ProcArguments  : ssi_sta_caas_xreport_timing args
## ProcDependency : ssi_sta_caas_timing_points_split
## ProcInfluence  : 2
## ProcRenamed    : 0
##------------------------------------------------------------------
proc ssi_sta_caas_xreport_timing args {
    global CORNER MODE CAAS_TOOL_PLATFORM
    set tool "snps"
    if { [info exist CAAS_TOOL_PLATFORM] } { set tool $CAAS_TOOL_PLATFORM }
    set is_path_collection "None"
    if { $CAAS_TOOL_PLATFORM == "snps" } {
        catch { set is_path_collection  [lindex [get_attribute -quiet $args path_type] 0] }
    } else {
        catch { set is_path_collection  [lindex [get_property -quiet $args path_type] 0] }
    }
    if { $is_path_collection == "min" ||  $is_path_collection == "max" } {
    	set path_collection $args
        puts "**WARN: ssi_sta_caas_xreport_timing Arguments are Path Collection ! Tool_Platform=$tool | $args"
    } else {
	#set rpt_string      "$args"
	#regsub -all {\{|\}} $rpt_string "" rpt_string
        set path_collection  [ssi_sta_caas_get_timing_paths $args]
    }
    echo "**INFO: Created Base Path Collection as : [sizeof_collection $path_collection]  <CMD>  get_timing_paths/report_timing $args | [sizeof_collection $path_collection] "
    set view_flow "default"
    catch { set view_flow "$CORNER.$MODE"}
    foreach_in_collection path $path_collection {
            set view ""
            catch { set view     [ssi_sta_caas_get_path_attr $path $tool scenario_name]  }
            if { $view == "" } {  set view     $view_flow    }
            if { $view == "" } {  set view     "default"     }
            set start         [get_object_name [ssi_sta_caas_get_path_attr $path $tool startpoint]]
            set end           [get_object_name [ssi_sta_caas_get_path_attr $path $tool endpoint]]
            set start_clk     [get_object_name [ssi_sta_caas_get_path_attr $path $tool startpoint_clock]];
            set end_clk       [get_object_name [ssi_sta_caas_get_path_attr $path $tool endpoint_clock]];
            set start_clk_src [get_object_name [ssi_sta_caas_get_path_attr [get_clocks $start_clk] $tool sources]];
            set end_clk_src   [get_object_name [ssi_sta_caas_get_path_attr [get_clocks $end_clk]   $tool sources]];
            set start_clk_mst [get_object_name [ssi_sta_caas_get_path_attr [get_clocks $start_clk] $tool master_pin]];
            set end_clk_mst   [get_object_name [ssi_sta_caas_get_path_attr [get_clocks $end_clk]   $tool master_pin]];
            set crpr_point    [get_object_name [ssi_sta_caas_get_path_attr $path $tool crpr_common_point]]
	    set crpr_point     "None"
	    set crp_obj       [ssi_sta_caas_get_path_attr $path $tool crpr_common_point]
	    if { [sizeof_collection $crp_obj] } {
            	set crpr_point    [get_object_name $crp_obj]
	    }
	    set data_points   [ssi_sta_caas_get_path_attr $path $tool points]

	    set crpr_L        $crpr_point
            set crpr_L_path   [ssi_sta_caas_get_path_attr $path          $tool launch_clock_paths]
            set crpr_L_points [ssi_sta_caas_get_path_attr $crpr_L_path   $tool points]
            set crp_L_obj     [ssi_sta_caas_get_path_attr $crpr_L_points $tool object]
	    if { [sizeof_collection $crp_L_obj] } {
	    	catch { set crpr_L   [lindex [get_object_name $crp_L_obj] [expr [lsearch [get_object_name $crp_L_obj] $crpr_point] + 1 ]] }
	    }

	    set crpr_C        $crpr_point
            set crpr_C_path   [ssi_sta_caas_get_path_attr $path          $tool capture_clock_paths]
            set crpr_C_points [ssi_sta_caas_get_path_attr $crpr_C_path   $tool points]
            set crp_C_obj     [ssi_sta_caas_get_path_attr $crpr_C_points $tool object]
	    if { [sizeof_collection $crp_C_obj] } {
	    	catch { set crpr_C   [lindex [get_object_name $crp_C_obj] [expr [lsearch [get_object_name $crp_C_obj] $crpr_point] + 1 ]] }
	    }

            # CRPR Segregation
	    if { $crpr_point == "" || $crpr_point == "None" } {
	        set crpr_pointx  ""
	    } else {
            	set crpr_pointx $crpr_point
	    }
            #puts "Start=$start / $start_clk / $start_clk_src / $start_clk_mst"
            #puts "End=$end / $end_clk / $end_clk_src / $end_clk_mst"
            #puts "CRPR=$crpr_pointx / crpr_C=$crpr_C / crpr_L=$crpr_L"
            ## RC vs Device Data
            #puts "L=[sizeof_collection $crpr_L_path] / D=[sizeof_collection $data_points] / C=[sizeof_collection $crpr_C_path]"
            set return_point_data [ssi_sta_caas_timing_points_split $data_points "" "" $tool 0]

	    set arr_rc        [lindex $return_point_data 0]
	    set arr_cell      [lindex $return_point_data 1]
	    set stg_level     [lindex $return_point_data 2]
	    set totalXY       [lindex $return_point_data 3]
	    set totalarr      [lindex $return_point_data 4]
	    set totalsi       [lindex $return_point_data 5]
	    set datatrace     [lindex $return_point_data 6]
	    set nodetrace     [lindex $return_point_data 7]
	    set buf_level     [lindex $return_point_data 8]
	    set logic_level   [lindex $return_point_data 9]
	    set arr_buf       [lindex $return_point_data 10]
	    set arr_logic     [lindex $return_point_data 11]
	    set start_offset  [lindex $return_point_data 12]
            # Offset
            set arr_rc        [expr $arr_rc - $start_offset]
            #puts "arr_rc=$arr_rc arr_cell=$arr_cell totalsi=$totalsi start_offset=$start_offset"

            set return_point_data_L [ssi_sta_caas_timing_points_split $crpr_L_points "" "" $tool 0]
	    set arr_rc_L      [lindex $return_point_data_L 0]
	    set arr_cell_L    [lindex $return_point_data_L 1]
	    set stg_level_L   [lindex $return_point_data_L 2]
	    set totalXY_L     [lindex $return_point_data_L 3]
	    set totalarr_L    [lindex $return_point_data_L 4]
	    set totalsi_L     [lindex $return_point_data_L 5]
	    set datatrace_L   [lindex $return_point_data_L 6]
	    set nodetrace_L   [lindex $return_point_data_L 7]

            set return_point_data_C [ssi_sta_caas_timing_points_split $crpr_C_points "" "" $tool 0]
	    set arr_rc_C      [lindex $return_point_data_C 0]
	    set arr_cell_C    [lindex $return_point_data_C 1]
	    set stg_level_C   [lindex $return_point_data_C 2]
	    set totalXY_C     [lindex $return_point_data_C 3]
	    set totalarr_C    [lindex $return_point_data_C 4]
	    set totalsi_C     [lindex $return_point_data_C 5]
	    set datatrace_C   [lindex $return_point_data_C 6]
	    set nodetrace_C   [lindex $return_point_data_C 7]

            set return_point_data_CRL [ssi_sta_caas_timing_points_split $crpr_L_points "" $crpr_pointx $tool 0]
	    set arr_rc_CRL      [lindex $return_point_data_CRL 0]
	    set arr_cell_CRL    [lindex $return_point_data_CRL 1]
	    set stg_level_CRL   [lindex $return_point_data_CRL 2]
	    set totalXY_CRL     [lindex $return_point_data_CRL 3]
	    set totalarr_CRL    [lindex $return_point_data_CRL 4]
	    set totalsi_CRL     [lindex $return_point_data_CRL 5]
	    set datatrace_CRL   [lindex $return_point_data_CRL 6]
	    set nodetrace_CRL   [lindex $return_point_data_CRL 7]

            set return_point_data_CRC [ssi_sta_caas_timing_points_split $crpr_C_points "" $crpr_pointx $tool 0]
	    set arr_rc_CRC      [lindex $return_point_data_CRC 0]
	    set arr_cell_CRC    [lindex $return_point_data_CRC 1]
	    set stg_level_CRC   [lindex $return_point_data_CRC 2]
	    set totalXY_CRC     [lindex $return_point_data_CRC 3]
	    set totalarr_CRC    [lindex $return_point_data_CRC 4]
	    set totalsi_CRC     [lindex $return_point_data_CRC 5]
	    set datatrace_CRC   [lindex $return_point_data_CRC 6]
	    set nodetrace_CRC   [lindex $return_point_data_CRC 7]

            set return_point_data_LCR [ssi_sta_caas_timing_points_split $crpr_L_points $crpr_pointx "" $tool 0]
	    set arr_rc_LCR      [lindex $return_point_data_LCR 0]
	    set arr_cell_LCR    [lindex $return_point_data_LCR 1]
	    set stg_level_LCR   [lindex $return_point_data_LCR 2]
	    set totalXY_LCR     [lindex $return_point_data_LCR 3]
	    set totalarr_LCR    [lindex $return_point_data_LCR 4]
	    set totalsi_LCR     [lindex $return_point_data_LCR 5]
	    set datatrace_LCR   [lindex $return_point_data_LCR 6]
	    set nodetrace_LCR   [lindex $return_point_data_LCR 7]

            set return_point_data_CCR [ssi_sta_caas_timing_points_split $crpr_C_points $crpr_pointx "" $tool 0]
	    set arr_rc_CCR      [lindex $return_point_data_CCR 0]
	    set arr_cell_CCR    [lindex $return_point_data_CCR 1]
	    set stg_level_CCR   [lindex $return_point_data_CCR 2]
	    set totalXY_CCR     [lindex $return_point_data_CCR 3]
	    set totalarr_CCR    [lindex $return_point_data_CCR 4]
	    set totalsi_CCR     [lindex $return_point_data_CCR 5]
	    set datatrace_CCR   [lindex $return_point_data_CCR 6]
	    set nodetrace_CCR   [lindex $return_point_data_CCR 7]

            set path_type       [ssi_sta_caas_get_path_attr $path $tool path_type]
            set class_factor   "1"
            set use_factor     "1"
            set launch         "late"
            set capture        "early"
            set launch_attr    "max"
            set capture_attr   "min"
            set rpt_type_data(map)      [list report_type   snpsreport_type       cdnsreport_type  class_factor use_factor   launch   launch_attr  capture    capture_attr]
            set rpt_type_data(max)      [list " -late "     " -delay_type max "   " -late  "       "-1"         "1"          "late"   "max"        "early"    "min"]
            set rpt_type_data(min)      [list " -early "    " -delay_type min "   " -early "       "1"          "0"          "early"  "min"        "late"     "max"]

            if { $start_clk_mst == "" } { set start_clk_mst $start_clk_src}
            if { $end_clk_mst   == "" } { set end_clk_mst   $end_clk_src  }

            set report_type      [lindex $rpt_type_data($path_type) 0]
            set snpsreport_type  [lindex $rpt_type_data($path_type) 1]
            set cdnsreport_type  [lindex $rpt_type_data($path_type) 2]
            set class_factor     [lindex $rpt_type_data($path_type) 3]
            set use_factor       [lindex $rpt_type_data($path_type) 4]
            set launch           [lindex $rpt_type_data($path_type) 5]
            set launch_attr      [lindex $rpt_type_data($path_type) 6]
            set capture          [lindex $rpt_type_data($path_type) 7]
            set capture_attr     [lindex $rpt_type_data($path_type) 8]

            # Slack
            set slk           [ssi_sta_caas_get_path_attr $path $tool slack]
            if { $slk == ""  || $slk == inf || $slk == INFINITY} {
                puts "\n\n**WARN: The Path Slack is $slk or Unconstrainted .. Skipping\n"
                continue
            }
            set norm_slk      $slk
            #set norm_slk     [ssi_sta_caas_get_path_attr $path $tool normalized_slack]
            set slk_type      [ssi_sta_caas_get_path_attr $path $tool path_type]
            set norm_dly      [ssi_sta_caas_get_path_attr [ssi_sta_caas_get_path_attr $path $tool endpoint_clock] $tool period]
            #set norm_dly     [ssi_sta_caas_get_path_attr $path $tool normalized_delay]
            #catch { set norm_dly      [format "%0.4f"[expr $slk / ($norm_ + 0.0000000001)]}
            catch { if { $norm_dly == "" } { set norm_dly [ssi_sta_caas_get_path_attr [ssi_sta_caas_get_path_attr $path $tool endpoint_clock] $tool period] }}
            if { $norm_dly == ""    } { set norm_dly 1.000 ; set norm_slk $slk}
            # Setup
            if { $slk_type == "max" } {
                #puts "Debug Freq Setup"
                set freq          [format "%0.0fMhz"    [expr 1000.0/($norm_dly)]]
                if { [regexp "cdns" $tool] } {
                    set freq          [format "%0.0fMhz/%0.0fMhz"   [expr 1000.0/($norm_dly - $slk + 0.000)] [expr 1000.0/($norm_dly)]  ]
                } else {
                    set freq          [format "%0.0fMhz/%0.0fMhz"   [expr 1000.0/($norm_dly - $slk + 0.000)] [expr 1000.0/($norm_dly)]  ]
                }
                #puts "EQ=1000.0/($slk/$norm_slk - $slk),D=$norm_dly,NS=$norm_slk,S=$slk"
	    # Hold
            } else {
                #puts "Debug Freq Hold"
                set freq          [format "%0.0fMhz"    [expr 1000.0/($norm_dly)]]
                set freq          [format "%0.0fMhz/%0.0fMhz"   [expr 1000.0/($norm_dly - $slk + 0.000)] [expr 1000.0/($norm_dly)]]
		#set epsetup       [get_attr -quiet [get_attr -quiet $path endpoint] max_slack]
                #puts "EQ=1000.0/($norm_dly + $slk - $epsetup + 0.000),D=$norm_dly,NS=$norm_slk,S=$slk"
	    }
            #puts "start3 tool=$tool norm_dly=$norm_dly norm_slk=$norm_slk freq=$freq slk=$slk"

            # Skew
            set crpr          [ssi_sta_caas_get_path_attr $path $tool common_path_pessimism]
            set start_lat     [ssi_sta_caas_get_path_attr $path $tool startpoint_clock_latency]
            set end_lat       [ssi_sta_caas_get_path_attr $path $tool endpoint_clock_latency]
            set start_edge    [ssi_sta_caas_get_path_attr $path $tool startpoint_clock_open_edge_type]
            set end_edge      [ssi_sta_caas_get_path_attr $path $tool endpoint_clock_open_edge_type]
            set start_lat_rel $start_lat
            set end_lat_rel   $end_lat

            # Latency Adjust For Cadence
            if { [regexp "cdns" $tool] } {
                #puts "Debug Latnecy CDNS"
                set start_lat_inv [get_property -quiet $path launching_clock_source_arrival_time]
                set end_lat_inv   [get_property -quiet $path capturing_clock_source_arrival_time]
	        set start_lat     [format "%0.4f" [expr 0.00 + $start_lat_rel + 0.00 - $start_lat_inv + 0.00]]
	        set end_lat       [format "%0.4f" [expr 0.00 + $end_lat_rel   + 0.00 - $end_lat_inv + 0.00]]
                #puts "L=$start_lat_inv C=$end_lat_inv L2-$start_lat  C2=$end_lat"
            }
            #puts "L=$start_lat_rel C=$end_lat_rel L2-$start_lat  C2=$end_lat"
            set launch_capture_type   "From_Clk_To_Clk"
            if { $start_lat_rel == "" } { set start_lat_rel 0.000 }
            if { $start_lat     == "" } { set start_lat     0.000  ; regsub -all {From_Clk} $launch_capture_type {From_Async} launch_capture_type }
            if { $end_lat_rel   == "" } { set end_lat_rel   0.000 }
            if { $end_lat       == "" } { set end_lat       0.000  ; regsub -all {To_Clk}   $launch_capture_type {To_Async} launch_capture_type }

            set launch_edge    "pos_edge"
            set capture_edge   "pos_edge"
            if { $start_edge == "rise" } {
                set launch_edge    "pos_edge"
            } else {
                set launch_edge    "neg_edge"
            }
            if { $end_edge == "rise" } {
                set capture_edge    "pos_edge"
            } else {
                set capture_edge    "neg_edge"
            }

            #Default Value
            set start_clk_arr [ssi_sta_caas_get_path_attr [get_clocks -quiet $start_clk] $tool clock_source_latency_${launch}_${start_edge}_${launch_attr}]
            set end_clk_arr   [ssi_sta_caas_get_path_attr [get_clocks -quiet $end_clk  ] $tool clock_source_latency_${capture}_${end_edge}_${capture_attr}]
            set window        [ssi_sta_caas_get_path_attr [get_pins -quiet $start_clk_src] $tool arrival_window]
            if { $window == "" } {
                set window    [ssi_sta_caas_get_path_attr [get_ports -quiet $start_clk_src] $tool arrival_window]
            }
            regsub -all {\{} $window {}  window
            regsub -all {\}} $window {}  window
            if { $window != ""} {
                    set window_arr [split $window " "]
                    set i 0
                    while {$i < [llength $window_arr] } {
                        set data [lrange $window_arr $i [expr $i + 7]]
                        set i [expr $i+8]
                        if { [lindex $data 0] == $start_clk_mst &  [lindex $data 1] == $launch_edge} {
                            if {      $launch_edge == "pos_edge" & $launch_attr == "min"  } {
                                set start_clk_arr [lindex $data 3]
                            } elseif {$launch_edge == "neg_edge" & $launch_attr == "min" } {
                                set start_clk_arr [lindex $data 4]
                            } elseif {$launch_edge == "pos_edge" & $launch_attr == "max" } {
                                set start_clk_arr [lindex $data 6]
                            } elseif {$launch_edge == "neg_edge" & $launch_attr == "max" } {
                                set start_clk_arr [lindex $data 7]
                            }
                        }
                    }
            }

            set window    [ssi_sta_caas_get_path_attr [get_pins -quiet $end_clk_src] $tool arrival_window]
            if { $window == "" } {
                set window    [ssi_sta_caas_get_path_attr [get_ports -quiet $end_clk_src] $tool arrival_window]
            }

            regsub -all {\{} $window {}  window
            regsub -all {\}} $window {}  window
            if { $window != ""} {
	            set window_arr [split $window " "]
	            set i 0
	            while {$i < [llength $window_arr] } {
	                set data [lrange $window_arr $i [expr $i + 7]]
	                set i [expr $i+8]
	                if { [lindex $data 0] == $end_clk_mst &  [lindex $data 1] == $capture_edge} {
	                    if {      $capture_edge == "pos_edge" & $capture_attr == "min"  } {
	                       set end_clk_arr [lindex $data 3]
	                    } elseif {$capture_edge == "neg_edge" & $capture_attr == "min" } {
	                       set end_clk_arr [lindex $data 4]
	                    } elseif {$capture_edge == "pos_edge" & $capture_attr == "max" } {
	                       set end_clk_arr [lindex $data 6]
	                    } elseif {$capture_edge == "neg_edge" & $capture_attr == "max" } {
	                       set end_clk_arr [lindex $data 7]
	                    }
	                }
	            }
            }
            #puts "Debug Skew"
            set skew          [expr 0 + $end_lat     - $start_lat + $crpr + 0]
            set skew_S1       [expr 0 + $end_clk_arr - $start_clk_arr + 0]
            set skew_S2       [expr 0 + $end_lat     - $start_lat - $skew_S1 + 0 ]

            # Data
            #puts "Debug Arrival"
            set arr_time      [ssi_sta_caas_get_path_attr $path $tool arrival]
            set data_dly      [expr $arr_time -  $start_lat_rel] ; # Same as start_lat in Snps

            # Required
            #puts "Debug LibTime"
            set req_time      [ssi_sta_caas_get_path_attr $path $tool required]
            set lib_time1     [ssi_sta_caas_get_path_attr $path $tool endpoint_hold_time_value];
            set lib_time2     [ssi_sta_caas_get_path_attr $path $tool endpoint_setup_time_value];
            set lib_time3     [ssi_sta_caas_get_path_attr $path $tool endpoint_removal_time_value];
            set lib_time4     [ssi_sta_caas_get_path_attr $path $tool endpoint_recovery_time_value]
            set lib_time      [expr $class_factor*(0 + $lib_time1 + $lib_time2 + $lib_time3 + $lib_time4 + 0)]
            set uncert        [expr 0 + [ssi_sta_caas_get_path_attr $path $tool clock_uncertainty] + 0 ]
            set margin        [expr 0 + $req_time - $end_lat - $crpr - $lib_time + 0 ]


            #puts "Debug Required"
            # Phase
            set start_clk_ph  [ssi_sta_caas_get_path_attr $path $tool startpoint_clock_open_edge_value];
            # Candece Non Sense
            if { [regexp "cdns" $tool] } {
                set end_clk_ph    [ssi_sta_caas_get_path_attr $path $tool normalized_delay]
            } else {
                set end_clk_ph    [ssi_sta_caas_get_path_attr $path $tool endpoint_clock_open_edge_value];
            }
            set max_delayx    "Synchronous_RT"
	    if { $start_clk_ph == "" || $end_clk_ph == "" } {
	       set max_delayx     [ssi_sta_caas_get_path_attr $path $tool exception_delay]
               set start_clk_ph   0.000
               set end_clk_ph     $max_delayx
	    }
            #if { [regexp "Async" $launch_capture_type] } {
            #   puts "Path Type launch_capture_type=$launch_capture_type  start_clk_ph=$start_clk_ph  end_clk_ph=$end_clk_ph  crpr=$crpr     margin=$margin lib_time=$lib_time"
            #}
            #report_timing $path -nos

            set phase_delta   0.000
	    catch {set phase_delta   [expr $end_clk_ph - $start_clk_ph]}

	    # Back Calculation
            #puts "Debug Calculation : $start_clk_ph + $start_lat + $data_dly"
            set AT_x          [expr $start_clk_ph + $start_lat + $data_dly ]
            set RT_x          [expr $end_clk_ph   + $end_lat   + $crpr  + $margin + $lib_time ]
            set Bslk          [expr $class_factor*($AT_x - $RT_x)]
            set adjustslk     [expr $slk - $Bslk]

            #puts "Debug Xtlk/Stage"

            # Xtlk adjust
	    set totalsi_clk     [expr abs($totalsi_L) + abs($totalsi_C)]
	    # Stage adjust
	    set data_stages     [expr ($stg_level + 1) / 2]
	    set clk_stages_L    [expr ($stg_level_L - 1) / 2]
	    set clk_stages_C    [expr ($stg_level_C - 1) / 2]
	    set clk_stages_LCR  [expr ($stg_level_LCR - 2) / 2]
	    set clk_stages_CCR  [expr ($stg_level_CCR - 2) / 2]
	    set clk_stages_CRL  [expr ($stg_level_CRL + 1) / 2]
	    set clk_stages_CRC  [expr ($stg_level_CRC + 1) / 2]

	    # Uncommon Dly Adjust
	    set clk_common      [expr ($totalarr_CRL + $totalarr_CRC)/2]
            # Cadence adjust
            if { [regexp "cdns" $tool] } {
                set clk_uncommon_L  [expr $arr_rc_LCR + $arr_cell_LCR]
                set clk_uncommon_C  [expr $arr_rc_CCR + $arr_cell_CCR]
            } else {
	        set clk_uncommon_L  [expr $totalarr_LCR - $totalarr_CRL ]
	        set clk_uncommon_C  [expr $totalarr_CCR - $totalarr_CRC ]
            }
	    set clk_stg_common      $clk_stages_CRC
	    set clk_stg_uncommon_L  $clk_stages_LCR
	    set clk_stg_uncommon_C  $clk_stages_CCR

	    set imbalance           [expr $data_stages + $clk_stg_uncommon_L - $clk_stg_uncommon_C]

            # Verbose
            #puts "margin=$margin | phase_delta=$phase_delta | lib_time=$lib_time | Data=$data_dly (RC=$arr_rc Cell=$arr_cell Si=$totalsi) | Skew=$skew {skew_S1=$skew_S1 skew_S2=$skew_S2} | CR=$crpr | SP(Lat)=$start_lat | EP(Lat)=$end_lat | Slack=$slk | norm_dly=$norm_dly | freq=$freq"
            if { [regexp "cdns" $tool] } {

                global report_timing_format
                set org_format    $report_timing_format
                set custom_format {fanout  load   slew     total_derate incr_delay delay_mean delay_sigma delay arrival voltage pin_location timing_point cell}
                                   #Fanout Cap    DTrans   Trans        Delta      Mean       Sensit      Incr  Path    Voltage Location     Point (ref)
                catch { set_table_style -nosplit  -no_frame_fix_width }
                catch { set report_timing_format $custom_format       }
	        if { $slk_type == "max" } {
            	    report_timing  -late -path_type full_clock $path
	        } else {
            	    report_timing  -early -path_type full_clock $path
	        }
                set report_timing_format $org_format

            } else {

	        global timing_report_fixed_width_columns_on_left
                suppress_message [list CMD-005 CMD-104]
                catch { set org_format [get_app_var timing_report_fixed_width_columns_on_left] } ; # PT
                catch { set_app_var timing_report_fixed_width_columns_on_left true             } ; # PT
                catch { set_app_options -name    time.report_timing_column_order -value [list Fanout  Cap Trans Derate  Delta  Incr Path Voltage Location Point]} ; # FC
                unsuppress_message [list CMD-005 CMD-104]
            	report_timing -nets -input_pins -path_type full_clock_expanded -nos -voltage -physical -derate -cap -cross -significant 4 -tran $path

                suppress_message [list CMD-005 CMD-104]
                catch { set_app_var timing_report_fixed_width_columns_on_left $org_format } ; # PT
                catch { set_app_options -name    time.report_timing_column_order -value [list]} ; # FC
                unsuppress_message [list CMD-005 CMD-104]


            }


	    set crpr_comment ""
            if { $crpr_L == $crpr_point || $crpr_C == $crpr_point } { set crpr_comment "(Add -path_type full_clock in args!)"}
            # Key Points
            echo "#--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------"
            echo "# Summary $tool"
            echo "#--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------"
            echo "View       :  $view"
            echo "Class      :  $path_type"
            echo "Start      :  $start @ $start_clk"
            echo "End        :  $end @ $end_clk"
            echo "StartCK_Arr:  $start_clk_src @ $start_clk_mst @ $start_clk_arr using clock_source_latency_${launch}_${start_edge}_${launch_attr}"
            echo "EndCK_Arr  :  $end_clk_src @ $end_clk_mst @ $end_clk_arr using clock_source_latency_${capture}_${end_edge}_${capture_attr}"
            echo "Common     :  $crpr_point"
            echo "DivgLau    :  $crpr_L $crpr_comment"
            echo "DivgCap    :  $crpr_C $crpr_comment"
            echo "DivgImbal  :  $imbalance ($data_stages + $clk_stg_uncommon_L - $clk_stg_uncommon_C)"
            echo "Slack      :  $slk @ $norm_slk/$norm_dly Freq=$freq"
            echo "Base       :  AT=$arr_time |  RT=$req_time | MaxDelay=$max_delayx | Launch/Capture_Type=$launch_capture_type"
            # Timing Equation
            #puts "$start_clk_ph,$start_lat,$data_dly,$slk|$end_clk_ph,$end_lat,$crpr,$margin,$lib_time"
            echo "#--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------"
            echo [format "LaunchEq:  PH= %+0.3f > LP= %+0.3f > DP= %+0.3f > SL= %+0.3f"              $start_clk_ph  $start_lat $data_dly $slk ]
            echo [format "CapturEq:  PH= %+0.3f > CP= %+0.3f > CR= %+0.3f > MR= %+0.3f > LB= %+0.3f" $end_clk_ph    $end_lat   $crpr     $margin $lib_time]
            echo [format "BackCalc:  AT= %+0.3f   RT= %+0.3f   SK= %+0.3f   UN= %+0.3f > AD= %+0.3f  (SL~ %+0.3f + %+0.3f)" $AT_x $RT_x $skew $uncert $adjustslk $Bslk $adjustslk]
            echo [format "SplitDly:  DP= %+0.3f + LB= %+0.3f - SK= %+0.3f  (S1= %+0.3f   S2= %+0.3f  CR= %+0.3f CLKSI= %+0.3f)  (Effective Margin/Phase Adjust Not Accounted)"     $data_dly $lib_time $skew $skew_S1 $skew_S2 $crpr $totalsi_clk]
            echo "#--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------"
            echo [format "DataSplit: DP= %+0.3f   RC= %+0.3f   DV= %+0.3f   SI= %+0.3f   XY= %+5.1f  STG= %+0.1f (Final= %+0.3f)" $data_dly $arr_rc $arr_cell $totalsi $totalXY $data_stages $totalarr ]
            echo [format "DataSplit: DV= %+0.3f   BF= %+0.3f   LG= %+0.3f   SI= %+0.3f   XY= %+5.1f  STG= %+0.1f/%+0.1f (Final= %+0.3f)" $arr_cell $arr_buf $arr_logic $totalsi $totalXY $buf_level $logic_level $totalarr ]
            echo "#--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------"
    catch { echo [format "LClkSplit: LP= %+0.3f   RC= %+0.3f   DV= %+0.3f   SI= %+0.3f   XY= %+5.1f  STG= %+0.1f (Final= %+0.3f)" $start_lat $arr_rc_L $arr_cell_L $totalsi_L $totalXY_L $clk_stages_L $totalarr_L] }
    catch { echo [format "LClkCRPR-: LP= %+0.3f   RC= %+0.3f   DV= %+0.3f   SI= %+0.3f   XY= %+5.1f  STG= %+0.1f (Final= %+0.3f)" $totalarr_CRL $arr_rc_CRL $arr_cell_CRL $totalsi_CRL $totalXY_CRL $clk_stages_CRL  $totalarr_CRL] }
    catch { echo [format "LClkCRPR+: LP= %+0.3f   RC= %+0.3f   DV= %+0.3f   SI= %+0.3f   XY= %+5.1f  STG= %+0.1f (Final= %+0.3f)" $clk_uncommon_L $arr_rc_LCR $arr_cell_LCR $totalsi_LCR $totalXY_LCR $clk_stages_LCR $totalarr_LCR] }
            echo "#--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------"
    catch { echo [format "CClkSplit: CP= %+0.3f   RC= %+0.3f   DV= %+0.3f   SI= %+0.3f   XY= %+5.1f  STG= %+0.1f (Final= %+0.3f)" $end_lat $arr_rc_C $arr_cell_C $totalsi_C $totalXY_C $clk_stages_C $totalarr_C] }
    catch { echo [format "CClkCRPR-: CP= %+0.3f   RC= %+0.3f   DV= %+0.3f   SI= %+0.3f   XY= %+5.1f  STG= %+0.1f (Final= %+0.3f)" $totalarr_CRC $arr_rc_CRC $arr_cell_CRC $totalsi_CRC $totalXY_CRC  $clk_stages_CRC $totalarr_CRC] }
    catch { echo [format "CClkCRPR+: CP= %+0.3f   RC= %+0.3f   DV= %+0.3f   SI= %+0.3f   XY= %+5.1f  STG= %+0.1f (Final= %+0.3f)" $clk_uncommon_C $arr_rc_CCR $arr_cell_CCR $totalsi_CCR $totalXY_CCR  $clk_stages_CCR $totalarr_CCR] }
            echo "#--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------"
    catch { echo "#Slack,#Freq,#Period_Window,#Uncertainty,#Margin,#Data,#Data(RC),#Data(Si),#Data(Cell),#Data(BufInv),#Data(Logic),#Data(LibReqd),#Data(Stages),#DataBufInv(Stages),#DataLogic(Stages),#Data(XY),#Clock(Skew),#Clock(Si),#ClockLat(Start),#ClockLat(End),#Clock(CRPR),#ClockStages(Common),#ClockStages(Launch),#ClockStages(Capture),#ClockXY(Common),#ClockXY(Launch),#ClockXY(Capture),#ImbalanceStages,#Start,#End,#ClockBranch,#ClockLaunch,#ClockCapture,#PathTrace" }
    catch { echo "$slk,$freq,$phase_delta,$uncert,$margin,$data_dly,$arr_rc,$totalsi,$arr_cell,$arr_buf,$arr_logic,$lib_time,$data_stages,$buf_level,$logic_level,$totalXY,$skew,$totalsi_clk,$start_lat,$end_lat,$crpr,$clk_stg_common,$clk_stg_uncommon_L,$clk_stg_uncommon_C,$totalXY_CRL,$totalXY_LCR,$totalXY_CCR,$imbalance,$start,$end,$crpr_point,$crpr_L,$crpr_L,$datatrace" }

            echo "#--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------"
    }
}
proc ssi_sta_caas_gen_template_1 {CAAS_TOOL CAAS_TOOL_PLATFORM tdir out_files_path_arr inputs_arr} {
    global CAAS_SCRIPT
    upvar $inputs_arr inputs
    upvar $out_files_path_arr out_files_path
    set  out_files_ptr             "\n\n\
                                   \n\
                                   #==============================================================================\n\
                                   ## Define Procs\n\
                                   #==============================================================================\n\
                                   redirect -file source.ssi_sta_caas_master.log  { source $CAAS_SCRIPT }\n\
                                   ssi_sta_caas_get_tool_version\n\
                                   #==============================================================================\n\
                                   ## Define Globals\n\
                                   #==============================================================================\n\
                                   global CAAS_TOOL_PLATFORM CAAS_TOOL\n\
                                   ssi_sta_caas_get_tool_version\n\
                                   array unset ref_summary_arr ; # Define Arrays\n\
                                   array unset tar_summary_arr ; # Define Arrays\n\
                                   array unset ref_node_arr    ; # Define Arrays\n\
                                   array unset tar_node_arr    ; # Define Arrays\n\
                                   array unset ref_paths_arr   ; # Define Arrays\n\
                                   array unset tar_paths_arr   ; # Define Arrays\n\
                                   \n\n\
                                   set ref_tool            $CAAS_TOOL ; # ptx inv fcx tem\n\
                                   set ref_tool_platform   $CAAS_TOOL_PLATFORM\n\
                                   set tar_tool            \$CAAS_TOOL  ;#$inputs(tar_tool) ; # ptx inv fcx tem\n\
                                   set tar_tool_platform   \$CAAS_TOOL_PLATFORM\n\
                                   set ref_scenario        $inputs(ref_scenario) ; # add scenario name for fcx/inv mapping\n\
                                   set tar_scenario        $inputs(tar_scenario) ; # add scenario name for fcx/inv mapping\n\
                                   set incr_tag            \"$inputs(tar_prefix)\" ; # add new tag for mapping one step to many\n\
                                   set tool                \$tar_tool ; # ptx inv fcx tem\n\
                                   puts \[format \"<STA::CAAS::PROC> RefxDB %-50s  \[date\]\"   \"ssi_sta_caas_profile_timingpath : Selected Ref Platform/Tool/Scenarios as \$ref_tool_platform/\$ref_tool/\$ref_scenario\"\]\n\
                                   puts \[format \"<STA::CAAS::PROC> TarxDB %-50s  \[date\]\"   \"ssi_sta_caas_profile_timingpath : Selected Tar Platform/Tool/Scenarios as \$tar_tool_platform/\$tar_tool/\$tar_scenario\"\]\n\
                                   puts \[format \"<STA::CAAS::PROC> TagxDB %-50s  \[date\]\"   \"ssi_sta_caas_profile_timingpath : Selected Tag \$incr_tag\"\]\n\
                                   \n\n\
                                   set empty_collection    \[remove_from_collection \[all_clocks\] \[all_clocks\]\]\n\
                                   set ref_paths           \$empty_collection\n\
                                   set tar_paths           \$empty_collection\n\
                                   \n\n\
                                   set j                   0\n\
                                   set path_cnt_ref        $inputs(path_count)\n\
                                   set path_cnt_tar        0\n\
                                   set path_cnt_blk        0\n\
                                   set path_cnt_val        0\n\
                                   set path_cnt_bkt        \[expr 0.1 * \$path_cnt_ref\]\n\
                                   \n\n\
                                   #==============================================================================\n\
                                   ## Define Alias Tool Switch\n\
                                   #==============================================================================\n\
                                   set max_slack           20000\n\
                                   set pba_type            $inputs(pba_mode) ; # none , path , exhaustive\n\
                                   set retime_mode         \"none\"\n\
                                   if { \$pba_mode == \"path\"       } { set retime_mode \"path\" }\n\
                                   if { \$pba_mode == \"exhaustive\" } { set retime_mode \"exhaustive\" }\n\
                                   set force_startend      $inputs(force_startend)\n\
                                   set debug               $inputs(debug)\n\
                                   if { \$tar_tool == \"fcx\" } { current_scenario \$tar_scenario }\n\
                                   \n\n\
                                   alias snps_report_timing_collection \"get_timing_paths                 -path_type full_clock_expanded  -slack_lesser_than \$max_slack \"\n\
                                   if { \$tar_scenario != \"set_tar_scenario\" && \$tar_tool != \"ptx\"} {\n\
                                     puts \[format \"<STA::CAAS::PROC> InitDB %-50s  \[date\]\"   \"ssi_sta_caas_profile_timingpath : Updating Reporting Type for Scenario=\$tar_scenario \"\]\n\
                                     alias snps_report_timing_collection \"get_timing_paths               -path_type full_clock_expanded  -slack_lesser_than \$max_slack -scenario \$tar_scenario\"\n\
                                   } else {\n\
                                     puts \[format \"<STA::CAAS::PROC> InitDB %-50s  \[date\]\"   \"ssi_sta_caas_profile_timingpath : Warning No Scenario Set Worst Case Will Be Picked Scenario=\$tar_scenario \"\]\n\
                                   }\n\
                                   if { \$retime_mode == \"none\"} {\n\
                                        alias cdns_report_timing_collection \"report_timing     -collection    -path_type full_clock -view \$tar_scenario -max_slack  \$max_slack \"\n\
                                   } else { \n\
                                        alias cdns_report_timing_collection \"report_timing     -collection    -retime_mode \$retime_mode -path_type full_clock -view \$tar_scenario -max_slack  \$max_slack \"\n\
                                   }\n\
                                   alias snps_report_timing_collection_max \"snps_report_timing_collection -delay max -pba \$pba_type \"\n\
                                   alias snps_report_timing_collection_min \"snps_report_timing_collection -delay min -pba \$pba_type \"\n\
                                   alias cdns_report_timing_collection_max \"cdns_report_timing_collection -late  \"\n\
                                   alias cdns_report_timing_collection_min \"cdns_report_timing_collection -early \"\n\
                                   alias xrt	                             ssi_sta_caas_xreport_timing \n\
                                   alias xrte	                             ssi_sta_caas_xreport_timing -delay min \n\
                                   \n\n\
                                   if { \$tar_tool_platform ==  \"cdns\" } { alias auto_report_timing_collection     cdns_report_timing_collection     }\n\
                                   if { \$tar_tool_platform ==  \"cdns\" } { alias auto_report_timing_collection_max cdns_report_timing_collection_max }\n\
                                   if { \$tar_tool_platform ==  \"cdns\" } { alias auto_report_timing_collection_min cdns_report_timing_collection_min }\n\
                                   if { \$tar_tool_platform ==  \"snps\" } { alias auto_report_timing_collection     snps_report_timing_collection     }\n\
                                   if { \$tar_tool_platform ==  \"snps\" } { alias auto_report_timing_collection_max snps_report_timing_collection_max }\n\
                                   if { \$tar_tool_platform ==  \"snps\" } { alias auto_report_timing_collection_min snps_report_timing_collection_min }\n\
                                   \n\n\
                                   puts \[format \"<STA::CAAS::PROC> InitDB %-50s  \[date\]\"   \"ssi_sta_caas_profile_timingpath : Initialize for pba_mode=\$pba_type \"\]\n\
                                   \n\n\
                                   #==============================================================================\n\
                                   ## File Operations/References\n\
                                   #==============================================================================\n\
                                   set tdir                $tdir\n\
                                   set path_rpt_dir        \$tdir/post_process\n\
                                   set tool_path_rpt_dir   \$path_rpt_dir/\$tool.tar\$incr_tag\n\
                                   set scripts_dir         \$tdir/scripts\$incr_tag\n\
                                   set compare_dir         \$tdir/delta\$incr_tag\n\
                                   \n\n\
                                   file mkdir              \$tool_path_rpt_dir\n\
                                   file mkdir              \$scripts_dir\n\
                                   file mkdir              \$compare_dir\n\
                                   \n\n\
                                   set ref_export_tcl      $out_files_path(export_tcl)  ; # Define DB to Import\n\
                                   set ref_gen_tcl         $out_files_path(gen_tcl)     ; # Define DB to Extract\n\
                                   set ref_node_csv        $out_files_path(node_csv)    ; # Define Node Ref Data\n\
                                   set ref_summary_csv     $out_files_path(summary_csv) ; # Define Summary Ref Data\n\
                                   catch                   { exec ln -sfn  \$ref_export_tcl   \$compare_dir/ref_export.tcl  }\n\
                                   catch                   { exec ln -sfn  \$ref_gen_tcl      \$compare_dir/ref_gen.tcl     }\n\
                                   catch                   { exec ln -sfn  \$ref_node_csv     \$compare_dir/ref_node.csv    }\n\
                                   catch                   { exec ln -sfn  \$ref_summary_csv  \$compare_dir/ref_summary.csv }\n\
                                   \n\n\
                                   set tar_file_tag                  $inputs(tag)_tar.\$tar_tool.$inputs(max_min).$inputs(slack_lesser_than).\$incr_tag\n\
                                   set out_files_path(summary_csv)   \$path_rpt_dir/\$tar_file_tag.summary.csv\n\
                                   set out_files_path(node_csv)      \$path_rpt_dir/\$tar_file_tag.node.csv\n\
                                   set out_files_path(export_tcl)    \$path_rpt_dir/\$tar_file_tag.export.tcl\n\
                                   set out_files_path(gen_tcl)       \$path_rpt_dir/\$tar_file_tag.gen.tcl\n\
                                   set out_files_path(dsummary_csv)  \$compare_dir/\$tar_file_tag.delta.summary.csv\n\
                                   set out_files_path(dnode_csv)     \$compare_dir/\$tar_file_tag.delta.node.csv\n\
                                   set out_files_path(miss_summary)  \$compare_dir/\$tar_file_tag.missed.summary.csv\n\
                                   set out_files_path(miss_node)     \$compare_dir/\$tar_file_tag.missed.node.csv\n\
                                   foreach x \[array names out_files_path\] {\n\
                                       set out_files_ptr(\$x)  \[open \$out_files_path(\$x)  w+\]\n\
                                   }\n\
                                   \n\n\
                                   set tar_export_tcl      \$out_files_path(export_tcl)  ; # Define DB to Import\n\
                                   set tar_gen_tcl         \$out_files_path(gen_tcl)     ; # Define DB to Extract\n\
                                   set tar_node_csv        \$out_files_path(node_csv)    ; # Define Node Tar Data\n\
                                   set tar_summary_csv     \$out_files_path(summary_csv) ; # Define Summary Tar Data\n\
                                   catch                   { exec ln -sfn  \$tar_export_tcl   \$compare_dir/tar_export.tcl  }\n\
                                   catch                   { exec ln -sfn  \$tar_gen_tcl      \$compare_dir/tar_gen.tcl     }\n\
                                   catch                   { exec ln -sfn  \$tar_node_csv     \$compare_dir/tar_node.csv    }\n\
                                   catch                   { exec ln -sfn  \$tar_summary_csv  \$compare_dir/tar_summary.csv }\n\
                                   \n\n\
                                   set dnode_csv           \$out_files_path(dnode_csv)    ; # Define Delta Node Tar Data\n\
                                   set dsummary_csv        \$out_files_path(dsummary_csv) ; # Define Delta Summary Tar Data\n\
                                   \n\n\
                                   #==============================================================================\n\
                                   ## Begin Path Extraction\n\
                                   #==============================================================================\n\
                                   puts \[format \"<STA::CAAS::PROC> InitDB %-50s  \[date\]\"   \"ssi_sta_caas_profile_timingpath : Initialize Parsing for Ref Path DB Paths=\$path_cnt_ref\"\]\n\
                                   \n"
    return $out_files_ptr
}
proc ssi_sta_caas_gen_without_buffer {with_buffers} {
    global CAAS_TOOL_PLATFORM
        set without_buffers ""
        set skipped_buffers ""
        foreach el $with_buffers {
            if { $el != "-through" } {
                #set ref_cell [get_attribute [get_pins -quiet $el] cell.ref_name]
                if { $CAAS_TOOL_PLATFORM == "snps" } {
                    set ref_cell [get_attribute [get_pins -quiet $el] cell.ref_name]
                } else {
                    set ref_cell [get_property [get_pins -quiet $el] cell.ref_name]
                }
                set is_buf_inv [sizeof_collection [get_lib_cells -quiet */$ref_cell -filter "number_of_pins==2 && is_combinational==true"]]
                if {  $is_buf_inv == 0 } {
                    set without_buffers "$without_buffers -through $el"
                } else {
                    set skipped_buffers "$skipped_buffers -through $el"

                }
            }
        }
        return [list $without_buffers $skipped_buffers]
}

proc ssi_sta_caas_gen_template_2 {idx slk_type expected_node_offset pt_summary_data} {
        set with_buffers [lindex [split $pt_summary_data ","] end]
        set out_files_ptr       "\n\n
                                   #---------------------------------------------------------------------------------\n\
                                   incr path_cnt_tar \n\
                                   incr path_cnt_blk \n\
                                   set tar_paths_arr($idx)  \$empty_collection \n\
                                   catch { set tar_paths_arr($idx)  \[auto_report_timing_collection_$slk_type  $with_buffers -to [lindex [split $pt_summary_data ","] end-4]  -from [lindex [split $pt_summary_data ","] end-5] \] } \n\
                                   if { ! \[sizeof_collection \$tar_paths_arr($idx)\] && \$force_startend == \"1\" } { \n\
                                         #set without_buffers \[ssi_sta_caas_gen_without_buffer \"$with_buffers\"\] \n\
                                         catch { set tar_paths_arr($idx)  \[auto_report_timing_collection_$slk_type -to [lindex [split $pt_summary_data ","] end-4]  -from [lindex [split $pt_summary_data ","] end-5] \] } \n\
                                   }\n\
                                   if { \$debug } { report_timing -nos \$tar_paths_arr($idx) }\n\
                                   \n\
                                   catch {\n\
                                     if { \[sizeof_collection \$tar_paths_arr($idx)\] } {  \n\
                                         incr path_cnt_val \n\
                                         append_to_collection       tar_paths \$tar_paths_arr($idx)  \n\
                                         set mapped_path_data       \[ssi_sta_caas_path_id_map_loop  \$tar_paths_arr($idx) $idx \$tar_filex \$j \$tar_tool_platform\]  \n\
	                                 if { \$debug } { puts \"<Debug> Mapped Data \$mapped_path_data\" }\n\
	                                 set j                      \[lindex \$mapped_path_data 0\]  \n\
	                                 set tar_summary_head       \[lindex \$mapped_path_data 1\]  \n\
	                                 set tar_summary_arr($idx)  \[lindex \$mapped_path_data 2\]  \n\
	                                 set tar_node_datalist      \[lindex \$mapped_path_data 3\]  \n\
	                                 puts \$out_files_ptr(gen_tcl) \"\\nset tar_summary_arr($idx) \$tar_summary_arr($idx)\"  \n\
                                         foreach x \$tar_node_datalist {  \
    	                                     set tar_node_arr($idx.\[lindex \[split \$x \",\"\] end\])  \"\$x\"  \n\
     	                                     set tar_pin_arr(\[lindex \[split \$x \",\"\] end\])        $idx  \n\
	                                     puts \$out_files_ptr(node_csv) \"\$x\"  \n\
	                                     puts \$out_files_ptr(gen_tcl)  \"set tar_node_arr($idx.\[lindex \[split \$x \",\"\] end\]) \$x\"  \n\
                                         }\n\
	                                 puts \$out_files_ptr(summary_csv) \"\$tar_summary_arr($idx)\"  \n\
                                     } else {  \n\
                                         puts \"       -- Skipped ID=$idx | Node Offset = $expected_node_offset / Present=\$j\"  \n\
                                         set j $expected_node_offset  \n\
                                         regsub -all {^#,#,} \$missing_data_string \"#Missing,$idx,\" missing_data  \n\
                                         puts \$out_files_ptr(summary_csv) \"\$missing_data\"  \n\
                                         set  tar_missed_arr($idx) \"\$missing_data\"  \n\
                                     }  \n\
      	                           \n\
                                   }\n\
                                   set ref_summary_arr($idx)  \"$pt_summary_data\"\n  \
                                   if { \$path_cnt_blk >= \$path_cnt_bkt }  {\n\
	                                puts \"\\t\\t\\t\\t\\t\\t \[date\] Processed Iter=\$path_cnt_bkt Cummulative=\$path_cnt_tar Total=\$path_cnt_ref Valid=\$path_cnt_val\"\n\
                                        set path_cnt_blk 0\n\
                                   }\n\
                                   #---------------------------------------------------------------------------------\n\
                                   "
        return $out_files_ptr
}


proc ssi_sta_caas_gen_template_3 {paths} {


    set out_files_ptr   "\
                          ##------------------------------------------------------------------\n\
	                  ## Correlate\n\
                          ##------------------------------------------------------------------\n\
                          \n\n\n\
                                puts \[format \"<STA::CAAS::PROC> PathCh %-50s  \[date\]\"   \"ssi_sta_caas_profile_timingpath : Starting Local Path Correlation.\"\]\n\
                                set ref_summary_idx  \[array names ref_summary_arr\]\n\
                                set ref_node_idx     \[array names ref_node_arr\]\n\
                                set tar_summary_idx  \[array names tar_summary_arr\]\n\
                                set tar_node_idx     \[array names tar_node_arr\]\n\
                                set tar_miss_idx     \[array names tar_missed_arr\]\n\
                                array unset mismatch_data_summary ; set cnt_summary 0 \n\
                                array unset mismatch_data_node    ; set cnt_node   0\n\
	                        set common_summary_idx \[list\]\n\
	                        foreach idx \[lsort \[array names tar_summary_arr\]\] {\n\
	                          if { !\[info exist ref_summary_arr(\$idx)\] } { set mismatch_data_summary(\$idx) 1 ; incr cnt_summary ; continue }
                                  set ref_data \$ref_summary_arr(\$idx)\n\
	                          set tar_data \$tar_summary_arr(\$idx)\n\
                                  #File,#PathID,#Slack,#Freq,#Period_Window,#Margin,#Data,#Data(RC),#Data(Si),#Data(Cell),#Data(LibReqd),#Data(Stages),#Data(XY),#Clock(Skew),\n\
                                  #Clock(Si),#ClockLat(Start),#ClockLat(End),#Clock(CRPR),#ClockStages(Common),#ClockStages(Launch),#ClockStages(Capture),#ClockXY(Common),\n\
                                  ##ClockXY(Launch),#ClockXY(Capture),#ImbalanceStages,#Start,#End,#ClockBranch,#ClockLaunch,#ClockCapture,#PathTrace\n\
	                          regsub -all {#} \$ref_data  {#REF_}  ref_data  ; set ref_arr   \[split \$ref_data  \",\"\] ; set ref_valid  \[lrange \$ref_arr  2 27\];\n\
	                          regsub -all {#} \$tar_data  {#TAR_}  tar_data  ; set tar_arr   \[split \$tar_data  \",\"\] ; set tar_valid  \[lrange \$tar_arr  2 27\];\n\
                                  set csv_data  \"\$idx\"\n\
	                          regsub {ID-0000001} \$csv_data \"#PathID\" csv_data\n\
	                          foreach ref_attr \$ref_valid  tar_attr \$tar_valid {\n\
	                              set csv_data \"\$csv_data,\$ref_attr,\$tar_attr\"\n\
	                          }\n\n\
	                          lappend common_summary_idx \"\$csv_data\"\n\
	                          puts \$out_files_ptr(dsummary_csv) \"\$csv_data\"\n\
	                        }\n\n\n\
	                        set common_summary_idx \[list\]\n\
	                        foreach idx \[lsort \[array names tar_node_arr\]\] {\n\
	                          if { !\[info exist ref_node_arr(\$idx)\]} { set mismatch_data_node(\$idx) 1 ; incr cnt_node ; continue }
	                          set ref_data \$ref_node_arr(\$idx)\n\
	                          set tar_data \$tar_node_arr(\$idx)\n\
	                          regsub -all {#} \$ref_data  {#REF_}  ref_data  ; set ref_arr   \[split \$ref_data  \",\"\] ; set ref_valid  \[lrange \$ref_arr  2 end\];\n\
	                          regsub -all {#} \$tar_data  {#TAR_}  tar_data  ; set tar_arr   \[split \$tar_data  \",\"\] ; set tar_valid  \[lrange \$tar_arr  2 end\];\n\
                                  #File,#PathID,#GrossIndex,#Slack,#Index,#Direction,#Delay,#Transition,#Xtlk,#Capacitance(Pin),#Capacitance(Net),#Resistance(Net),#Length(Net),#Cell,#Derate,#Node\n\
	                          set csv_data  \"\$idx\"\n\
	                          regsub {ID00000000.#Node} \$csv_data \"#PathID.#Node\" csv_data\n\
	                          foreach ref_attr \$ref_valid  tar_attr \$tar_valid {\n\
	                              set csv_data \"\$csv_data,\$ref_attr,\$tar_attr\"\n\
	                          }\n\n\
	                          lappend common_summary_idx \"\$csv_data\"\n\
	                          puts \$out_files_ptr(dnode_csv) \"\$csv_data\"\n\
	                        }\n\n\n\
                                foreach x \[array names mismatch_data_summary\] {\n\
	                          puts \$out_files_ptr(miss_summary) \"\$x\"\n\
                                }\n\
                                foreach x \[array names mismatch_data_node\] {\n\
	                          puts \$out_files_ptr(miss_node) \"\$x\"\n\
                                }\n\n\
                                foreach x \[array names out_files_ptr\] {\n\n\
                                  puts \"<INFO> :  Check File: \$out_files_path(\$x)\"\n\
                                  close \$out_files_ptr(\$x)\n\n\
                                }\n\n\
	                        puts \"\"\n\
	                        puts \[format  \"<INFO> :  %10s  %10s   %10s  %10s\"\ \"#Tool\"   \"#Paths\"  \"#Nodes\"    \"#Misses\" \]\n\
	                        puts \[format  \"          %10s  %10s   %10s  %10s\"\ \"Reference\"   \"\[llength \$ref_summary_idx\]\"  \"\[llength \$ref_node_idx\]\"    \"\[llength \$tar_miss_idx\]\"\]\n\
	                        puts \[format  \"          %10s  %10s   %10s  %10s\"\ \"Target\"      \"\[llength \$tar_summary_idx\]\"  \"\[llength \$tar_node_idx\]\"    \"\[llength \$tar_miss_idx\]\"\]\n\
	                        puts \[format  \"          %10s  %10s   %10s  %10s\"\ \"Delta\"       \"\$cnt_summary\"                  \"\$cnt_node\"                    \"\[llength \$tar_miss_idx\]\"\]\n\
	                        puts \"\"\n\
	                        puts \"<INFO> :  Final Comparison Data Dumped :\"\n\
	                        puts \"          - \$out_files_path(dsummary_csv)\"\n\
	                        puts \"          - \$out_files_path(dnode_csv)\"\n\
	                        puts \"\"\n\
                          ##------------------------------------------------------------------\n\
	                  ## Summarize\n\
                          ##------------------------------------------------------------------\n\
	                  \n    puts \"<INFO> : Valid  Paths Found     = \[sizeof_collection \$tar_paths \] / Commits = [sizeof_collection $paths ]\"\n\
	                  \n    puts \"<INFO> : Valid  Paths Directory = \$path_rpt_dir\"\n\
                          \n\n\n\
                          "
    return $out_files_ptr
}




proc ssi_sta_caas_profile_timingpath {args} {
# Proc : Report Timing Paths : ssi_sta_caas_profile_timingpath

    # Configure Tool Platform
    puts "\n\n"
    global  CAAS_TOOL_PLATFORM CAAS_TOOL CORNER
    if { ![info exist CAAS_TOOL_PLATFORM] } {
        puts [format "<STA::CAAS::PROC> Error  %-50s  [date]"   "ssi_sta_caas_profile_timingpath : Missing Global ! <CMD> global CAAS_TOOL_PLATFORM  ;  set CAAS_TOOL_PLATFORM snps ; # cdns"  ]
        return Error
    }
    set tool "snps"
    if { [info exist CAAS_TOOL_PLATFORM]  } { set tool $CAAS_TOOL_PLATFORM }
    puts "\n\n"

    # Default inputs
    parse_proc_arguments -args $args proc_x_args
    array unset inputs
    set inputs(sort_collection)         "0"
    set inputs(debug)                   "0"
    set inputs(tag)                     "ref_paths"
    set inputs(slack_lesser_than)       "-0.0009"
    set inputs(max_min)                 "max"
    set inputs(tool)                    "auto"
    set inputs(pba_mode)                "none"
    set inputs(out_dir)                 "[pwd]/paths_sta_corr"
    set inputs(supported_tools)         [list ptx fcx inv]
    set inputs(tar_tool)                "ptx"
    set inputs(tar_prefix)              ""
    set inputs(tar_scenario)            "set_tar_scenario"
    set inputs(ref_scenario)            "set_ref_scenario"
    set inputs(force_startend)          "0"

    # Configure Tool
    if { $inputs(tool) == "auto" } {
        set inputs(tool) [ssi_sta_caas_get_tool_version]
        puts [format "<STA::CAAS::PROC> Infox  %-50s  [date]"   "ssi_sta_caas_profile_timingpath : $inputs(tool) auto inferred as  [ssi_sta_caas_get_tool_version] / CAAS_TOOL_PLATFORM=$CAAS_TOOL_PLATFORM" ]
    } elseif { [lsearch $inputs(supported_tools) $inputs(tool)]  == 0 } {
        set inputs(tool) [ssi_sta_caas_get_tool_version]
        puts [format "<STA::CAAS::PROC> Warnx  %-50s  [date]"   "ssi_sta_caas_profile_timingpath : $inputs(tool) auto inferred as  [ssi_sta_caas_get_tool_version] as user tool variant is not supported" ]
    } elseif { $inputs(tool)  != [ssi_sta_caas_get_tool_version] } {
        set inputs(tool) [ssi_sta_caas_get_tool_version]
        puts [format "<STA::CAAS::PROC> Error  %-50s  [date]"   "ssi_sta_caas_profile_timingpath : $inputs(tool) doens't match with auto inferred [ssi_sta_caas_get_tool_version] " ]
    }

    # Parse Final Vars
    foreach x [array names proc_x_args] {
        regsub -all {\-} $x {} y
        set inputs($y) $proc_x_args($x)
    }
    if { $inputs(debug) }        { puts "<Debug>:             Step : Parse Final Vars" }

    # Infer Vars
    set inputs(path_count)              [sizeof_collection $inputs(collection)]
    set inputs(tool_platform)           $CAAS_TOOL_PLATFORM
    if { $inputs(debug) }        { puts "<Debug>:             Step : Infer Vars" }

    # Print Arguments
    puts [format "<STA::CAAS::PROC> Start  %-50s  [date]"   "ssi_sta_caas_profile_timingpath : $inputs(out_dir)" ]
    foreach x [array names inputs] {
        puts [format "\t\t\t\t\t       | %-20s = %-20s" $x $inputs($x) ]
    }
    if { $inputs(debug) }        { puts "<Debug>:             Step : Print Arguments" }


    # Perform Dir/File Setup
    set  tdir          	        $inputs(out_dir)/$inputs(tag)
    set  path_rpt_dir 	        $tdir/post_process
    set  tool_path_rpt_dir 	$path_rpt_dir/$inputs(tool).ref
    set  scripts_dir 	        $tdir/scripts
    file mkdir        	        $scripts_dir
    file mkdir        	        $tool_path_rpt_dir

    set  tdir                   [file normalize $tdir]
    set  path_rpt_dir           [file normalize $path_rpt_dir]
    set  tool_path_rpt_dir      [file normalize $tool_path_rpt_dir]
    set  scripts_dir            [file normalize $scripts_dir]
    file mkdir                  $path_rpt_dir

    set ref_file_tag                "$inputs(tag)_ref.$inputs(tool).$inputs(max_min).$inputs(slack_lesser_than)"
    set out_files_path(summary_csv) "$path_rpt_dir/$ref_file_tag.summary.csv"
    set out_files_path(node_csv)    "$path_rpt_dir/$ref_file_tag.node.csv"
    set out_files_path(export_tcl)  "$path_rpt_dir/$ref_file_tag.export.tcl"
    set out_files_path(gen_tcl)     "$path_rpt_dir/$ref_file_tag.gen.tcl"
    foreach x [array names out_files_path] {
        set out_files_ptr($x)  [open $out_files_path($x)  w+]
    }
    if { $inputs(debug) }        { puts "<Debug>:             Step : Perform Dir/File Setup" }

    # Perform File Header
    puts $out_files_ptr(gen_tcl) [ssi_sta_caas_gen_template_1 $CAAS_TOOL $CAAS_TOOL_PLATFORM $tdir out_files_path inputs]

    if { $inputs(debug) }        { puts "<Debug>:             Step : Perform File Header" }

    # Perform Flow Vars
    set  debug                  $inputs(debug)
    set  tag                    $inputs(tag)
    set  tool                   $inputs(tool)
    set  tool_platform          $inputs(tool_platform)
    set  max_min                $inputs(max_min)
    set  slack                  $inputs(slack_lesser_than)
    set  path_collection        $inputs(collection)
    set  sort_collection        $inputs(sort_collection)

    set  empty_collection       [remove_from_collection [all_clocks] [all_clocks]]
    if { $inputs(debug) }        { puts "<Debug>:             Step : Perform Flow Vars" }

    # Path Filtering
    puts "\n"
    puts [format "<STA::CAAS::PROC> Timing %-50s  [date]"   "ssi_sta_caas_profile_timingpath : Setup/Hold=$max_min Slack_Less_Than=$slack"]
    # TODO: TOOL CMD
    set  path_collection_valid_path      [filter_collection $path_collection            "path_type==$max_min"]
    set  path_collection_valid_pathslack [filter_collection $path_collection_valid_path "slack<=$slack"]
    set  paths                           $path_collection_valid_pathslack
    puts [format "<STA::CAAS::PROC> Timing %-50s  [date]"   "ssi_sta_caas_profile_timingpath : Valid Paths For Analysis: [sizeof_collection $path_collection_valid_pathslack]"]
    puts [format "<STA::CAAS::PROC> Timing %-50s  [date]"   "ssi_sta_caas_profile_timingpath : Paths sorted by Slack ? $sort_collection"]
    set paths $path_collection_valid_pathslack
    if { $sort_collection } {
	set paths [sort_collection $path_collection_valid_pathslack slack]
    }
    puts [format "<STA::CAAS::PROC> Timing %-50s  [date]"   "ssi_sta_caas_profile_timingpath : TotalPaths=[sizeof_collection $path_collection]"]
    puts [format "<STA::CAAS::PROC> Timing %-50s  [date]"   "ssi_sta_caas_profile_timingpath : TotalPaths\[$max_min.Slack_Lt_$slack\]=[sizeof_collection $path_collection_valid_pathslack]"]
    if { $inputs(debug) }        { puts "<Debug>:             Step : Path Filtering" }


    # Path Parsing
    puts "\n"
    set path_count              [sizeof_collection $paths]
    set rpt_type_data(map)      [list report_type   snpsreport_type       cdnsreport_type  class_factor use_factor   launch   launch_attr  capture    capture_attr]
    set rpt_type_data(max)      [list " -late "     " -delay_type max "   " -late  "       "-1"         "1"          "late"   "max"        "early"    "min"]
    set rpt_type_data(min)      [list " -early "    " -delay_type min "   " -early "       "1"          "0"          "early"  "min"        "late"     "max"]
    set i                       0
    set j                       0
    set k                       0
    set total_pct               [expr 0.1 * $path_count]


    # Indexing Path Elements
    puts [format "<STA::CAAS::PROC> PathCh %-50s  [date]"   "ssi_sta_caas_profile_timingpath : Indexing Data Paths"]
    if { $CAAS_TOOL_PLATFORM == "snps" } {
        set filtered_pins [filter_collection [get_attribute $paths        points.object] "direction==in"]
        puts "                                                 - Found [sizeof_collection $filtered_pins] filtered_pins/snps"
        set input_pins   [sort_collection $filtered_pins full_name]
    } else {
        set filtered_pins [filter_collection [get_pins -quiet [get_property [get_property $paths  timing_points] pin]] "direction==in"]
        puts "                                                 - Found [sizeof_collection $filtered_pins] filtered_pins/cdns"
        set input_pins   [sort_collection $filtered_pins full_name]
    }
    set buf_inv_pins [get_pins -of_object [get_cells -quiet -of_object $input_pins -filter "number_of_pins==2 && is_combinational==true"] -filter "direction==in"]
    set logic_pins   [remove_from_collection $input_pins $buf_inv_pins]
    puts "                                                 - Found [sizeof_collection $input_pins] all pins"
    puts "                                                 - Found [sizeof_collection $buf_inv_pins] buf_inv pins"
    puts "                                                 - Found [sizeof_collection $logic_pins] logic pins"
    puts $out_files_ptr(gen_tcl)  "####################################################################"
    puts $out_files_ptr(gen_tcl)  " # Inst Pin Index Hash"
    puts $out_files_ptr(gen_tcl)  "####################################################################"
    puts $out_files_ptr(gen_tcl)  " puts \[format \"<STA::CAAS::PROC> PathCh %-50s  \[date\]\"   \"ssi_sta_caas_profile_timingpath : Initialize Node Indexing Array\"\]"
    puts $out_files_ptr(gen_tcl)  " array unset XodePins"
    puts $out_files_ptr(gen_tcl)  " array unset YodePins"

    set count 0
    foreach_in_collection x $logic_pins {
        puts $out_files_ptr(gen_tcl) [format " set XodePins(%s) %010d" [get_object_name $x] $count]
        puts $out_files_ptr(gen_tcl) [format " set YodePins(%010d) %s" $count [get_object_name $x]]
        incr count
    }
    puts $out_files_ptr(gen_tcl)  " puts \[format \"<STA::CAAS::PROC> PathCh %-50s  \[date\]\"   \"ssi_sta_caas_profile_timingpath : Completed Node Indexing Array\"\]"
    puts $out_files_ptr(gen_tcl)  "####################################################################"
    puts $out_files_ptr(gen_tcl)  " puts \[format \"<STA::CAAS::PROC> PathCh %-50s  \[date\]\"   \"ssi_sta_caas_profile_timingpath : Initialize Parsing for Ref Path DB\"\]"




    puts [format "<STA::CAAS::PROC> PathCh %-50s  [date]"   "ssi_sta_caas_profile_timingpath : Begin Path Parsing Loop $paths"]
    if { $inputs(debug) }        { puts "<Debug>:             Step : Path Parsing / Loop Start $max_min" }
    foreach_in_collection path $paths {
    	set idx [format "ID%08d" $i]
    	incr   i
        incr   k
        # Monitor Parsing Count
        if { $k >= $total_pct }  {
	    puts "\t\t\t\t\t\t [date] Processed Iter=$k Cummulative=$i Total=$path_count"
            set k 0
        }
        # Quick Attribute Fetch
    	set spoint_obj   [ssi_sta_caas_get_path_attr $path $tool_platform startpoint]
    	set epoint_obj   [ssi_sta_caas_get_path_attr $path $tool_platform endpoint]
        set slk_type     [ssi_sta_caas_get_path_attr $path $tool_platform path_type]
        set slack        [ssi_sta_caas_get_path_attr $path $tool_platform slack]
        set spoint       [get_object_name $spoint_obj]
    	set epoint       [get_object_name $epoint_obj]
        # Reporting Adjust
	set pt_filex         $tool_path_rpt_dir/${max_min}path.$idx.txt
        set report_type      [lindex $rpt_type_data($slk_type) 0]
        set snpsreport_type  [lindex $rpt_type_data($slk_type) 1]
        set cdnsreport_type  [lindex $rpt_type_data($slk_type) 2]
        set class_factor     [lindex $rpt_type_data($slk_type) 3]
        set use_factor       [lindex $rpt_type_data($slk_type) 4]
        set launch           [lindex $rpt_type_data($slk_type) 5]
        set launch_attr      [lindex $rpt_type_data($slk_type) 6]
        set capture          [lindex $rpt_type_data($slk_type) 7]
        set capture_attr     [lindex $rpt_type_data($slk_type) 8]

        # Extract Path Summary
        if { $inputs(debug) }        { puts "<Debug>:             Step : Path Parsing / Loop ssi_sta_caas_path_id_map_loop" }
        ssi_sta_caas_path_id_map_loop $path $idx $pt_filex $j $tool_platform

        set mapped_path_data            [ssi_sta_caas_path_id_map_loop $path $idx $pt_filex $j $tool_platform]
       	set j                           [lindex $mapped_path_data 0]

       	set pt_summary_head             [lindex $mapped_path_data 1]
       	set pt_summary_data             [lindex $mapped_path_data 2]
       	set pt_node_datalist            [lindex $mapped_path_data 3]

        regsub -all {\[} $pt_summary_data  {\\[} pt_summary_data
        regsub -all {\]} $pt_summary_data  {\\]} pt_summary_data

        regsub -all {\[} $pt_node_datalist {\\[} pt_node_datalist
        regsub -all {\]} $pt_node_datalist {\\]} pt_node_datalist
        set expected_node_offset        $j
	if { $inputs(debug) }        { puts "<Debug>:             Step : Path Parsing / $idx report_type=$report_type | snps=$snpsreport_type | cdns=$cdnsreport_type" }

        # Stream Ref Header Summary
	if { $i == 1 } {
            puts $out_files_ptr(summary_csv) "$pt_summary_head"

            puts $out_files_ptr(gen_tcl)     "  set ref_summary_arr([format "ID%08d" -1])  \"$pt_summary_head\""
            puts $out_files_ptr(gen_tcl)     "  set tar_summary_arr([format "ID%08d" -1])  \"$pt_summary_head\""
            puts $out_files_ptr(gen_tcl)     "  puts \$out_files_ptr(summary_csv)          \"$pt_summary_head\""
            puts $out_files_ptr(gen_tcl)     "  regsub -all {\[^,|#\]} \$tar_summary_arr([format "ID%08d" -1]) {} missing_data_string\n"
            puts $out_files_ptr(gen_tcl)     "  # Path/Node Data Info ID00000000 Will Have Header as well to support quick compare !\n"

            puts $out_files_ptr(export_tcl)  "  # CSV Header Info"
            puts $out_files_ptr(export_tcl)  "  set ref_summary_arr([format "ID%08d" -1])  \"$pt_summary_head\"\n"
            puts $out_files_ptr(export_tcl)  "  # Path/Node Data Info ID00000000 Will Have Header as well to support quick compare !\n"
	}
	#if { $inputs(debug) }        { puts "<Debug>:             Step : Path Parsing / $idx Summary Header $pt_summary_head" }

        # Stream Ref Data Summary
        puts $out_files_ptr(summary_csv) "$pt_summary_data"
        puts $out_files_ptr(gen_tcl)     "  #Path ID=$idx"
        puts $out_files_ptr(gen_tcl)     "  set idx       $idx"
        puts $out_files_ptr(gen_tcl)     "  set tar_filex \$tool_path_rpt_dir/${max_min}path.$idx.txt\n"
        puts $out_files_ptr(export_tcl)  "\n  set ref_summary_arr($idx)  \"$pt_summary_data\""

	#if { $inputs(debug) }        { puts "<Debug>:             Step : Path Parsing / $idx Summary Data $pt_summary_data" }


        # Stream Ref Node Summary
       	foreach x $pt_node_datalist {
            puts $out_files_ptr(node_csv)    "$x"
            puts $out_files_ptr(gen_tcl)     "  set ref_node_arr($idx.[lindex [split $x ","] end])  \"$x\""
            puts $out_files_ptr(export_tcl)  "  set ref_node_arr($idx.[lindex [split $x ","] end])  \"$x\""
       	}
	if { $inputs(debug) }        { puts "<Debug>:             Step : Path Parsing / $idx Path Node Extracted $x" }

        puts $out_files_ptr(gen_tcl) [ssi_sta_caas_gen_template_2 $idx $slk_type $expected_node_offset $pt_summary_data]
	if { $inputs(debug) }        { puts "<Debug>:             Step : Path Parsing / $idx Path ReExtract Completed" }
    }
    if { $inputs(debug) }        { puts "<Debug>:             Step : Path Parsing / Completed" }

    #Path Correlation Section
    puts $out_files_ptr(gen_tcl) [ssi_sta_caas_gen_template_3 $paths]
    if { $inputs(debug) }        { puts "<Debug>:             Step : Path Correlation Section / $idx Path ReExtract Completed" }
    # Close All Files
    puts "\n"
    puts [format "<STA::CAAS::PROC> FileOP %-50s  [date]"   "ssi_sta_caas_profile_timingpath : Output Files"]
    foreach x [array names out_files_path] {
        puts [format "<STA::CAAS::PROC> FileOP %-50s"   "                              $out_files_path($x)"]
        close $out_files_ptr($x)
    }


 return
}


proc ssi_sta_caas_create_timing_paths { max_path_per_range pba_mode min_max scenario} {
# Proc : Report Timing Paths : ssi_sta_caas_create_timing_paths
    global CAAS_TOOL CAAS_TOOL_PLATFORM CORNER
    catch { suppress_message UITE-487 ; suppress_message UITE-502 } ; # PT Only

    set step_size   0.005
    set init_size   0.010
    set final_size -0.100
    set terminal_size -99999
    set slack_bins [list]
    while { $init_size >= $final_size } {
        lappend slack_bins $init_size
        set init_size [expr $init_size - $step_size]
    }
    lappend slack_bins $terminal_size
    set slack_bins_next [lrange $slack_bins 1 end]
    lappend slack_bins_next $terminal_size

    set path_groups [get_path_groups]
    set empty_collection [remove_from_collection [get_clocks] [get_clocks]]
    set paths $empty_collection
    puts [format "<STA::CAAS::PROC> PathsCol %-50s"  "$CAAS_TOOL_PLATFORM/$CAAS_TOOL"]

    foreach_in_collection pg $path_groups {
        foreach bin1 $slack_bins bin2 $slack_bins_next {
            if { $CAAS_TOOL_PLATFORM == "snps" } {
                set temp_paths [get_timing_paths -group $pg -slack_less $bin1 -slack_greater $bin2 -max_path $max_path_per_range -pba $pba_mode -delay $min_max -path_type full_clock_expanded ]
            } else {
                if { $min_max == "max" } { set min_max "late" }
                if { $min_max == "min" } { set min_max "early" }
                if { $pba_mode == "none" } { set retime_mode "none" }
                if { $pba_mode == "path" } { set retime_mode "path" }
                if { $pba_mode == "exhaustive" } { set retime_mode "exhaustive" }
                #puts "<CMD> report_timing -collection -path_group $pg -max_slack $bin1 -min_slack $bin2 -max_path $max_path_per_range -$min_max -path_type full_clock -view $scenario"
                if { $retime_mode == "none" } {
                    set temp_paths [report_timing -collection -path_group [get_object_name $pg] -max_slack $bin1 -min_slack $bin2 -max_path $max_path_per_range -$min_max -path_type full_clock -view $scenario]
                } else {
                    set temp_paths [report_timing -collection -path_group [get_object_name $pg] -max_slack $bin1 -min_slack $bin2 -max_path $max_path_per_range -retime_mode $retime_mode -$min_max -path_type full_clock -view $scenario]
                }
            }
            if {  [sizeof_collection $temp_paths] > 0 } {
                append_to_collection -unique paths $temp_paths
                puts "\t\t\t\t$scenario Group = [get_object_name $pg] | Slack Bins: $bin1 to $bin2 | Paths = [sizeof_collection $temp_paths] | All = [sizeof_collection $paths]"
            }

        }
    }
    catch { unsuppress_message UITE-487 ; unsuppress_message UITE-502 } ; # PT Only
    return $paths
}


CAAS_DEFINE_PROC_ARGS ssi_sta_caas_profile_timingpath \
    -info "dumps path data for is arguments for timing correlation" \
    -define_args  [list \
                        {-sort_collection       "Default : 0          " AString string optional} \
                        {-debug                 "Default : 0          " AString string optional} \
                        {-pba_mode              "Same as report_timing" AString string optional} \
                        {-slack_lesser_than     "Same as report_timing" AString string optional} \
                        {-tool                  "Default : Empty pt_shell , innovus , fc_shell" AString string optional} \
                        {-tag                   "Default : <DESIGN>.<MODE>.<PVT_RC_CORNER>" AString string optional} \
                        {-tar_prefix            "Default : {}" AString string optional} \
                        {-tar_scenario          "Default : set_tar_scenario" AString string optional} \
                        {-ref_scenario          "Default : set_ref_scenario" AString string optional} \
                        {-force_startend        "Default : 0 ignore repater arcs" AString string optional} \
                        {-tar_tool              "Default : ptx" AString string optional} \
                        {-max_min               "Default : min max" AString string optional} \
                        {-out_dir               "Default : \[pwd\]/paths_sta_corr" AString string optional} \
                        {-collection            "Profiled Path Collection" AString string required } \
                  ]

#   _   _      _   _ _     _        _             _ _ _
#  | \ | | ___| |_| (_)___| |_     / \  _   _  __| (_) |_
#  |  \| |/ _ \ __| | / __| __|   / _ \| | | |/ _` | | __|
#  | |\  |  __/ |_| | \__ \ |_   / ___ \ |_| | (_| | | |_
#  |_| \_|\___|\__|_|_|___/\__| /_/   \_\__,_|\__,_|_|\__|
#
#


proc ssi_sta_caas_gen_netlist_audit { outdir tool} {
    global CAAS_TOOL CAAS_TOOL_PLATFORM CORNER
    # Compare List for :
    #                           Port
    #                           Nets
    #                           Modules
    #                           SEQ
    #                           LAT
    #                           ICG
    #                           MAC
    #                           Combo
    #                           Buffers + Invertors

    file mkdir $outdir/$tool
    set design [lindex [split [lindex [get_object_name [current_design]] 0] ":"] 0]

    set file_prefix "$outdir/$tool/$design.netlist_audit"
    set summary   [open $file_prefix.summary.rpt   w+]
    set port_v    [open $file_prefix.port.rpt      w+]
    set libcell_v [open $file_prefix.libcell.rpt   w+]


    array unset netlist_audit_data
    set empty_collection [remove_from_collection [get_clocks *] [get_clocks *]]
    set nets             [get_nets  -hierarchical *]
    set port_i           [get_ports * -filter "direction==in"]
    set port_o           [get_ports * -filter "direction==out"]
    set port_io          [get_ports * -filter "direction==inout"]
    set cells            [get_cells -hierarchical *]

    set cells_hier       [filter_collection $cells "is_hierarchical==true"]
    set cells_real       [filter_collection $cells "is_hierarchical==false"]
    set cells_real_xseq  [filter_collection $cells_real "is_sequential==true"]
    set cells_real_xcom  [filter_collection $cells_real "is_sequential==false"]
    #puts "Done Level 0"

    # Level 1
    set netlist_audit_data(L1_00__________)   $empty_collection
    set netlist_audit_data(L1_01_NETS_ALL)    $nets

    set netlist_audit_data(L1_02_BUS_IN)      $empty_collection
    set netlist_audit_data(L1_03_BUS_OUT)     $empty_collection
    set netlist_audit_data(L1_04_BUS_INOUT)   $empty_collection

    set netlist_audit_data(L1_05_PORT_IN)     $port_i
    set netlist_audit_data(L1_06_PORT_OUT)    $port_o
    set netlist_audit_data(L1_07_PORT_INOUT)  $port_io

    set netlist_audit_data(L1_08_INST_ALL)    $cells
    set netlist_audit_data(L1_09_INST_HIER)   $cells_hier
    set netlist_audit_data(L1_10_INST_REAL)   $cells_real
    #puts "Done Level 1"

    # Level 2
    set netlist_audit_data(L2_00__________)   $netlist_audit_data(L1_10_INST_REAL)
    set netlist_audit_data(L2_01_INST_XSEQ)   $cells_real_xseq
    set netlist_audit_data(L2_02_INST_XCOM)   $cells_real_xcom
    #puts "Done Level 2"

    # Level 3 - Seq
    set xicg_cond        "(is_integrated_clock_gating_cell==true)"
    set xmem_cond        "(is_integrated_clock_gating_cell==false && is_memory_cell==true)"
    set xmac_cond        "(is_integrated_clock_gating_cell==false && is_macro_cell==true)"
    set xlat_cond        "(is_integrated_clock_gating_cell==false && (is_rise_edge_triggered==false && is_fall_edge_triggered==false) && (is_negative_level_sensitive==true  || is_positive_level_sensitive==true))"
    set xdff_cond        "(is_integrated_clock_gating_cell==false && (is_rise_edge_triggered==true  || is_fall_edge_triggered==true)  && (is_negative_level_sensitive==false && is_positive_level_sensitive==false))"

    set netlist_audit_data(L3_00__________)   $netlist_audit_data(L2_01_INST_XSEQ)
    set categ L3_01_INST_XICG ; set cond $xicg_cond ; set ref_col $cells_real_xseq ; set netlist_audit_data($categ) [filter_collection $ref_col $cond] ; set cells_real_xseq [remove_from_collection $cells_real_xseq $netlist_audit_data($categ)]
    set categ L3_02_INST_XMEM ; set cond $xmem_cond ; set ref_col $cells_real_xseq ; set netlist_audit_data($categ) [filter_collection $ref_col $cond] ; set cells_real_xseq [remove_from_collection $cells_real_xseq $netlist_audit_data($categ)]
    set categ L3_03_INST_XLAT ; set cond $xlat_cond ; set ref_col $cells_real_xseq ; set netlist_audit_data($categ) [filter_collection $ref_col $cond] ; set cells_real_xseq [remove_from_collection $cells_real_xseq $netlist_audit_data($categ)]
    set categ L3_04_INST_XDFF ; set cond $xdff_cond ; set ref_col $cells_real_xseq ; set netlist_audit_data($categ) [filter_collection $ref_col $cond] ; set cells_real_xseq [remove_from_collection $cells_real_xseq $netlist_audit_data($categ)]
    set categ L3_05_INST_XSEQ ; set cond ""         ; set ref_col $cells_real_xseq ; set netlist_audit_data($categ) $ref_col                           ; set cells_real_xseq [remove_from_collection $cells_real_xseq $netlist_audit_data($categ)]
    #puts "Done Level 3"

    # Level 4 - Com
    set xbuf_cond     "number_of_pins==2 && is_combinational==true"
    set xphy_cond     "number_of_pins==1 && is_combinational==true"
    #set xphy_cond     "is_clock_used_as_data==false && is_clock_used_as_clock==false"

    set netlist_audit_data(L4_00__________)   $netlist_audit_data(L2_02_INST_XCOM)
    set categ L4_01_INST_XREP ; set cond $xbuf_cond ; set ref_col $cells_real_xcom ; set netlist_audit_data($categ) [filter_collection $ref_col $cond] ; set cells_real_xcom [remove_from_collection $cells_real_xcom $netlist_audit_data($categ)]
    set categ L4_02_INST_XPHY ; set cond $xphy_cond ; set ref_col $cells_real_xcom ; set netlist_audit_data($categ) [filter_collection $ref_col $cond] ; set cells_real_xcom [remove_from_collection $cells_real_xcom $netlist_audit_data($categ)]
    set categ L4_03_INST_XCOM ; set cond ""         ; set ref_col $cells_real_xcom ; set netlist_audit_data($categ) $ref_col                           ; set cells_real_xcom [remove_from_collection $cells_real_xcom $netlist_audit_data($categ)]
    #puts "Done Level 4"
    #puts "Done Level 1-4"

    # Audit LibCell Data
    array unset libcell_array
    set ref_cell_mapping_list [lsearch -all -inline -regexp [array names netlist_audit_data] {^L3_0|^L4_0}]
    set ref_cell_mapping_list [lsort [lsearch -all -inline -not -regexp $ref_cell_mapping_list {________}]]
    puts $libcell_v "#Category,#Ref_Name,#Count"
    foreach xcateg $ref_cell_mapping_list {
        set cells $netlist_audit_data($xcateg)
        if {$CAAS_TOOL_PLATFORM == "snps" } {
            set ref_cells [get_attribute -quiet $cells ref_name]
        } else {
            set ref_cells [get_property -quiet $cells ref_name]
        }
        set ref_cells_u [lsort -unique $ref_cells]

        foreach xcell [lsort $ref_cells_u] {
            set cell_cnt [llength [lsearch -all -inline $ref_cells $xcell]]
            set libcell_array($xcateg,$xcell,$cell_cnt) 1
            puts $libcell_v "$xcateg,$xcell,$cell_cnt"
        }
    }
    #puts "Done Level 5"

    # Audit Port Data
    array unset port_array
    foreach_in_collection port [get_ports *] {
        set port_name [get_object_name $port]
        if {$CAAS_TOOL_PLATFORM == "snps" } {
            set port_dir  [get_attribute $port direction]
        } else {
            set port_dir  [get_property $port direction]
        }
        set bus_name $port_name
        regsub -all {\[\d+\]} $port_name {[*]} bus_name
        if { ![info exist port_array($port_dir,$bus_name)] } {
          set port_array($port_dir,$bus_name) $port
        } else {
          append_to_collection port_array($port_dir,$bus_name) $port
        }
    }
    #puts "Done Level 6"

    puts $port_v "#Direction,#Bus_ID,#Bus_Size,#Port_Name"
    foreach dir_bus [lsort [array names port_array]] {
        set port_size [sizeof_collection $port_array($dir_bus)]
        set dir [lindex [split $dir_bus ","] 0]
        foreach_in_collection port $port_array($dir_bus) {
            set port_name [get_object_name $port]
            puts $port_v "$dir_bus,$port_size,$port_name"
            if { $dir == "in"    } { append_to_collection -unique netlist_audit_data(L1_02_BUS_IN)     [index_collection $port_array($dir_bus) 0] }
            if { $dir == "out"   } { append_to_collection -unique netlist_audit_data(L1_03_BUS_OUT)    [index_collection $port_array($dir_bus) 0]}
            if { $dir == "inout" } { append_to_collection -unique netlist_audit_data(L1_04_BUS_INOUT)  [index_collection $port_array($dir_bus) 0]}
        }
    }

    # Audit Summary
    foreach x [lsort  [array names netlist_audit_data]] {
        puts $summary [format " %-20s   =  %15s  " $x [sizeof_collection $netlist_audit_data($x)]  ]
    }

    # Audit Configs
    if { $CAAS_TOOL_PLATFORM == "snps"} {  redirect  -file $file_prefix.config.rpt  {printvar -application } }
    if { $CAAS_TOOL_PLATFORM == "cdns"} {  redirect  -file $file_prefix.config.rpt  {report_globals        } }
    close $summary
    close $port_v
    close $libcell_v
    puts [format "<STA::CAAS::PROC> FileOP %-50s"   "$file_prefix.summary.rpt"]
    puts [format "<STA::CAAS::PROC> FileOP %-50s"   "$file_prefix.port.rpt"]
    puts [format "<STA::CAAS::PROC> FileOP %-50s"   "$file_prefix.libcell.rpt"]
    puts ""
}



#   ____
#  / ___| _   _ _ __ ___  _ __ ___   __ _ _ __ _   _
#  \___ \| | | | '_ ` _ \| '_ ` _ \ / _` | '__| | | |
#   ___) | |_| | | | | | | | | | | | (_| | |  | |_| |
#  |____/ \__,_|_| |_| |_|_| |_| |_|\__,_|_|   \__, |
#                                              |___/
#

# Master Gen All Correlation Data
proc ssi_sta_caas_gen_data { OUTDIR TAG user_corner_config_arr max_path_per_group_bin pba_mode slack_less force_startend netlist_setup_hold CAAS_TAR_TOOL} {
    global CAAS_TOOL CAAS_TOOL_PLATFORM CORNER
    set max_path        $max_path_per_group_bin
    set pba_mode        $pba_mode
    set slack_less      $slack_less
    set force_startend  $force_startend

    if { [regexp "netlist" $netlist_setup_hold] } {
        #==================================================================================================================
        # Non-Corner Config
        #==================================================================================================================
        # Netlist Audit Data generation
        ssi_sta_caas_gen_netlist_audit $OUTDIR $TAG/phy_db/$CORNER
    }

    if { [regexp "setup|hold" $netlist_setup_hold] } {
        #==================================================================================================================
        # Corner Config
        #==================================================================================================================
        upvar $user_corner_config_arr user_corner_config
        array unset setup_corner_config
        array unset hold_corner_config
        array set setup_corner_config {}
        array set hold_corner_config {}
        puts "\n\n"
	puts "  User Corner Config Defined: "
        parray user_corner_config
        puts "\n\n"
	if { $CAAS_TOOL_PLATFORM == "cdns" } {
	    set all_valid_setup [all_analysis_views -type setup]
	    set all_valid_hold  [all_analysis_views -type hold]
	    foreach corner [array name user_corner_config] {
	        set inv_corner $user_corner_config($corner)
	        if { [lsearch -exact $all_valid_setup $inv_corner] >= 0 } { set setup_corner_config($inv_corner) $corner }
	        if { [lsearch -exact $all_valid_hold $inv_corner]  >= 0 } { set hold_corner_config($inv_corner)  $corner }
	    }
	} else {
	    if { $CAAS_TOOL == "ptx" } {
	        foreach corner [array name user_corner_config] {
	            if { $CORNER == $corner } {
	                set hold_corner_config($corner)  $user_corner_config($corner)
	                set setup_corner_config($corner) $user_corner_config($corner)
	           }
	        }
	    }
	}

        set valid_setup_corners [array name setup_corner_config]
        set valid_hold_corners  [array name hold_corner_config]
        if { ![regexp "setup" $netlist_setup_hold] } { set valid_setup_corners [list] }
        if { ![regexp "hold"  $netlist_setup_hold] } { set valid_hold_corners  [list] }

	#==================================================================================================================
	# Timing Audit Data generation - Setup
	#==================================================================================================================
	foreach scenario $valid_setup_corners {
	    set min_max  "max"
	    set paths_max [ssi_sta_caas_create_timing_paths $max_path $pba_mode $min_max $scenario]
	    set paths     $paths_max
	    puts "  Sizeof Collection:($scenario/$min_max): [sizeof_collection $paths]"
	    ssi_sta_caas_profile_timingpath -force_startend $force_startend -tag $scenario -pba_mode $pba_mode -slack_lesser_than  $slack_less -max_min $min_max -out_dir $OUTDIR/$TAG/tmg_$min_max -collection $paths -tar_tool $CAAS_TAR_TOOL -tar_scenario  $setup_corner_config($scenario) -ref_scenario $scenario
	}
	#==================================================================================================================
	# Timing Audit Data generation - Hold
	#==================================================================================================================
	foreach scenario $valid_hold_corners {
	    set min_max  "min"
	    set paths_min [ssi_sta_caas_create_timing_paths $max_path $pba_mode $min_max $scenario]
	    set paths     $paths_min
	    puts "  Sizeof Collection :($scenario/$min_max): [sizeof_collection $paths]"
	    ssi_sta_caas_profile_timingpath -force_startend $force_startend -tag $scenario -pba_mode $pba_mode -slack_lesser_than $slack_less -max_min $min_max -out_dir $OUTDIR/$TAG/tmg_$min_max -collection $paths -tar_tool $CAAS_TAR_TOOL -tar_scenario  $hold_corner_config($scenario) -ref_scenario $scenario
	}
    }
}

# Master Overview Proc
proc ssi_sta_caas_get_procs {} {
        puts [format "<ssi_STA_CAAS::PROC> Start %-50s  [date]"   "ssi_sta_caas_get_procs : Following are the Preloaded ssi_sta_caas Process" ]
        set procs_in_scope  [lsort [info proc ssi_sta_caas*]]
        foreach x $procs_in_scope {
                puts  [format "                          - \033\[32m%-40s \033\[31m%-s\033\[0m" $x "[info args $x]"]
        }
}
