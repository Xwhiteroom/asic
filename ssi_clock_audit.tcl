# Copyright (c) 2026 Syed Shakir Iqbal (Xwhiteroom)
# SPDX-License-Identifier: MIT
# --- Build ASCII tree + collect level->object map (per node's subtree) ---
#
#---------------------------------------------------------------------------------------------
proc ssi_audit_print_stage {red_blue comment} {
      if { $red_blue == "blue" } {
              puts [format "\033\[34m%-30s %-100s \033\[0m" [date] "$comment" ]
      } else {
              puts [format "\033\[31m%-30s %-100s \033\[0m" [date] "$comment" ]  
      }
}
#---------------------------------------------------------------------------------------------
proc ssi_fc_current_design { } {
        set design_name [lindex [split [get_object_name [current_design]] ":"] end]
        regsub -all {.design$} $design_name {} design_name 
        return $design_name
}

#---------------------------------------------------------------------------------------------
proc ssi_audit_unclocked_registers {outdir dft_pat_list_of_clocknames_collection scenario_should_be_mode_dot_corner} {
        set design_name [ssi_fc_current_design]
        set dft_pat_list $dft_pat_list_of_clocknames_collection
        set scenario $scenario_should_be_mode_dot_corner
        set outdir $outdir
        file mkdir $outdir
        set outdir [file normalize $outdir]
        ssi_audit_print_stage blue [format "\n\n=============================================================================================" ]
        ssi_audit_print_stage red  [format "<SDC_GEN> : Created o/p directory %s"  "$outdir"]
        set filter_tag "unclocked_registers"
        set empty_collection [remove_from_collection [all_clocks] [all_clocks]]


        # Set Clock Filters
        set valid_dft_clocks [get_clocks -quiet $dft_pat_list]
        if { [llength    $dft_pat_list] == "0" } { 
                ssi_audit_print_stage red  [format "\n<SDC_GEN> : No DFT Pattern Provided  (%03d) Clocks  dft_pat_list=%s"  "[sizeof_collection $valid_dft_clocks]" "$dft_pat_list"]
        } elseif { [sizeof_collection $valid_dft_clocks] } { 
                ssi_audit_print_stage red  [format "\n<SDC_GEN> : DFT Pattern Provided  (%03d) Clocks     dft_pat_list=%s"  "[sizeof_collection $valid_dft_clocks]" "$dft_pat_list"]
                ssi_audit_print_stage blue [format "            Clocks : [get_object_name $valid_dft_clocks]"]
        } else {
                ssi_audit_print_stage red  [format "\n<SDC_GEN> : DFT Pattern Provided  (%03d) Matches    dft_pat_list=%s"  "[sizeof_collection $valid_dft_clocks]" "$dft_pat_list"]
        }
        set valid_func_clocks [remove_from_collection [all_clocks] $valid_dft_clocks]
        ssi_audit_print_stage red  [format "\n<SDC_GEN> : Valid  (%03d) Clocks  for fuctional case  "  "[sizeof_collection $valid_func_clocks]" "$dft_pat_list"]
        ssi_audit_print_stage blue [format "            Clocks : [get_object_name $valid_func_clocks]"]

        # Set Register Collection
        set all_seq             [get_cells -hier -filter "is_hierarchical==false && is_sequential==true"]
        set all_seq_ck          [get_pins -of_object $all_seq -filter "is_clock_used_as_clock==true && direction==in"]
        set all_seq_lck         [get_pins -of_object $all_seq -filter "lib_pin.is_clock_pin==true && direction==in"]
        set all_seq_lrst        [get_pins -of_object $all_seq -filter "lib_pin.is_async_pin==true && direction==in"]

        set all_reg_ck          [all_register -clock_pins]
        set all_reg_rst         [all_register -async_pins]        
        set master_ck           [add_to_collection -unique $all_seq_ck  $all_reg_ck]
        set total_ck            [sizeof_collection $master_ck]

        set reset_ports [get_ports -quiet  [all_fanin -flat -startpoints_only -to $all_seq_lrst ]]
        set clock_ports [get_ports -quiet  [all_fanin -flat -startpoints_only -to $all_seq_lck]]
        set clock_reset [remove_from_collection -intersect $clock_ports $reset_ports]
        set clock_ports [remove_from_collection $clock_ports $clock_reset]
        set reset_ports [remove_from_collection $reset_ports $clock_reset]
        
        ssi_audit_print_stage blue [format "=============================================================================================" ]
        ssi_audit_print_stage red  [format "<SDC_GEN> : Initial Stats for $design_name"]
        ssi_audit_print_stage blue [format "            %-50s = %10s" "Is_Sequential_True" "[sizeof_collection $all_seq]" ]
        ssi_audit_print_stage blue [format "            %-50s = %10s" "Is_Sequential_True_CK" "[sizeof_collection $all_seq_ck]" ]
        ssi_audit_print_stage blue [format "            %-50s = %10s" "All_Reg_CK" "[sizeof_collection $all_reg_ck]" ]
        ssi_audit_print_stage blue [format "            %-50s = %10s" "Master_CK" "[sizeof_collection $master_ck]" ]
        ssi_audit_print_stage blue [format "=============================================================================================" ]        
        ssi_audit_print_stage blue [format "            %-50s = %10s" "ClockPorts" "[sizeof_collection $clock_ports]" ]
        ssi_audit_print_stage blue [format "            %-50s = %10s" "ResetPorts" "[sizeof_collection $reset_ports]" ]  
        ssi_audit_print_stage blue [format "            %-50s = %10s" "CkRstPorts" "[sizeof_collection $clock_reset]" ]                
        ssi_audit_print_stage blue [format "=============================================================================================" ]

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
        ssi_audit_print_stage red  [format "<SDC_GEN> : Missing Source Trace for Unclocked Registers : $both_cnt"]        
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
        ssi_audit_print_stage blue [format "=============================================================================================" ]
        ssi_audit_print_stage red  [format "<SDC_GEN> : Completed Report Generation for  $design_name  $status"]
        ssi_audit_print_stage blue [format "            [file normalize $outdir/$filter_tag.master.csv]"]
        ssi_audit_print_stage blue [format "            [file normalize $outdir/$filter_tag.func.csv]"]
        ssi_audit_print_stage blue [format "            [file normalize $outdir/$filter_tag.dft.csv]"]
        ssi_audit_print_stage blue [format "            [file normalize $outdir/$filter_tag.both.csv]"]
        ssi_audit_print_stage red  [format "<SDC_GEN> : Identified Possible Missing Sources For Clocks [llength [array names missing_src_data]]"]
        ssi_audit_print_stage blue [format "            [file normalize $outdir/$filter_tag.missing_source.rpt]"]
        ssi_audit_print_stage blue [format "            <CMD> sh wc -l [file normalize $outdir]/$filter_tag.*"]        
        ssi_audit_print_stage blue [format "=============================================================================================" ]

        return $status
}



#---------------------------------------------------------------------------------------------
# TODO : Run Script
#---------------------------------------------------------------------------------------------
# ssi_audit_unclocked_registers clock_audit  [list *TAM* ] FC_MODE.FC_CORNER
set design_name [ssi_fc_current_design]
ssi_audit_unclocked_registers /proj/sb_c3d_pd4/c3x_lid_chnl_l/shared/fcfp0016/clock_audit/$design_name  [list  ] FC_MODE.FC_CORNER

