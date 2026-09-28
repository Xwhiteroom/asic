# This file shows how to generate a custom timing report which is very
# similar to the builtin 'report_timing -input_pins' command.  The
# main procedure is 'custom_report_timing'.  Any arguments specified
# are passed to the 'get_timing_paths' command.

define_user_attribute -quiet -type float -classes {net} total_steiner_length
define_user_attribute -quiet -type float -classes {net} total_route_length
define_user_attribute -quiet -type string -classes {net} route_data_string
define_user_attribute -quiet -type string -classes {net} physical_routing_rule
define_user_attribute -quiet -type string -classes {net} estimated_parasitic_info
#define_user_attribute -quiet -type string -classes {net} high_fanout_pin_count
define_user_attribute -quiet input_map -classes lib_pin -type string -import 

set fmt_check_dominant_exception 1
set fmt_max_cell_column_width 50
set fmt_path_count_parallel_threshold 100
set fmt_prev_next_slacks_input_map_filter 1

set fmt_disable_bucket_mode 0
#needs to be a float
set fmt_bucket_limit 50.0
set fmt_bucket_size  100

if {[info exists ::fmt_high_fanout_limit] == 0} {
    set ::fmt_high_fanout_limit 50
}
set fmt_vt_field_length 7
set fmt_vt_types  {}
set fmt_vt_regexp {}

if {[info exist ::P(FMT_SKIP_IPNAME_LIST)]} {
    array set ::FMTIPNames2Skip ""
    foreach ip2skip $::P(FMT_SKIP_IPNAME_LIST) {
        set ::FMTIPNames2Skip($ip2skip) 1
    }
} else {
    array set ::FMTIPNames2Skip ""
}

###############################################################################
# PROCEDURE: load_pcwlol_weights_file
#
# Load weighting factors from CSV file for weighted LOL counting
# File format: cell_name,weight_factor
###############################################################################
proc load_pcwlol_weights_file {file} {
    global pcwlol_weights_hash

    array set pcwlol_weights_hash {}

    if {[file exists $file] == 0} {
        echo "ERROR: PCWLOL weights file $file does not exist"
        return 0
    }

    if [catch {open $file r} fh] {
        echo "ERROR: Cannot open PCWLOL weights file $file: $fh"
        return 0
    }

    set line_count 0
    set first_line 1
    while {[gets $fh line] >= 0} {
        set line [string trim $line]
        if {$line == ""} {
            continue
        }
        set parts [split $line ","]
        if {[llength $parts] != 2} {
            echo "WARNING: Invalid line in weights file (line $line_count): $line"
            continue
        }
        set cell_name [string trim [lindex $parts 0]]
        set weight [string trim [lindex $parts 1]]

        if {![string is double $weight]} {
            # If this is the first line and weight is not numeric, assume it's a header
            if {$first_line} {
                set first_line 0
                continue
            }
            echo "WARNING: Invalid weight value for $cell_name: $weight"
            continue
        }
        # Clear flag after first valid line
        set first_line 0
        set pcwlol_weights_hash($cell_name) $weight
        incr line_count
    }
    close $fh

    echo "INFO: Loaded $line_count weighting factors from $file"
    return 1
}

###############################################################################
# PROCEDURE: get_cell_weight_factor
#
# Get the weighting factor for a given cell ref_name
# Returns the factor from the hash, or 1.0 if not found
###############################################################################
proc get_cell_weight_factor {ref_name} {
    global pcwlol_weights_hash

    if {[info exists pcwlol_weights_hash] == 0} {
        return 1.0
    }

    # Direct lookup
    if {[info exists pcwlol_weights_hash($ref_name)]} {
        return $pcwlol_weights_hash($ref_name)
    }

    # Default to 1.0 if not found - print warning
    puts stderr "WARNING: Missing weight for cell $ref_name, using default 1.0"
    return 1.0
}

proc fmt_load_vt_def {file} {
    global P
    global fmt_vt_types
    global fmt_vt_regexp
    global fmt_vt_field_length

    set fmt_vt_types  {}
    set fmt_vt_regexp {}
    #Min widths for printing 1(100%)
    set fmt_vt_field_length 7

    if {[file exists $file] == 0} {
        echo "ERROR: vt-def file $file does not exist, cannot print vt types in the fmt"
        return 0
    }
    if {[catch {source $file}] != 0} {
        echo "ERROR: failed to load vt-def file $file, cannot print vt types in the fmt"
        return 0
    }

    if {[array exists pt_opt_src_tags] != 1} {
        echo "ERROR: vt-def file $file did not defined pt_opt_src_tags array, cannot print vt types in the fmt"
        return 0
    }
    
    if {[info exists P(TIMING_FMT_VT_CHOICES)]} {
        foreach str $P(TIMING_FMT_VT_CHOICES) {
            if {[regexp {^(\S+)\:(\S+)} $str match orig_vt_name print_vt_name]} {
            } else {
                set orig_vt_name  $str
                set print_vt_name $str
            }
            if {[info exists pt_opt_src_tags($orig_vt_name)]} {
                set vt_len [string length $print_vt_name]
                if {$vt_len > $fmt_vt_field_length} {
                    set fmt_vt_field_length $vt_len
                }
                lappend fmt_vt_types  $print_vt_name
                lappend fmt_vt_regexp $pt_opt_src_tags($orig_vt_name)
            } else {
                echo "ERROR: $orig_vt_name was not defined in vt-def file $file, omitting"
            }
        }
    } else {
        foreach vt_type [array names pt_opt_src_tags] {
            if {[string compare $vt_type "any"] != 0} {
                set vt_len [string length $vt_type]
                if {$vt_len > $fmt_vt_field_length} {
                    set fmt_vt_field_length $vt_len
                }
                lappend fmt_vt_types  $vt_type
                lappend fmt_vt_regexp $pt_opt_src_tags($vt_type)
            }
        }
    }
    return 1
}

proc load_route_steiner_file {file} {
    if {[regexp {.gz$} $file]} {
        if [catch {open "| /tool/pandora64/.package/gzip-1.8/bin/zcat $file" r} myfh] {
            puts stderr "Cannot open $file: $myfh"
            return 0
        }
    } else {
        if [catch {open $file r} myfh] {
            puts stderr "Cannot open $file: $myfh"
            return 0
        }
    }

    set current_net ""

    while {[gets $myfh line] >= 0} {
        #reorder this so that our current format is first
        if {[catch {lassign $line the length of net netname is tot_len}]} {
            #puts stderr "ERROR: bad line\n\t$line"
            continue
        }
        
        if {$the eq {The}} {
            set current_net [get_net -quiet $netname]
            if {[sizeof $current_net] == 0} {continue}
            set_user_attribute -quiet $current_net total_steiner_length $tot_len
            set current_net {}
        }
    }
    close $myfh
    return 1
}

proc load_route_physical_file {file} {
    if {[regexp {.gz$} $file]} {
        if [catch {open "| /tool/pandora64/.package/gzip-1.8/bin/zcat $file" r} myfh] {
            puts stderr "Cannot open $file: $myfh"
            return 0
        }
    } else {
        if [catch {open $file r} myfh] {
            puts stderr "Cannot open $file: $myfh"
            return 0
        }
    }

    #Have we found a "complete" entry and can skip parsing until we find a new net name?
    #Start with 1 because we're going to be looking for the net name first
    set complete 1

    set current_net ""
    set route_data  ""
    set total_length 0
    while {[gets $myfh line] >= 0} {
        if {[catch {lassign $line first second}]} {
            #puts stderr "ERROR: bad line\n\t$line"
            continue
        }
        if {$complete == 1} {
            #IF we've completed a net, only look for the name and don't do anything else
            #All further parsing would be unnecessary
            if {$first eq {flat_net} || $first eq {full_name}} {
                #Set the net we're now working on 
                set current_net [get_net -quiet $second]
                #Found a new net mark complete to 0
                set complete 0
            }
            continue
        }
        if {$first eq {number_of_vias}} {
            #extract via info
            lappend route_data "V=$second"
        } elseif {$first eq {route_length}} {
            #extract route info
            set metal_list [lrange $line 1 end]
            
            foreach layer_info $metal_list {
                lassign $layer_info metal_name metal_length
                if {($metal_name ne {}) && [regexp {[0-9\.]+} $metal_length] && ($metal_length != 0)} {
                    lappend route_data "$metal_name=$metal_length"
                    set total_length [expr {$total_length + $metal_length}]
                }
            }
            if {$total_length != 0} {
                set est_length [get_attribute -quiet $current_net total_steiner_length]
                if {($est_length ne {}) && ($est_length != 0)} {
                    lappend route_data "R=[format %.3f [expr {$total_length/$est_length}]]"
                }
                lappend route_data "Total=$total_length"
            }
            set_user_attribute -quiet $current_net route_data_string [join $route_data { }]
            set_user_attribute -quiet $current_net total_route_length $total_length
            
            set current_net {}
            set route_data  {}
            set total_length 0

            set complete 1
        } 
    }
    #This whole "end of file" section should be unnecessary with the $complete method of finalizing a net
#    if {$current_net ne {}} {
#        if {$total_length != 0} {
#            set est_length [get_attribute -quiet $current_net total_steiner_length]
#            if {$est_length ne {}} {
#                lappend route_data "R=[format %.3f [expr {$total_length/$est_length}]]"
#            }
#            lappend route_data "Total=$total_length"
#        }
#        set_user_attribute -quiet $current_net route_data_string [join $route_data { }]
#        #set leaf_nets [get_nets -quiet -of_objects [get_pins -filter "direction != out" -quiet -leaf -of_objects $current_net] -boundary_type lower -filter "full_name != [get_attribute $current_net full_name]"]
#        #if {[sizeof_collection $leaf_nets] > 0} {
#        #    set_user_attribute -quiet $leaf_nets route_data_string [join $route_data { }]
#        #}
#    }
    close $myfh
    return 1
}


proc load_route_info_files {phys_file steiner_file {via_ladder_file ""} {ipname ""}} {
    global P
    set parse_options ""
    if {![file exists $phys_file]} {
        echo "ERROR>> Can't open Phys Route info file $phys_file"
        return 0
    }

    # this mean we have a generated tcl cmd file setting net route related attribute
    # no need to parse on the fly, just source it
    if { [regexp {\.tcl$} $phys_file] } {
        source $phys_file
        return
    }
    if {[string length $steiner_file] != 0} {
        if {![file exists $steiner_file]} {
            echo "ERROR>> Can't open Steiner Route file $steiner_file"
            return 0
        } else {
            set parse_options "-steiner $steiner_file"
        }
    }
    if {([string length $via_ladder_file] != 0) && !([file exists $via_ladder_file])} {
        echo "ERROR>> Can't open Via Ladder file $via_ladder_file"
        return 0
    }
    set scenario_name ""
    if {[info command current_scenario] == "current_scenario"} {
        set scenario_name "[current_scenario]."
    }
    set inst_list ""
    if {$ipname == ""} {
        set tmpfile "${scenario_name}[get_attribute [current_design] full_name].route_info.tcl"
    } else {
        global cell_to_inst
        global cell_to_inst_topcell

        if {![info exists cell_to_inst]} {
            build_cell_to_inst_map
        }
        set tmpfile "${scenario_name}$ipname.route_info.tcl"
        if [string match $ipname $cell_to_inst_topcell] {
            
        } elseif {[info exists cell_to_inst($ipname)]} {
            set parse_options "$parse_options -inst \"$cell_to_inst($ipname)\""
            set inst_list $cell_to_inst($ipname)
        } else {
        }
    }
    regsub -all {(/|\[|\])} $tmpfile {_} tmpfile
    
    set tmpfile "$::pt_tmp_dir/$tmpfile"
    eval "exec $P(FLOW_DIR)/$P(FAMILY)/scripts/timing/parse_route_files.pl $parse_options -physical $phys_file -output $tmpfile"
    source $tmpfile
    if {[string length $via_ladder_file] != 0} {
        load_route_via_ladder_file $via_ladder_file $inst_list
    }
    return 1;
}

proc load_route_via_ladder_file {file {ip_inst_list ""} {verbose 0}} {
    if {[regexp {.gz$} $file]} {
        if [catch {open "| /tool/pandora64/.package/gzip-1.8/bin/zcat $file" r} myfh] {
            puts stderr "Cannot open $file: $myfh"
            return 0
        }
    } else {
        if [catch {open $file r} myfh] {
            puts stderr "Cannot open $file: $myfh"
            return 0
        }
    }

    #Have we found a "complete" entry and can skip parsing until we find a new net name?
    #Start with 1 because we're going to be looking for the net name first
    set current_net ""
    set route_data  ""
    set total_length 0
    set start 0
    set count 0

    while {[gets $myfh line] >= 0} {
        if {[catch {lassign $line first l1 l2 l3 l4 l5 l6 l7 l8 l9 l10}]} {
            #puts stderr "ERROR: bad line\n\t$line"
            continue
        }
        
        if {$start == 0} {
            if {$first eq {Cell/pins}} {
                #if {[regexp {\s+Cell\/pins that have via ladders that match constraints} $line match]} {}
                if {"$l1 $l2 $l3 $l4 $l5 $l6 $l7" eq {that have via ladders that match constraints:}} {
                    if {$verbose} {
                        echo "Found beginning of ladder section in $file"
                    }
                    set start 1
                    set count 0
                    set missed 0
                } else {
                    set start 0
                }
            }
        } elseif {$first eq "Cell"} {
            set instance $l2
            set pinname  $l5
            set ladder   $l10

            #set instance [lindex $line 2]
            #set pinname  [lindex $line 5]
            #set ladder   [lindex $line 10]
            #if {[regexp {\s+Cell\s=\s(\S+)\sPin\s=\s(\S+)\s\*\sDerived\sLadder\s=\s(\S+)\s} $line match instance pinname ladder]} {}
            set pin_group ""
            if {[llength $ip_inst_list]} {
                set pin_list ""
                foreach ip_inst_name $ip_inst_list {
                    lappend pin_list "$ip_inst_list/${instance}/${pinname}"
                }
                set pin_group [get_pins -quiet $pin_list]
            } else {
                set pin_group [get_pins -quiet "${instance}/${pinname}"]
            }
            foreach_in_collection current_pin $pin_group {
                set current_net [get_nets -quiet -of_object $current_pin] 
                if {$current_net eq ""} {
                    incr missed
                    continue   
                }
                set current_string [get_attribute -quiet $current_net route_data_string]
                if {$current_string eq "" } {
                    #set current_net [get_net -segments -top_net_of_hierarchical_group -of_object [get_pin "${instance}/${pinname}"]]
                    #-filter option doesn't work
                    set current_net_segments [filter_collection [get_nets -quiet -segments -of_object $current_pin] "defined(route_data_string)"]
                    
                    if {[sizeof_collection $current_net_segments] > 0} {
                        set current_string [get_attribute -quiet [index_collection $current_net_segments 0] route_data_string]
                    }
                } 
                if {$current_string eq "" } {
                    incr missed
                    if {$verbose} {
                        echo "MISSED: ${instance}/${pinname}"
                    }
                    continue
                }
                
                set new_string "VL=$ladder $current_string"
                set_user_attribute -quiet $current_net route_data_string $new_string
                incr count
            }
            # echo "Updating route_data_string on net [get_object_name $current_net] to $new_string"
        } elseif {$first eq {Cell/pins}} {
            #if {[regexp {\s+Cell/pins that have constraints but do not have a via ladder} $line match]} {}
            if {"$l1 $l2 $l3 $l4 $l5 $l6 $l7 $l8 $l9 $l10" eq {that have constraints but do not have a via ladder:}} {
                if {$verbose} {
                    echo "Found end of ladder section in $file."
                    echo "Added $count VL= attributes.  Couldn't add $missed VL's"
                }
                set start 0
            }  
        }
    }
    close $myfh
    return 1
}

proc hier_load_route_data_files { cell_name phys_file {steiner_file ""} {via_ladder_file ""}} {
    global cell_to_inst
    global cell_to_inst_topcell

    if {![file exists $phys_file]} {
	echo "ERROR>> Can't open Phys Route info file $phys_file"
	return
    }
    if {([string length $steiner_file] != 0) && !([file exists $steiner_file])} {
        echo "ERROR>> Can't open Steiner Route file $steiner_file"
	return
    }

    if {![info exists cell_to_inst]} {
	build_cell_to_inst_map
    }

    if [string match $cell_name $cell_to_inst_topcell] {
        if {[string length $steiner_file] != 0} {
            load_route_steiner_file $steiner_file
        }
        load_route_physical_file $phys_file
        if {[string length $via_ladder_file] != 0} {
            load_route_via_ladder_file $via_ladder_file
        }
    } else {
        if {[info exists cell_to_inst($cell_name)]} {
            foreach inst_name $cell_to_inst($cell_name) {
                set myinst [current_instance $inst_name]
                if {[string compare $myinst "0"] != 0} {
                    if {[string length $steiner_file] != 0} {
                        load_route_steiner_file $steiner_file
                    }
                    load_route_physical_file $phys_file
                    if {[string length $via_ladder_file] != 0} {
                        load_route_via_ladder_file $via_ladder_file
                    }
                } else {
                    puts "ERROR: failed to switch to instance $inst_name ($cell_name)"
                }
                current_instance
            }
        } else {
            puts "WARNING: No design named \"$cell_name\" loaded, skipping $phys_file"
	}
    }
}

###############################################################################
# PROCEDURE: report_format_float
#
# Use this procedure to format a float other than with the default %g.
# Correctly handles INFINITY and UNINIT values.  Use the result as a 
# string, not a float.
###############################################################################
proc report_format_float {number {sig_digits 2}} {
#  catch {format $format_str $number}
  switch -exact -- $number {
    ""       { }
    UNINIT   { }
    INFINITY { }
    NA       { }
    default {
        set fnumber [format "%.${sig_digits}f" $number]
        if {[string length $fnumber] > [expr {$sig_digits + 6}]} {
            return [format "%.${sig_digits}g" $number]
        } else {
            return $fnumber
        }
    }
  }
  return $number;
}

###############################################################################
# PROCEDURE: report_convert_direction
#
# Maps pin direction attribute values into more descriptive words.
###############################################################################
proc report_convert_direction { dir } {
    switch -exact -- $dir {
	in { set result input }
	out { set result output }
	default { set result $dir }
    }
    return $result;
}

###############################################################################
# PROCEDURE: report_get_date
#
# Returns a string of the current date.
###############################################################################
proc report_get_date { } {
    set  input [open "| date"]
    set date [read -nonewline $input]
    close $input
    return $date
}

###############################################################################
# PROCEDURE: report_print_header
#
# Prints a report header for the current design.
###############################################################################
proc report_print_header {title} {
  global sh_product_version;
  echo "****************************************"
  echo [format "Report : %s" $title]
  echo [format "Design : %s" [get_object_name [current_design]]]
  echo [format "Version: %s" $sh_product_version]
  echo [format "Date   : %s" [report_get_date]]
  echo "****************************************\n"
}

###############################################################################
# PROCEDURE: report_get_info_string
#
# Return the summary info for a startpoint or endpoint.
###############################################################################
proc report_get_info_string { point clock_name is_level} {
  set info_string ""
  set edge_level ""
  set flop_latch "flip-flop"
  if {[string compare $clock_name ""] == 0} {
    set clocked_by_string ""
  } else {
    if {$is_level} {
      set edge_level "level-sensitive "
      set flop_latch "latch"
    } else {
      set edge_level "edge-triggered "
    }
    set clocked_by_string [format " clocked by %s" $clock_name]
  }
  if {[string compare [get_attribute $point object_class] "port"] == 0} {
    set point_name [get_attribute $point full_name]
    set direction [report_convert_direction [get_attribute $point direction]]
    if {[string compare $direction "out"]} {
      set edge_level ""
    }
    set info_string [format "%s (%s%s port%s)" $point_name $edge_level \
		     $direction $clocked_by_string]
  } else {
    set cell [get_cells -of_objects $point]
    set point_name [get_attribute $cell full_name]
    unset cell
    set info_string [format "%s (%s%s%s)" $point_name $edge_level $flop_latch\
		     $clocked_by_string]
  }
  return $info_string;
}   

proc _get_gater_pin_info {clkpin cell_column_width} {
    set clkpin_dir  [get_attribute $clkpin direction]
    
    set gater_pin ""
    set gater_net ""
    set src_type  ""
    if { ([string compare $clkpin_dir "out"] == 0) || ([string compare $clkpin_dir "internal"] == 0) } {
        set src_type "*int_clk*"
    } else {
        set gater_net [get_nets -top_net_of_hierarchical_group -of_object $clkpin -quiet]
        if {[sizeof_collection $gater_net] <= 0} {
            set src_type "*int_clk*"
        } else {
            if {[string compare $clkpin_dir "inout"] == 0} {
                set clkpin_name [get_attribute $clkpin full_name]
                set gaters [get_pins -leaf -quiet -of_object $gater_net -filter "(direction != in) && (direction != internal) && (full_name != $clkpin_name)"]
            } else {
                set gaters [get_pins -leaf -quiet -of_object $gater_net -filter "(direction != in) && (direction != internal)"]
            }
            if {[sizeof_collection $gaters] == 0 } {
                set net2port [get_ports -quiet -of_object $gater_net -filter "direction != out"]
                if {[sizeof_collection $net2port] == 0 } {
                    set src_type "*int_clk*"
                } else {
                    set src_type "*ext_clk*"
                }
            } else {
                set gater_pin [index_collection $gaters 0]

                set cell_name [get_attribute $gater_pin cell.ref_name]
                if {[expr {[string length $cell_name] + 2 }] > $cell_column_width} {
                    set cell_name2print "[string range $cell_name 0 [expr {$cell_column_width - 6}]]..."
                } else {
                    set cell_name2print $cell_name
                }
                set src_type "($cell_name2print)"
            }
        }
    }
    return [list $gater_pin $gater_net $src_type]
}

proc get_least_common_multiple {p q {sig_digit 2} {loop_limit 10}} {
    set scale [expr {10.0 * 10.0 ** $sig_digit}]
    set p [expr {int($p * $scale + 0.5 )} ]
    set q [expr {int($q * $scale + 0.5 )} ]

    set m [expr {$p * $q}]

    set result 0    
    if {!$m} {
        #DO NOTHING
    } else {
        set x 0;
        while {$x < $loop_limit} {
            set p [expr {$p % $q}]
            if {!$p} {
                set result [expr {($m / $q) / $scale }]
                break
            }
            set q [expr {$q % $p}]
            if {!$q} {
                set result [expr {($m / $p) / $scale }]
                break
            }   
        }
    }
    return $result
}

proc _gen_cycle_count {delta period {sig_digits 2}} {   
    set scale [expr {10.0 ** $sig_digits}]
    set cycle_count [expr {int($delta/$period * 10.0 * $scale + 0.5) / $scale} ]
    set int_cycle_count [expr {int($cycle_count)}]
    if {($cycle_count == $int_cycle_count) && ([expr $int_cycle_count % 5] == 0)} {
        return [expr {$int_cycle_count/10.0}]
    } else {
        return "1"
    }
}

proc get_path_cycle_count {path {is_max 1} {sig_digits 2}} {
    #INFO: Calculate path cycles
    #Rule 1: set_min/max_delay paths are always cycle count of 1 or 0.5
    #Rule 2: Transparent latch paths always have a cycle count of X
    #Rule 3: If the launch and capture clock don't match cycle count is always 1
    #Rule 4: Same head hold paths have cycle count of 1
    
    set is_mm_delay [_path_is_min_max_delay_check $path]
    
    if {([string compare [get_app_var timing_enable_through_paths] true] == 0)} {
        #CHECK CYCLE TIMES IF TRACINGING THROUGH LATCHES
        set start_is_level 0
        set end_is_level   0
    } else {
        set start_is_level [expr {![string compare [get_attribute $path startpoint_is_level_sensitive] "true"]}]
        set end_is_level [expr {![string compare [get_attribute $path endpoint_is_level_sensitive] "true"]}]
        if { $is_max && ($start_is_level || $end_is_level) } {
            if {$is_mm_delay} {
                return 1
            } else {
                return "X"
            }
        }
    }

    set start_clock  [get_attribute $path startpoint_clock -quiet]
    set end_clock    [get_attribute $path endpoint_clock -quiet]
    set cycle_count  1

    if {[string compare $start_clock ""] != 0} {
        set time_lent [get_attribute -quiet $path time_lent_to_startpoint]
        if {$time_lent > 0.0} {
            #Launched by transparent latches
            if {$is_mm_delay} {
                set cycle_count 1
            } else {
                set cycle_count "X"
            }
        } elseif { [string compare $end_clock ""] != 0 } {
            set start_clock_edge [get_attribute $path startpoint_clock_open_edge_value -quiet]
            set end_clock_edge   [get_attribute $path endpoint_clock_close_edge_value -quiet]

            if { ([string compare $start_clock_edge ""] == 0) || ([string compare $end_clock_edge ""] == 0)} {
                #SANITY CHECK
                set cycle_count 1
            } else {
                if { $end_clock_edge == $start_clock_edge } {
                    if {$is_mm_delay} {
                        set cycle_count 1
                    } elseif {$is_max} {
                        set cycle_count 0
                    } else {
                        set cycle_count 1
                    }
                } else {
                    set clock_edge_delta [expr {abs($end_clock_edge - $start_clock_edge)}]
                    set start_clock_period [get_attribute $start_clock period]
                    set end_clock_period   [get_attribute $end_clock period]
                    
                    if {($start_clock_period == 0) || ($end_clock_period == 0)} {
                        #GOOFY CASE THAT SHOULD NEVER HAPPEN
                        set cycle_count 1
                    } elseif {$start_clock_period == $end_clock_period} {
                        set cycle_count [_gen_cycle_count $clock_edge_delta $end_clock_period $sig_digits]
                    } elseif {$is_mm_delay} {
                        set cycle_count 1
                    } else {
                        set period_lcm [get_least_common_multiple $start_clock_period $end_clock_period $sig_digits]
                        
                        if {$period_lcm == 0} {
                            set cycle_count 1
                        } else {       
                            if {$start_clock_period < $end_clock_period} {
                                if {[expr {$period_lcm/$start_clock_period}] > 10} {
                                    set cycle_count 1
                                } else {
                                    set cycle_count [_gen_cycle_count $clock_edge_delta $start_clock_period $sig_digits]
                                }
                            } else {
                                if {[expr {$period_lcm/$end_clock_period}] > 10} {
                                    set cycle_count 1
                                } else {
                                    set cycle_count [_gen_cycle_count $clock_edge_delta $end_clock_period $sig_digits]
                                }
                            }
                        }
                    }
                }
            }
        } else {
            #UNCONSTRAINED NO CAPTURE CLOCK
        }
    } else {
        #UNCONSTRAINED NO LAUNCH CLOCK
    }
    
    return $cycle_count
}

proc get_path_weighted_slack {path cycle_count {is_max 1} {sig_digits 2}} {
    #Calculate weighted slack
    #Transitive slack.... ugh
    set slack [get_attribute $path slack]
    
    if { [string compare $slack INFINITY] == 0} {
        set weighted_slack "NA"
    } elseif { !$is_max || ($cycle_count == 0) } {
        #set weighted_slack [report_format_float $slack $sig_digits 0]
        set weighted_slack [format "%.${sig_digits}f" $slack]
    } elseif { [regexp {[a-zA-Z]+} $cycle_count] == 1} {
        #set weighted_slack [report_format_float $slack $sig_digits 0]
        set weighted_slack [format "%.${sig_digits}f" $slack]
    } else {
        #set weighted_slack [report_format_float [expr {$slack/$cycle_count}] $sig_digits 0]
        set weighted_slack [format "%.${sig_digits}f" [expr {$slack/$cycle_count}]]
    }
    return $weighted_slack
}

proc get_path_prev_slack {path {is_max 1} {sig_digits 2}} {
    if {[get_app_var timing_save_pin_arrival_and_slack] == false} {
        return "NA"
    }

    set startpoint [get_attribute $path startpoint]

    set prev_slack ""
    if {([string compare [get_attribute $startpoint object_class] "port"] == 0) || ([get_attribute -quiet $startpoint is_hierarchical]) } {
        set prev_slack "NA"
    } elseif {([get_attribute $startpoint cell.is_black_box] == true)} {
        #SKIP MACROS
        set prev_slack [get_attribute -quiet $startpoint cell.hdm_prev_slack ]
        if {[string compare $prev_slack ""] == 0} {
            set prev_slack "NA"
        }
    } else {
        if {([string compare [get_attribute $startpoint is_clock_pin] "true"] == 0)} {
            set is_clk_pin 1
        } else {
            set is_clk_pin 0
        }        
        set is_min_max_delay_check [_path_is_min_max_delay_check $path]
        set input_delay [get_attribute $path startpoint_input_delay_value -quiet]
        
        if { ([string compare $input_delay ""] != 0) || ($is_min_max_delay_check && !$is_clk_pin)} {
            #DON'T MESS w/ set_input_delay or set_min/max_delay paths
            set prev_slack "NA"
        } elseif { ([get_attribute $startpoint is_negative_level_sensitive_data_pin] || [get_attribute $startpoint is_positive_level_sensitive_data_pin]) } {
            set prev_slack [_get_worst_prioritized_slack $startpoint $is_max]
        } elseif {$is_clk_pin} {
            if { $is_max } {
                set timarcs [get_timing_arcs -from $startpoint -filter "(is_disabled == false) && (is_user_disabled == false) && sense =~ setup* && to_pin.is_data_pin == true"]
            } else {
                set timarcs [get_timing_arcs -from $startpoint -filter "(is_disabled == false) && (is_user_disabled == false) && sense =~ hold* && to_pin.is_data_pin == true"]
            }
            set dpins ""
            append_to_collection -unique dpins [get_attribute $timarcs to_pin]
            if {!$::fmt_prev_next_slacks_input_map_filter} {
                set prev_slack [_get_worst_prioritized_slack $dpins $is_max]
            } elseif {[sizeof_collection $dpins] > 1} {
                set startinst [get_attribute $startpoint cell.full_name]
                set qpoint [index_collection [get_attribute $path points] 1]
                if { \
                       ([string compare [get_attribute $qpoint "object.direction"] {out}] == 0) && \
                       ([string compare [get_attribute -quiet $qpoint object.cell.full_name] [get_attribute $startpoint cell.full_name]] == 0) \
                   } {
                    set input_map [get_attribute -quiet $qpoint object.lib_pin.input_map]
                    if {[string compare $input_map ""] != 0} {
                        array set map_hash {}
                        foreach map_pin $input_map {
                            set map_hash($map_pin) 1
                        }
                        set real_dpins ""
                        foreach_in_collection dpin $dpins {
                            set pin_name [get_attribute $dpin lib_pin_name]
                            if {[info exists map_hash($pin_name)]} {
                                append_to_collection real_dpins $dpin
                            }
                        }
                        set prev_slack [_get_worst_prioritized_slack $real_dpins $is_max]
                    } else {
                        #No input_map, assume all d-pins are ok
                        set prev_slack [_get_worst_prioritized_slack $dpins $is_max]
                    }
                } else {
                    #GOOFY CELL and/or path don't look for prev slack
                }
            } else {
                set prev_slack [_get_worst_prioritized_slack $dpins $is_max]
            }
            if {[string compare $prev_slack ""] == 0} {
                set prev_slack [get_attribute -quiet $startpoint cell.hdm_prev_slack ]
            }
        }
    }
    if {[string compare $prev_slack ""] == 0} {
        set prev_slack "NA"
    } elseif {([string compare $prev_slack INFINITY] == 0) || ([string compare $prev_slack NA] == 0) || ([string compare $prev_slack UNINIT] == 0)} {
        #DO NOTHING
    } else {
        set prev_slack [format "%.${sig_digits}f" $prev_slack]
    }
    return $prev_slack
}

proc _path_is_min_max_delay_check {path} {
    if {!$::fmt_check_dominant_exception} {
        return 0
    }
    set dominant_exception_type [get_attribute $path dominant_exception -quiet]
    if { [string compare $dominant_exception_type "min_max_delay"] == 0} {
        set min_max_check_value [get_attribute -quiet $path exception_delay]
        if {([string compare $min_max_check_value ""] == 0) || ([string compare $min_max_check_value "UNINIT"] == 0)} {
            return 0
        } else {
            return 1
        }
    } else {
        return 0
    }
}

proc get_efo_base_cell {library efo_base_cell_name} {
    set efo_base_cell [get_lib_cells -quiet -of_object $library -filter "base_name == $efo_base_cell_name"]
    if { [sizeof_collection $efo_base_cell] == 1} {
        return $efo_base_cell
    }
    set libname [get_attribute $library full_name]
    global efo_library_map
    if { [info exists efo_library_map] && [array exists efo_library_map] && [info exists efo_library_map($libname)]} {
        set efo_base_cell [get_lib_cell -quiet "$efo_library_map($libname)/$efo_base_cell_name"]
        if { [sizeof_collection $efo_base_cell] == 1} {
            return $efo_base_cell
        }
    }
    
    if { [regexp {([^\.]+)\.([^\.]+)\.(.+)} $libname match ipname type corner] } {
        #foundry A STYLE
        set efo_base_cell [get_lib_cell -quiet "*.$type.$corner/$efo_base_cell_name"]
        if { [sizeof_collection $efo_base_cell] == 1} {
            return $efo_base_cell
        }
        
    } elseif { [regexp {([^\_]+)\_([^\_]+)\_(.+)} $libname match ipname type corner] } {
        #foundry B STYLE
        set efo_base_cell [get_lib_cell -quiet "*_${type}_${corner}/$efo_base_cell_name"]
        if { [sizeof_collection $efo_base_cell] == 1} {
            return $efo_base_cell
        }
    }
    
    #LAZY CATCH ALL
    set efo_base_cell [get_lib_cell -quiet "*/$efo_base_cell_name"]
    if { [sizeof_collection $efo_base_cell] == 1} {
        return $efo_base_cell
    }
    return ""
}

proc calc_efo {pin dir {is_max 1}} {
    if { [get_attribute $pin is_hierarchical] } {
        return ""
    }
    
    if { $is_max} {
        set minMax "max"
    } else {
        set minMax "min"
    }
    set ceff [get_attribute -quiet $pin cached_ceff_${minMax}_${dir}]
    if { [string compare $ceff ""] == 0 } {
        return ""
    }
    global fmt_ceff_unit_fix
    if {[info exists fmt_ceff_unit_fix] == 0} {
        set design_cap_unit [get_attribute [get_design] capacitance_unit_in_farad]
        set fmt_ceff_unit_fix [expr {1e-12 / $design_cap_unit}]
    }
    
    set ceff [expr {$ceff * $fmt_ceff_unit_fix}]
    
    set scaled_lib_obj [get_attribute $pin receiver_model_scaling_libs_${minMax} -quiet]
    set cell_name [get_attribute [get_cells -of_object $pin] ref_name]
    set pin_name  [get_attribute $pin lib_pin_name]
    
    if {[sizeof_collection $scaled_lib_obj] >= 1} {
        set lib_obj  [index_collection $$scaled_lib_obj 0]
        set lib_cell [get_lib_cells -quiet -of_object $lib_obj -filter "base_name == $cell_name"]
        if { [sizeof_collection $lib_cell] == 0} {
            echo "ERROR: library [get_attribute $lib_obj full_name] doesn't have $cell_name for some reason???"
            return ""
        }
        set lib_pin  [get_lib_pins -quiet -of_object $lib_cell -filter "base_name == $pin_name"]
        if { [sizeof_collection $lib_pin] == 0} {
            echo "ERROR: library [get_attribute $lib_obj full_name]/$cell_name doesn't have a pin $pin_name for some reason???"
            return ""
        }
    } else {
        set lib_pin [get_lib_pins -of_object $pin]
    }
    set drive_res [get_attribute $lib_pin drive_resistance_${dir}]
    if { ([string compare $drive_res ""] == 0) || ($drive_res == 0)} {
        return ""
    }
    
    set library [get_libs -of_object [get_lib_cells -of_object $lib_pin]]
    
    #my $EFO_Basecell    = $Rev::rc->getValueNoSafety('Timing','efo_base_cell_name');
    #my $EFO_Baseinput   = $Rev::rc->getValueNoSafety('Timing','efo_base_inputpin_name');
    #my $EFO_Baseoutput  = $Rev::rc->getValueNoSafety('Timing','efo_base_outputpin_name');
    global efo_base_cell_name
    global efo_base_cell_input_name
    global efo_base_cell_output_name
    if { [info exists efo_base_cell_name] == 0 } {
        set efo_base_cell_name "inx1"
    }
    if { [info exists efo_base_cell_input_name] == 0 } {
        set efo_base_cell_input_name "A"
    }
    if { [info exists efo_base_cell_output_name] == 0 } {
        set efo_base_cell_output_name "Z"
    }
    
    #set efo_base_cell [get_lib_cells -of_object $library -filter "base_name == $efo_base_cell_name"]
    set efo_base_cell [get_efo_base_cell $library $efo_base_cell_name]
    if { [sizeof_collection $efo_base_cell] == 0} {
        #echo "ERROR: library [get_attribute $library full_name] has no base cell of name $efo_base_cell_name"
        return ""
    }
    set efo_base_input  [get_lib_pin -quiet -of_object $efo_base_cell -filter "base_name == $efo_base_cell_input_name"]
    set efo_base_output [get_lib_pin -quiet -of_object $efo_base_cell -filter "base_name == $efo_base_cell_output_name"]
    if { [sizeof_collection $efo_base_input] == 0} {
        #echo "ERROR: library [get_attribute $efo_base_cell full_name] has no input pin named $efo_base_cell_input_name"
        return ""
    }
    if { [sizeof_collection $efo_base_output] == 0} {
        #echo "ERROR: library [get_attribute $efo_base_cell full_name] has no output pin named $efo_base_cell_output_name"
        return ""
    }
    
    set base_input_cap_dir [get_attribute $efo_base_input pin_capacitance_${minMax}_${dir} -quiet]
    set base_input_cap [get_attribute $efo_base_input pin_capacitance]
    set base_drive_res [get_attribute $efo_base_output drive_resistance_${dir}]
    
    
    set drive_ratio [expr {$base_drive_res/$drive_res}]
    
    if { [string compare $base_input_cap_dir ""] != 0} {
        set optimal_cap [expr {$base_input_cap_dir * $drive_ratio}]
    } else {
        set optimal_cap [expr {$base_input_cap * $drive_ratio}]
    }
    if { $optimal_cap != 0 } {
        return [expr {$ceff / $optimal_cap}]
    } else {
        return ""
    }
}

proc gen_efo_report {{pins ""}} {
    if {[sizeof_collection $pins] == 0} {
        set pins [get_pins -hierarchical * -filter "is_hierarchical == false"]
    }
    foreach_in_collection pin $pins {
        set rise_efo [calc_efo $pin rise]
        set fall_efo [calc_efo $pin fall]
        
    }
    return 1
    
}
proc write_efo_table {libname} {
    set library [get_libs $libname -quiet]
    if { [sizeof_collection $library] == 0} {
        echo "ERROR: no library by $libname found!!"
        return 0
    }
    
    #my $EFO_Basecell    = $Rev::rc->getValueNoSafety('Timing','efo_base_cell_name');
    #my $EFO_Baseinput   = $Rev::rc->getValueNoSafety('Timing','efo_base_inputpin_name');
    #my $EFO_Baseoutput  = $Rev::rc->getValueNoSafety('Timing','efo_base_outputpin_name');   
    set base_efo_cell_name        "inx1"
    set base_efo_cell_input_name  "A"
    set base_efo_cell_output_name "Z"
    
    set base_efo_cell   [get_lib_cells -quiet -of_object $library -filter "base_name == $base_efo_cell_name"]
    if { [sizeof_collection $base_efo_cell] == 0} {
        echo "ERROR: library [get_attribute $library full_name] has no base cell of name $base_efo_cell_name"
        return 0
    }
    
    set base_efo_input  [get_lib_pin -quiet -of_object $base_efo_cell -filter "base_name == $base_efo_cell_input_name"]
    set base_efo_output [get_lib_pin -quiet -of_object $base_efo_cell -filter "base_name == $base_efo_cell_output_name"]
    if { [sizeof_collection $base_efo_input] == 0} {
        echo "ERROR: library [get_attribute $base_efo_cell full_name] has no input pin named $base_efo_cell_input_name"
        return 0
    }
    if { [sizeof_collection $base_efo_output] == 0} {
        echo "ERROR: library [get_attribute $base_efo_cell full_name] has no output pin named $base_efo_cell_output_name"
        return 0
    }
    
    set base_input_cap [get_attribute $base_efo_input pin_capacitance]
    set base_drive_res_rise [get_attribute $base_efo_output drive_resistance_rise]
    set base_drive_res_fall [get_attribute $base_efo_output drive_resistance_fall]
    
    foreach_in_collection libcell [sort_collection [get_lib_cells -of_object $library] base_name]  {
        set libcell_name [get_attribute $libcell base_name]
        foreach_in_collection outpin [get_lib_pins -quiet -of_object $libcell -filter "(pin_direction != in) && (pin_direction != internal)"] {
            set outpin_name [get_attribute $outpin base_name]
            set drive_res_rise [get_attribute $outpin drive_resistance_rise -quiet]
            set drive_res_fall [get_attribute $outpin drive_resistance_fall -quiet]
            if { ([string compare $drive_res_rise ""] == 0) || ($drive_res_rise == 0)} {
                set ratio_rise -1
            } else {
                set ratio_rise [expr {$base_drive_res_rise/$drive_res_rise}]
            }
            if { ([string compare $drive_res_fall ""] == 0) || ($drive_res_fall == 0)} {
                set ratio_fall -1
            } else {
                set ratio_fall [expr {$base_drive_res_fall/$drive_res_fall}]
            }
            set average [expr {($ratio_rise + $ratio_fall) /2 }]
            echo [format "%20s %10s %8.4f" $libcell_name $outpin_name $average] 
            #echo [format "%20s %10s %8.4f %8.4f %8.4f" $libcell_name $outpin_name $ratio_rise $ratio_fall $average] 
        }
    }
}

proc get_path_next_slack {path {is_max 1} {sig_digits 2}} {
    if {[get_app_var timing_save_pin_arrival_and_slack] == false} {
        return "NA"
    }
    set endpoint  [get_attribute $path endpoint]    
    set end_clock [get_attribute $path endpoint_clock -quiet]
    set clock_pin [get_attribute $path endpoint_clock_pin -quiet]

    set next_slack ""
    
    if { \
           ([string compare [get_attribute $endpoint object_class] "port"] == 0) || \
           ([get_attribute -quiet $endpoint is_hierarchical]) || \
           ([string compare [get_attribute $clock_pin object_class] "port"] == 0) \
       } {
        set next_slack "NA"
    } elseif {([get_attribute [get_cells -of_object $endpoint] is_black_box] == true)} {
        set next_slack [get_attribute -quiet $endpoint cell.hdm_next_slack ]
        if {[string compare $next_slack ""] == 0} {
        #SKIP MACROS
            set next_slack "NA"
        }
    } elseif { ([string compare $end_clock ""] == 0) || ([string compare $clock_pin ""] == 0)} {
        #SKIP goofy non-clocked endpoints
        set next_slack "NA"
    } elseif { \
                 ([string compare [get_attribute $clock_pin cell.full_name] [get_attribute $endpoint cell.full_name]] != 0) || \
                 ([string compare "**async_default**" [get_attribute -quiet $path path_group.full_name]] == 0) \
             } {
        #SKIP NON-SEQ and other goofy stuff
        set next_slack "NA"
    } else {
        if { ([get_attribute $endpoint is_negative_level_sensitive_data_pin] || [get_attribute $endpoint is_positive_level_sensitive_data_pin]) } {
            set timarcs [get_timing_arcs -from $endpoint -filter "(is_disabled == false) && (is_user_disabled == false) && (sense =~ *_unate || sense =~ rise_to_* || sense =~ fall_to_*)"]
            set qpins [get_attribute $timarcs to_pin]
        } else {
            set timarcs [get_timing_arcs -from $clock_pin -filter "(is_disabled == false) && (is_user_disabled == false) && (sense =~ *edge* || sense =~ rising_to_* || sense =~ falling_to_*)"]
            set qpins ""
            append_to_collection -unique qpins [get_attribute $timarcs to_pin]
            if {!$::fmt_prev_next_slacks_input_map_filter} {
                #Do nothing
            } elseif {[sizeof_collection $qpins] > 1} {
                if {[sizeof_collection [get_pins -of_object [get_cells -of_object $endpoint] -filter "is_data_pin == true"]] > 1} {
                    #DO NOTHING, since there is a single d pin no need to check for input_maps
                } else {
                    set imap_qpins [filter_collection $qpins "defined(lib_pin.input_map)"]
                    if {[sizeof_collection $imap_qpins] > 0} {
                        set real_qpins ""
                        set dpin_name [get_attribute $endpoint lib_pin_name]
                        foreach_in_collection qpin $imap_qpins {
                            foreach map_pin [get_attribute -quiet $qpin lib_pin.input_map] {
                                if {[string compare $dpin_name $map_pin] == 0} {
                                    append_to_collection real_qpins $qpin
                                    break
                                }
                            }
                        }
                        set qpins $real_qpins
                    } else {
                        #DO NOTHING, w/o any input maps assume all Q pins are valid next_pins
                    }
                }
            } else {
                #DO NOTHING, single q pin no point
            }
        }
        set next_slack [_get_worst_prioritized_slack $qpins $is_max]
        if {[string compare $next_slack ""] == 0} {
            set next_slack [get_attribute -quiet $endpoint cell.hdm_next_slack]
        }
    }
    if {[string compare $next_slack ""] == 0} {
        set next_slack "NA"
    } elseif {([string compare $next_slack INFINITY] == 0) || ([string compare $next_slack NA] == 0) || ([string compare $next_slack UNINIT] == 0)} {
        #DO NOTHING
    } else {
        set next_slack [format "%.${sig_digits}f" $next_slack]
    }
    return $next_slack
}

proc _get_prioritized_slack {pin {is_max 1}} {
    global fmt_slack_pecking_order
    
    if { ([info exists timrev_slack_pecking_order] == 0) } {
        set fmt_slack_pecking_order normal
    }
    
    if { $is_max} {
        set min_max "max"
    } else {
        set min_max "min"
    }
    set prioritized_rise_slack ""
    set prioritized_fall_slack ""
    
    foreach slacktype $fmt_slack_pecking_order {
        if { [string compare $slacktype conditional_pba] == 0 } {
            set current_rise_slack [get_attribute -quiet $pin pba_${min_max}_rise_slack]
            set current_fall_slack [get_attribute -quiet $pin pba_${min_max}_fall_slack]
        } elseif { [string compare $slacktype pba] == 0 } {
            set current_rise_slack [get_attribute -quiet $pin pba_${min_max}_rise_slack]
            set current_fall_slack [get_attribute -quiet $pin pba_${min_max}_fall_slack]
        } else {
            set current_rise_slack [get_attribute $pin ${min_max}_rise_slack]
            set current_fall_slack [get_attribute $pin ${min_max}_fall_slack]
            
        }
        if { ([string compare $prioritized_rise_slack ""] == 0) && \
               ([string compare $current_rise_slack "INFINITY"] != 0) && \
               ([string compare $current_rise_slack "NA"] != 0) && \
               ([string compare $current_rise_slack ""] != 0) \
           } {
            set prioritized_rise_slack $current_rise_slack
        }
        if { ([string compare $prioritized_fall_slack ""] == 0) && \
               ([string compare $current_fall_slack "INFINITY"] != 0) && \
               ([string compare $current_fall_slack "NA"] != 0) && \
               ([string compare $current_fall_slack ""] != 0) \
           } {
            set prioritized_fall_slack $current_fall_slack
        }
        if { ([string compare $prioritized_rise_slack ""] != 0) && ([string compare $prioritized_fall_slack ""] != 0) } {
            #FOUND MATCH QUIT
            break
        }
    }
    return [list $prioritized_rise_slack $prioritized_fall_slack]
}

proc _get_worst_prioritized_slack {pin {is_max 1}} {
    global fmt_slack_pecking_order
    
    if { ([info exists timrev_slack_pecking_order] == 0) } {
        set fmt_slack_pecking_order normal
    }
    
    if { $is_max} {
        set min_max "max"
    } else {
        set min_max "min"
    }
    set prioritized_rise_slack ""
    set prioritized_fall_slack ""
    
    foreach slacktype $fmt_slack_pecking_order {
        if { [string compare $slacktype conditional_pba] == 0 } {
            set current_rise_slacks [get_attribute -quiet $pin pba_${min_max}_rise_slack]
            set current_fall_slacks [get_attribute -quiet $pin pba_${min_max}_fall_slack]
        } elseif { [string compare $slacktype pba] == 0 } {
            set current_rise_slacks [get_attribute -quiet $pin pba_${min_max}_rise_slack]
            set current_fall_slacks [get_attribute -quiet $pin pba_${min_max}_fall_slack]
        } else {
            set current_rise_slacks [get_attribute $pin ${min_max}_rise_slack]
            set current_fall_slacks [get_attribute $pin ${min_max}_fall_slack]
            
        }
        set rise_value ""
        foreach rise_value $current_rise_slacks {
            if {([string compare $rise_value "INFINITY"] != 0) && \
                  ([string compare $rise_value "NA"] != 0) && \
                  ([string compare $rise_value ""] != 0) \
               } {
                if {([string compare $prioritized_rise_slack ""] == 0) || ($prioritized_rise_slack > $rise_value)} {
                    set prioritized_rise_slack $rise_value
                }
            }
        }

        set fall_value ""
        foreach fall_value $current_fall_slacks {
            if {([string compare $fall_value "INFINITY"] != 0) && \
                  ([string compare $fall_value "NA"] != 0) && \
                  ([string compare $fall_value ""] != 0) \
               } {
                if {([string compare $prioritized_fall_slack ""] == 0) || ($prioritized_fall_slack > $fall_value)} {
                    set prioritized_fall_slack $fall_value
                }   
            }
        }

        if { ([string compare $prioritized_rise_slack ""] != 0) && ([string compare $prioritized_fall_slack ""] != 0) } {
            #FOUND MATCH QUIT
            break
        }
    }
    if {[string compare $prioritized_rise_slack ""] == 0} {
        return $prioritized_fall_slack
    } elseif {[string compare $prioritized_fall_slack ""] == 0} {
        return $prioritized_rise_slack
    } elseif {$prioritized_rise_slack > $prioritized_fall_slack} {
        return $prioritized_fall_slack
    } else {
        return $prioritized_rise_slack
    }
}

proc _get_ipname {pin} {
    global DesignIPNames
    global FMTIPNames2Skip
    if {$pin == ""} {
        return ""
    }
    
    set obj_class [get_attribute -quiet $pin object_class]
    if {$obj_class == "port"} {
        return [get_attribute -quiet [current_design] full_name]
    } elseif {$obj_class == "cell"} {
        set leaf_inst $pin
    } else {
        set leaf_inst [get_cells -of_object $pin]
    }
    
    set orig_ipname [get_attribute -quiet $leaf_inst original_ref_name]

    if {$orig_ipname != ""} {
        set ipname $orig_ipname
    } else {
        set ipname [get_attribute -quiet $leaf_inst ref_name] 
    }
    
    set stripped_ipname ""
    
    set parent_list "parent_cell"
    while { ($ipname != "") && \
              !( \
                   [info exists DesignIPNames($ipname)] || \
                   ([regexp {(.+)_[0-9]+$} $ipname match stripped_ipname] && [info exists DesignIPNames($stripped_ipname)]) \
                   ) \
          } {
        
        set orig_ipname [get_attribute -quiet $leaf_inst "${parent_list}.original_ref_name"]
        if {$orig_ipname != ""} {
            set ipname $orig_ipname
        } else {
            set ipname [get_attribute -quiet $leaf_inst "${parent_list}.ref_name"]
        }
        set parent_list "$parent_list.parent_cell";
        set stripped_ipname ""
    }
    if {$stripped_ipname != ""} {
        set ipname $stripped_ipname
    }
    if {($ipname != "") && [info exists FMTIPNames2Skip($ipname)]} {
        return [_get_ipname [get_attribute -quiet $leaf_inst $parent_list]]
    } else {
        return $ipname
    }
}

proc _get_block_list {path_insts} {
    upvar "print_options" print_options
    global DesignIPNames

    set blocklist ""
    set top_design [get_attribute [current_design] full_name]
    if {$print_options(subblocks)} {
        set top_insts [filter_collection -regexp $path_insts {(is_hierarchical == true) || ((is_hierarchical == false) && (full_name !~ ".*\/.*"))}]
        set prevblock ""
        foreach_in_collection tinst $top_insts {
            set cell_name [get_attribute -quiet $tinst original_ref_name]
            if {$cell_name == ""} {
                set cell_name [get_attribute -quiet $tinst ref_name]
            }
            if {$cell_name != ""} {
                if {$cell_name != $prevblock} {
                    set prevblock $cell_name
                    lappend blocklist $cell_name
                }
            } elseif {[string compare [get_attribute -quiet $tinst is_hierarchical] false] == 0} {
                if {$top_design != $prevblock} {
                    set prevblock $top_design
                    lappend blocklist $top_design
                }
            }
        }
        if {[llength $blocklist] == 0} {
            set hinsts [filter_collection $path_insts  "is_hierarchical == true"]
            if {[sizeof_collection $hinsts] > 0} {
                set blocklist "X"
            } else {
                foreach_in_collection path_inst $path_insts {
                    set parent_cellname [get_attribute -quiet $path_inst "parent_cell.original_ref_name"]
                    if {$parent_cellname == ""} {
                        set parent_cellname [get_attribute -quiet $path_inst "parent_cell.ref_name"]
                    }
                    if {$parent_cellname == ""} {
                        set blocklist $parent_cellname
                        break
                    }
                }
            }
        }
        
    } elseif {!([info exists DesignIPNames]) || ([array size DesignIPNames] <= 0)} {
        #DO NOTHING YET
    } else {
        set top_insts [filter_collection -regexp $path_insts {(is_hierarchical == true) || ((is_hierarchical == false) && (full_name !~ ".*\/.*"))}]
        set prevblock ""
        foreach_in_collection tinst $top_insts {
            set ipname [_get_ipname $tinst]
            if {$ipname != ""} {
                if {$ipname != $prevblock} {
                    set prevblock $ipname
                    lappend blocklist $ipname
                }
            } elseif {[string compare [get_attribute -quiet $tinst is_hierarchical] false] == 0} {
                if {$top_design != $prevblock} {
                    set prevblock $top_design
                    lappend blocklist $top_design
                }
            }
        }
        if {[llength $blocklist] == 0} {
            foreach_in_collection path_inst $path_insts {
                set ipname [_get_ipname $path_inst]
                if {$ipname != ""} {
                    lappend blocklist $ipname
                    break
                }
            }
        }
    }
    if {[llength $blocklist] == 0} {
        return $top_design
    } else {
        return $blocklist
    }
}

proc print_custom_path_header {path {path_number 1} {segment_cnt 0} {is_max 1}} {    
    upvar "print_options" print_options
    global DesignIPNames

    #THIS GET USED SEVERAL TIMES SO CACHE IT
    set sig_digits $print_options(sig_digits)
    set fileID $print_options(fileID)
    
    set path_points [get_attribute $path points]
    set launch_clk_paths [get_attribute -quiet $path launch_clock_paths]
    set capture_clk_paths [get_attribute -quiet $path capture_clock_paths]
    
    #Default length is 11, IE length of *ideal_clk*
    set cell_column_width 11
    global fmt_max_cell_column_width
    
    set startpoint_ref ""
    set endpoint_ref ""
    
    set prev_point ""
    set prev_instname ""
    
    set path_insts [get_attribute -quiet [filter_collection $path_points "object.object_class==pin"] object.cell]
    foreach libcell_name [get_attribute -quiet $path_insts ref_name] {
        set cellname_length [string length $libcell_name]
        if {$cellname_length > $cell_column_width} {
            if {$cellname_length > $fmt_max_cell_column_width} {
                set cell_column_width $fmt_max_cell_column_width
                break
            } else {
                set cell_column_width $cellname_length
            }
        }
    }


    #if {[string compare [get_attribute -quiet $path startpoint.object_class] port] == 0} {
    #     lappend blocklist "*IO*"
    #}
    set blocklist [_get_block_list $path_insts]
    #if {[string compare [get_attribute -quiet $path endpoint.object_class] port] == 0} {
    #     lappend blocklist "*IO*"
    #}
    set startpoint_name ""
    set endpoint_name   ""
    if {[string compare $print_options(pin_mode) "net"] == 0} {
        set startpoint_ref ""
        set cnt 0
        foreach_in_collection point $path_points {
            if {([string compare [get_attribute $point object.object_class] "port"] == 0) ||
                ([string compare [get_attribute -quiet $point object.is_hierarchical] "true"] == 0)} {
                set startpoint_ref $point
                break
            }
            set dir [get_attribute $point object.direction]
            if {([string compare $dir "internal"] != 0)} {
                if {($cnt == 0) && (([string compare $dir "in"] == 0) || ([string compare $dir "inout"] == 0))} {
                    #TRY NEXT PIN
                } else {
                    set startpoint_ref $point
                    break
                }
            }
            incr cnt
        }
        
        set endpoint_ref ""
        for {set x [expr {[sizeof_collection $path_points] - 1}]} {$x > 0} {incr x -1} {
            set point [index_collection $path_points $x]
            if {([string compare [get_attribute $point object.object_class] "port"] == 0) ||
                ([string compare [get_attribute -quiet $point object.is_hierarchical] "true"] == 0)} {
                set endpoint_ref $point
                break
            }
            if {([string compare [get_attribute $point object.direction] "internal"] != 0)} {
                set endpoint_ref $point
                break
            }
        }
        
        #set drivers   [filter_collection $path_points "(object.class == port) || (object.is_hierarchical == true) || ((object.direction != internal) && (object.direction != in))"]
        #set recievers [filter_collection $path_points "(object.class == port) || (object.is_hierarchical == true) || ((object.direction != internal) && (object.direction != out))"]
        #set startpoint_ref [index_collection $drivers 0]
        if { ([string compare $startpoint_ref ""] != 0) } {
            set startpoint_name [get_attribute -quiet $startpoint_ref object.net.full_name]
            if {[string compare $startpoint_name ""] != 0} {
                set rise_fall [get_attribute $startpoint_ref rise_fall]
                if { [string compare $rise_fall "rise"] == 0 } {
                    set startpoint_name "$startpoint_name@R"
                } elseif { [string compare $rise_fall "fall"] == 0 } {
                    set startpoint_name "$startpoint_name@F"
                } else {
                    set startpoint_name "$startpoint_name@?"
                }
            }
        }
        
        #set endpoint_ref   [index_collection $recievers [expr {[sizeof_collection $recievers] - 1}]]
        if { ([string compare $endpoint_ref ""] != 0)} {
            set endpoint_name "[get_attribute -quiet $endpoint_ref object.net.full_name]"
            if {[string compare $endpoint_name ""] != 0} {
                set rise_fall [get_attribute $endpoint_ref rise_fall]
                if { [string compare $rise_fall "rise"] == 0 } {
                    set endpoint_name "$endpoint_name@R"
                } elseif { [string compare $rise_fall "fall"] == 0 } {
                    set endpoint_name "$endpoint_name@F"
                } else {
                    set endpoint_name "$endpoint_name@?"
                }
            }
        }
    }
    
    if { [string compare $startpoint_name ""] == 0 } {
        set start_point [index_collection $path_points 0]
        if {[string compare $print_options(pin_mode) "datapin"] == 0} {
            if { \
                   ([string compare [get_attribute $start_point object.object_class] "pin"] == 0) && \
                   ([string compare [get_attribute $start_point object.direction] "out"] != 0)} \
              {
                  set start_inst [get_attribute $start_point object.cell.full_name]                  
                  for {set x 1} {$x < [sizeof_collection $path_points]} {incr x} {
                      set next_point [index_collection $path_points $x]
                      if {[string compare [get_attribute $next_point object.object_class] "pin"] != 0} {
                          break
                      } else {
                          set next_pin_dir [get_attribute $next_point object.direction]
                          if {[string compare $next_pin_dir "internal"] == 0} {
                              continue
                          } elseif {[string compare $next_pin_dir "in"] == 0} {
                              #SCREWY INOUT PATH OR SOMETHING JUST USE ORIGNAL STARTPOINT
                              break
                          } else {
                              if {[string compare [get_attribute $next_point object.cell.full_name] $start_inst] == 0} {
                                  set start_point $next_point
                              } else {
                                  #SCREWY INOUT PATH OR SOMETHING JUST USE ORIGNAL STARTPOINT
                              }
                              break
                          }
                      }
                  }
              }
        }

        set startpoint_name [get_attribute $start_point object.full_name]
        set start_rise_fall [get_attribute $start_point rise_fall]
        if { [string compare $start_rise_fall "rise"] == 0 } {
            set startpoint_name "$startpoint_name@R"
        } elseif { [string compare $start_rise_fall "fall"] == 0 } {
            set startpoint_name "$startpoint_name@F"
        } else {
            set startpoint_name "$startpoint_name@?"
        }
    }
    if { [string compare $endpoint_name ""] == 0 } {
        set endpoint_name [get_attribute [get_attribute $path endpoint] full_name]
        set end_rise_fall [get_attribute [index_collection $path_points [expr {[sizeof_collection $path_points] - 1}]] rise_fall]
        if { [string compare $end_rise_fall "rise"] == 0 } {
            set endpoint_name "$endpoint_name@R"
        } elseif { [string compare $end_rise_fall "fall"] == 0 } {
            set endpoint_name "$endpoint_name@F"
        } else {
            set endpoint_name "$endpoint_name@?"
        }
    }
    #FINISH OFF THE COLUMN WIDTH BY CHECKING CLOCK NETWORKS
    set start_clock [get_attribute $path startpoint_clock -quiet]
    if { ([sizeof_collection $launch_clk_paths] == 0) } {
        if { ([string compare $start_clock ""] != 0) && ([get_attribute $start_clock propagated_clock])} {
            set gater_info [ _get_gater_pin_info [get_attribute [index_collection $path_points 0] object] $fmt_max_cell_column_width]
            set gater_cellname_length [string length [lindex $gater_info 2]]
            if {$gater_cellname_length > $cell_column_width} {
                set cell_column_width $gater_cellname_length
            }
        }
    } elseif {$cell_column_width < $fmt_max_cell_column_width} {
        foreach clk_cellname [get_attribute -quiet [get_attribute -quiet $launch_clk_paths points] object.cell.ref_name] {
            #BOZO: just blindly add 2 for () on gater name
            set cellname_length [expr {2 + [string length $clk_cellname]}]
            if {$cellname_length > $cell_column_width} {
                if {$cellname_length > $fmt_max_cell_column_width} {
                    set cell_column_width $fmt_max_cell_column_width
                    break
                } else {
                    set cell_column_width $cellname_length
                }
            }
        }
    }
    
    set end_clock [get_attribute $path endpoint_clock -quiet]
    if { ([sizeof_collection $capture_clk_paths] == 0) } {
        set output_delay [get_attribute $path endpoint_output_delay_value -quiet]
        if { [string compare $output_delay ""] != 0 } {
            #DO NOTHING SINCE *max_del* < 9
        } else {
            if  { ([string compare $end_clock ""] != 0) && ([get_attribute $end_clock propagated_clock])} {
                set clock_pin [get_attribute $path endpoint_clock_pin -quiet]       
                if {[string compare $clock_pin ""] != 0} {
                    set gater_info [ _get_gater_pin_info $clock_pin $fmt_max_cell_column_width] 
                    set gater_cellname_length [string length [lindex $gater_info 2]]
                    if {$gater_cellname_length > $cell_column_width} {
                        set cell_column_width $gater_cellname_length
                    } 
                }
            }
        }
    } elseif {$cell_column_width < $fmt_max_cell_column_width} {
        foreach clk_cellname [get_attribute -quiet [get_attribute -quiet $capture_clk_paths points] object.cell.ref_name] {
            #BOZO: just blindly add 2 for () on gater name
            set cellname_length [expr {2 + [string length $clk_cellname]}]
            if {$cellname_length > $cell_column_width} {
                if {$cellname_length > $fmt_max_cell_column_width} {
                    set cell_column_width $fmt_max_cell_column_width
                    break
                } else {
                    set cell_column_width $cellname_length
                }
            }
        }
    }
    set print_options(cell_column_width) $cell_column_width

    set blockstr "\# Blocks: $blocklist"

    if { $segment_cnt > 0 } {
        set path_number "$path_number.$segment_cnt"
    }
    
    set cycle_count [get_path_cycle_count $path $is_max $sig_digits]
    #set wslack_value [get_path_weighted_slack $path $cycle_count $is_max $sig_digits]
    
    #set prev_slack [get_path_prev_slack $path $is_max]
    #set next_slack [get_path_next_slack $path $is_max]
    
    #set total_delay  [get_attribute $path arrival]


    set worst_tran [lindex [lsort -decreasing -real [get_attribute -quiet $path_points transition]] 0]
    set worst_tran_percent "N/A"
    if  { [string compare $end_clock ""] != 0} {
        set end_clk_period [get_attribute $end_clock period]
        if {([string compare $end_clk_period ""] != 0) && ($end_clk_period > 0)} {
            set worst_tran_percent [format "%.2f" [expr {$worst_tran / $end_clk_period}]]
        }
    }

    set path_group [get_attribute $path path_group -quiet]
    if {[string compare $path_group ""] == 0} {
        set path_group_name "(none)"
    } else {
        set path_group_name [get_attribute $path_group full_name]
    }
    set path_type [get_attribute $path path_type]
    if { [get_attribute $path is_recalculated] } {
        set path_type "$path_type (recalculated)"
    }
    
    puts $fileID "\# Path: $path_number Start: $startpoint_name End: $endpoint_name";
    
    puts $fileID [format "\# Cycles: %s   Weighted_Slack: %s   Prev_Slack: %s   Next_Slack: %s" \
                    $cycle_count \
                    [get_path_weighted_slack $path $cycle_count $is_max $sig_digits] \
                    [get_path_prev_slack $path $is_max $sig_digits] \
                    [get_path_next_slack $path $is_max $sig_digits] \
                   ]
    

    puts $fileID [format "\# Path_Group: %s   Path_Type: %s\n# Start_Clock: %s    End_Clock: %s    Worst_Tran: %s(%s%%)\n$blockstr" \
                    $path_group_name \
                    $path_type \
                    [_get_clock_header_str $start_clock $sig_digits] \
                    [_get_clock_header_str $end_clock $sig_digits] \
                    [report_format_float $worst_tran $sig_digits] \
                    $worst_tran_percent \
                   ]

    if {$print_options(route_delay_threshold) >= 0} {
        set total_route_len   0
        set total_steiner_len 0
        set nets [get_nets -of_object [get_attribute -quiet $path_points object]]
        foreach route_len [get_attribute -quiet $nets total_route_length] {
            if {[string compare $route_len ""] != 0} {
                set total_route_len [expr {$total_route_len + $route_len}]
            }
        }
        foreach steiner_len [get_attribute -quiet $nets total_steiner_length] {
            if {[string compare $steiner_len ""] != 0} {
                set total_steiner_len [expr {$total_steiner_len + $steiner_len}]
            }
        }
        if {$total_steiner_len > 0} {
            set route_vs_steiner [format "%.3f" [expr {$total_route_len/$total_steiner_len}]]
        } else {
            set route_vs_steiner "N/A"
        }
        puts $fileID [format "\# Route_Distance: %.${sig_digits}f Route_Ratio: %s" \
                        $total_route_len \
                        $route_vs_steiner \
                       ]
    }

    if {$print_options(report_vt)} {
        set vt_typ_str ""
        set vt_cnt_str ""
        set total_cnt 0
        foreach libcell_name [get_attribute -quiet [add_to_collection -unique [filter_collection $path_insts "is_hierarchical == false"] {}] lib_cell.full_name] {
            for {set x 0} {$x < [llength $::fmt_vt_types]} {incr x} {
                if {[regexp [lindex $::fmt_vt_regexp $x] $libcell_name]} {
                    incr vt_count([lindex $::fmt_vt_types $x]) 
                    incr total_cnt
                    break
                }
            }
        }
        set vt_len [expr {[string length $total_cnt] + 9}]
        if {$vt_len < $::fmt_vt_field_length} {
            set vt_len $::fmt_vt_field_length
        }
        
        set vt_typ_str "\# VT_Types: "
        set vt_cnt_str "\# VT_Count: "
        foreach vt_type $::fmt_vt_types {
            if {[info exists vt_count($vt_type)]} {
                set cnt $vt_count($vt_type)
                set vt_typ_str [format "%s %${vt_len}s" $vt_typ_str $vt_type]
                set vt_cnt_str [format "%s %${vt_len}s" $vt_cnt_str "${cnt}\([format %.2f [expr {$cnt * 100.00/$total_cnt}]]%\)"]
            } else {                
                set vt_typ_str "$vt_typ_str [format %${vt_len}s $vt_type]"
                set vt_cnt_str "$vt_cnt_str [format %${vt_len}s 0(0%)]"
            }
        }
        puts $fileID "$vt_typ_str\n$vt_cnt_str"
    }

    if { $segment_cnt > 0 } {
        puts $fileID "\# Path Segment: #$segment_cnt"
    }
    
    set fw [expr {max(8,$sig_digits + 6)}]
    set float_line [make_dashed_line $fw]
    if {$print_options(show_xtalk)} {
        set header_format "%${fw}.${fw}s %${fw}.${fw}s %${fw}.${fw}s %3s %${cell_column_width}s %${fw}.${fw}s %${fw}.${fw}s"
        set delta_delay_str "NID"
        set delta_tran_str  "DTran"
        set dash_line "$float_line $float_line $float_line [make_dashed_line 3] [make_dashed_line $cell_column_width] $float_line $float_line"
    } else {
        set header_format "%${fw}.${fw}s %${fw}.${fw}s %s%3s %${cell_column_width}s %${fw}.${fw}s%s"
        set delta_delay_str ""
        set delta_tran_str  ""
        set dash_line "$float_line $float_line [make_dashed_line 3] [make_dashed_line $cell_column_width] $float_line"
    }
    
    set derate_str ""
    if {$print_options(show_derate)} {
        set header_format "$header_format %${fw}.${fw}s"
        set derate_str "Derate"
        set dash_line "$dash_line $float_line"
    } else {
        set header_format "$header_format%s"
    }
    
    set mean_str ""
    set sensit_str ""
    if {$print_options(show_variation)} {
        set header_format "$header_format %${fw}.${fw}s %${fw}.${fw}s"
        set mean_str "Mean"
        set sensit_str "Sensit"
        set dash_line "$dash_line $float_line $float_line"
    } else {
        set header_format "$header_format%s%s"
    }
    
    set voltage_str ""
    if {$print_options(show_volt)} {
        set header_format "$header_format %${fw}.${fw}s"
        set voltage_str "Voltage"
        set dash_line "$dash_line $float_line"
    } else {
        set header_format "$header_format%s"
    }
    set header_format "$header_format %${fw}.${fw}s %${fw}.${fw}s%s %${fw}.${fw}s%s   %s"
    set dash_line "$dash_line ${float_line} ${float_line}- ${float_line}-   [make_dashed_line 30]" 
    set header [format $header_format \
                  "Path" \
                  "Incr" \
                  $delta_delay_str \
                  "Dir" \
                  "Fanout" \
                  "Tran" \
                  $delta_tran_str \
                  $derate_str \
                  $mean_str \
                  $sensit_str \
                  $voltage_str \
                  "TotC" \
                  "Ceff" " " \
                  "GatC" " " \
                  "Instance or Net (arc)" \
                 ]
    puts $fileID "\n$header\n$dash_line"
    set print_options(format_str) $header_format
    #return 1
    return [expr {[string length $header] + 10}]
}

proc _get_clock_header_str {clock {sig_digits 2}}  {    
    if {[sizeof_collection $clock]} {
        set period [get_attribute -quiet $clock period]
        if {[string compare $period ""] == 0} {
            set period "??"
        } else {
            set period [format "%.${sig_digits}f" $period]
        }
        #set clock_name " \"[get_attribute $clock full_name] ($period)\""
        set clock_name " [get_attribute $clock full_name]\($period\)"
    } else {
        set clock_name "*NA*"
    }
    return $clock_name
}

proc print_custom_clock {clockobject printname edge_type edge_value \
                           latency time_lent uncertainty crpr path_margin external_delay_info min_max_check networkdelay \
                           clock_source_point gaterpoint endpoint \
                           {is_max 1} } {
    
    upvar "print_options" print_options
    
    #THIS GET USED SEVERAL TIMES SO CACHE IT
    set sig_digits $print_options(sig_digits)
    set sig_cap_digits $print_options(sig_cap_digits)
    set fileID $print_options(fileID)
    
    set full_name "$printname ([format %.${sig_digits}f $edge_value])"
    
    set rise_fall $edge_type
    set increment [expr {$latency + $time_lent}]
    
    set external_delay_type  [lindex $external_delay_info 0]
    set external_delay_value [lindex $external_delay_info 1]
    if { [string compare $external_delay_value ""] != 0 } {
        if { $is_max && ([string compare $external_delay_type "output"] == 0) } {
            set external_delay_value [expr {0.0 - $external_delay_value}]
        }
        
        #Clock Network is external so add it to the latency
        set latency   [expr {$latency + $networkdelay}]
        set increment [expr {$increment + $networkdelay + $external_delay_value}]
    }
    
    if { [string compare $rise_fall "rise"] == 0 } {
        set direction " R "
    } elseif { [string compare $rise_fall "fall"] == 0 } {
        set direction " F "
    } else {
        set direction " ? "
    }
    
    if { $latency != 0.0 } {
        #set full_name "$full_name latency: [report_format_float $latency $sig_digits 0]"
        set full_name "$full_name latency: [format %.${sig_digits}f $latency]"
        if {!$::timing_point_arrival_attribute_compatibility} {
            set networkdelay [expr {$networkdelay - $latency}]
        }
    }
    if { $time_lent != 0.0 } {
        #set full_name "$full_name time_lent: [report_format_float $time_lent $sig_digits 0]"
        set full_name "$full_name time_lent: [format %.${sig_digits}f $time_lent]"
        if {!$::timing_point_arrival_attribute_compatibility} {
            set networkdelay [expr {$networkdelay - $time_lent}]
        }
    }
    if { [string compare $external_delay_value ""] != 0 } {
        #set full_name "$full_name ExtDel: [report_format_float $external_delay_value $sig_digits 0]"
        set full_name "$full_name ExtDel: [format %.${sig_digits}f $external_delay_value]"
    }
    set arrival   [expr {$edge_value + $increment}]
    
    set startpoint_tran 0
    set endpoint_tran 0
    set gater_pin ""
    set gater_net ""
    set gater_print_str ""
   
    if { [string compare $clock_source_point ""] == 0 } {
        if { [string compare $endpoint ""] == 0 } {
            if { [string compare $external_delay_value ""] != 0 } {
                set src_type "*ext_clk*"
            } else {
                set src_type "*???_clk*"
            }
        } else {
            if { [string compare [get_attribute $endpoint object_class] timing_point] == 0 } {
                set endpin [get_attribute $endpoint object]
                set endpoint_tran [report_format_float [get_attribute $endpoint transition] $sig_digits]
            } else {
                set endpin $endpoint
            }
            
            if { [string compare [get_attribute $endpin object_class] "port"] == 0} {
                set src_type  "*ext_clk*"
            } elseif { [string compare $external_delay_value ""] != 0 } {
                set src_type "*ext_clk*"
            } else {
                #set clocksources [get_attribute $clockobject sources]
                if { [string compare $gaterpoint ""] != 0 } {
                    if { [string compare [get_attribute $gaterpoint object_class] timing_point] == 0 } {
                        set gater_pin [get_attribute $gaterpoint object]
                    } else {
                        set gater_pin $gaterpoint
                    }
                    set gater_net [get_nets -quiet -of_object $gater_pin]
                    if {([get_attribute $clockobject propagated_clock] == false)} {
                        set src_type "*ideal_clk*"
                    } elseif { [string compare [get_attribute $gater_pin object_class] "port"] == 0 } {
                        set src_type "*ext_clk*"
                    } else {
                        set cell_name [get_attribute $gater_pin cell.ref_name]
                        if {[expr {[string length $cell_name] + 2}] > $print_options(cell_column_width)} {
                            set cell_name2print "[string range $cell_name 0 [expr {$print_options(cell_column_width) - 6}]]..."
                        } else {
                            set cell_name2print $cell_name
                        }
                        set src_type "($cell_name2print)"
                    }
                } else {
                    set gater_pin_info [_get_gater_pin_info $endpin $print_options(cell_column_width)] 
                    set gater_pin [lindex $gater_pin_info 0]
                    set gater_net [lindex $gater_pin_info 1]
                    if {([get_attribute $clockobject propagated_clock] == false)} {
                        set src_type "*ideal_clk*"
                    } else {
                        set src_type  [lindex $gater_pin_info 2]
                    }
                }
            }
            
        }
    } elseif {([get_attribute $clockobject propagated_clock] == false)} {
        set src_type "*ideal_clk*"
    } else {
        if { [string compare [get_attribute $clock_source_point object_class] timing_point] == 0 } {
            set startobj [get_attribute $clock_source_point object]
        } else {
            set startobj $clock_source_point
        }
        if { [string compare [get_attribute $startobj object_class] "pin"] == 0 } {
            set src_type "*gen_clk*"
        } else {
            set src_type "*ext_clk*"
        }
    }

    set gater_netdata [list "ZL" "-" "-"]
    if { [string compare $gater_net ""] != 0 } {
        set fanout [get_attribute -quiet $gater_net number_of_leaf_loads]
        set gater_arrival [expr {$arrival + $networkdelay}]
        
        if {$is_max} {
            set pincap [get_attribute -quiet $gater_net pin_capacitance_max_${rise_fall}]
            set total_cap [get_attribute -quiet $gater_net total_capacitance_max]
            if { [string compare $gater_pin ""] != 0 } {
                set ceff [get_attribute -quiet $gater_pin cached_ceff_max_${rise_fall}]
            } else {
                set ceff 0.0
            }
        } else {
            set total_cap [get_attribute -quiet $gater_net total_capacitance_min]
            set pincap [get_attribute -quiet $gater_net pin_capacitance_min_${rise_fall}]
            if { [string compare $gater_pin ""] != 0 } {
                set ceff [get_attribute -quiet $gater_pin cached_ceff_min_${rise_fall}]
            } else {
                set ceff 0.0
            }
        }
        
        if {[string length $total_cap] == 0} {
            set total_cap 0.0
        }
        if {[string length $pincap] == 0} {
            set pincap 0.0
        }
        if {[string length $ceff] == 0} {
            set ceff 0.0
        } else {
            global fmt_ceff_unit_fix
            if {[info exists fmt_ceff_unit_fix] == 0} {
                set design_cap_unit [get_attribute [get_design] capacitance_unit_in_farad]
                set fmt_ceff_unit_fix [expr {1e-12 / $design_cap_unit}]
            }
            set ceff [expr {$ceff * $fmt_ceff_unit_fix}]
        }
        if {[get_attribute $gater_net has_valid_parasitics]} {
            set rctype "RC"
        } else {
            set rctype "ZL"
        }
        if {$total_cap != 0.0} {
            set ceff_vs_totalc [expr {$ceff/$total_cap * 100}]
            set gatc_vs_totalc [expr {$pincap/$total_cap * 100}]
        } else {
            set ceff_vs_totalc 0.0
            set gatc_vs_totalc 0.0
        }
        
        set gater_netdata [list $rctype $ceff_vs_totalc $gatc_vs_totalc ]
        
        set gater_derate_str ""
        if {$print_options(show_derate)} {
            set gater_derate_str "-" 
        }
        
        set gater_mean_str ""
        set gater_sensit_str ""
        if { $print_options(show_variation)} {
            set gater_mean_str "-"
            set gater_sensit_str "-"
        }
        
        set gater_volt_str ""
        if {$print_options(show_volt)} {
            set gater_volt_str "-"
        }
        
        if {$print_options(show_xtalk)} {
            set gater_delta_delay "-"
            set gater_delta_tran "-"
        } else {
            set gater_delta_delay ""
            set gater_delta_tran ""
        }
        set gater_print_str [format $print_options(format_str) \
                               [report_format_float $gater_arrival $sig_digits] \
                               [report_format_float $networkdelay  $sig_digits] \
                               $gater_delta_delay \
                               $direction \
                               $fanout \
                               $endpoint_tran \
                               $gater_delta_tran \
                               $gater_derate_str \
                               $gater_mean_str \
                               $gater_sensit_str \
                               $gater_volt_str \
                               [report_format_float $total_cap $sig_cap_digits] \
                               [report_format_float $ceff $sig_cap_digits] " "\
                               [report_format_float $pincap $sig_cap_digits] " "\
                               [get_attribute $gater_net full_name] \
                              ]
    }
    
    set clk_tran "-"
    
    set clk_derate_str ""
    if {$print_options(show_derate)} {
        set clk_derate_str "-" 
    }
    
    set clk_mean_str ""
    set clk_sensit_str ""
    if { $print_options(show_variation)} {
        set clk_mean_str "-"
        set clk_sensit_str "-"
    }
    
    set clk_volt_str ""
    if {$print_options(show_volt)} {
        set clk_volt_str "-"
    }
    
    set clk_rctype "-"
    set clk_ceff_vs_totc "-"
    set clk_gate_vs_totc "-"
    set clk_ceff_vs_totc_percent " "
    set clk_gate_vs_totc_percent " "
    
    
    if {$print_options(show_xtalk)} {
        #set clk_delta_delay "-"
        #set clk_delta_tran  "-"
        set clk_delta_delay " "
        set clk_delta_tran  " "
    } else {
        set clk_delta_delay ""
        set clk_delta_tran  ""
    }
    
    puts $fileID [format $print_options(format_str) \
                    [report_format_float $arrival $sig_digits] \
                    [report_format_float $increment $sig_digits] \
                    $clk_delta_delay \
                    $direction \
                    $src_type \
                    $clk_tran \
                    $clk_delta_tran \
                    $clk_derate_str \
                    $clk_mean_str \
                    $clk_sensit_str \
                    $clk_volt_str \
                    $clk_rctype \
                    $clk_ceff_vs_totc $clk_ceff_vs_totc_percent \
                    $clk_gate_vs_totc $clk_gate_vs_totc_percent \
                    $full_name \
                   ]
    
    if { [string length $gater_print_str] > 0} {
        puts $fileID $gater_print_str
    }
    
    return $gater_netdata
}

proc print_custom_path_modification {arrival value type} {
    upvar "print_options" print_options
    
    #THIS GET USED SEVERAL TIMES SO CACHE IT
    set sig_digits $print_options(sig_digits)
    set fileID $print_options(fileID)
        
    set rctype "-" 
    set ceff_vs_totc "-"
    set ceff_vs_totc_percent " "
    set gate_vs_totc "-"
    set gate_vs_totc_percent " "
    
    set transition_time "-"

    set direction " - "
    set arrival [expr {$arrival + $value}]

    if {$print_options(show_derate)} {
        set derate_str "-"
    } else {
        set derate_str ""
    }

    if {$print_options(show_variation)} {
        set mean_str "-"
        set sensit_str "-"
    } else {
        set mean_str ""
        set sensit_str ""
    }
    
    if {$print_options(show_volt)} {
        set voltage_str "-"
    } else {
        set voltage_str ""
    }
    
    if {$print_options(show_xtalk)} {
        set delta_delay " "
        set delta_tran  " "
        #set delta_delay [get_attribute -quiet $port_point annotated_delay_delta]
        #set delta_tran  [get_attribute -quiet $port_point annotated_delta_transition]
        #if { [string compare $delta_delay ""] == 0 } {
        #    set delta_delay 0.0
        #}
        #if { [string compare $delta_tran ""] == 0 } {
        #    set delta_tran 0.0
        #}
        #set delta_delay [report_format_float $delta_delay "%.${sig_digits}f"]
        #set delta_tran  [report_format_float $delta_tran  "%.${sig_digits}f"]
    } else {
        set delta_delay ""
        set delta_tran  ""
    }
    
    puts $fileID [format $print_options(format_str) \
                    [report_format_float $arrival $sig_digits] \
                    [report_format_float $value $sig_digits] \
                    $delta_delay \
                    $direction \
                    "-" \
                    $transition_time \
                    $delta_tran \
                    $derate_str \
                    $mean_str \
                    $sensit_str \
                    $voltage_str \
                    $rctype \
                    $ceff_vs_totc $ceff_vs_totc_percent \
                    $gate_vs_totc $gate_vs_totc_percent \
                    $type \
                   ]
    return $arrival
}

proc print_custom_port {port_point external_delay_info netvalues startpoint_arrival {is_max 1}} {
    upvar "print_options" print_options
    
    #THIS GET USED SEVERAL TIMES SO CACHE IT
    set sig_digits $print_options(sig_digits)
    set fileID $print_options(fileID)
    
    set port_dir  "([get_attribute $port_point object.direction])"
    set full_name [get_attribute $port_point object.full_name]
    
    set external_delay_type  [lindex $external_delay_info 0]
    set external_delay_value [lindex $external_delay_info 1]
    if { [string compare $external_delay_value ""] == 0 } {
        set external_delay_value 0.0
    }
    
    if { [string compare $external_delay_type "min_max"] == 0} {
        if {$is_max} {
            set external_delay_type "maxdel"
        } else {
            set external_delay_type "mindel"
        }
    }
    
    set rctype [lindex $netvalues 0]
    set ceff_vs_totc [lindex $netvalues 1]
    set gate_vs_totc [lindex $netvalues 2]
    if {[string compare $ceff_vs_totc "-"] != 0} {
        set ceff_vs_totc [format "%.2f" $ceff_vs_totc]
        set ceff_vs_totc_percent "%"
    } else {
        set ceff_vs_totc "-"
        set ceff_vs_totc_percent " "
    }
    if {[string compare $gate_vs_totc "-"] != 0} {
        set gate_vs_totc [format "%.2f" $gate_vs_totc]
        set gate_vs_totc_percent "%"
    } else {
        set gate_vs_totc "-"
        set gate_vs_totc_percent " "
    }
    
    set arrival [expr {[get_attribute $port_point arrival] + $startpoint_arrival}]
    if {[string compare $external_delay_type "output"] == 0} {
        set arrival [expr {$arrival + $external_delay_value}]
        if {$is_max} {
            set transition_time "extmax"
        } else {
            set transition_time "extmin"
        }
    } elseif {([string compare $external_delay_type "extdel"] == 0)} {
        set arrival [expr {$arrival + $external_delay_value}]
        if {$is_max} {
            set transition_time "extmax"
        } else {
            set transition_time "extmin"
        }
    } elseif {([string compare $external_delay_type maxdel] == 0) || ([string compare $external_delay_type mindel] == 0)} {
        set arrival $external_delay_value
        set transition_time $external_delay_type
    } else {
        set transition_time [report_format_float [get_attribute $port_point transition] $sig_digits]
    }
    
    set rise_fall [get_attribute $port_point rise_fall]
    
    if { [string compare $rise_fall "rise"] == 0 } {
        set direction " R "
    } elseif { [string compare $rise_fall "fall"] == 0 } {
        set direction " F "
    } else {
        set direction " ? "
    }
    
    set derate_str ""
    if {$print_options(show_derate)} {
        set derate_str "-"
    }
    set mean_str ""
    set sensit_str ""
    if {$print_options(show_variation)} {
        set mean_str "-"
        set sensit_str "-"
    }
    
    set voltage_str ""
    if {$print_options(show_volt)} {
        set volt [get_attribute $port_point voltage -quiet]
        if {($volt == "") || ([string compare $volt UNINIT] == 0)} {
            set voltage_str "-"
        } else {
            set voltage_str [report_format_float $volt $sig_digits]
        }
    }
    
    if {$print_options(show_xtalk)} {
        set delta_delay " "
        set delta_tran  " "
        #set delta_delay [get_attribute -quiet $port_point annotated_delay_delta]
        #set delta_tran  [get_attribute -quiet $port_point annotated_delta_transition]
        #if { [string compare $delta_delay ""] == 0 } {
        #    set delta_delay 0.0
        #}
        #if { [string compare $delta_tran ""] == 0 } {
        #    set delta_tran 0.0
        #}
        #set delta_delay [report_format_float $delta_delay "%.${sig_digits}f"]
        #set delta_tran  [report_format_float $delta_tran  "%.${sig_digits}f"]
    } else {
        set delta_delay ""
        set delta_tran  ""
    }
    
    set print_str [format $print_options(format_str) \
                    [report_format_float $arrival $sig_digits] \
                    [report_format_float $external_delay_value $sig_digits] \
                    $delta_delay \
                    $direction \
                    $port_dir \
                    $transition_time \
                    $delta_tran \
                    $derate_str \
                    $mean_str \
                    $sensit_str \
                    $voltage_str \
                    $rctype \
                    $ceff_vs_totc $ceff_vs_totc_percent \
                    $gate_vs_totc $gate_vs_totc_percent \
                    $full_name \
                   ]
    puts $fileID $print_str
    if {$print_options(physical)} {
        set loc_str [_get_location_str $port_point ""]
        if {$loc_str != ""} {
            set whitespace_padding [expr {[string length $print_str] - [string length $full_name] - 4}]
            puts $fileID [format "\#LOC\#\#%${whitespace_padding}s %s" " " $loc_str]
        }
    }
    
    return $arrival
}

proc calc_mean_and_sensit_values {pointA pointB {sig_digits 2}} {
    set mean_str "-"
    set sensit_str "-"
    set prev_variation_arrival    [get_attribute -quiet $pointA variation_arrival]
    set current_variation_arrival [get_attribute -quiet $pointB variation_arrival]
    if {([sizeof_collection $prev_variation_arrival] == 1) && ([sizeof_collection $current_variation_arrival] == 1)} {
        set prev_mean    [get_attribute -quiet $prev_variation_arrival    mean]
        set current_mean [get_attribute -quiet $current_variation_arrival mean]
        if {([string compare $prev_mean ""] != 0) && ([string compare $current_mean ""] != 0)} {
            set mean_str [report_format_float [expr {$current_mean - $prev_mean}] $sig_digits]
        }
        set prev_std_dev    [get_attribute -quiet $prev_variation_arrival    std_dev]
        set current_std_dev [get_attribute -quiet $current_variation_arrival std_dev]
        if {([string compare $prev_std_dev ""] != 0) && ([string compare $current_std_dev ""] != 0) && ([expr abs($current_std_dev)] > [expr abs($prev_std_dev)])} {
            set sensit_str [report_format_float [expr {sqrt(($current_std_dev)**2 - ($prev_std_dev)**2)}] $sig_digits]
        }
    }
    return "$mean_str $sensit_str"
}

proc calc_crpr_value {path} {
    if {[string compare [get_app_var timing_pocvm_enable_analysis] false] == 0} {
        set crpr_value [get_attribute -quiet $path common_path_pessimism]
        if {[string compare $crpr_value ""] == 0} {
            return 0
        } else {
            return $crpr_value
        }
    }
    set ep_cp_sigma [get_attribute -quiet $path variation_endpoint_clock_latency.std_dev]
    set crpr_mean   [get_attribute -quiet $path variation_common_path_pessimism.mean]
    set crpr_sigma  [get_attribute -quiet $path variation_common_path_pessimism.std_dev]

    if {($ep_cp_sigma == "") || ($crpr_mean == "") || ($crpr_sigma == "")} {
        return 0
    }
    if {[string compare [get_att $path path_type] "max"] == 0} {
        set K_sigma -1
    } else {
        set K_sigma 1
    }

    set sigma2  [expr {$ep_cp_sigma**2 - $crpr_sigma**2}]
    if { $sigma2 < 0 } {
        set sigma2 [expr {-1 * sqrt(abs ( $sigma2))}]
    } else {
        set sigma2 [expr {sqrt($sigma2)}]
    }
    
    return [expr {$crpr_mean + ($K_sigma * [get_app_var timing_pocvm_corner_sigma] * ($sigma2 - $ep_cp_sigma))}]
}

#There is a bug in primetime so this doesn't actually work right now.
#Saving it for onces they finnaly fix it
proc _bad_calc_pocv_hold_value {path} {
    if {[string compare [get_app_var timing_pocvm_enable_analysis] false] == 0} {
        set crpr_value [get_attribute -quiet $path common_path_pessimism]
        if {[string compare $crpr_value ""] == 0} {
            return 0
        } else {
            return $crpr_value
        }
    }
    set ep_cp_sigma [get_attribute $path variation_endpoint_clock_latency.std_dev]
    set crpr_mean   [get_attribute $path variation_endpoint_hold_time_value.mean]
    set crpr_sigma  [get_attribute $path variation_endpoint_hold_time_value.std_dev]

    if {[string compare [get_att $path path_type] "max"] == 0} {
        set K_sigma 1
    } else {
        set K_sigma -1
    }

    set sigma2  [expr {$ep_cp_sigma**2 - $crpr_sigma**2}]
    if { $sigma2 < 0 } {
        set sigma2 [expr {-1 * sqrt(abs ( $sigma2))}]
    } else {
        set sigma2 [expr {sqrt($sigma2)}]
    }
    
    return [expr {$crpr_mean + ($K_sigma * [get_app_var timing_pocvm_corner_sigma] * ($sigma2 - $ep_cp_sigma))}]
}

# Helper procedure to check if the timing_point has incremental annotated delay
# Returns 1 if incremental_annotated_* attribute is set on the arc, 0 otherwise
# DMPTBSPA-17261: Add annotation attributes to fmt report
proc _has_incremental_annotated_delay {timing_point is_max rise_fall} {
    # Get the timing_arc directly from the timing_point attribute (much faster than get_timing_arcs)
    set arc [get_attribute -quiet $timing_point timing_arc]

    if {[sizeof_collection $arc] == 0} {
        return 0
    }

    # Check the appropriate incremental_annotated attribute based on path type and direction
    if {$is_max} {
        if {[string compare $rise_fall "rise"] == 0} {
            set annot_val [get_attribute -quiet $arc incremental_annotated_max_rise]
        } else {
            set annot_val [get_attribute -quiet $arc incremental_annotated_max_fall]
        }
    } else {
        if {[string compare $rise_fall "rise"] == 0} {
            set annot_val [get_attribute -quiet $arc incremental_annotated_min_rise]
        } else {
            set annot_val [get_attribute -quiet $arc incremental_annotated_min_fall]
        }
    }
    # If the arc has incremental annotation, return true
    if {[string compare $annot_val ""] != 0 && $annot_val != 0} {
        return 1
    }
    return 0
}


proc print_custom_inst {pointA pointB constraint_data netvalues startpoint_arrival {IsRepeater ""} {is_max 1} {fanin_slack_delta -1} {is_crpr_point 0}} {
    
    upvar "print_options" print_options
    
    #THIS GET USED SEVERAL TIMES SO CACHE IT
    set sig_digits $print_options(sig_digits)
    set fileID $print_options(fileID)
    
    if {[llength $constraint_data] != 0} {
        set is_constraint 1
        
        set constraint_type  [lindex $constraint_data 0]
        set constraint_dir   [lindex $constraint_data 1]
        set constraint_value [lindex $constraint_data 2]
        
        if { [string compare $constraint_type "min_max"] == 0} {
            if {$is_max} {
                set constraint_type "maxdel"
            } else {
                set constraint_type "mindel"
            }
        }
    } else {
        set is_constraint 0
    }
    
    
    set rctype [lindex $netvalues 0]
    set ceff_vs_totc [lindex $netvalues 1]
    set gate_vs_totc [lindex $netvalues 2]
    if {[string compare $ceff_vs_totc "-"] != 0} {
        set ceff_vs_totc [format "%.2f" $ceff_vs_totc]
        set ceff_vs_totc_percent "%"
    } else {
        set ceff_vs_totc "-"
        set ceff_vs_totc_percent " "
    }
    if {[string compare $gate_vs_totc "-"] != 0} {
        set gate_vs_totc [format "%.2f" $gate_vs_totc]
        set gate_vs_totc_percent "%"
    } else {
        set gate_vs_totc "-"
        set gate_vs_totc_percent " "
    }
    
    set delta_delay ""
    set delta_tran  ""
    set derate_str  ""
    set mean_str    ""
    set sensit_str  ""
    set voltage_str ""
    set fanin_str   ""
    if { ([string compare $pointA ""] == 0) || ([string compare $pointA "?"] == 0) } {
        #DUMMY INPUT        
        set inst_name [get_attribute $pointB object.cell.full_name]
        set cell_name [get_attribute $pointB object.cell.ref_name]
        if { [string compare $pointA "?"] == 0 } {
            set full_name "$inst_name (? -> [get_attribute $pointB object.lib_pin_name])"
        } else {
            set full_name "$inst_name (?)"
        }
        
        if {$is_constraint} {
            set previous_arrival $constraint_value
            
            if { [string compare $constraint_type "extdel"] != 0 } {
                #WTF?!?
                echo "ERROR: $constraint_type isn't normal for $full_name"
            }
        } else {
            set previous_arrival 0.0
        }

        set arrival [expr {[get_attribute $pointB arrival] + $startpoint_arrival}]

        if {$is_constraint} {
            if { [string compare $constraint_type "extdel"] != 0 } {
                #WTF?!?
                echo "ERROR: $constraint_type isn't normal for $full_name"
            }
            set increment $constraint_value
        } else {
            set increment 0.0
        }
        
        set transition_time [get_attribute $pointB transition] 
        if {[string compare $transition_time UNINIT] == 0} {
            set transition_time 0.0
        }
        set transition_time [report_format_float $transition_time $sig_digits]

        set rise_fall [get_attribute $pointB rise_fall]
        
        if { $print_options(show_derate) } {
            set derate_str "-"
        }
        
        if {$print_options(show_variation)} {
            set mean_str "-"
            set sensit_str "-"
        }
        
        if {$print_options(show_volt)} {
            set volt [get_attribute $pointB voltage -quiet]
            if {($volt == "") || ([string compare $volt UNINIT] == 0)} {
                set voltage_str "-"
            } else {
                set voltage_str [report_format_float $volt $sig_digits]
            }
        }
        
        if {$print_options(show_xtalk)} {
            if {$is_constraint} {
                #NO XTALK POSSIBLE FOR THIS ARC
                set delta_delay "-"
                set delta_tran  "-"
            } else {
                set delta_delay [get_attribute -quiet $pointB annotated_delay_delta]
                set delta_tran  [get_attribute -quiet $pointB annotated_delta_transition]
                if { [string compare $delta_delay ""] == 0 } {
                    set delta_delay 0.0
                }
                if { [string compare $delta_tran ""] == 0 } {
                    set delta_tran 0.0
                }
                set delta_delay [report_format_float $delta_delay $sig_digits]
                set delta_tran  [report_format_float $delta_tran  $sig_digits]
            }
        }
    } elseif { ([string compare $pointB ""] == 0) || ([string compare $pointB "?"] == 0)} {
        #DUMMY OUTPUT
        if { [string compare [get_attribute $pointA object_class] "timing_point"] == 0} {
            set is_tim_point 1
        } else {
            set is_tim_point 0
        }
        if { $is_tim_point } {
            #set pinA [get_attribute $pointA object]
            set pinA_name [get_attribute $pointA object.lib_pin_name]
            set cell_name [get_attribute $pointA object.cell.ref_name]
            set inst_name [get_attribute $pointA object.cell.full_name]

            set previous_arrival [get_attribute $pointA arrival]
            set rise_fall [get_attribute $pointA rise_fall]
            if {$print_options(show_volt)} {
                set volt [get_attribute $pointA voltage -quiet]
                if {($volt == "") || ([string compare $volt UNINIT] == 0)} {
                    set voltage_str "-"
                } else {
                    set voltage_str [report_format_float $volt $sig_digits]
                }
            }
        } else {
            set pinA_name [get_attribute $pointA lib_pin_name]
            set cell_name [get_attribute $pointA cell.ref_name]
            set inst_name [get_attribute $pointA cell.full_name]

            set previous_arrival 0.0
            set rise_fall "?"
            if {$print_options(show_volt)} {
                set volt [get_attribute $pointA power_rail_voltage_max -quiet]
                if {($volt == "") || ([string compare $volt UNINIT] == 0)} {
                    set voltage_str "-"
                } else {
                    set voltage_str [report_format_float $volt $sig_digits]
                }
            }
        }

        if { [string compare $pointB "?"] == 0 } {
            set full_name "$inst_name ($pinA_name -> ?)"
        } else {
            set full_name "$inst_name ($pinA_name)"
            if { \
                   ($fanin_slack_delta >= 0 ) && \
                   ([get_attribute $pointA object.cell.is_black_box] == false) && \
                   ([get_attribute $pointA object.cell.is_sequential] == true)
             } {
                set fanin_str [_get_slack_fanin_str [get_attribute $pointA object] $is_max $sig_digits $fanin_slack_delta 1]
            }
        }
        
        if {[string compare $previous_arrival ""] == 0} {
            set previous_arrival 0.0
        }
        
        if {$is_constraint} {
            if {([string compare $constraint_type "mindel"] == 0) || ([string compare $constraint_type "maxdel"] == 0)} {
                set previous_arrival 0.0
            } 
            set arrival [expr {$previous_arrival + $constraint_value + $startpoint_arrival}] 
            set increment $constraint_value

            if { [string compare $constraint_type "extdel"] != 0 } {
                set transition_time $constraint_type
                set rise_fall $constraint_dir
            } else {
                if { $is_max } {
                    set transition_time "extmax"
                } else {
                    set transition_time "extmin"
                }
            }
        } else {
            set arrival [expr {$previous_arrival + $startpoint_arrival}]
            set increment 0.0
            if { [string compare $pointB "?"] == 0 } {
                set transition_time "?"
            } elseif { $is_tim_point } {
                set transition_time [report_format_float [get_attribute $pointA transition] $sig_digits]
            } else {
                set transition_time "?"
            }
        }
        
        if { $print_options(show_derate) } {
            if {$is_constraint} {
                if { $is_tim_point } {
                    if {$is_max} {
                        set derate [get_attribute $pointA object.cell.late_${rise_fall}_cell_check_derate_factor -quiet]
                    } else {
                        set derate [get_attribute $pointA object.cell.early_${rise_fall}_cell_check_derate_factor -quiet]
                    }
                } else {
                    if {$is_max} {
                        set derate [get_attribute $pointA cell.late_${rise_fall}_cell_check_derate_factor -quiet]
                    } else {
                        set derate [get_attribute $pointA cell.early_${rise_fall}_cell_check_derate_factor -quiet]
                    }
                }

                if { [string compare $derate ""] != 0 } {
                    set derate_str [report_format_float $derate $sig_digits]
                } else {
                    set derate_str "??"
                }
            } else {
                set derate_str "-"
            }
        }
        if {$print_options(show_variation)} {
            if {$is_constraint} {
                #???? variation constraint ???
                set mean_str "-"
                set sensit_str "-"
            } else {
                set mean_str "-"
                set sensit_str "-"
            }
        }
        if {$print_options(show_xtalk)} {
            #NO XTALK POSSIBLE FOR THIS ARC
            #set delta_delay "-"
            #set delta_tran  "-"
            set delta_delay " "
            set delta_tran  " "
        }
    } else {
        #NORMAL INSTANCE
        if {$is_constraint} {
            set pinB $pointB
        } else {
            set pinB [get_attribute $pointB object]
        }
        
        #set inst [get_cell -of_object $pinA]
        set inst_name [get_attribute $pointA object.cell.full_name]
        set cell_name [get_attribute $pointA object.cell.ref_name]
        set pinA_name [get_attribute $pointA object.lib_pin_name]
        set pinB_name [get_attribute $pinB lib_pin_name]
        set full_name "$inst_name ($pinA_name -> $pinB_name)"
        
        set previous_arrival [get_attribute $pointA arrival]
        if {[string compare $previous_arrival ""] == 0} {
            set previous_arrival 0.0
        }
        
        if {$is_constraint} {
            set arrival [expr {$previous_arrival + $constraint_value + $startpoint_arrival}] 
            set increment $constraint_value
            set transition_time $constraint_type
            set rise_fall $constraint_dir
            if { $print_options(show_derate) } {
                if {$is_max} {
                    set derate [get_attribute $pointA object.cell.late_${rise_fall}_cell_check_derate_factor -quiet]
                } else {
                    set derate [get_attribute $pointA object.cell.early_${rise_fall}_cell_check_derate_factor -quiet]
                }
                if { [string compare $derate ""] != 0 } {
                    set derate_str [report_format_float $derate $sig_digits]
                } else {
                    set derate_str "??"
                }
            }
            if {$print_options(show_variation)} {
                #???? variation constraint ???
                set mean_str "-"
                set sensit_str "-"
            }
            if {$print_options(show_volt)} {
                #BOZO Just use the data pins voltage for this one
                set volt [get_attribute $pointA voltage -quiet]
                if {($volt == "") || ([string compare $volt UNINIT] == 0)} {
                    set voltage_str "-"
                } else {
                    set voltage_str [report_format_float $volt $sig_digits]
                }
            }
            if {$print_options(show_xtalk)} {
                #set delta_delay "-"
                #set delta_tran  "-"
                set delta_delay " "
                set delta_tran  " "
            }
        } else {
            set arrival [get_attribute $pointB arrival]
            set increment [expr {$arrival - $previous_arrival}]
            set arrival [expr {$arrival + $startpoint_arrival}]
            set transition_time [report_format_float [get_attribute $pointB transition] $sig_digits]
            set rise_fall [get_attribute $pointB rise_fall]
            
            set efo [calc_efo $pinB $rise_fall]
            if { [string compare $efo ""] != 0 } {
                set full_name [format "%s EFO=%.${sig_digits}f" $full_name $efo]
            }
            if {$is_crpr_point} {
                set full_name "$full_name \#CRPR_COMMON_POINT"
            }
            if { $print_options(show_derate) } {
                set derate [get_attribute $pointB -quiet applied_derate]
                if { [string compare $derate ""] != 0 } {
                    set derate_str [report_format_float $derate $sig_digits]
                } else {
                    set derate_str "?"
                }
            }
            
            if {$print_options(show_variation)} {
                set calc_values [calc_mean_and_sensit_values $pointA $pointB $sig_digits]
                set mean_str [lindex $calc_values 0]
                set sensit_str [lindex $calc_values 1]
            }
            if {$print_options(show_volt)} {
                set volt [get_attribute $pointB voltage -quiet]
                if {($volt == "") || ([string compare $volt UNINIT] == 0)} {
                    set voltage_str "-"
                } else {
                    set voltage_str [report_format_float $volt $sig_digits]
                }
            }
            if {$print_options(show_xtalk)} {
                #set delta_delay [get_attribute -quiet $pointB annotated_delay_delta]
                #set delta_tran  [get_attribute -quiet $pointB annotated_delta_transition]
                #if { [string compare $delta_delay ""] == 0 } {
                #    set delta_delay 0.0
                #}
                #if { [string compare $delta_tran ""] == 0 } {
                #    set delta_tran 0.0
                #}
                #set delta_delay [report_format_float $delta_delay "%.${sig_digits}f"]
                #set delta_tran  [report_format_float $delta_tran  "%.${sig_digits}f"]
                set delta_delay " "
                set delta_tran  " "
            }
            if { \
                   ($fanin_slack_delta >= 0 ) && \
                   ([get_attribute $pointA object.cell.is_black_box] == false) && \
                   ([string compare [get_attribute $pointA object.direction] "internal"] != 0) && \
                   ([string compare [get_attribute $pinB direction] "internal"] != 0) \
               } \
              {
                  set fanin_str [_get_slack_fanin_str $pinB $is_max $sig_digits $fanin_slack_delta]
              }
        }
    }
    
    if {[string length $cell_name] > $print_options(cell_column_width)} {
        set cell_name2print "[string range $cell_name 0 [expr {$print_options(cell_column_width) - 4}]]..."
    } else {
        set cell_name2print $cell_name
    }
    if { [string compare $rise_fall "rise"] == 0 } {
        set direction " R "
    } elseif { [string compare $rise_fall "fall"] == 0 } {
        set direction " F "
    } else {
        set direction " ? "
    }
    # DMPTBSPA-17261: Check for incremental annotated delay on incoming arc to pointA and add H marker
    set incr_str [report_format_float $increment $sig_digits]
    if {$print_options(show_annotation)} {
        if {[string compare $pointA ""] != 0 && [string compare $pointA "?"] != 0 && !$is_constraint} {
            if {[_has_incremental_annotated_delay $pointA $is_max $rise_fall]} {
                set incr_str "${incr_str} H"
            }
        }
    }
    set print_str [format $print_options(format_str) \
                     [report_format_float $arrival $sig_digits] \
                     $incr_str \
                     $delta_delay \
                     $direction \
                     $cell_name2print \
                     $transition_time \
                     $delta_tran \
                     $derate_str \
                     $mean_str \
                     $sensit_str \
                     $voltage_str \
                     $rctype \
                     $ceff_vs_totc $ceff_vs_totc_percent \
                     $gate_vs_totc $gate_vs_totc_percent \
                     $full_name \
                    ] 
    
    puts $fileID $print_str
    if {$print_options(physical)} {
        set loc_str [_get_location_str $pointA $pointB $IsRepeater]
        if {$loc_str != ""} {
            set whitespace_padding [expr {[string length $print_str] - [string length $full_name] - 4}]
            puts $fileID [format "\#LOC\#\#%${whitespace_padding}s %s" " " $loc_str]
        }
    }
    
    if { [string compare $fanin_str ""] != 0 } {
        set whitespace_padding [expr {[string length $print_str] - [string length $full_name]}]
        puts $fileID [format "\#\#%${whitespace_padding}s %s" " " $fanin_str]
    }
    return $arrival
}

proc _get_slack_fanin_str {to_pin {is_max 1} {sig_digits 2} {fanin_slack_delta 1} {sequential 0}} {               
    set fanin_str ""
    set slack_fanin_list ""
    set slack_min ""
    set slack_max ""

    if {$sequential} {
        if {[get_attribute $to_pin is_data_pin] == false} {
            return ""
        }
        set clkpins [get_attribute -quiet \
                        [get_timing_arcs -quiet -to $to_pin -filter " \
                                                             (is_cellarc == true) && \
                                                             (is_disabled == false) && \
                                                             (is_user_disabled == false) && \
                                                             (from_pin.is_clock_pin) && \
                                                             (sense =~ setup_* || sense =~ hold_*) \
                                                         " \
                          ] \
                        from_pin \
                    ]
        set frompins [get_attribute -quiet \
                        [get_timing_arcs -quiet -from $clkpins -filter " \
                                                             (is_cellarc == true) && \
                                                             (is_disabled == false) && \
                                                             (is_user_disabled == false) && \
                                                             (sense =~ setup_* || sense =~ hold_*) && \
                                                             (to_pin.direction != internal) && \
                                                             (to_pin.direction != out) \
                                                         " \
                          ] \
                        to_pin \
                       ]
        set frompins [add_to_collection -unique $frompins ""]
        if {[sizeof_collection $frompins] <= 1} {
            return ""
        }
    } else {
        set frompins [get_attribute \
                        [get_timing_arcs -quiet -to $to_pin -filter " \
                                                             (is_cellarc == true) && \
                                                             (is_disabled == false) && \
                                                             (is_user_disabled == false) && \
                                                             (sense =~ *_unate || sense =~ rise_to_* || sense =~ fall_to_*) && \
                                                             (from_pin.direction != internal) && \
                                                             (from_pin.direction != out) \
                                                         " \
                          ] \
                        from_pin
                     ]
        set frompins [add_to_collection -unique $frompins ""]
        if {[sizeof_collection $frompins] <= 1} {
            return ""
        }
    }
    foreach_in_collection frompin $frompins {
        set frompin_name [get_attribute $frompin lib_pin_name]        
        set worst_slack [_get_worst_prioritized_slack $frompin $is_max]
        if { ([string compare $worst_slack ""] != 0) } {
            #lappend slack_fanin_list [list $frompin_name [report_format_float $worst_slack $sig_digits 0]]
            lappend slack_fanin_list [list $frompin_name [format "%.${sig_digits}f" $worst_slack]]
            if { ([string compare $slack_min ""] == 0) || ($slack_min > $worst_slack)} {
                set slack_min $worst_slack
            }
            if { ([string compare $slack_max ""] == 0) || ($slack_max < $worst_slack)} {
                set slack_max $worst_slack
            }
        }   
    }
    if { \
           ([llength $slack_fanin_list] > 1) && ([string compare $slack_min ""] != 0) && \
           ([string compare $slack_max ""] != 0) && \
           ([expr {abs($slack_max - $slack_min)}] >= $fanin_slack_delta) } \
      {
          foreach fanin_info [lsort -real -index 1 $slack_fanin_list] {
              set fanin_str "$fanin_str [lindex $fanin_info 0]:[lindex $fanin_info 1]"
          }
      }
    return $fanin_str
}


proc _get_location_str {pointA pointB {IsRepeater ""}} {
    set aLoc [_get_point_xy $pointA]
    set bLoc [_get_point_xy $pointB]
    if {[string equal 1 $IsRepeater]} {
      set EffStr " IsRepeater"
    } else {
      set EffStr ""
    }
    if {$aLoc == ""} {
        if {$bLoc == ""} {
            return ""
        } elseif {$pointA != ""} {
            return "* -> $bLoc$EffStr"
        } else {
            return "$bLock$EffStr"
        }
    } elseif {$bLoc == ""} {
        if {$pointB != ""} {
            return "$aLoc -> $pointB$EffStr"
        } else {
            return "$aLoc$EffStr"
        }
    } else {
        return "$aLoc -> $bLoc$EffStr"
    }
}

proc _get_point_xy {point} {
    if {$point == ""} {
        return ""
    }
    
    if { \
           ($point != "") && \
           ([get_attribute -quiet $point is_hierarchical] != "true") && \
           ([get_attribute -quiet $point object.is_hierarchical] != "true") && \
           ([get_attribute -quiet $point object.direction] != "internal") && \
           ([get_attribute -quiet $point direction] != "internal") \
       } {
        
        set xLoc [get_attribute -quiet $point x_coordinate]
        set yLoc [get_attribute -quiet $point y_coordinate]
        if {($xLoc == "") || ($xLoc == "UNINIT")} {
            set xLoc "N/A"
        }
        if {($yLoc == "") || ($yLoc == "UNINIT")} {
            set yLoc "N/A"
        }
        return "(X: $xLoc Y: $yLoc)" 
    } else {
        return ""
    }
}

proc print_custom_net {pointA pointB startpoint_arrival {is_max 1} {fanout_slack_delta -1} {route_delay_threshold -1} {is_crpr_point 0}} {
        
    upvar "print_options" print_options
    #THIS GET USED SEVERAL TIMES SO CACHE IT
    set sig_digits $print_options(sig_digits)
    set sig_cap_digits $print_options(sig_cap_digits)
    set fileID $print_options(fileID)
    
    #set pinA [get_attribute $pointA object]
    if {[string compare [get_attribute -quiet $pointA object.is_hierarchical] "true"] == 0} {
        if {([string compare [get_attribute -quiet $pointB object.is_hierarchical] "true"] == 0) && ([string compare [get_attribute -quiet $pointA object.direction] "in"] == 0)} {
            set net [get_nets -of_object [get_attribute $pointA object] -boundary_type lower]
        } else {
            set net [get_attribute $pointB object.net]
        }
        set fanout "-"
    } else {
        #set net     [get_nets -of_object $pinA]
        set net     [get_attribute $pointA object.net]
        set fanout  [get_attribute -quiet $net number_of_leaf_loads]
    }
    set netname [get_attribute $net full_name]
    if {$is_crpr_point} {
        set netname "$netname \#CRPR_COMMON_POINT"
    }
    #set pinA_name [get_attribute $pointA lib_pin_name]
    #set pinB_name [get_attribute $pointB lib_pin_name]
    
    set arrival [get_attribute $pointB arrival]
    set previous_arrival [get_attribute $pointA arrival]
    
    set increment [expr {$arrival - $previous_arrival}]
    set arrival [expr {$arrival + $startpoint_arrival}]
    set transition_time [get_attribute $pointB transition]
    
    set rise_fall [get_attribute $pointB rise_fall]

    if {$is_max} {
        set pincap [get_attribute -quiet $net pin_capacitance_max_${rise_fall}]
        set total_cap [get_attribute -quiet $net total_capacitance_max]
        #set ceff [get_attribute -quiet $pinA cached_ceff_max_${rise_fall}]
        set ceff [get_attribute -quiet $pointA object.cached_ceff_max_${rise_fall}]
    } else {
        set total_cap [get_attribute -quiet $net total_capacitance_min]
        set pincap [get_attribute -quiet $net pin_capacitance_min_${rise_fall}]
        #set ceff [get_attribute -quiet $pinA cached_ceff_min_${rise_fall}]
        set ceff [get_attribute -quiet $pointA object.cached_ceff_min_${rise_fall}]
    }

    if {[string length $total_cap] == 0} {
        set total_cap 0.0
    }
    if {[string length $pincap] == 0} {
        set pincap 0.0
    }
    if {[string length $ceff] == 0} {
        set ceff 0.0
    } else {
        global fmt_ceff_unit_fix
        if {[info exists fmt_ceff_unit_fix] == 0} {
            set design_cap_unit [get_attribute [get_design] capacitance_unit_in_farad]
            set fmt_ceff_unit_fix [expr {1e-12 / $design_cap_unit}]
        }
        set ceff [expr {$ceff * $fmt_ceff_unit_fix}]
    }
    if {[get_attribute $net has_valid_parasitics]} {
        set est_rctype [get_attribute $net estimated_parasitic_info -quiet]
        if { [string compare $est_rctype ""] != 0 } {
            set rctype $est_rctype
        } else {
            set rctype "RC"
        }
    } else {
        set rctype "ZL"
    }
    if {$total_cap != 0.0} {
        set ceff_vs_totalc [expr {$ceff/$total_cap * 100}]
        set gatc_vs_totalc [expr {$pincap/$total_cap * 100}]
    } else {
        set ceff_vs_totalc 0.0
        set gatc_vs_totalc 0.0
    }
    
    set derate_str ""
    if { $print_options(show_derate) } {
        set derate [get_attribute $pointB -quiet applied_derate]
        
        if { [string compare $derate ""] != 0 } {
            set derate_str [report_format_float $derate $sig_digits]
        } else {
            set derate_str "?"
        }
    }
    
    set mean_str ""
    set sensit_str ""
    if {$print_options(show_variation)} {
        set calc_values [calc_mean_and_sensit_values $pointA $pointB $sig_digits]
        set mean_str [lindex $calc_values 0]
        set sensit_str [lindex $calc_values 1]
    }
    
    set voltage_str ""
    if {$print_options(show_volt)} {
        set volt [get_attribute $pointB voltage -quiet]
        if {($volt == "") || ([string compare $volt UNINIT] == 0)} {
            set voltage_str "-"
        } else {
            set voltage_str [report_format_float $volt $sig_digits]
        }
    }
    
    if { [string compare $rise_fall "rise"] == 0 } {
        set direction " R "
    } elseif { [string compare $rise_fall "fall"] == 0 } {
        set direction " F "
    } else {
        set direction " ? "
    }
    
    if {$print_options(show_xtalk)} {
        set delta_delay [get_attribute -quiet $pointB annotated_delay_delta]
        set delta_tran  [get_attribute -quiet $pointB annotated_delta_transition]
        if { [string compare $delta_delay ""] == 0 } {
            set delta_delay 0.0
        }
        if { [string compare $delta_tran ""] == 0 } {
            set delta_tran 0.0
        }
        set delta_delay [report_format_float $delta_delay $sig_digits]
        set delta_tran  [report_format_float $delta_tran  $sig_digits]
        
    } else {
        set delta_delay ""
        set delta_tran  ""
    }
    set print_str [format $print_options(format_str) \
                     [report_format_float $arrival $sig_digits] \
                     [report_format_float $increment $sig_digits] \
                     $delta_delay \
                     $direction \
                     $fanout \
                     [report_format_float $transition_time $sig_digits] \
                     $delta_tran \
                     $derate_str \
                     $mean_str \
                     $sensit_str \
                     $voltage_str \
                     [report_format_float $total_cap $sig_cap_digits] \
                     [report_format_float $ceff $sig_cap_digits] " " \
                     [report_format_float $pincap $sig_cap_digits] " "\
                     $netname \
                    ]
    puts $fileID $print_str
    set whitespace_padding [expr {[string length $print_str] - [string length $netname]}]
    
    if { \
           ($fanout_slack_delta >= 0) && \
           ([string compare $fanout "-"] != 0) && \
           ($fanout > 1) && \
           ($fanout < $::fmt_high_fanout_limit) && \
           ([string compare [get_attribute $pointB object.object_class ] port] != 0) \
       } {
        if {($fanout == 2) && \
              ( \
                  ([string compare [get_attribute $pointA object.direction ] inout] == 0) || \
                  ([string compare [get_attribute $pointB object.direction ] inout] == 0) \
                  ) \
          } {
            #FAILSAFE FOR INOUTS
        } else {
            set fanout_str [_get_slack_fanout_str $net $is_max $sig_digits $fanout_slack_delta $print_options(max_fanout_limit)]
            if {[string compare $fanout_str ""] != 0} {
                puts $fileID [format "\#\#%${whitespace_padding}s %s" " " $fanout_str]
            }    
        }
    }
    
    if { ($route_delay_threshold >= 0) && ($increment >= $route_delay_threshold) } {
        set route_info [get_attribute -quiet $net route_data_string]
        if { [string compare $route_info ""] != 0 } {
            puts $fileID [format "\#\#%${whitespace_padding}s %s" " " $route_info]
        } elseif {[string compare [get_attribute -quiet $pointB object.is_hierarchical] "false"] == 0 } {
            set route_info [get_attribute -quiet [get_nets -segments -top_net_of_hierarchical_group -of_objects [get_attribute $pointB object]] route_data_string]
            if { [string compare $route_info ""] != 0 } {
                puts $fileID [format "\#\#%${whitespace_padding}s %s" " " $route_info]
            }
        }
    }
    return [list $rctype $ceff_vs_totalc $gatc_vs_totalc]
}

proc _get_slack_fanout_str {net {is_max 1} {sig_digits 2} {fanout_slack_delta 1} {max_fanout_limit 8}} {
    if {($fanout_slack_delta < 0) || ($max_fanout_limit < 1)} {
        return ""
    }
    set loads [get_attribute $net leaf_loads]
    if {[sizeof_collection $loads] <= 1} {
        return ""
    }
    set slack_list ""
    foreach_in_collection load_pin $loads {
        set worst_slack [_get_worst_prioritized_slack $load_pin $is_max]
        if { ([string compare $worst_slack ""] != 0) } {
            #lappend slack_list [report_format_float $worst_slack $sig_digits 0]
            lappend slack_list [format "%.${sig_digits}f" $worst_slack]
        }
    }
    if { ([llength $slack_list] <= 1)} {
        return ""
    }
    set fanout_str ""
    set slack_list [lsort -real $slack_list]
    set slack_max [lindex $slack_list [expr {[llength $slack_list] - 1}]]
    set slack_min [lindex $slack_list 0]
    if { ([expr {abs($slack_max - $slack_min)}] >= $fanout_slack_delta) } {
        if { [llength $slack_list] <= $max_fanout_limit} {
            set fanout_str $slack_list
        } else {
            set fanout_str [lrange $slack_list 0 [expr {$max_fanout_limit - 1}]]
            set fanout_str "$fanout_str... $slack_max"
        }
    }
    return $fanout_str
}

proc print_custom_timing_segment {path_obj startpoint_arrival external_delay prior_netdata {is_max 1} {fanin_slack_delta -1} {fanout_slack_delta -1} {crpr_common_point ""}} {
    
    upvar "print_options" print_options
    
    set route_delay_threshold $print_options(route_delay_threshold)
    set tmp_route_delay_threshold $route_delay_threshold
    set prev_point ""
    set prev_object ""
    set prev_class  ""
    set prev_arrival 0.0
    if { [string compare $prior_netdata ""] == 0 } {
        set netvalues [list "ZL" "-" "-"]
    } else {
        set netvalues $prior_netdata
    }
    
    set cell_delay    0
    set wire_delay    0
    set nid_delay     0
    # Always use float initialization for stage counts
    set stage_cnt     0.0
    set eff_stage_cnt 0.0
    set net_cnt       0

    # Check if weighted LOL counting is enabled
    set use_weighted_lol $print_options(use_weighted_lol)

    foreach_in_collection timing_path $path_obj {
        set path_points [get_attribute $timing_path points]
        set path_point_sizeof [sizeof_collection $path_points]
    
        set saw_driver 0
        set point_cnt 0
        set force_route_info 0
        set IsRepeater 0

        foreach_in_collection point $path_points {
            set current_object [get_attribute $point object]
            set current_class [get_attribute $current_object object_class]
            set current_arrival [get_attribute $point arrival]
            set current_is_hier [get_attribute -quiet $current_object is_hierarchical]

            if { ($current_is_hier == false) && ($net_cnt > 0)} {
                if {[info exists print_options(effective_stage_regexp)]} {
                    if {([regexp $print_options(effective_stage_regexp) [get_attribute -quiet $current_object cell.ref_name]] == 0)} {
                        set IsRepeater 0
                    } else {
                        set IsRepeater 1 
                    }
                } else {
                    set IsRepeater 0
                }
            }

            if { [string compare $current_arrival ""] == 0} {
                set current_arrival 0.0
            }
            #set current_tran [get_attribute $point transition]
            #if {$worst_tran < $current_tran} {
            #    set worst_tran $current_tran
            #}

            if {$point_cnt == 0} {
                if { [string compare $prev_point ""] == 0 } {
                    if { [string compare $current_class "port"] == 0 } {
                        print_custom_port $point "input $external_delay" $netvalues $startpoint_arrival $is_max
                    } elseif { [string compare $external_delay ""] != 0 } {
                        print_custom_inst "?" $point "extdel ? $external_delay" $netvalues $startpoint_arrival $IsRepeater $is_max -1
                    }
                } elseif { \
                       ([string compare $prev_class $current_class] == 0) && \
                       ([string compare [get_attribute $prev_object full_name] [get_attribute $current_object full_name]] == 0) \
                   } {
                    if { [string compare $current_class "port"] == 0 } {
                        #DO NOTHING
                    } elseif { $prev_arrival != $current_arrival } {
                        print_custom_inst $prev_point $point "" $netvalues $startpoint_arrival $IsRepeater $is_max -1
                    } else {
                        #DO NOTHING
                    }
                } else {
                    if { [string compare $prev_class "pin"] == 0 } {
                        print_custom_inst $prev_point "?" "" $netvalues $startpoint_arrival $IsRepeater $is_max -1
                    }
                    if { [string compare $current_class "port"] == 0 } {
                        print_custom_port $point "input $external_delay" $netvalues $startpoint_arrival $is_max
                    } else {
                        print_custom_inst "?" $point "" $netvalues $startpoint_arrival $IsRepeater $is_max -1
                    }
                }
                incr point_cnt
            } else {
                set increment_delay [expr {$current_arrival - $prev_arrival}]
                if {$print_options(show_xtalk)} {
                    set point_delta_delay [get_attribute -quiet $point annotated_delay_delta]
                    if { [string compare $point_delta_delay ""] != 0 } {
                        set nid_delay [expr {$nid_delay + $point_delta_delay}]
                    }
                }
                
                if {$route_delay_threshold <= 0} {
                    set tmp_route_delay_threshold $route_delay_threshold
                } elseif { ([string compare $current_class "pin"] != 0) || !($current_is_hier) } {
                    set force_route_info 0
                    set tmp_route_delay_threshold $route_delay_threshold
                } elseif {$force_route_info == 0} {
                    for {set route_cnt_check [expr {$point_cnt + 1}]} {$route_cnt_check < [sizeof_collection $path_points]} {incr route_cnt_check} {
                        set next_point   [index_collection $path_points $route_cnt_check]
                        set next_object  [get_attribute $next_point object]
                        set next_class   [get_attribute $next_object object_class]
                        if {([string compare $next_class "pin"] != 0) || !([get_attribute -quiet $next_object is_hierarchical])} {
                            set next_arrival [get_attribute $next_point arrival]
                            if { [string compare $next_arrival ""] == 0} {
                                set next_arrival 0.0
                            }
                            if {[expr {$next_arrival - $current_arrival}] >= $route_delay_threshold} {
                                set force_route_info 1
                            }
                            break
                        }
                    } 
                    
                    if {$force_route_info == 1} {
                        set tmp_route_delay_threshold 0
                    } else {
                        set tmp_route_delay_threshold $route_delay_threshold
                    }
                }
                if { $saw_driver } {
                    set wire_delay [expr {$wire_delay + $increment_delay}]

                    if {([string compare $crpr_common_point ""] != 0) && ([string compare $crpr_common_point [get_attribute $current_object full_name]] == 0)} {
                        set is_crpr_point 1
                        set crpr_common_point ""
                    } else {
                        set is_crpr_point 0
                    }

                    set netvalues [print_custom_net $prev_point $point $startpoint_arrival $is_max $fanout_slack_delta $tmp_route_delay_threshold $is_crpr_point]
                    incr net_cnt
                    set saw_driver 0
                } else {
                    if { ([string compare $current_class "pin"] != 0) || $current_is_hier } {
                        #A PORT or NON-LEAF pin must always be followed by a net
                        set wire_delay [expr {$wire_delay + $increment_delay}]
                        set netvalues [print_custom_net $prev_point $point $startpoint_arrival $is_max $fanout_slack_delta $tmp_route_delay_threshold]
                        incr net_cnt
                        set saw_driver 1
                    } elseif { ([string compare $prev_class pin] != 0) || ([get_attribute $prev_object is_hierarchical]) } {
                        set wire_delay [expr {$wire_delay + $increment_delay}]
                        set netvalues [print_custom_net $prev_point $point $startpoint_arrival $is_max $fanout_slack_delta $tmp_route_delay_threshold]
                        incr net_cnt
                    } else {
                        if {$point_cnt == 1} {
                            set prev_inst_name [get_attribute $prev_object cell.full_name]
                            set current_inst_name [get_attribute $current_object cell.full_name]
                            if { [string compare $prev_inst_name $current_inst_name] != 0 } {
                                #HANDLE UNCONSTRAINED PATHS AND/OR ONES STARTED VIA set_input_delay THAT START AT A DRIVER PIN
                                if { [string compare $external_delay ""] == 0 } {
                                    #NO INPUT DELAY SO HAVEN'T PRINTED START POINT YET
                                    print_custom_inst "?" $prev_point "" $netvalues $startpoint_arrival $IsRepeater $is_max -1
                                }
                                set wire_delay [expr {$wire_delay + $increment_delay}]
                                set netvalues [print_custom_net $prev_point $point $startpoint_arrival $is_max $fanout_slack_delta $tmp_route_delay_threshold]
                                
                                incr point_cnt
                                incr net_cnt
                                set prev_point $point
                                set prev_object  $current_object
                                set prev_class   $current_class
                                set prev_arrival $current_arrival
                                continue
                            }
                        }
                        if {([string compare $crpr_common_point ""] != 0) && ([string compare $crpr_common_point [get_attribute $current_object full_name]] == 0)} {
                            set is_crpr_point 1
                            set crpr_common_point ""
                        } else {
                            set is_crpr_point 0
                        }
                        set cell_delay [expr {$cell_delay + $increment_delay}]
                        print_custom_inst $prev_point $point "" $netvalues $startpoint_arrival $IsRepeater $is_max $fanin_slack_delta $is_crpr_point
                        set netvalues [list "ZL" "-" "-"]
                        set current_dir [get_attribute $current_object direction]
                        if { [string compare $current_dir "internal"] != 0 } {
                            set saw_driver 1
                            if { ($current_is_hier == false) && ($net_cnt > 0)} {
                                # Get cell ref_name for weighting
                                set cell_ref_name [get_attribute -quiet $current_object cell.ref_name]

                                # Determine cell weight based on mode
                                if {$use_weighted_lol} {
                                    set cell_weight [get_cell_weight_factor $cell_ref_name]
                                } else {
                                    set cell_weight 1
                                }

                                # Add weighted count to stage_cnt (common for both modes)
                                set stage_cnt [expr {$stage_cnt + $cell_weight}]

                                # For eff_stage_cnt, check if it's a buffer/inverter
                                if {[info exists print_options(effective_stage_regexp)]} {
                                    if {([regexp $print_options(effective_stage_regexp) $cell_ref_name] == 0)} {
                                        # Not a buffer/inverter - add weighted count
                                        set eff_stage_cnt [expr {$eff_stage_cnt + $cell_weight}]
                                    }
                                } else {
                                    set eff_stage_cnt [expr {$eff_stage_cnt + $cell_weight}]
                                }
                            }
                        }
                    }
                }
                
                
                incr point_cnt
                if { ($point_cnt != $path_point_sizeof) } {
                    #DON'T MESS W/ THE ENDPOINT HERE
                    if { [string compare $current_class "port"] == 0 } {
                        print_custom_port $point "" $netvalues $startpoint_arrival $is_max
                    } elseif { $current_is_hier } {
                        #PRINT INTERMEDIARY non-leaf instpins
                        print_custom_inst $point "" "" $netvalues $startpoint_arrival $IsRepeater $is_max -1
                    }
                }
            }
            set prev_point   $point
            set prev_object  $current_object
            set prev_class   $current_class
            set prev_arrival $current_arrival
        }
    }

    # Format the return values based on whether weighted mode is enabled
    if {$use_weighted_lol} {
        # Weighted mode: return as formatted floats (2 decimal places)
        set stage_cnt_out [format "%.2f" $stage_cnt]
        set eff_stage_cnt_out [format "%.2f" $eff_stage_cnt]
    } else {
        # Non-weighted mode: return as integers
        set stage_cnt_out [expr {int($stage_cnt)}]
        set eff_stage_cnt_out [expr {int($eff_stage_cnt)}]
    }

    return [list $prev_point $netvalues $cell_delay $wire_delay $nid_delay $stage_cnt_out $eff_stage_cnt_out $IsRepeater]
}

proc make_dashed_line { {length 60} } {
    set dash_str ""
    for {set i 0} { $i < $length} {incr i} {
        set dash_str "${dash_str}-"
    }
    return $dash_str    
}

proc print_custom_timing_path {path {path_count 1} {segment 0}} {    
    upvar "print_options" print_options
    set sig_digits $print_options(sig_digits)
    set fileID $print_options(fileID)
    #set PTIME [clock microseconds]
    set path_points [get_attribute $path points]
    set launch_clk_paths [get_attribute -quiet $path launch_clock_paths]
    set capture_clk_paths [get_attribute -quiet $path capture_clock_paths]
    
    set transparent_latch_paths [get_attribute -quiet $path transparent_latch_paths]
    if { [sizeof_collection $transparent_latch_paths] > 0} {
        foreach_in_collection latch_path $transparent_latch_paths {
            incr segment
            print_custom_timing_path $latch_path $path_count $segment 
        }
        #INCREMENT COUNTER FOR DATA PATH
        incr segment
    }
    
    set slack [get_attribute $path slack]
    set startpt [get_attribute $path startpoint]
    set endpt [get_attribute $path endpoint]
    set path_type [get_attribute $path path_type]
    set is_max [expr {[string compare $path_type "max"] == 0}]
    
    set data_cell_delay 0
    set data_net_delay  0 
    
    set start_clock [get_attribute $path startpoint_clock -quiet]
    set end_clock [get_attribute $path endpoint_clock -quiet]
    set start_is_level [expr {! [string compare [get_attribute $path startpoint_is_level_sensitive] "true"]}]
    set end_is_level [expr {! [string compare [get_attribute $path endpoint_is_level_sensitive] "true"]}]
    
    if {([string compare [get_app_var timing_enable_through_paths] true] == 0)} {
        set end_is_level 0
    }
    
    set is_min_max_delay_check [_path_is_min_max_delay_check $path]
    
    #set DTIME [clock microseconds]
    #GET THE COLUMN WIDTH STARTPOINT & ENDPOINT NAME
    set header_length [print_custom_path_header $path $path_count $segment $is_max]

    #puts stderr "HEADER == [expr {[clock microseconds] - $DTIME}]"
    set dashed_line [make_dashed_line $header_length] 
    #puts $fileID $dashed_line
    
    #set DTIME [clock microseconds]
    set startpoint_arrival 0.0
    set input_delay 0.0
    set gater_netdata ""
    if {[string compare $start_clock ""] != 0} {
        #GET THE CLK NAME
        set launch_clock_invert ""
        if {[string compare [get_attribute $path startpoint_clock_is_inverted] "true"] == 0} {
            set launch_clock_invert "'"
        }
        set launch_clock_name       [format "%s%s" [get_attribute $start_clock full_name] $launch_clock_invert]
        set launch_clock_edge_type  [get_attribute $path startpoint_clock_open_edge_type -quiet]
        set launch_clock_edge_value [get_attribute $path startpoint_clock_open_edge_value -quiet]
        
        #min/max delay commands wipe out launch clock edge
        if { [string compare $launch_clock_edge_value ""] == 0} {
            set launch_clock_edge_value 0.0
        }
        
        set startpoint_arrival $launch_clock_edge_value
        set startpoint_latency [get_attribute $path startpoint_clock_latency]
        set time_lent [get_attribute $path time_lent_to_startpoint]
        set input_delay [get_attribute $path startpoint_input_delay_value -quiet]
      
        if {$::timing_point_arrival_attribute_compatibility} {
            set startpoint_arrival [expr {$startpoint_arrival + $startpoint_latency}]        
            if {$time_lent > 0.0} {
                set startpoint_arrival [expr {$startpoint_arrival + $time_lent}]
            }
            if {[string compare $input_delay ""] != 0} {
                set startpoint_arrival [expr {$startpoint_arrival + $input_delay}]
            }
        }

        #PRINT THE LAUNCHING CLOCK NETWORK
        set launch_clk_gaterpoint ""
        set launch_clk_endpoint ""
        set launch_clk_latency 0
        set launch_clk_segment_cnt [sizeof_collection $launch_clk_paths]

        if { $launch_clk_segment_cnt > 0} {
            set final_launch_clk_path   [index_collection $launch_clk_paths [expr {$launch_clk_segment_cnt - 1}]]
            set final_launch_clk_points [get_attribute $final_launch_clk_path points]
            
            set launch_clk_startpoint [index_collection $final_launch_clk_points 0]
            if { [sizeof_collection $final_launch_clk_points] > 1 } {
                for {set gater_index [expr {[sizeof_collection $final_launch_clk_points] - 2}]} {$gater_index >= 0} {incr gater_index -1} {
                    set launch_clk_gaterpoint [index_collection $final_launch_clk_points $gater_index]
                    if {[string compare [get_attribute -quiet $launch_clk_gaterpoint object.is_hierarchical] false] == 0} {
                        break
                    }
                }
            }
            set launch_clk_endpoint  [index_collection $final_launch_clk_points [expr {[sizeof_collection $final_launch_clk_points] - 1}]]
            
            set launch_clk_arrival [get_attribute $launch_clk_endpoint arrival]

            set launch_clk_latency [get_attribute [index_collection $launch_clk_paths 0] startpoint_clock_latency]
            if {$::timing_point_arrival_attribute_compatibility} {
                set launch_clk_start_time  0
                #set launch_clk_latency [get_attribute [index_collection $launch_clk_paths 0] startpoint_clock_latency]
            } else {
                set launch_clk_start_time  $launch_clock_edge_value
            }

            print_custom_clock $start_clock $launch_clock_name $launch_clock_edge_type $launch_clock_edge_value \
              $launch_clk_latency 0 0 0 0 "" "" 0 \
              $launch_clk_startpoint "" $launch_clk_endpoint $is_max            

            
            if {$print_options(full_clock_expanded) || ($launch_clk_segment_cnt == 1)} {
                set lclk_data [ print_custom_timing_segment $launch_clk_paths $launch_clk_start_time 0 "" $is_max -1 -1]
            } else {
                set final_launch_clk_start_time [expr {[get_attribute [index_collection [get_attribute [index_collection $launch_clk_paths end-1] points] end] arrival] - $launch_clk_latency}]
                if {$::timing_point_arrival_attribute_compatibility} {
                    set final_launch_clk_start_time [expr {$final_launch_clk_start_time - $launch_clock_edge_value}]
                }
                set lclk_data [ print_custom_timing_segment $final_launch_clk_path $launch_clk_start_time $final_launch_clk_start_time "" $is_max -1 -1]
            }
            
            set last_launch_clk_point [lindex $lclk_data 0]
            set last_launch_netdata [lindex $lclk_data 1]
            
            if { [string compare [get_attribute [get_attribute $last_launch_clk_point object] object_class] "port"] == 0 } {
                set constraint_str ""
                if {[string compare $input_delay ""] != 0} {
                    set constraint_str "extdel $input_delay"
                }
                print_custom_port $last_launch_clk_point $constraint_str $last_launch_netdata $launch_clk_start_time $is_max 
            } else {
                set constraint_str ""
                if {[string compare $input_delay ""] != 0} {
                    set constraint_str "extdel ? $input_delay"
                }
                set IsRepeater ""
                print_custom_inst $last_launch_clk_point "" $constraint_str $last_launch_netdata $launch_clk_start_time $IsRepeater $is_max -1
            }
            
            puts $fileID ""
        } else {
          
        }
        set launch_clk_endpoint [index_collection $path_points 0]
        if {[string compare $input_delay ""] != 0} {
            #REFERENCE DELAY
            set launch_clk_gaterpoint ""
            set launch_clk_latency $startpoint_latency
        }
        if {!$::timing_point_arrival_attribute_compatibility} {
            set start_network_delay [get_attribute -quiet $launch_clk_endpoint arrival]
        } else {
            set start_network_delay [expr {$startpoint_arrival - $launch_clk_latency - $time_lent - $launch_clock_edge_value}]
        }
        if {[string compare $start_network_delay ""] == 0} {
            set start_network_delay 0.0
        }
        set gater_netdata [print_custom_clock $start_clock $launch_clock_name $launch_clock_edge_type $launch_clock_edge_value \
                             $launch_clk_latency $time_lent 0 0 0 "" "" $start_network_delay \
                             "" $launch_clk_gaterpoint [index_collection $path_points 0] $is_max]
        
    }
    #puts stderr "START-CLOCK == [expr {[clock microseconds] - $DTIME}]"
    
    #set DTIME [clock microseconds]
    
    set data_path_data [ print_custom_timing_segment $path $startpoint_arrival $input_delay $gater_netdata \
                           $is_max $print_options(fanin_slack_delta) $print_options(fanout_slack_delta)]

    
    set last_data_point [lindex $data_path_data 0]
    set last_netdata    [lindex $data_path_data 1]
    set data_cell_delay [lindex $data_path_data 2]
    set data_net_delay  [lindex $data_path_data 3]
    #set data_nid_delay  [lindex $data_path_data 3]
    set data_stage_cnt  [lindex $data_path_data 5]
    set eff_stage_cnt   [lindex $data_path_data 6]
    set IsRepeater   [lindex $data_path_data 7]

    set last_data_obj [get_attribute $last_data_point object]
    set last_data_obj_class [get_attribute $last_data_obj object_class]
    
    set data_arrival [get_attribute $last_data_point arrival]
    if {[string compare $data_arrival ""] == 0} {
        set required_time 0.0
    }
    set data_arrival [expr {$data_arrival + $startpoint_arrival}]
    if { [string compare $last_data_obj_class "port"] == 0 } {
        print_custom_port $last_data_point "" $last_netdata $startpoint_arrival $is_max
    } else {
        print_custom_inst $last_data_point "" "" $last_netdata $startpoint_arrival $IsRepeater $is_max $print_options(fanin_slack_delta)
    }

    set at_rt_offset [expr {max(8,$sig_digits + 6)}]
    
    puts $fileID [format "%${at_rt_offset}s \#\# Data Arrival Time\n" [report_format_float $data_arrival $sig_digits]]
    #puts stderr "DATA-PATH == [expr {[clock microseconds] - $DTIME}]"
    
    #set DTIME [clock microseconds]
    #echo [format "\#\# Data Arrival Time  %.${sig_digits}f\n" $data_arrival]

    if { [string compare $slack INFINITY] == 0 } {
        #UNCONSTRAINED NO TOUCH
        set endpoint_clock_latency 0
    } elseif { [string compare $end_clock ""] != 0 } {
        set clock_pin [get_attribute $path endpoint_clock_pin -quiet]
        if { $end_is_level && $is_max } {
            set capture_edge_type [get_attribute $path endpoint_clock_open_edge_type]
            set capture_edge_value [get_attribute $path endpoint_clock_open_edge_value -quiet]
        } else {
            set capture_edge_type [get_attribute $path endpoint_clock_close_edge_type]
            set capture_edge_value [get_attribute $path endpoint_clock_close_edge_value -quiet]
        }
        
        #HANDLE GOOFY CASE W/ set_max_delay
        if { [string compare $capture_edge_value ""] == 0} {
            set capture_edge_value 0.0
        }

        
        set uncertainty [get_attribute $path clock_uncertainty -quiet]
        if {[string compare $uncertainty ""] == 0} {
            set uncertainty 0
        }
        set jitter  [get_attribute $path clock_jitter -quiet]
        if {[string compare $jitter ""] == 0} {
            set jitter 0
        }
        set common_path_pessimism [calc_crpr_value $path]
    
        set path_margin [get_attribute -quiet $path path_margin]
        if {([string compare $path_margin ""] == 0) || ([string compare $path_margin UNINIT] == 0) || ([string compare $path_margin INFINITY] == 0)} {
            set path_margin 0.0
        } elseif {$is_max} {
            set path_margin [expr {0.0 - $path_margin}]
        }

        set output_delay [get_attribute $path endpoint_output_delay_value -quiet]
        
        set min_max_check_value ""
        #STUPID BUG w/ recovery/removal arcs and min/max commands
        set use_min_max_fix 0
        if { $is_min_max_delay_check } {
            set min_max_check_value [get_attribute -quiet $path exception_delay]
            if {([string compare $min_max_check_value ""] == 0) || ([string compare $min_max_check_value "UNINIT"] == 0)} {
                set min_max_check_value 0
            }
        }
        
        set constraint_info {}
         if { [string compare $output_delay ""] != 0 } {
            #UH...
        } elseif {[string compare $clock_pin ""] != 0} {
            if { $is_max && $end_is_level } {
                set constraint_type "borrow"
                set constraint_value [get_attribute $path time_borrowed_from_endpoint]
            } else {
                 if {[string compare "**async_default**" [get_attribute [get_attribute $path path_group] full_name]] == 0} {
                    if { $is_max } {
                        set constraint_type "recovery"
                    } else {
                        set constraint_type "removal"
                    }
                } else {
                    if { $is_max } {
                        set constraint_type "setup"
                    } else {
                        set constraint_type "hold"
                    }
                }
                set constraint_attribute [format "endpoint_%s_time_value" $constraint_type]
                set constraint_value [get_attribute $path $constraint_attribute -quiet]
                
                if {[string compare $constraint_value ""] == 0} { 
                    set constraint_value 0
                    set use_min_max_fix 1
                } elseif { $is_max } {
                    set constraint_value [expr {0.0 - $constraint_value}]
                    #set use_min_max_fix 1
                }
            }
            if {[string compare $constraint_value ""] != 0} {    
                set constraint_info [list $constraint_type $capture_edge_type $constraint_value]
            }
        } else {
            set constraint_info {}
        }
        
        set capture_clock_invert ""
        if {[string compare [get_attribute $path endpoint_clock_is_inverted] "true"] == 0} {
            set capture_clock_invert "'"
        }
        set capture_clock_name [format "%s%s" [get_attribute $end_clock full_name] $capture_clock_invert]
        
        set capture_clock_tim_point ""
        if { [sizeof_collection $capture_clk_paths] > 0} {
            #set first_capture_clk_point [index_collection [get_attribute [index_collection $capture_clk_paths 0] points] 0]
            set final_capture_clk_path [index_collection $capture_clk_paths [expr {[sizeof_collection $capture_clk_paths] - 1}]]
            set final_capture_clk_points [get_attribute $final_capture_clk_path points]
            
            set final_capture_clk_point_sizeof [sizeof_collection $final_capture_clk_points] 
            
            set capture_clock_tim_point [index_collection $final_capture_clk_points [expr {$final_capture_clk_point_sizeof - 1}]]
            
            set capture_clk_startpoint [index_collection $final_capture_clk_points 0]
            if { $final_capture_clk_point_sizeof > 1 } {
                for {set gater_index [expr {$final_capture_clk_point_sizeof - 2}]} {$gater_index >= 0} {incr gater_index -1} {
                    set capture_clk_gaterpoint [index_collection $final_capture_clk_points $gater_index]
                    if {[string compare [get_attribute -quiet $capture_clk_gaterpoint object.is_hierarchical] false] == 0} {
                        break
                    }
                }
            } else {
                set capture_clk_gaterpoint ""
            }
            set capture_clk_endpoint   [index_collection $final_capture_clk_points [expr {$final_capture_clk_point_sizeof - 1}]]
            
            set capture_clk_arrival [get_attribute $capture_clk_endpoint arrival]
            #set capture_clk_start   [get_attribute $first_capture_clk_point arrival]
            #set total_capture_delay [expr {$capture_edge_value + $endpoint_clock_latency}]
            set capture_clk_latency [get_attribute [index_collection $capture_clk_paths 0] startpoint_clock_latency]
            set capture_clk_extdelay 0.0 
            set endpoint_clock_latency $capture_clk_arrival
            set capture_network_delay [expr {$endpoint_clock_latency - $capture_clk_latency}]
            #set capture_network_delay [get_attribute $path endpoint_clock_latency]
            #set endpoint_clock_latency [expr {$capture_network_delay + $capture_clk_latency}]
        } else {
            set endpoint_clock_latency [get_attribute $path endpoint_clock_latency]
            
            set capture_network_delay $endpoint_clock_latency


            set capture_clk_startpoint ""
            set capture_clk_gaterpoint ""
            set capture_clk_latency 0.0

            set capture_clk_extdelay $capture_edge_value

            if { [string compare $output_delay ""] != 0 } {
                if { [string compare $last_data_obj_class "port"] == 0} {
                    set capture_clk_endpoint $last_data_point
                } else {
                    #MAX DELAY PINS DON'T HAVE A CLK NETWORK SO SET TO NULL
                    set capture_clk_endpoint ""
                }
                set capture_clk_extdelay [expr {$capture_clk_extdelay + $output_delay}]
            } else {
                set capture_clk_endpoint $clock_pin
            }
        }
        
        set capture_clk_segment_cnt [sizeof_collection $capture_clk_paths]
        set final_arrival 0.0
        if {$capture_clk_segment_cnt  == 0} {

            print_custom_clock $end_clock $capture_clock_name $capture_edge_type $capture_edge_value \
              $capture_clk_latency 0 $uncertainty $common_path_pessimism $path_margin "output $output_delay" $min_max_check_value $capture_network_delay \
              "" $capture_clk_gaterpoint $capture_clk_endpoint $is_max

            if { [string compare $output_delay ""] != 0 } {
                #UH...
                if {$is_max} {
                    set final_arrival [expr {$capture_edge_value + $capture_clk_latency + $capture_network_delay - $output_delay}]
                } else {
                    set final_arrival [expr {$capture_edge_value + $capture_clk_latency + $capture_network_delay + $output_delay}] 
                }
            } elseif {[llength constraint_info] > 0} {
                if { ([string compare $capture_clock_tim_point ""] != 0) && \
                       ([string compare [get_attribute [get_attribute $capture_clock_tim_point object] full_name] [get_attribute $clock_pin full_name]] == 0) \
                   } {
                    set final_arrival [print_custom_inst $capture_clock_tim_point "" $constraint_info $last_netdata $capture_clk_extdelay $IsRepeater $is_max -1]
                } elseif {[string compare [get_attribute $clock_pin object_class] "port"] == 0} {
                    #BOZO??? NO IDEA WHAT TO DO HERE
                } elseif {[string compare $clock_pin ""] != 0} {
                    set final_arrival [print_custom_inst $clock_pin "" $constraint_info $last_netdata [expr {$endpoint_clock_latency + $capture_clk_extdelay}] $IsRepeater $is_max -1]
                } else {
                }
            } elseif { $is_min_max_delay_check } {
                #BOZO???
                #echo "I HAVE NO IDEA WHAT TO DO HERE W/ a set_min/max_delay commands w/ a capture clock but w/o a clock pin"    
            }
        } else {
            print_custom_clock $end_clock $capture_clock_name $capture_edge_type $capture_edge_value \
              $capture_clk_latency 0 $uncertainty $common_path_pessimism $path_margin "" $min_max_check_value 0 \
              $capture_clk_startpoint $capture_clk_gaterpoint $capture_clk_endpoint $is_max
            
            set prev_clk_point ""
            set saw_driver 0
            
            if {!$::timing_point_arrival_attribute_compatibility} {
                set capture_clk_extdelay [expr {$capture_edge_value + $capture_clk_extdelay}]
            }
            if {$common_path_pessimism != 0.0} {   
                set crpr_common_point [get_attribute -quiet $path crpr_common_point.full_name]
            } else {
                set crpr_common_point ""
            }
            if {$print_options(full_clock_expanded) || ($capture_clk_segment_cnt == 1)} {
                set capture_clk_data [ print_custom_timing_segment $capture_clk_paths $capture_clk_extdelay 0 "" $is_max -1 -1 $crpr_common_point]
            } else {
                set final_capture_start_time [expr {[get_attribute [index_collection [get_attribute [index_collection $capture_clk_paths end-1] points] end] arrival] - $capture_clk_latency}]
                if {$::timing_point_arrival_attribute_compatibility} {
                    set final_capture_start_time [expr {$final_capture_start_time - $capture_edge_value}]
                }
                set capture_clk_data [ print_custom_timing_segment [index_collection $capture_clk_paths end] $capture_clk_extdelay $final_capture_start_time "" $is_max -1 -1 $crpr_common_point]
            }
            
            set last_capture_clk_point [lindex $capture_clk_data 0]
            set last_capture_clk_netdata [lindex $capture_clk_data 1]
            set last_capture_clk_object [get_attribute $last_capture_clk_point object]

            if { [string compare $output_delay ""] != 0 } {
                #NEED TO FLIP OUTPUT DELAY
                if { $is_max } {
                    set output_delay [expr {0.0 - $output_delay}]
                }
                if { [string compare [get_attribute $last_capture_clk_object object_class] "port"] == 0 } {
                    set final_arrival [print_custom_port $last_capture_clk_point "output $output_delay" $last_capture_clk_netdata $capture_clk_extdelay $is_max]
                } else {
                    set final_arrival [print_custom_inst $last_capture_clk_point "" "extdel ? $output_delay" $last_capture_clk_netdata $capture_clk_extdelay $IsRepeater $is_max -1]
                }
            } elseif { [string compare [get_attribute $last_capture_clk_object object_class] "port"] == 0 } {
                #UH....
                set final_arrival [print_custom_port $last_capture_clk_point "" $last_capture_clk_netdata $capture_clk_extdelay $is_max]
            } else {
                set capture_clk_constraint $constraint_info
                set final_arrival [print_custom_inst $last_capture_clk_point "" $capture_clk_constraint $last_capture_clk_netdata $capture_clk_extdelay $IsRepeater $is_max -1]
            }
        }
        if {$common_path_pessimism != 0.0} {
            set final_arrival [print_custom_path_modification $final_arrival $common_path_pessimism "CRPR"]
        }
        if {$path_margin != 0.0} {
            set final_arrival [print_custom_path_modification $final_arrival $path_margin "Path_Margin"]
        }
        if {$uncertainty != 0.0} {
            set final_arrival [print_custom_path_modification $final_arrival $uncertainty "Uncertainty"]
        }
        if {$jitter != 0.0} {
            set final_arrival [print_custom_path_modification $final_arrival [expr {$jitter * -1.0}] "Jitter"]
        }
        if {$is_min_max_delay_check} {
            if {$is_max} {
                set final_arrival [print_custom_path_modification $final_arrival $min_max_check_value "Max_Delay"]
            } else {
                set final_arrival [print_custom_path_modification $final_arrival $min_max_check_value "Min_Delay"]
            }
            
            if {$use_min_max_fix} {
                set required_time [expr {[get_attribute $path required] + $min_max_check_value}]
            } elseif { [string compare $output_delay ""] != 0 } {
                set required_time [get_attribute $path required]
            } else {
                set required_time [expr {[get_attribute $path required] + $capture_edge_value} ]
            }
        } else {
            set required_time [expr {[get_attribute $path required] + $capture_edge_value} ]
        }
        if {[string compare [get_app_var timing_pocvm_enable_analysis] true] == 0} {
            if {$is_max} {
                set slack_adjust [expr {$slack - ($required_time - $data_arrival)}]
            } else {
                set slack_adjust [expr {($data_arrival - $required_time) - $slack}]
            }
            if {$slack_adjust != 0.0} {
                set required_time [print_custom_path_modification $required_time $slack_adjust "Statistical_Adjustment"]
            }
        }
        puts $fileID [format "%${at_rt_offset}s \#\# Data Required Time" [report_format_float $required_time $sig_digits]]
    } elseif { $is_min_max_delay_check } {
        #MIN/MAX DELAY CMD
        set min_max_check_value [get_attribute -quiet $path exception_delay]
        if {([string compare $min_max_check_value ""] == 0) || ([string compare $min_max_check_value "UNINIT"] == 0)} {
            set min_max_check_value 0
        }
        if { $is_max } {
            #set min_max_check_value [expr {$slack - $data_arrival}]
            set min_max_check_type "maxdel"
        } else {
            #set min_max_check_value [expr {0.0 - [get_attribute $path required]}]
            set min_max_check_type "mindel"
        }
        if { [string compare $last_data_obj_class "port"] == 0 } {
            print_custom_port $last_data_point "$min_max_check_type $min_max_check_value" $last_netdata 0 $is_max
        } else {
            print_custom_inst $last_data_point "" "$min_max_check_type ? $min_max_check_value" $last_netdata 0 $IsRepeater $is_max -1
        }

        #NO UNCERTAINTY

        #?? CAN YOU HAVE CRPR HERE?
        set common_path_pessimism [calc_crpr_value $path]
        if {$common_path_pessimism != 0.0} {
            print_custom_path_modification 0 $common_path_pessimism "CRPR"
        }

        set path_margin [get_attribute -quiet $path path_margin]
        if {([string compare $path_margin ""] == 0) || ([string compare $path_margin UNINIT] == 0)} {
            set path_margin 0.0
        } elseif {$is_max} {
            set path_margin [expr {0.0 - $path_margin}]
            if {$path_margin != 0.0} {
                print_custom_path_modification 0 $path_margin "Path_Margin"
            }
        }

        #set required_time [expr {[get_attribute $path required] + $capture_edge_value} ]
        
        set required_time [get_attribute $path required]
        if {[string compare [get_app_var timing_pocvm_enable_analysis] true] == 0} {
            if {$is_max} {
                set slack_adjust [expr {$slack - ($required_time - $data_arrival)}]
            } else {
                set slack_adjust [expr {($data_arrival - $required_time) - $slack}]
            }
            if {$slack_adjust != 0.0} {
                set required_time [print_custom_path_modification $required_time $slack_adjust "Statistical Adjustment"]
            }
        }
        puts $fileID [format "%${at_rt_offset}s \#\# Data Required Time" [report_format_float $required_time $sig_digits]]
    } elseif { [string compare $slack INFINITY] != 0 } {
        puts "ERROR: Have no idea how I'm here!!!! No min/max delay or clock but i have slack some how"
    } else {
        #UNCONSTRAINED PATH
    }
    #puts stderr "END-CLOCK == [expr {[clock microseconds] - $DTIME}]"
    
    if { [string compare $slack INFINITY] != 0 } {
        set formated_slack [format "%.${sig_digits}f" $slack]
    } else {
        set formated_slack $slack
    }
    puts $fileID $dashed_line
    
    set total_data_delay [expr {$data_cell_delay + $data_net_delay}]
    
    if { $total_data_delay == 0 } {
        set data_cell_percent 0
        set data_net_percent  0
    } else {
        set data_cell_percent [expr {abs($data_cell_delay / $total_data_delay) * 100.0 }]
        set data_net_percent  [expr {abs($data_net_delay / $total_data_delay) * 100.0 }]
    }
    
    
    if { ([string compare $start_clock ""] != 0) && ([string compare $end_clock ""] != 0) } {
        if { $is_max } {
            set clock_skew [expr {[get_attribute $path startpoint_clock_latency] - ($endpoint_clock_latency + $common_path_pessimism)}]
        } else {
            set clock_skew [expr {($endpoint_clock_latency + $common_path_pessimism) - [get_attribute $path startpoint_clock_latency]}]
        }
        if {$::timing_point_arrival_attribute_compatibility && ([sizeof_collection $capture_clk_paths] > 0)}  {
            if { $is_max } {
                set clock_skew [expr {$clock_skew + $capture_edge_value}]
            } else {
                set clock_skew [expr {$clock_skew - $capture_edge_value}]
            }
        }
        set clock_skew [format "%.${sig_digits}f" $clock_skew]
    } else {
        set clock_skew NA
    }

    set nid_total_str ""
    if {$print_options(show_xtalk)} {
        set nid_data_delay [lindex $data_path_data 4]
        if { $total_data_delay == 0 } {
            set nid_percent 0
        } else {
            set nid_percent [expr {abs($nid_data_delay / $total_data_delay) * 100.0 }]
        }
        set nid_total_str [format " NID_Delay: %.${sig_digits}f(%.2f%%)" $nid_data_delay $nid_percent]
    }
    puts $fileID [format "Slack: %s Cell_Delay: %.${sig_digits}f(%.2f%%) Wire_Delay: %.${sig_digits}f(%.2f%%)%s Clock_Skew: %s Stages: %s Eff_Stages: %s" \
                    $formated_slack \
                    $data_cell_delay \
                    $data_cell_percent \
                    $data_net_delay \
                    $data_net_percent \
                    $nid_total_str \
                    $clock_skew \
                    $data_stage_cnt \
                    $eff_stage_cnt \
                   ]
    
    unset startpt
    unset endpt
    unset start_clock
    unset end_clock
    #puts $fileID "PTIME $path_count: [expr {[clock microseconds] - $PTIME}]"
    return 1
}

proc write_fmt {args} {
    global TILEBUILDER_CPUS
    global TILEBUILDER_TMPDIR
    global P
    suppress_message CMD-041
    suppress_message LNK-041

    # Check if weighted LOL counting is enabled
    set use_weighted_lol 0
    if {[info exists P(TIMING_TRACKER_WEIGHTED_STAGES)] && $P(TIMING_TRACKER_WEIGHTED_STAGES)} {
        set use_weighted_lol 1
        # Load PCWLOL weights file if specified and weighted mode is enabled
        if {[info exists P(LOLSTAT_PCW_FACTORS_FILE)]} {
            if {[load_pcwlol_weights_file $P(LOLSTAT_PCW_FACTORS_FILE)] == 0} {
                echo "WARNING: Failed to load weights file, falling back to non-weighted mode"
                set use_weighted_lol 0
            }
        } else {
            echo "WARNING: TIMING_TRACKER_WEIGHTED_STAGES is set but LOLSTAT_PCW_FACTORS_FILE is not defined"
            echo "WARNING: Falling back to non-weighted mode"
            set use_weighted_lol 0
        }
    }

    array set options ""
    set options(-crosstalk_delta) 0
    set options(-derate) 0
    set options(-variation) 0
    set options(-voltage) 0
    #set options(-transition_time) 0
    
    set options(-significant_digits) [get_app_var report_default_significant_digits]
    set options(-fanin_slack_delta) 0
    set options(-fanout_slack_delta) 0
    set options(-max_fanout_limit) 8
    set options(-route_delay_threshold) -1
    set options(-physical) 0
    set options(-annotation_attributes) 0
    
    #set options(-ncpus) $TILEBUILDER_CPUS
    set options(-path_start_index) 1
    set options(-header_mode) net
    set options(-subblocks) 0
    set options(-report_vt) 0

    set options(-nworst) 1
    set options(-max_paths) 1
    
    #FORCE THIS ON
    set options(-include_hierarchical_pins) 1


    parse_proc_arguments -args $args options
    
    set tim_path_ops ""
    if {[info exists options(-start_end_pair)]} {
        set tim_path_ops "$tim_path_ops -start_end_pair"
    } else {
        set tim_path_ops "$tim_path_ops -nworst $options(-nworst) -max_paths $options(-max_paths)"
        if {[info exists options(-unique_pins)]} {
            set tim_path_ops "$tim_path_ops -unique_pins"
        }
    }
    
    if {$options(-derate)} {
        if {([llength [get_app_var -list variation_report_timing_increment_format]]) && \
              ([string compare [get_app_var variation_report_timing_increment_format] delay_variation] == 0)} \
          {   
              set options(-variation) 1
          }
    }
    
    #THESE GUYS ARE ORDER DEPENDANT SO HAVE TO DO IT THIS WAY
    for {set i 0} {$i < [llength $args]} {incr i} {
        set key [lindex $args $i]
        if {[regexp {^\-(rise_|fall_)?(to|from|through)} $key]} {
            incr i
            set tim_path_ops "$tim_path_ops $key \"[lindex $args $i]\""
        }
    }
    foreach boolean_option {-true -false -include_hierarchical_pins -justify -trace_latch_borrow -normalized_slack -dont_merge_duplicates -pocv_pruning} {
        if {([info exists options($boolean_option)]) && ($options($boolean_option) == 1)} {
            set tim_path_ops "$tim_path_ops $boolean_option"
        }
    }
    foreach list_option { -exclude -rise_exclude -fall_exclude -group -dvfs_scenarios} {
        if {([info exists options($list_option)]) && ([string length $options($list_option)] > 0) && ([llength $options($list_option)] > 0)} {
            set tim_path_ops "$tim_path_ops $list_option \"$options($list_option)\""
        }
    }
    foreach string_option {-delay_type -path_type -true_threshold -slack_greater_than -slack_lesser_than -pba_mode -domain_crossing} {
        if {([info exists options($string_option)]) && ([string length $options($string_option)] > 0)} {
            set tim_path_ops "$tim_path_ops $string_option $options($string_option)"
        }
    }
    
    if {[info exists options(path_objects)]} {
        set paths $options(path_objects)
    } else {
        set paths [eval [concat "get_timing_paths " $tim_path_ops]]
    }
    
    if {$options(-path_start_index) <= 1} {
        report_print_header "timing"
    }
    
    if {[string compare $paths ""] == 0} {
        puts "No paths.\n";
        unsuppress_message CMD-041
        return 0;
    }
    
    # checking for option -pin_header_mode
    set pin_header_mode pin
    if {[string compare $options(-header_mode) net] == 0} {
        set pin_header_mode net
    } elseif {[string compare $options(-header_mode) pin] == 0} {
        #DO NOTHING
    } elseif {[string compare $options(-header_mode) datapin] == 0} {
        set pin_header_mode datapin
    } else {
        echo "ERROR: invalid header_mode $options(-header_mode), forcing to pin mode"
    }
    if {[info exists options(-sig_cap_digits)] == 0} {
        set options(-sig_cap_digits) $options(-significant_digits)
    }

    #DEBUG
    #global print_options
   
    array set print_options ""
    set print_options(pin_mode)              $pin_header_mode
    set print_options(subblocks)             $options(-subblocks)
    set print_options(show_xtalk)            $options(-crosstalk_delta) 
    set print_options(show_derate)           $options(-derate) 
    set print_options(show_variation)        $options(-variation) 
    set print_options(show_volt)             $options(-voltage) 
    set print_options(sig_digits)            $options(-significant_digits) 
    set print_options(sig_cap_digits)        $options(-sig_cap_digits) 
    set print_options(fanin_slack_delta)     $options(-fanin_slack_delta) 
    set print_options(fanout_slack_delta)    $options(-fanout_slack_delta) 
    set print_options(max_fanout_limit)      $options(-max_fanout_limit) 
    set print_options(route_delay_threshold) $options(-route_delay_threshold)
    set print_options(physical)              $options(-physical)
    set print_options(show_annotation)       $options(-annotation_attributes)
    
    if {[info exist options(-path_type)] && [regexp "^full_clock_e" $options(-path_type)]} {
        set print_options(full_clock_expanded) 1
    } else {
        set print_options(full_clock_expanded) 0
    }

    if {[info exists P]} {
        set bf_iv_regex_list ""
        if {[info exists P(INV_CELL_PATTERN)]} {
            foreach inv_pattern $P(INV_CELL_PATTERN) {
                set inv_pattern [regsub -all {\*} $inv_pattern {.*}]
                lappend bf_iv_regex_list $inv_pattern
            }
        }
        if {[info exists P(BUF_CELL_PATTERN)]} {
            foreach buf_pattern $P(BUF_CELL_PATTERN) {
                set buf_pattern [regsub -all {\*} $buf_pattern {.*}]
                lappend bf_iv_regex_list $buf_pattern
            }
        }
        if {[llength bf_iv_regex_list] > 0} {
            set print_options(effective_stage_regexp) "\^\([join $bf_iv_regex_list {|}]\)\$"
        }
    }
    set print_options(use_weighted_lol)      $use_weighted_lol

    if {$options(-report_vt)} {
        if {[llength $::fmt_vt_types] <= 0} {
            echo "ERROR: fmt_vt_types is not set, cannot use -report_vt"
            set print_options(report_vt) 0
        } elseif {[llength $::fmt_vt_types] != [llength $::fmt_vt_regexp]} {
            echo "ERROR: fmt_vt_types($::fmt_vt_types) doesn't have the same number of entries as fmt_vt_regexp($fmt_vt_regexp), cannot use -report_vt"
            set print_options(report_vt) 0
        } else {
            set print_options(report_vt) 1
        }
    } else {
        set print_options(report_vt) 0
    }

    if {[info exists options(-output)]} {
        if {[catch {open $options(-output) w} masterFH]} {
            puts stderr "ERROR: Cannot open $options(-output): $masterFH"
        }
    } else {
        set masterFH stdout
    }
    #set design_cap_unit [get_attribute [get_design] capacitance_unit_in_farad]
    #set ceff_unit_fix [expr 1e-12 / $design_cap_unit]
    set path_cnt [sizeof_collection $paths]
    
    if {[info exists options(-ncpus)]} {
        if {$options(-ncpus) > $path_cnt} {
            set options(-ncpus) $path_cnt
        }
    } else {
        if {$path_cnt < $::fmt_path_count_parallel_threshold} {
            set options(-ncpus) 1
        } elseif {$TILEBUILDER_CPUS > $path_cnt} {
            set $options(-ncpus) $path_cnt
        } else {
            set options(-ncpus) $TILEBUILDER_CPUS
        }
    }
    
    if {$options(-ncpus) <= 1} {
        set print_options(fileID) $masterFH
        
        set path_index $options(-path_start_index)
        foreach_in_collection path $paths {
            print_custom_timing_path $path $path_index 0 
            puts $masterFH ""
            incr path_index
        }
    } else {
        global tcl_platform
        set machine [exec /bin/hostname]
        set mypid [pid]
        set outfilename "$TILEBUILDER_TMPDIR/$tcl_platform(user).$machine.$mypid"
        
        set cmds2run ""

        if {[expr {$path_cnt/$::fmt_bucket_size}] > $::fmt_bucket_limit} {
            set bucket_size [expr {int(ceil($path_cnt/$::fmt_bucket_limit))}]
        } else {
            set bucket_size $::fmt_bucket_size
        }

        set cpu_bucket_size [expr {int($path_cnt / $options(-ncpus))}]

        if {$::fmt_disable_bucket_mode || ([expr {$path_cnt/$bucket_size}] < [expr {$path_cnt/$cpu_bucket_size}])} {
            set do_bucket_mode 0
            set bucket_size $cpu_bucket_size
        } else {
            set do_bucket_mode 1
        }
        if {$do_bucket_mode} {
            set outfile_list ""
            set end 0
            set i 0
            while {$end < $path_cnt} {
                set start $end
                set end [expr {$end + $bucket_size - 1}]
                
                if {$end >= $path_cnt} {
                    set end [expr {$path_cnt - 1}]
                }
                echo "$i\($bucket_size\): $start -> $end"
                set rpt_file "$outfilename.$i.rpt"
                set log_file "$outfilename.$i.log"
                lappend cmds2run [list parallel_paths2fmt $rpt_file $paths $start $end $options(-path_start_index) ]
                
                lappend cmds2run $log_file
                lappend outfile_list $rpt_file

                incr end
                incr i
            }
        } else {
            set outfile_list ""
            for {set i 0} {$i < $options(-ncpus)} {incr i} {
                set start [expr {$bucket_size * $i}]
                if {$i == [expr {$options(-ncpus) - 1}]} {
                    set end [expr {$path_cnt - 1}]
                } else {
                    set end [expr {$start + $bucket_size - 1}]
                }
                #echo "$i\($bucket_size\): $start -> $end"
                set rpt_file "$outfilename.$i.rpt"
                set log_file "$outfilename.$i.log"
                lappend cmds2run [list parallel_paths2fmt $rpt_file $paths $start $end $options(-path_start_index) ]
                
                lappend cmds2run $log_file
                lappend outfile_list $rpt_file
            }
        }
        parallel_execute $cmds2run
        
        foreach tmpfile $outfile_list {
            if {[catch {open $tmpfile r} fileID]} {
                puts stderr "ERROR: Cannot open $tmpfile: $fileID"
            } else {
                while {[gets $fileID line] >= 0} {
                    puts $masterFH $line
                }
                close $fileID
            }
            file delete $tmpfile
        }
    }
    if {[string compare $masterFH stdout] != 0} {
        close $masterFH
    }
    unsuppress_message CMD-041
    unsuppress_message LNK-041
    return 1
}


define_proc_attributes write_fmt \
  -info "Generated a formatted timing report, takes same arguments as report_timing" \
  -define_args {
      {-to "To pins, ports, nets, or clocks" to_list list optional}
      {-rise_to "Rising to pins, ports, nets, or clocks" rise_to_list list optional}
      {-fall_to "Falling to pins, ports, nets, or clocks" fall_to_list list optional}
      {-from    "From pins, ports, nets, or clocks" from_list list optional} 
      {-rise_from "Rising from pins, ports, nets, or clocks" rise_from_list list optional}
      {-fall_from "Falling from pins, ports, nets, or clocks" fall_from_list list optional}
      {-exclude "Exclude pins, ports, nets or cells" exclude_list list optional}
      {-rise_exclude "Exclude rising of pins, ports, nets or cells" rise_exclude_list list optional}
      {-fall_exclude "Exclude falling of pins, ports, nets or cells" fall_exclude_list list optional}
      {-through "Through pins, ports, or nets" through_list list {optional merge_duplicates}}
      {-rise_through "Rising through pins, ports, or nets" rise_through_list list {optional merge_duplicates}}
      {-fall_through "Falling through pins, ports, or nets" fall_through_list list {optional merge_duplicates}}
      
      {-delay_type "Type of path delay" delay_type one_of_string {optional value_help {values {max min min_max max_rise max_fall min_rise min_fall}}}}      
      {-nworst "List N worst paths to endpoint: Value >= 1" paths_per_endpoint int optional}
      {-max_paths "Maximum number of paths per path group to output: Value >= 1" count int optional}
      {-path_type "Format for path report" format one_of_string {optional value_help {values {full full_clock full_clock_expanded}}}}
      {-unique_pins "Find paths through unique pins" "" boolean optional}
      {-start_end_pair "List worst path per start-endpoint pair" "" boolean optional}
      {-slack_greater_than "Display paths with slack greater than this" slack_limit float optional}
      {-slack_lesser_than "Display paths with slack less than this" slack_limit float optional}
      {-ignore_register_feedback "Ignore feedback loops to registers" feedback_slack_cutoff float optional}
      {-report_ignored_register_feedback "???" "" boolean optional}
      {-group "Limit report to paths in these groups" group_name list optional}
      {-normalized_slack "Paths  are gathered and sorted using normalized slack instead of slack" "" boolean optional}
      {-trace_latch_borrow "Trace timing paths through borrowing latches" "" boolean optional}
      {-pba_mode "Path-based analysis mode default is exhaustive" effort one_of_string {optional value_help {values {path exhaustive}}}}
      {-dont_merge_duplicates "Do not merge paths that appear in more than one scenario" "" boolean optional}
      {-domain_crossing "Specifies the domain crossing report mode" domain_crossing_mode one_of_string {optional value_help {values {all only_crossing exclude_crossing}}}}
      {-dvfs_scenarios "Specifies a collection of DVFS scenarios to analyze" dvfs_scenarios_list list {optional merge_duplicates}}
      {-pocv_pruning "Prunes away all subcritical paths which have no impact on high-sigma failure rate" "" boolean optional}
          
      {-input_pins "Show input pins in path: always true" "" boolean optional}
      {-nets "Display net names: always true" ""  boolean optional}
      {-transition_time "Display transition time for each pin: always true" ""  boolean optional}
      {-nosplit "Do not split lines when columns overflow: always true"  ""  boolean optional}
      {-capacitance "Dummy Place Holder" "" boolean optional}
      
      {-exceptions "Scope of timing exceptions reporting, Not supported placeholder" exception_type one_of_string {optional value_help {values {dominant overridden all}}}}
      {-pre_commands  "Not supported placeholder" pre_command_string string optional}
      {-post_commands "Not supported placeholder" pre_command_string string optional}
      
      {-true "Find true paths, obsolete?" "" boolean optional}
      {-false "Reports only false-path. Requires -nworst, obsolete?" "" boolean optional}
      {-justify "Justify paths with input vector, obsolete?" "" boolean optional}
      {-true_threshold "Path-length threshold, obsolete?" path_delay float optional}
      
      {-sort_by "Sort by normalized slack (slack|group), doesn't not work for fmt" sort_by one_of_string {optional value_help {values {slack group}}}}
      
      {-include_hierarchical_pins "Create timing point for each hierarchical pin in path" "" boolean optional}
      
      {-significant_digits "Number of digits after the  decimal  point to  be displayed  for time values" digits int optional}
      {-sig_cap_digits "Number of digits after the  decimal point to  be displayed for capacitance values" digits int optional}
      {-derate "Show derate factors" "" boolean optional}
      {-variation "Report variation-aware info" "" boolean optional}
      {-voltage "Report pin voltages" "" boolean optional}
      {-crosstalk_delta "Show crosstalk effects, forced true for si-runs" "" boolean optional}
      {-fanin_slack_delta "If delta between min & max slacks exceeds this value fanin slack information for a inst will be printed" fanin_delta float optional}
      {-fanout_slack_delta "If delta between min & max slacks exceeds this value fanout slack information for a net will be printed" fanin_delta float optional}
      {-max_fanout_limit "Number of fannout slacks to print" fanout_limit int optional}
      {-route_delay_threshold "Print route information for any net w/ a wire delay greater than X, use -1 to disable" wire_delay float optional}
      {-ncpus "Number of threads to use" cpu_count int optional}
      {-path_start_index "Starting index for the path number, defaults to 1" number int optional}
      {-header_mode "The path header is pin based, default mode" header_mode one_of_string {optional value_help {values {pin datapin net}}}}
      {-subblocks "Include sub-blocks in the path header" "" boolean optional}
      {-report_vt "Print a vt summary report in the path footer" "" boolean optional}
      {-supply_net_group "Show supply net group names for path elements" "" boolean optional}
      {-physical "Show the physical locations for pins" "" boolean optional}
      {-annotation_attributes "Show annotation attributes (H marker) for annotated delays" "" boolean optional}

      {-output "Prints directly to given file rather than stdout" file_name string optional}
      
      {path_objects "Timing path collection" path_collection string optional}
  }

proc parallel_paths2fmt { scratch_file paths start_index end_index path_start_count} {
    
    upvar "print_options" print_options
    
    if {[catch {open $scratch_file w} fileID]} {
        puts stderr "ERROR: Cannot open $scratch_file: $fileID"
        return 0
    }
    set print_options(fileID) $fileID
    set path_count [expr {$start_index + $path_start_count}]
    for {set i $start_index} {$i <= $end_index} {incr i} {
        set path [index_collection $paths $i]
        print_custom_timing_path $path $path_count 0 
        puts $fileID ""
        incr path_count
    }
    close $fileID
    return 1
}
