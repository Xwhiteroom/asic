# Copyright (c) 2026 Syed Shakir Iqbal (Xwhiteroom)
# SPDX-License-Identifier: MIT
#
#---------------------------------------------------------------------------------------------
proc ssi_audit_print_stage {red_blue comment} {
      if { $red_blue == "blue" } {
              puts [format "\033\[34m%-30s %-100s \033\[0m" [date] "$comment" ]
      } else {
              puts [format "\033\[31m%-30s %-100s \033\[0m" [date] "$comment" ]  
      }
}
proc ssi_audit_print_stage {color comment } {
    if { [regexp "red" $color] } {
        set code 31
    } elseif { [regexp "green" $color] } {
        set code 32
    } elseif { [regexp "orange" $color] } {
        set code 33
    } elseif { [regexp "blue" $color] } {
        set code 34
    } else {
        set code 0
    }
    if { [regexp "nodate" $color] } {
        set xdate ""
    } else {
        set xdate [date]
    }

    puts [format "\033\[${code}m%-30s %-100s \033\[0m" $xdate "$comment"]
}
proc ssi_fc_current_design { } {
        set design_name [lindex [split [get_object_name [current_design]] ":"] end]
        regsub -all {.design$} $design_name {} design_name 
        return $design_name
}


proc ssi_get_x_ports {} {
        set all_seq             [get_cells -hier -filter "is_hierarchical==false && is_sequential==true"]
        set all_seq_ck          [get_pins -of_object $all_seq -filter "is_clock_used_as_clock==true && direction==in"]
        set all_seq_lck         [get_pins -of_object $all_seq -filter "lib_pin.is_clock_pin==true && direction==in"]
        set all_seq_lrst        [get_pins -of_object $all_seq -filter "lib_pin.is_async_pin==true && direction==in"]
        set reset_ports         [get_ports -quiet  [all_fanin -flat -startpoints_only -to $all_seq_lrst ]]
        set clock_ports         [get_ports -quiet  [all_fanin -flat -startpoints_only -to $all_seq_lck]]
        set clock_reset         [remove_from_collection -intersect $clock_ports $reset_ports]
        set clock_ports         [remove_from_collection $clock_ports $clock_reset]
        set reset_ports         [remove_from_collection $reset_ports $clock_reset]
        return  [list $clock_ports $clock_reset $reset_ports ]
}
proc ssi_get_clock_ports    {} {    return [lindex [ssi_get_x_ports] 0] }
proc ssi_get_clkrst_ports   {} {    return [lindex [ssi_get_x_ports] 1] }
proc ssi_get_reset_ports    {} {    return [lindex [ssi_get_x_ports] 2] }

#---------------------------------------------------------------------------------------------
proc ssi_audit_unclocked_registers {outdir dft_pat_list_of_clocknames_collection scenario_should_be_mode_dot_corner} {
        set design_name [ssi_fc_current_design]
        set dft_pat_list $dft_pat_list_of_clocknames_collection
        set scenario $scenario_should_be_mode_dot_corner
        set outdir $outdir
        file mkdir $outdir
        set outdir [file normalize $outdir]
        ssi_audit_print_stage blue  [format "\n\n=============================================================================================" ]
        ssi_audit_print_stage green [format "<CLK_AUD> : Created o/p directory %s"  "$outdir"]
        set filter_tag "unclocked_registers"
        set empty_collection [remove_from_collection [all_clocks] [all_clocks]]


        # Set Clock Filters
        set valid_dft_clocks [get_clocks -quiet $dft_pat_list]
        if { [llength    $dft_pat_list] == "0" } { 
                ssi_audit_print_stage red   [format "\n<CLK_AUD> : No DFT Pattern Provided  (%03d) Clocks  dft_pat_list=%s"  "[sizeof_collection $valid_dft_clocks]" "$dft_pat_list"]
        } elseif { [sizeof_collection $valid_dft_clocks] } { 
                ssi_audit_print_stage green [format "\n<CLK_AUD> : DFT Pattern Provided  (%03d) Clocks     dft_pat_list=%s"  "[sizeof_collection $valid_dft_clocks]" "$dft_pat_list"]
                ssi_audit_print_stage blue  [format "            Clocks : [get_object_name $valid_dft_clocks]"]
        } else {
                ssi_audit_print_stage red   [format "\n<CLK_AUD> : DFT Pattern Provided  (%03d) Matches    dft_pat_list=%s"  "[sizeof_collection $valid_dft_clocks]" "$dft_pat_list"]
        }
        set valid_func_clocks [remove_from_collection [all_clocks] $valid_dft_clocks]
        ssi_audit_print_stage green [format "\n<CLK_AUD> : Valid  (%03d) Clocks  for fuctional case  "  "[sizeof_collection $valid_func_clocks]" "$dft_pat_list"]
        ssi_audit_print_stage blue  [format "            Clocks : [get_object_name $valid_func_clocks]"]

        # Set Register Collection
        set all_seq             [get_cells -hier -filter "is_hierarchical==false && is_sequential==true"]
        set all_seq_ck          [get_pins -of_object $all_seq -filter "is_clock_used_as_clock==true && direction==in"]
        set all_seq_lck         [get_pins -of_object $all_seq -filter "lib_pin.is_clock_pin==true && direction==in"]
        set all_seq_lrst        [get_pins -of_object $all_seq -filter "lib_pin.is_async_pin==true && direction==in"]

        set all_reg_ck          [all_register -clock_pins]
        set all_reg_rst         [all_register -async_pins]        
        set master_ck           [add_to_collection -unique $all_seq_ck  $all_reg_ck]
        set total_ck            [sizeof_collection $master_ck]

        set x_ports             [ssi_get_x_ports]
        set reset_ports         [lindex $x_ports 2]
        set clock_reset         [lindex $x_ports 1]
        set clock_ports         [lindex $x_ports 0]
        
        ssi_audit_print_stage blue  [format "=============================================================================================" ]
        ssi_audit_print_stage green [format "<CLK_AUD> : Initial Stats for $design_name"]
        ssi_audit_print_stage blue  [format "            %-50s = %10s" "Is_Sequential_True" "[sizeof_collection $all_seq]" ]
        ssi_audit_print_stage blue  [format "            %-50s = %10s" "Is_Sequential_True_CK" "[sizeof_collection $all_seq_ck]" ]
        ssi_audit_print_stage blue  [format "            %-50s = %10s" "All_Reg_CK" "[sizeof_collection $all_reg_ck]" ]
        ssi_audit_print_stage blue  [format "            %-50s = %10s" "Master_CK" "[sizeof_collection $master_ck]" ]
        ssi_audit_print_stage blue  [format "=============================================================================================" ]        
        ssi_audit_print_stage blue  [format "            %-50s = %10s" "ClockPorts" "[sizeof_collection $clock_ports]" ]
        ssi_audit_print_stage blue  [format "            %-50s = %10s" "ResetPorts" "[sizeof_collection $reset_ports]" ]  
        ssi_audit_print_stage blue  [format "            %-50s = %10s" "CkRstPorts" "[sizeof_collection $clock_reset]" ]                

        if { $total_ck == 0} { return 0 }

        # Creat DB
        array unset clock_db

        set clock_db(99_Total_CK)   $master_ck

        set type "01_TieOff_CK" ;       set clock_db($type)  [filter_collection $master_ck "constant_value==0"] ; set master_ck [remove_from_collection $master_ck $clock_db($type)]
        set type "02_NoClk_D+CK" ;      set clock_db($type)  [filter_collection $master_ck "undefined(clocks)"] ; #set master_ck [remove_from_collection $master_ck $clock_db($type)]

        set temp_db0    $empty_collection
        set temp_db0_0  $empty_collection
        set temp_db0_1  $empty_collection

        set temp_db1_0  $empty_collection
        set temp_db1_1  $empty_collection

        set temp_db2    $empty_collection
        set temp_db2_0  $empty_collection
        set temp_db2_1  $empty_collection

        set out_0 [open "$outdir/$filter_tag.master.csv" w+] 
        set out_1 [open "$outdir/$filter_tag.func.csv"   w+] 
        set out_2 [open "$outdir/$filter_tag.dft.csv"    w+] 
        set out_3 [open "$outdir/$filter_tag.both.csv"   w+] 
        set out_4 [open "$outdir/$filter_tag.missing_source.rpt" w+] 

        puts $out_0 "#Design,#Scenario,#Report_Tag,#Comment,#ClockPin,#Pin_Name,#Func_Clock,#DFT_Clock,#Missing_Src"
        puts $out_1 "#Design,#Scenario,#Report_Tag,#Comment,#ClockPin,#Pin_Name,#Clock,#Missing_Src"
        puts $out_2 "#Design,#Scenario,#Report_Tag,#Comment,#ClockPin,#Pin_Name,#Clock,#Missing_Src"
        puts $out_3 "#Design,#Scenario,#Report_Tag,#Comment,#ClockPin,#Pin_Name,#Clock,#Missing_Src"

        set func_cnt 0
        set dft_cnt 0
        set both_cnt 0
        array unset missing_src_data
        foreach_in_collection xck $master_ck {
                # Pin
                set pin_name  [get_object_name $xck]

                set comment_func ""
                set comment_dft ""

                set is_ck_pin [get_attribute -quiet $xck is_clock_pin]
                set clocks  [get_attribute -quiet  $xck clocks]
                # Func Category
                set fclocks [sort_collection [remove_from_collection -intersect $clocks $valid_func_clocks] full_name]
                if {[sizeof_collection $fclocks] == 0  } {  
                        set func_clock  "None"
                } else { 
                        set func_clock  [join [lsort -unique [get_object_name $fclocks]] "|" ]
                }
                set comment_func [format "Func%03d" [sizeof_collection $fclocks]]

                # DFT Category
                set tclocks [sort_collection [remove_from_collection -intersect $clocks $valid_dft_clocks]  full_name]
                if {[sizeof_collection $tclocks] == 0  } {  
                        set dft_clock  "None"
                } else { 
                        set dft_clock  [join [lsort -unique [get_object_name $tclocks]] "|" ]
                }
                set comment_dft [format "DFT%03d" [sizeof_collection $tclocks]]

                set is_true_clock "ClockPin"
                if  { $is_ck_pin == "false" } { set is_true_clock "NonClockPin" }

                # Comment Process/Enhance
                set fanin_cmt "NA"
                if { [sizeof_collection $fclocks] == 0 && [sizeof_collection $tclocks] == 0 } {
                        # Both Unclocked
                        set comment_func "FAIL_Func"
                        set comment_dft  "FAIL_DFT"
                        set cone    [all_fanin -start -flat -trace all -to $pin_name]
                        set cone_port [get_ports -quiet $cone]
                        set fanin_cmt ""
                        if { [sizeof_collection $cone_port] } { 
                           set port_ck    [remove_from_collection -intersect $cone_port $clock_ports]
                           set port_rst   [remove_from_collection -intersect $cone_port $reset_ports]
                           set port_ckrst [remove_from_collection -intersect $cone_port $clock_reset]
                           if { [sizeof_collection $port_ck] } {
                                set port_x [join [lsort -unique [get_object_name $port_ck]] "|" ]
                                set fanin_cmt "$fanin_cmt|ClkPort:$port_x"
                           }
                           if { [sizeof_collection $port_ckrst] } {
                                set port_x [join [lsort -unique [get_object_name $port_ckrst]] "|" ]
                                set fanin_cmt "$fanin_cmt|ClkRst:$port_x"
                           }
                           if { [sizeof_collection $port_rst] } {
                                set port_x [join [lsort -unique [get_object_name $port_rst]] "|" ]
                                set fanin_cmt "$fanin_cmt|Reset:$port_x"
                           }
                        } 
                        regsub -all {^\|} $fanin_cmt {} fanin_cmt
                        set cone_pins  [get_pins -quiet $cone]
                        if { [sizeof_collection $cone_pins] && [sizeof_collection $cone_port] == 0 } {
                           set cell_x [join [lsort -unique [get_object_name [get_cells -of_object $cone_pins]]] "|" ]
                           set fanin_cmt "Cells:$cell_x"
                        } 
                        if { ![info exist missing_src_data($fanin_cmt)] } {
                            set missing_src_data($fanin_cmt) [list $pin_name]
                        } else {
                            lappend missing_src_data($fanin_cmt) $pin_name
                        }
                        puts $out_1 "$design_name,$scenario,$filter_tag,$comment_func,$is_true_clock,$pin_name,$func_clock,$fanin_cmt"
                        puts $out_2 "$design_name,$scenario,$filter_tag,$comment_dft,$is_true_clock,$pin_name,$dft_clock,$fanin_cmt"  
                        puts $out_3 "$design_name,$scenario,$filter_tag,$comment_func/$comment_dft,$is_true_clock,$pin_name,$func_clock,$dft_clock,$fanin_cmt"
                        incr func_cnt
                        incr dft_cnt
                        incr both_cnt
                } elseif { [sizeof_collection $tclocks] == 0} {
                        # Only DFT Unclocked 
                        set comment_dft  "FAIL_DFT/PASS_$comment_func"
                        puts $out_2 "$design_name,$scenario,$filter_tag,$comment_dft,$is_true_clock,$pin_name,$func_clock,$fanin_cmt"
                        incr dft_cnt
                } elseif { [sizeof_collection $fclocks] == 0 } {
                        # Only Func Unclocked 
                        set comment_func  "FAIL_Func/PASS_$comment_dft"
                        puts $out_1 "$design_name,$scenario,$filter_tag,$comment_func,$is_true_clock,$pin_name,$dft_clock,$fanin_cmt"
                        incr func_cnt
                } 
                puts $out_0 "$design_name,$scenario,$filter_tag,$comment_func/$comment_dft,$is_true_clock,$pin_name,$func_clock,$dft_clock,$fanin_cmt"

                if { [sizeof_collection $clocks] == 0 } {
                        append_to_collection    temp_db0 $xck
                        if  { $is_ck_pin == "false" } { 
                                append_to_collection    temp_db0_0 $xck
                        } else {
                                append_to_collection    temp_db0_1 $xck
                        }
                } elseif { [sizeof_collection $clocks] == 1 } {
                        if { [sizeof_collection [remove_from_collection $clocks $valid_dft_clocks]] } {
                                append_to_collection    temp_db1_0 $xck
                        } else {
                                append_to_collection    temp_db1_1 $xck
                        }
                } else {
                        append_to_collection    temp_db2 $xck
                        if { [sizeof_collection [remove_from_collection -intersect $clocks $valid_func_clocks]] } {
                                append_to_collection    temp_db2_0 $xck
                        }
                        if { [sizeof_collection [remove_from_collection -intersect $clocks $valid_dft_clocks]] } {
                                append_to_collection    temp_db2_1 $xck
                        }
                }
        }

        ssi_audit_print_stage blue [format "=============================================================================================" ]  
        if { $both_cnt > 0 } {
            set xclr red
        } else {
            set xclr green            
        }
        ssi_audit_print_stage $xclr  [format "<CLK_AUD> : Missing Source Trace for Unclocked Registers : $both_cnt"]        
        foreach x [lsort [array names missing_src_data]] {
            puts $out_4 "# Root/Sinks=[llength $missing_src_data($x)] Root: $x"
            ssi_audit_print_stage red [format "            %-50s = %10s  (%0.2f%s)" "$x" "[llength $missing_src_data($x)]" "[expr 100.0 * [llength $missing_src_data($x)]/$both_cnt]" "%" ]
            foreach y $missing_src_data($x) {
                puts $out_4 "        $y" 
            }
        }
        ssi_audit_print_stage blue [format "=============================================================================================" ]        
        close $out_0
        close $out_1
        close $out_2
        close $out_3
        close $out_4

        set type "03_DXNoClk_CK"  ;     set clock_db($type) $temp_db0_0  ; set master_ck [remove_from_collection $master_ck $clock_db($type)]
        set type "04_CKNoClk_CK"  ;     set clock_db($type) $temp_db0_1  ; set master_ck [remove_from_collection $master_ck $clock_db($type)]
        set type "05_OneFClk_CK"  ;     set clock_db($type) $temp_db1_0  ; set master_ck [remove_from_collection $master_ck $clock_db($type)]
        set type "06_OneTClk_CK"  ;     set clock_db($type) $temp_db1_1  ; set master_ck [remove_from_collection $master_ck $clock_db($type)]
        set type "07_ManyFClk_CK" ;     set clock_db($type) $temp_db2_0  ; set master_ck [remove_from_collection $master_ck $clock_db($type)]
        set type "08_ManyTClk_CK" ;     set clock_db($type) $temp_db2_1  ; set master_ck [remove_from_collection $master_ck $clock_db($type)]

        # Array Query
        foreach categ  [lsort [array names clock_db]] {
                ssi_audit_print_stage blue [format "            %-50s = %10s  (%0.2f%s)" "$categ" "[sizeof_collection $clock_db($categ)]" "[expr 100.0 * [sizeof_collection $clock_db($categ)]/$total_ck]" "%" ]
        }

        # OutLog Query
        set func_status  "([expr {ceil(100.0 * $func_cnt/$total_ck)}] percent)"
        set dft_status   "([expr {ceil(100.0 * $dft_cnt/$total_ck)}] percent)"
        set status [list Func/$func_cnt$func_status DFT/$dft_cnt$dft_status "<OUTDIR>/$filter_tag.func.csv" "<OUTDIR>/$filter_tag.dft.csv"]
        ssi_audit_print_stage blue  [format "=============================================================================================" ]
        ssi_audit_print_stage $xclr [format "<CLK_AUD> : Completed Report Generation for  $design_name  $status"]
        ssi_audit_print_stage blue  [format "            [file normalize $outdir/$filter_tag.master.csv]"]
        ssi_audit_print_stage blue  [format "            [file normalize $outdir/$filter_tag.func.csv]"]
        ssi_audit_print_stage blue  [format "            [file normalize $outdir/$filter_tag.dft.csv]"]
        ssi_audit_print_stage blue  [format "            [file normalize $outdir/$filter_tag.both.csv]"]
        ssi_audit_print_stage $xclr [format "<CLK_AUD> : Identified Possible Missing Sources For Clocks [llength [array names missing_src_data]]"]
        ssi_audit_print_stage blue  [format "            [file normalize $outdir/$filter_tag.missing_source.rpt]"]
        ssi_audit_print_stage blue  [format "            <CMD> sh wc -l [file normalize $outdir]/$filter_tag.*"]        
        ssi_audit_print_stage blue  [format "=============================================================================================" ]

        return $status
}


#---------------------------------------------------------------------------------------------
proc ssi_trace_pin { pin } {
	set coll [filter_collection [all_fanin    -to $pin -flat ] direction==out]
	set col2 [filter_collection [all_fanout -from $pin -flat -pin_level 1 ] "(direction==in && object_class==pin) ||  (direction==out && object_class==port)"] 
	set col3 [filter_collection [all_fanin  -to   $pin -flat -pin_level 2 ] "(direction==in && object_class==port)"]   
    set coll  [append_to_collection col2 $coll]
    set coll  [append_to_collection coll $col3]
    set object   [get_attr -quiet $pin object_class]
    if { $object == "pin" } {
        set tcell [get_object_name [get_cells -of_object [get_pins -quiet $pin] ]]
    } else {
        set tcell [get_object_name [get_ports -quiet $port]]
    }
	puts [format "\n# Tracing $pin \n" ]
	ssi_audit_print_stage orange [format "%-50s  %-30s %-30s %-8s   * %-s"  REF LOC_XY COMMENT  FANOUT NAME]

	foreach_in_collection x $coll {
		set xname [get_object_name $x]
		set xloc  [lindex [get_attr -quiet  $x bbox] 0]
		set ref   [get_attr -quiet [get_cells -quiet  -of_obj $x] ref_name] 
        if {$ref == ""              } { set ref PORT}
        set comment ""
        set xcolor blue_nodate
        if {[regexp $tcell $xname]  } { set comment "$comment,Target"  ; set xcolor red_nodate }
        if {[regexp $ref   $xname]  } { set comment "$comment,RefMatch" ; set xcolor green_nodate}
        set fanout [sizeof_collection [get_attr [get_nets -of_object $x] leaf_loads]]
        if { $comment == "" } { set comment "-" }
		ssi_audit_print_stage $xcolor [format "%-50s  %-30s %-30s %-08d   ^ %-s"  $ref $xloc $comment $fanout $xname]
	}
}
#---------------------------------------------------------------------------------------------
# --- Point-set stats: bbox, count, centroid, max/min dist + index ---
proc ssi_point_stats {points} {
    set minx {} ; set miny {} ; set maxx {} ; set maxy {}
    set sumx 0.0 ; set sumy 0.0
    set count 0
    foreach p $points {
        lassign $p x y
        if {$minx eq "" || $x < $minx} { set minx $x }
        if {$miny eq "" || $y < $miny} { set miny $y }
        if {$maxx eq "" || $x > $maxx} { set maxx $x }
        if {$maxy eq "" || $y > $maxy} { set maxy $y }
        set sumx [expr {$sumx + $x}]
        set sumy [expr {$sumy + $y}]
        incr count
    }
    if {$count == 0} { return [list {} 0 {} {} {} {} {}] }
    set cx [expr {$sumx / $count}]
    set cy [expr {$sumy / $count}]

    set maxdist {} ; set maxidx {}
    set mindist {} ; set minidx {}
    set idx 0
    foreach p $points {
        incr idx
        lassign $p x y
        set d [expr {sqrt(pow($x-$cx,2)+pow($y-$cy,2))}]
        if {$maxdist eq "" || $d > $maxdist} { set maxdist $d ; set maxidx $idx }
        if {$mindist eq "" || $d < $mindist} { set mindist $d ; set minidx $idx }
    }

    set bbox [list [list [format "%.3f" $minx] [format "%.3f" $miny]] \
                   [list [format "%.3f" $maxx] [format "%.3f" $maxy]]]
    set centroid [list [format "%.3f" $cx] [format "%.3f" $cy]]

    return [list $bbox $count $centroid \
                 [format "%.3f" $maxdist] $maxidx \
                 [format "%.3f" $mindist] $minidx]
}

# --- Generalize a bus/instance name: digit runs -> "*" ---
proc ssi_generalize_bus_name {name} {
    return [regsub -all {\d+} $name {*}]
}

# --- Recursively emit one driver frame: its own compressed line, all its own compressed Load lines (grouped together), THEN its children (each rendered the same way). 
proc ssi__render_frame {fid} {
    upvar 1 outlines outlines
    upvar 1 f_indent f_indent
    upvar 1 f_level f_level
    upvar 1 f_name f_name
    upvar 1 f_annot f_annot
    upvar 1 f_x f_x
    upvar 1 f_y f_y
    upvar 1 f_points f_points
    upvar 1 f_pend_points f_pend_points
    upvar 1 f_pend_order f_pend_order
    upvar 1 f_children f_children

    set indent $f_indent($fid)
    set level  $f_level($fid)
    set points {}
    if {[info exists f_points($fid)]} { set points $f_points($fid) }

    set stats ""
    if {[llength $points] > 0} {
        lassign [ssi_point_stats $points] bbox n centroid maxd maxi mind mini
        set stats " bbox=$bbox centroid=$centroid"
        append stats " max_dist=${maxd}(idx${maxi}) min_dist=${mind}(idx${mini})"
    }
    set annot_txt [expr {$f_annot($fid) ne "" ? " ($f_annot($fid))" : ""}]
    set head [format "%05d" [llength $points]]
    lappend outlines "${indent}Driver{$head} (level $level): $f_name($fid)$annot_txt \[$f_x($fid),$f_y($fid)\]$stats"

    if {[info exists f_pend_order($fid)]} {
        foreach pattern $f_pend_order($fid) {
            set ppoints $f_pend_points($fid,$pattern)
            lassign [ssi_point_stats $ppoints] bbox n centroid maxd maxi mind mini
            set stats " bbox=$bbox centroid=$centroid"
            append stats " max_dist=${maxd}(idx${maxi}) min_dist=${mind}(idx${mini})"
            set head [format "%05d" [llength $ppoints]]
            lappend outlines "${indent}    Load{$head} (level $level): $pattern $stats"
        }
    }

    if {[info exists f_children($fid)]} {
        foreach child $f_children($fid) { ssi__render_frame $child }
    }
}

# --- Compress a report_buffer_trees rpt in two passes.
#     in_mode/out_mode: -file or -var
#       -file in_val   : in_val is a path, read from disk
#       -var  in_val   : in_val is the report text itself
#       -file out_val  : write the result to out_val (path), return out_val
#       -var  (no arg) : return the result as a string
# ---
proc ssi_compress_buffer_tree_rpt {in_mode in_val out_mode {out_val ""}} {
    set LOAD_RE {^(\s*)Load \(level (\d+)\): (\S+)(?:\s+\(([^()]*)\))?\s+\[([\-0-9.]+),\s*([\-0-9.]+)\]}
    set DRIVER_RE {^(\s*)Driver \(level (\d+)\): (\S+)(?:\s+\(([^()]*)\))?\s+\[([\-0-9.]+),\s*([\-0-9.]+)\]}

    switch -- $in_mode {
        -file {
            set fh [open $in_val r]
            set content [read $fh]
            close $fh
        }
        -var {
            set content $in_val
        }
        default {
            error "ssi_compress_buffer_tree_rpt: unknown input mode '$in_mode', expected -file or -var"
        }
    }
    set lines [split [string trimright $content "\n"] "\n"]

    # ---- Pass 1: accumulate per-frame stats + parent/child structure ----
    set st_level {} ; set st_id {}
    set next_id 0
    array unset f_points
    array unset f_pend_points
    array unset f_pend_order
    array unset f_indent
    array unset f_level
    array unset f_name
    array unset f_annot
    array unset f_x
    array unset f_y
    array unset f_children

    foreach line $lines {
        set is_load [regexp $LOAD_RE $line -> l_indent l_level l_name l_annot l_x l_y]
        set is_driver 0
        if {!$is_load} {
            set is_driver [regexp $DRIVER_RE $line -> l_indent l_level l_name l_annot l_x l_y]
        }

        if {$is_load} {
            while {[llength $st_level] > 0 && [lindex $st_level end] > $l_level} {
                set st_level [lrange $st_level 0 end-1]
                set st_id    [lrange $st_id 0 end-1]
            }
            set fid [lindex $st_id end]
            set pattern [ssi_generalize_bus_name $l_name]
            if {![info exists f_pend_order($fid)]} { set f_pend_order($fid) {} }
            if {![info exists f_pend_points($fid,$pattern)]} {
                set f_pend_points($fid,$pattern) {}
                lappend f_pend_order($fid) $pattern
            }
            lappend f_pend_points($fid,$pattern) [list $l_x $l_y]
            if {![info exists f_points($fid)]} { set f_points($fid) {} }
            lappend f_points($fid) [list $l_x $l_y]
            continue
        }
        if {$is_driver} {
            while {[llength $st_level] > 0 && [lindex $st_level end] >= $l_level} {
                set st_level [lrange $st_level 0 end-1]
                set st_id    [lrange $st_id 0 end-1]
            }
            set fid $next_id
            incr next_id
            set parent [lindex $st_id end]
            if {$parent ne ""} { lappend f_children($parent) $fid }
            set f_indent($fid) $l_indent
            set f_level($fid)  $l_level
            set f_name($fid)   $l_name
            set f_annot($fid)  $l_annot
            set f_x($fid)      $l_x
            set f_y($fid)      $l_y
            lappend st_level $l_level
            lappend st_id $fid
            continue
        }
    }

    # ---- Pass 2: stack bookkeeping only; render each root's entire
    #      subtree recursively the moment it's encountered ----
    set outlines {}
    set st_level {} ; set st_id {}
    set next_id 0

    foreach line $lines {
        set is_load [regexp $LOAD_RE $line -> l_indent l_level l_name l_annot l_x l_y]
        set is_driver 0
        if {!$is_load} {
            set is_driver [regexp $DRIVER_RE $line -> l_indent l_level l_name l_annot l_x l_y]
        }

        if {$is_load} {
            while {[llength $st_level] > 0 && [lindex $st_level end] > $l_level} {
                set st_level [lrange $st_level 0 end-1]
                set st_id    [lrange $st_id 0 end-1]
            }
            continue
        }
        if {$is_driver} {
            while {[llength $st_level] > 0 && [lindex $st_level end] >= $l_level} {
                set st_level [lrange $st_level 0 end-1]
                set st_id    [lrange $st_id 0 end-1]
            }
            set now_empty [expr {[llength $st_level] == 0}]
            set fid $next_id
            incr next_id
            lappend st_level $l_level
            lappend st_id $fid
            if {$now_empty} {
                ssi__render_frame $fid
            }
            continue
        }

        if {[llength $st_level] == 0} {
            lappend outlines $line
        }
    }

    set result [join $outlines "\n"]

    switch -- $out_mode {
        -file {
            set ofh [open $out_val w]
            puts $ofh $result
            close $ofh
            return $out_val
        }
        -var { return $result }
        default {
            error "ssi_compress_buffer_tree_rpt: unknown output mode '$out_mode', expected -file or -var"
        }
    }
}



#---------------------------------------------------------------------------------------------
# JSON export for ssi_trace_clk_tree -- does NOT modify ssi_trace_clk_tree.
# Calls it as-is, then derives parent/loads for every visited node purely from the "chain" strings already present in its returned dict (e.g. chain "1.2.3" -> parent chain "1.2"), so no second fanout walk is needed and ssi_trace_clk_tree's own behavior/output is untouched.
#---------------------------------------------------------------------------------------------
proc ssi_json_escape {s} {
    return [string map {"\\" "\\\\" "\"" "\\\"" "\n" "\\n" "\t" "\\t"} $s]
}
proc ssi_json_str {s} {
    return "\"[ssi_json_escape $s]\""
}
proc ssi_json_arr {lst} {
    set items {}
    foreach e $lst { lappend items [ssi_json_str $e] }
    return "\[[join $items ,]\]"
}
proc ssi_json_num_or_null {v} {
    if {$v eq "" || $v eq "-"} { return "null" }
    return $v
}

# Per-node attribute lookup -- independent of ssi_trace_clk_tree.
proc ssi_node_json_record {node parent loads} {
    set inst_name "-"
    set ref_name  "-"
    set ref_class "com"
    set clocks    {}
    set loc       ""
    set internal_arc "-"

    if {[string first "/" $node] >= 0} {
        catch {
            set pin_h [get_pins -quiet $node]
            if {$pin_h ne ""} {
                set cell_h [get_cells -quiet -of_obj $pin_h]
                if {$cell_h ne ""} {
                    set inst_name [get_object_name $cell_h]
                    catch {set ref_name [get_attr -quiet $cell_h ref_name]}
                    catch {set loc [lindex [get_attr -quiet $cell_h bbox] 0]}

                    # classification: confirmed attr first (is_sequential is
                    # used elsewhere in this file), fall back to ref_name
                    # pattern match for anything not exposed as an attribute
                    # in this tool session.
                    if {![catch {set is_seq [get_attr -quiet $cell_h is_sequential]}] && $is_seq} {
                        set ref_class "seq"
                    } elseif {![catch {set is_icg [get_attr -quiet $cell_h is_integrated_clock_gating_cell]}] && $is_icg} {
                        set ref_class "icg"
                    } elseif {[regexp -nocase {srdff|dff|flop} $node]} {
                        set ref_class "seq"
                    } elseif {[regexp -nocase {ucg|kcgu|gclk|clk_gate|icg} $node]} {
                        set ref_class "icg"
                    } elseif {[regexp -nocase {inv} $ref_name]} {
                        set ref_class "inv"
                    } elseif {[regexp -nocase {buf} $ref_name]} {
                        set ref_class "buf"
                    }
                }
                catch {
                    set clk_objs [get_attr -quiet $pin_h clocks]
                    if {$clk_objs ne ""} { set clocks [get_object_name $clk_objs] }
                }
            }
        }
    } else {
        set inst_name $node
        set ref_class "port_out"
    }

    return [format {{"node":%s,"inst_name":%s,"ref_name":%s,"ref_class":%s,"driver":%s,"loads":%s,"clocks_arriving":%s,"loc":%s,"fanout":%s,"internal_arc":%s}} \
        [ssi_json_str $node] [ssi_json_str $inst_name] [ssi_json_str $ref_name] \
        [ssi_json_str $ref_class] [ssi_json_str $parent] [ssi_json_arr $loads] \
        [ssi_json_arr $clocks] [ssi_json_str $loc] \
        [llength $loads] [ssi_json_str $internal_arc]]
}

proc ssi_cts_json_export {node json_path {only_clock 1}} {
    set result [ssi_trace_clk_tree $node $only_clock]

    array set chain2node {}
    dict for {lvl objs} $result {
        foreach pair $objs {
            lassign $pair ch nm
            set chain2node($ch) $nm
        }
    }

    array set children_of {}
    foreach ch [array names chain2node] {
        set dot [string last "." $ch]
        set pch [expr {$dot < 0 ? "" : [string range $ch 0 [expr {$dot - 1}]]}]
        lappend children_of($pch) $ch
    }

    set json_items {}
    foreach ch [lsort [array names chain2node]] {
        set nm $chain2node($ch)
        set dot [string last "." $ch]
        set pch [expr {$dot < 0 ? "" : [string range $ch 0 [expr {$dot - 1}]]}]
        set parent_node [expr {[info exists chain2node($pch)] ? $chain2node($pch) : ""}]

        set loads {}
        if {[info exists children_of($ch)]} {
            foreach lc $children_of($ch) { lappend loads $chain2node($lc) }
        }

        lappend json_items [ssi_node_json_record $nm $parent_node $loads]
    }

    set jf [open $json_path w]
    puts $jf "\[[join $json_items ,]\]"
    close $jf
    return $result
}
#---------------------------------------------------------------------------------------------

proc ssi_trace_clk_tree {node   {only_clock 1} {prefix ""} {visited {}} {level 0} {chain "1"} {fh "stdout"}} {
      set result [dict create]
      dict lappend result $level [list $chain $node]
      lappend visited $node
      set clk_cond "is_clock_used_as_clock==true"
      if { $only_clock } {
        set fanouts [lsort [get_object_name [filter_collection  [all_fanout -flat -pin_level 1 -from $node] "$clk_cond" ]]]
      } else {
        set fanouts [lsort [get_object_name [all_fanout -flat -pin_level 1 -from $node]  ]]          
      }
      set fanouts [lsearch -all -inline -not -exact $fanouts $node]
      set count [llength $fanouts]

      set idx 0
      foreach child $fanouts {
          incr idx
          set is_last    [expr {$idx == $count}]
          set branch     [expr {$is_last ? "+--> " : "|--> "}]
          set nextpref   [expr {$is_last ? "$prefix    " : "$prefix|   "}]
          set childchain "${chain}.${idx}"
          if {[lsearch -exact $visited $child] >= 0} {
              puts $fh "${prefix}${branch}${child} (loop)"
              dict lappend result [expr {$level + 1}] [list $childchain $child]
          } else {
              puts $fh "${prefix}${branch}${child}"
              set childResult [ssi_trace_clk_tree $child $only_clock  $nextpref $visited [expr {$level + 1}] $childchain $fh]
              dict for {lvl objs} $childResult {
                  foreach pair $objs {
                      dict lappend result $lvl $pair
                  }
              }
          }
      }
      return $result
}

#---------------------------------------------------------------------------------------------

proc ssi_anchor_cellpin_ref_match {coll prefix } {
    ssi_audit_print_stage green  [format "<CTS_AUD> : Tracing Anchor Repeaters in Chain for $prefix:  [sizeof_collection $coll] "]
	ssi_audit_print_stage orange [format "%-50s  %-30s %-30s %-8s %-40s  * %-s"  REF LOC_XY COMMENT FANOUT CLOCKS NAME]
    set count_fail 0
    set count_pass 0
	foreach_in_collection x $coll {
		set xname [get_object_name $x]
		set xloc  [lindex [get_attr -quiet  $x bbox] 0]
        set xclocks [get_object_name [get_attribute -quiet  $x clocks]]
		set ref   [get_attr -quiet [get_cells -quiet  -of_obj $x] ref_name] 
        if {$ref == ""              } { set ref PORT}
        set comment ""
        set xcolor red_nodate
        if {[regexp $ref   $xname]  } { 
            set comment "$comment,Pass_RefMatch" ; set xcolor green_nodate
            incr count_pass            
        } else {
            incr count_fail
            set comment "$comment,Fail_RefResized" ; set xcolor red_nodate            
        }
        set fanout [sizeof_collection [get_attr [get_nets -of_object $x] leaf_loads]]
        if { $comment == "" } { set comment "-" }
        if { [llength $xclocks] == 0 } {
            set xclock  [format "NoClk/#Clks=[llength $xclocks]"]            
        } elseif { [llength $xclocks] >= 1 } {
            set xclock  [format "[lindex $xclocks 0]/#Clks=[llength $xclocks]"]            
        } else {
            set xclock  [format "[lindex $xclocks 0]/#Clks=[llength $xclocks]"]
        }
		ssi_audit_print_stage $xcolor [format "%-50s  %-30s %-30s %-08d %-40s  ^ %-s"  $ref $xloc $comment $fanout $xclock $xname]


	}
    ssi_audit_print_stage blue [format "=============================================================================================" ]  
    if { $count_fail > 0 } {
            set xcolor red
    } else {
        set xcolor green            
    }
    ssi_audit_print_stage $xcolor  [format "<CTS_AUD> : Tracing Anchor Repeaters in Chain for $prefix: FAIL=$count_fail / PASS=$count_pass / TOTAL=[sizeof_collection $coll] "]  
    ssi_audit_print_stage blue [format "=============================================================================================" ]      
}


#---------------------------------------------------------------------------------------------
# TODO : Run Script
#---------------------------------------------------------------------------------------------
regsub -all {_GUI/.*} [pwd] "GUI" run_dir
set run_data    [split $run_dir "/"]
set run_tag     [lindex $run_data end]
set fcfp_tag    [lindex $run_data end-4]

set design_name [ssi_fc_current_design]
set ports       [get_attr -quiet [get_clock] sources ]
set report_dir  "/proj/sb_c3d_pd4/audit/$design_name/$fcfp_tag/$run_tag"
set fc_scenario "FC_MODE.FC_CORNER"

file mkdir $report_dir
set xlog   $report_dir/run.log
# CLK
redirect -tee $xlog {set noclk_array [ssi_audit_unclocked_registers $report_dir  [list  ] $fc_scenario]}
# CTS
redirect $report_dir/cts_trace.rpt { set cts_array [ ssi_trace_clk_tree [index_collection $ports 0] ]}
ssi_audit_print_stage blue [format "=============================================================================================" ]      
ssi_audit_print_stage green  [format "<CTS_AUD> : Tracing Clock Ports :  "] 
foreach_in_collection clk_port [ssi_get_clock_ports] {
    set xfile $report_dir/CTS.trace.[get_object_name $clk_port]
    redirect -file $xfile  {report_buffer_tree -phy -hier -from $clk_port} 
    ssi_compress_buffer_tree_rpt -file $xfile -file $xfile.compressed
    ssi_audit_print_stage blue  [format "            [file normalize  $xfile]"]
}
ssi_audit_print_stage blue [format "=============================================================================================" ]      

# SCCTS Review
set NON_CREDIT_BUF_AT_OUTPUT [filter_collection [all_fanin  -pin_level 1 -to    [get_pins -hier -filter "full_name=~*FEEDX_cstrp* && direction ==in"]  ] "full_name!~*FEEDX_cstrp* && is_hierarchical==false"]
set NON_CREDIT_BUF_AT_INPUT  [filter_collection [all_fanout -pin_level 1 -from  [get_pins -hier -filter "full_name=~*FEEDX_cstrp* && direction ==out"] ] "full_name!~*FEEDX_cstrp* && is_hierarchical==false"]
set NON_CREDIT_BUF           ""
set NON_CREDIT_BUF           [add_to_collection $NON_CREDIT_BUF $NON_CREDIT_BUF_AT_OUTPUT]
set NON_CREDIT_BUF           [add_to_collection $NON_CREDIT_BUF $NON_CREDIT_BUF_AT_INPUT]
if { [sizeof_collection $NON_CREDIT_BUF] } {
    ssi_audit_print_stage red  [format "<CTS_AUD> : Found Non Credit Repeaters in Chain :  [sizeof_collection $NON_CREDIT_BUF] "]
    set NON_CREDIT_BUF [get_pins -of_object [get_cells -of_object $NON_CREDIT_BUF] -filter "direction==out"]
    foreach_in_collection x $NON_CREDIT_BUF {
        set xname [get_object_name $x]
        set cone  [all_fanin -quiet -flat -to [get_cells -of_object $x] -start]
        redirect -tee $report_dir/sscts_issues_tree.rpt  { ssi_trace_pin  $xname }
    }
} else {
    ssi_audit_print_stage green  [format "<CTS_AUD> : Found Non Credit Repeaters in Chain :  [sizeof_collection $NON_CREDIT_BUF] "]    
}


# Credit Check
set CREDIT_BUF_TYPE_CHECK [get_pins -hier -filter "full_name!~*SCCTS_* && full_name=~*FEEDX_cstrp* && is_hierarchical==false && direction==out"]
set SSCTS_BUF_TYPE_CHECK [get_pins -hier -filter "full_name=~*SCCTS_* && is_hierarchical==false && direction==out"]
redirect -tee $report_dir/credit_issues.rpt { ssi_anchor_cellpin_ref_match $CREDIT_BUF_TYPE_CHECK CREDIT_CELLS_$run_tag}
redirect -tee $report_dir/sscts_issues.rpt { ssi_anchor_cellpin_ref_match $SSCTS_BUF_TYPE_CHECK SCCTS_CELLS_$run_tag}

puts "**Info::  Open Files : "
puts "                       $report_dir/cts_trace.rpt" 
puts "                       $report_dir/sscts_issues.rpt" 
puts "                       $report_dir/credit_issues.rpt" 
puts "                       $report_dir/run.log" 
puts "                       $report_dir/unclocked_registers.missing_source.rpt"

