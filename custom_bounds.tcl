# =============================================================
# Repeater pipeline bounds - c3x_lid channel tiles
#   buses: SMN flit, TAM scan channel, TSV scan pipes, Crb hop
#   written to run unchanged on both c3x_lid_chnl_l and c3x_lid_chnl_r
#
# Taken from c3x_lid_chnl_r publish 0048, with chnl_l fixes to the Crb hop port
# patterns (see the Crb hop note above BUS_DEFS).  Measured on the chnl_l netlist:
#   crb   40 repeater flops - 20 forward + 20 return, 2 stages each direction.
#         The chnl_r numbers previously quoted here (39 flops, 6 stages, r2l via
#         CrbManagerToHop*) do NOT apply to chnl_l and hid a real bug: the
#         forward leg matched no origin port and its 20 flops went unbounded.
#   smn  464 repeater flops, 77 origin ports
#   scan 6720 repeater flops
#   tsv    0 origin ports - TsvIn/TsvOut_Scan_Channels*_TSV* is chnl_r only, so
#          the bus reports 0 chains here and is skipped, which is by design
#
# When re-using this file on a new netlist, CHECK THE COVERAGE LINE AND THE
# "not reached by any traced chain" WARNING at the end of the run.  A port
# pattern that has gone stale fails silently - it just contributes no origins.
#
# NOTE the Crb hop bus needs the bnd_out_pins (Q *and* QN) traversal added in
# this version - the hop manager alternates SDFQ* and SDFQN* stages, so the
# older Q-only bnd_q_of dead-ends at the first inverting stage and the whole
# bus goes unbounded.
#
# Walks the netlist instead of matching instance names: start at every origin
# port, follow the flop repeater chain to its terminal port, collect the flops,
# then group the chains by how many stages they have.
#
# Placement scheme - the first stage is bounded at the origin port and the last
# stage at the terminal port, with the rest spread evenly in between.  For an N
# stage chain the span D is cut into N-1 equal segments:
#
#   step = D / (N - 1)
#   stage i (1..N) centre = x_origin + (i - 1) * step
#
#   R1/port |--step--| R2 |--step--| R3 |--step--| R4/port
#
# A single stage chain (N = 1) has no span to divide and is centred midway
# between the two ports.
#
# x_origin / x_terminal are the AVERAGE x of the origin and terminal ports of
# all chains in the group, so the bounds track floorplan edits.
#
# Each bound is  centre +/- BOUND_HALF_X  in x.  In y it spans the height of the
# tile outline over that x range, NOT the design bounding box - both channel
# tiles are rectilinear (chnl_l is 66.5um tall on the right against a 184.8um
# bbox; chnl_r is 59.1um tall on the left against 207.0um).
#
# Wide-bus rule:
#   A bound is 2*BOUND_HALF_X across.  If the port group a stage sits against is
#   spread wider than that, a bound centred on the mean x cannot cover the bits -
#   it would squeeze the whole stage into one column and force long lateral runs
#   out to the outlying bits.  In that case the stage ADJACENT to the wide port
#   group (stage 1 for the origin side, stage N for the terminal side) is given
#   the port span itself as its bound instead of centre +/- BOUND_HALF_X.
#   In chnl_r this fires on TsvIn_Scan_ChannelsIn_TSV, whose 128 origin ports are
#   spread over 172um of the north edge; every other port group here is under
#   25um wide and takes the normal bound.
#
# Groups are keyed by stage count AND direction: the two directions traverse the
# same span in opposite order, so stage 1 of an L2R chain sits opposite stage 1
# of an R2L chain and they cannot share a bound.  Direction is taken from the
# sign of (x_terminal - x_origin), not from any naming convention.
#
# Netlist stage:
#   Runs on a mapped netlist (initial_map onward) and on an un-mapped one
#   (after_elab), where RTL-inferred registers are still generic *SEQGEN* cells
#   with a next_state data pin instead of D.  Inverting (Q-negated) repeaters
#   are followed too.  See bnd_is_data_pin / bnd_out_pins.
#
# Multibit handling:
#   - traversal enters a flop on Dn and leaves on Qn (D->Q, D1->Q1, ... D8->Q8),
#     so banked bits are followed individually
#   - a multibit flop can bank bits belonging to chains of different lengths.
#     A cell can only obey one bound, so the FIRST slot a cell is assigned to
#     wins, a warning is raised, and the cell is left where it was.
#
# Shared pipe segments:
#   The scan channel muxes one physical pipeline into several logical chains, so
#   the same flop is legitimately stage 17 of a 20 stage chain and stage 17 of a
#   22 stage chain.  That is the same first-wins rule as multibit, just at much
#   higher volume, so conflicts are reported as an aggregated summary rather
#   than one line per cell.  Set BND_VERBOSE_CONFLICTS to 1 for per-cell detail.
#
#   Claim order is therefore deliberate, not incidental: chains are sorted by
#   longest span, then most stages, then origin name, so the result does not
#   depend on how the port names happen to sort.
#
# Short / local chains:
#   Staging only means something if the chain actually travels in x.  A chain
#   whose origin and terminal ports are less than BND_MIN_SPAN apart in x (the
#   scan channel's ToNextStage relays enter and leave on the same tile edge, so
#   their span is ~0.01 um) is dropped up front: it forms no group and gets no
#   bounds.  Its flops are still bounded if a longer chain also runs through
#   them; if not they are left unconstrained on purpose and reported as such.
#
# To add another bus, append one {prefix cell_pattern {port_patterns}} row to
# BUS_DEFS - AND add the same cell_pattern to the multibit exclude list, which
# lives at tune/FxSynthesize/mbit_exclude.list (pointed at by the param
# MBIT_EXCLUDE_CELLLISTFILE).  That file currently holds exactly the cell_pattern
# of every row below:
#     *c3x_smn*repeat_C3ROUTER*dff*   smn
#     *ScanChanPipe*dff*              scan and tsv (they share a pattern)
#     *crb_hop*dff*                   crb
#
# The two lists MUST be kept in step.  A repeater the banker is free to merge can
# end up banked across two stages, and a bank obeys only one bound - so the other
# bit gets dragged the full stage pitch away from the port it drives.  On the crb
# bus that pitch is ~1413um.  Nothing in the flow enforces this coupling and
# nothing warns about it, hence this note.
# =============================================================

#if {![info exists TARGET_NAME] || ![regexp {^(FxSynthesize|FxPlace)$} $TARGET_NAME]} {
#    return
#}

puts "REPEATER-BOUNDS: '$TARGET_NAME'"

# ---------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------
#              prefix  cell pattern                     origin/terminal port patterns
# Patterns are written to cover both channel tiles, so this file can be shared:
#   chnl_l  rtrA / C3ROUTERA / INST0ROUTER / LID_CORE0 / Col0 / crb_hop_manager
#   chnl_r  rtrC / C3ROUTERC / INST2ROUTER / LID_CORE1,2 / Col1 / crb_hop_col1_col2
# A port pattern that matches nothing in a given tile simply contributes no
# origin ports; a bus with no origins reports 0 chains and is skipped.
#
# Only INPUT ports become chain origins, so it is fine (and simpler) to list a
# bus's output ports too - they are discovered as terminals by the traversal.
#
# Crb hop on chnl_l:
#   CrbManagerToHop* matches ZERO ports on this netlist - it is kept only in case
#   a future netlist brings that spelling back.  The forward direction's origins
#   are actually the I_crb_hop_manager_col0_* inputs on the right edge:
#     I_crb_hop_manager_col0_stage_d_4__0_ .. __8_   (in, x=3902.8)
#     I_crb_hop_manager_col0_en_out_3_               (in, x=3902.8)
#   -> LID_CORE0_Crb_ClkEn / _Data[0..7] (9 outputs on the bottom edge, x=2489.3).
#   Without those two patterns the forward leg has no origin port, is never
#   traced, and its 20 flops (I_crb_hop_manager_col0_gen_stage_4__/_5__) go
#   completely unbounded - the placer then parks them ~836um from the ports they
#   drive, in the middle of the tile at x=3323-3327.
#
#   The return direction origins ARE the bare LID_CORE0_CrbReturn_* inputs on the
#   bottom edge at x=2486, terminating on I_crb_hop_col0_col1_stage_d_2__* /
#   _en_out_1_ on the right edge.  (The FE_FEEDX-prefixed spelling described in
#   earlier revisions of this file is not what this netlist uses; the leading *
#   on the pattern is harmless and is kept to cover both.)
#
#   Both legs are 2 stages in THIS tile, not the 6 quoted for chnl_r - stages 2
#   and 3 of the logical pipeline live in the neighbouring tile.  So expect
#   crb_2stg_l2r_s1/s2 (return) and crb_2stg_r2l_s1/s2 (forward), 40 flops total.
#   With only 2 stages there is no intermediate staging to distribute: stage 1
#   lands on the origin port and stage 2 on the terminal port, leaving one long
#   (~1413um) hop between them.  The bounds put the flops at the correct ends;
#   they do not and cannot shorten that hop.
#
#   I_crb_hop_*_stage_d_* / _en_out_* also match the col0_col1 OUTPUT ports.
#   That is fine and deliberate - see the "only INPUT ports become origins" note
#   above.  The patterns are scoped to _stage_d_ / _en_out_ rather than a bare
#   I_crb_hop_* so the KCLK_FREE_AR / RCLK_FREE_AR inputs do not become origins.
set BUS_DEFS {
    {smn   {*c3x_smn*repeat_C3ROUTER*dff*}  {LID_CORE*_Smn*
                                             c3x_smn_rtr*_repeat_*}}
    {scan  {*ScanChanPipe*dff*}             {LID_CORE*_ScanTest_ScanChannelIn_signal*
                                             LID_CORE*_ScanTest_ScanChannelOut_signal*
                                             ScanChanIn_AcrossLid_staged*
                                             ScanChanOut_AcrossLid_staged*
                                             ScanChanOut_Col*_piped*
                                             ScanChanIn_Col*
                                             ScanInPipe_Chain_Col*_stages_*
                                             ScanOutPipe_Chain_Col*_stages_*}}
    {tsv   {*ScanChanPipe*dff*}             {TsvIn_Scan_ChannelsIn_TSV*
                                             TsvOut_Scan_ChannelsOut_TSV*}}
    {crb   {*crb_hop*dff*}                  {CrbManagerToHop*
                                             I_crb_hop_*_stage_d_*
                                             I_crb_hop_*_en_out_*
                                             *LID_CORE*_CrbReturn_*
                                             LID_CORE*_Crb_*}}
    {waker {*WakeRequest*dff*}              {LID_CORE*_WakeRequest_signal*
                                            I_c*x_lid_repA_cgen_chain_WakeRequest_*}}
    {glbirr {*GlbIrr*dff*}                  {LID_CORE*_GlbIrr_signal*
                                            I_c*x_lid_scfctp_dfd_I_c*x_lid_repA_cgen_chain_GlbIrr*}}
    {localirr {*DbgLocalIrr*dff*}           {LID_CORE*_DbgLocalIrr_signal*
                                            I_c*x_lid_scfctp_dfd_I_c*x_lid_repA_cgen_chain_DbgLocalIrr*}}
    {dbgdata {*DbgData*dff*}               {LID_CORE*_DbgData_signal*
                                            I_c*x_lid_scfctp_dfd_I_c*x_lid_repA_cgen_chain_DbgData_*}}    
    {dbgen {*Dbg*En_*dff}                  {LID_CORE*_DbgDbmuEn*
                                            LID_CORE*_SecureDbgEn*
                                            c*x_lid_tsv_dft_wrap_Cpl_SecureDbgEn_cdc}}
}

set BOUND_HALF_X            50.0
set BOUND_EDGE_HEIGHT       50.0   ;# height of a bound that sits against a top/bottom port edge
set BND_MIN_SPAN            50.0   ;# chains whose ports are closer than this in x get no staging
set BND_EDGE_TOL             5.0   ;# port y spread below this = ports lie on a horizontal edge
set BND_VERBOSE_CONFLICTS   0      ;# 1 = one warning line per conflicting cell

# ---------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------
proc bnd_cell_of {pin} { return [join [lrange [split $pin "/"] 0 end-1] "/"] }

# --- Sequential data pins ---------------------------------------------------
# Works on both a mapped and an un-mapped (pre initial_map) netlist:
#
#   mapped library flop     D -> Q      multibit  D1 -> Q1 ... Dn -> Qn
#   un-mapped *SEQGEN*      next_state -> Q
#
# On an elaborated netlist the RTL-inferred registers are still generic SEQGEN
# cells whose data input is next_state, so a D-only match walks off the end of
# the chain and every trace dead-ends.  SEQGEN also carries a data_in pin, but
# that is the latch (level sensitive) input and is tied off on these registers -
# only next_state is driven, so it is the one to follow.
proc bnd_is_data_pin {leaf} { return [regexp {^(D[0-9]*|next_state)$} $leaf] }

# Output pin(s) carrying the bit that arrived on $dpin.  Returns a COLLECTION,
# possibly of both polarities, because some repeaters are Q-negated:
#
#   D -> Q / QN        D1 -> Q1 / QN1        next_state -> Q / QN
#
# The Crb hop-manager chain alternates SDFQ* (Q) and SDFQN* (QN only) stages, so
# a Q-only lookup dead-ends at the first inverting flop.  Both polarities are
# returned rather than guessing, so an unloaded pin simply contributes nothing
# to the fanout and the real one is followed.  Inversion is irrelevant here -
# only the topology matters for placement.
proc bnd_out_pins {dpin} {
    set parts [split $dpin "/"]
    set leaf  [lindex $parts end]
    set base  [join [lrange $parts 0 end-1] "/"]
    if {$leaf eq "next_state"} {
        set cands {Q QN}
    } else {
        regsub {^D} $leaf {Q}  q
        regsub {^D} $leaf {QN} qn
        set cands [list $q $qn]
    }
    set res ""
    foreach c $cands {
        set p [get_flat_pins -quiet "$base/$c"]
        if {[sizeof_collection $p] == 0} { continue }
        if {$res eq ""} { set res $p } else { set res [add_to_collection $res $p -unique] }
    }
    return $res
}

# --- Tile outline -----------------------------------------------------------
# The tile is rectilinear, not a rectangle: the right hand section is only
# ~66.5um tall while the middle reaches 184.8um.  A bound must use the height of
# the tile where it actually sits, otherwise it claims area outside the block.
#
# bnd_hedges  - horizontal edges of the boundary as {xlo xhi y}
# bnd_y_range - {bottom top} of the tallest rectangle that fits inside the
#               outline across the whole x span, i.e. the lowest top edge and
#               the highest bottom edge seen anywhere in that span.
proc bnd_hedges {} {
    set pts [get_attribute -quiet [current_design] boundary]
    set n   [llength $pts]
    set edges {}
    for {set i 0} {$i < $n} {incr i} {
        set a [lindex $pts $i]
        set b [lindex $pts [expr {($i+1) % $n}]]
        if {[lindex $a 1] != [lindex $b 1]} { continue }          ;# vertical edge
        set x0 [lindex $a 0] ; set x1 [lindex $b 0]
        if {$x0 > $x1} { set t $x0 ; set x0 $x1 ; set x1 $t }
        lappend edges [list $x0 $x1 [lindex $a 1]]
    }
    return $edges
}

proc bnd_y_range {x0 x1} {
    global bnd_edges
    if {![info exists bnd_edges]} { set bnd_edges [bnd_hedges] }

    # Break the span at every outline step so a bound straddling one gets the
    # shorter of the two heights.
    set bps [list $x0 $x1]
    foreach e $bnd_edges {
        foreach v [list [lindex $e 0] [lindex $e 1]] {
            if {$v > $x0 && $v < $x1} { lappend bps $v }
        }
    }
    set bps [lsort -real -unique $bps]

    set top "" ; set bot ""
    for {set i 0} {$i < [llength $bps]-1} {incr i} {
        set mid [expr {0.5*([lindex $bps $i] + [lindex $bps [expr {$i+1}]])}]
        set hi "" ; set lo ""
        foreach e $bnd_edges {
            if {$mid < [lindex $e 0] || $mid > [lindex $e 1]} { continue }
            set y [lindex $e 2]
            if {$hi eq "" || $y > $hi} { set hi $y }
            if {$lo eq "" || $y < $lo} { set lo $y }
        }
        if {$hi eq ""} { continue }
        if {$top eq "" || $hi < $top} { set top $hi }
        if {$bot eq "" || $lo > $bot} { set bot $lo }
    }
    return [list $bot $top]
}

proc bnd_port_mean_x {names} {
    if {![llength $names]} { return "" }
    set sum 0.0
    foreach n $names {
        set bb [get_attribute -quiet [get_ports $n] bbox]
        set sum [expr {$sum + 0.5*([lindex [lindex $bb 0] 0] + [lindex [lindex $bb 1] 0])}]
    }
    return [expr {$sum / [llength $names]}]
}

proc bnd_port_mean_y {names} {
    if {![llength $names]} { return "" }
    set sum 0.0
    foreach n $names {
        set bb [get_attribute -quiet [get_ports $n] bbox]
        set sum [expr {$sum + 0.5*([lindex [lindex $bb 0] 1] + [lindex [lindex $bb 1] 1])}]
    }
    return [expr {$sum / [llength $names]}]
}

# --- Port edge classification and edge-hugging bounds -----------------------
# Ports on a vertical (left/right) edge are stacked in y, so a stage bounded
# against them should span the tile height.  Ports on a horizontal (top/bottom)
# edge all sit at one y, so the stage next to them only needs a shallow band
# against that edge - giving it the full tile height just lets the placer drift
# the flops away from the ports they feed.
#
# "vertical" if the port group's y values are spread, otherwise "bottom"/"top".
proc bnd_edge_of {ymin ymax} {
    global BND_EDGE_TOL
    set die [get_design_bounds]
    if {$ymin eq "" || $ymax eq ""} { return vertical }
    if {[expr {$ymax - $ymin}] > $BND_EDGE_TOL} { return vertical }
    if {[expr {$ymin - [lindex $die 1]}] < $BND_EDGE_TOL} { return bottom }
    return top
}

# A BOUND_EDGE_HEIGHT band hugging the top or bottom of the tile over [x0,x1].
#
# The x range is first narrowed to the part of the span where the outline
# actually REACHES that edge.  Without this a bound straddling the notch is
# handed the lower of the two heights by bnd_y_range and ends up flat against
# the wrong side of the tile - which is what pushed the TsvOut last stage down
# to y=0..59 when its ports are on the top edge at y=207.
#
# Returns {llx urx blly bury}, or "" if the span never reaches the edge.
proc bnd_edge_band {x0 x1 edge} {
    global bnd_edges BOUND_EDGE_HEIGHT
    if {![info exists bnd_edges]} { set bnd_edges [bnd_hedges] }

    set bps [list $x0 $x1]
    foreach e $bnd_edges {
        foreach v [list [lindex $e 0] [lindex $e 1]] {
            if {$v > $x0 && $v < $x1} { lappend bps $v }
        }
    }
    set bps [lsort -real -unique $bps]

    # local outline top/bottom of each sub-interval
    set sub {}
    for {set i 0} {$i < [llength $bps]-1} {incr i} {
        set a [lindex $bps $i] ; set b [lindex $bps [expr {$i+1}]]
        set mid [expr {0.5*($a+$b)}]
        set hi "" ; set lo ""
        foreach e $bnd_edges {
            if {$mid < [lindex $e 0] || $mid > [lindex $e 1]} { continue }
            set y [lindex $e 2]
            if {$hi eq "" || $y > $hi} { set hi $y }
            if {$lo eq "" || $y < $lo} { set lo $y }
        }
        if {$hi eq ""} { continue }
        lappend sub [list $a $b [expr {$edge eq "top" ? $hi : $lo}]]
    }
    if {![llength $sub]} { return "" }

    # the edge level the ports sit on = the extreme one anywhere in the span
    set lvl [lindex [lindex $sub 0] 2]
    foreach s $sub {
        set v [lindex $s 2]
        if {$edge eq "top"    && $v > $lvl} { set lvl $v }
        if {$edge eq "bottom" && $v < $lvl} { set lvl $v }
    }

    # keep only the part of the span that reaches it
    set lo "" ; set hi ""
    foreach s $sub {
        if {abs([lindex $s 2] - $lvl) > 0.001} { continue }
        if {$lo eq "" || [lindex $s 0] < $lo} { set lo [lindex $s 0] }
        if {$hi eq "" || [lindex $s 1] > $hi} { set hi [lindex $s 1] }
    }
    if {$lo eq ""} { return "" }

    if {$edge eq "top"} {
        return [list $lo $hi [expr {$lvl - $BOUND_EDGE_HEIGHT}] $lvl]
    }
    return [list $lo $hi $lvl [expr {$lvl + $BOUND_EDGE_HEIGHT}]]
}

# Forward one hop from a port or a Q pin.
# Returns {repeater_D_pins  terminal_output_ports}
# A flat pin name always contains "/", a port name never does - cheaper than
# querying object_class on every endpoint.
proc bnd_next {obj} {
    upvar #0 bnd_isrep isrep
    set dpins  {}
    set tports {}
    foreach_in_collection e [all_fanout -from $obj -flat -endpoints_only] {
        set en [get_object_name $e]
        if {[string first "/" $en] < 0} {
            if {[get_attribute -quiet $e direction] eq "out"} { lappend tports $en }
            continue
        }
        set leaf [lindex [split $en "/"] end]
        if {![bnd_is_data_pin $leaf]} { continue }
        if {[info exists isrep([bnd_cell_of $en])]} { lappend dpins $en }
    }
    return [list $dpins $tports]
}

# Depth first walk.  Emits {origin_port terminal_ports stage_D_pins} per chain.
proc bnd_walk {from path origin} {
    global bnd_chains
    lassign [bnd_next $from] dpins tports

    set nxt {}
    foreach d $dpins {
        if {[lsearch -exact $path $d] >= 0} { continue }                          ;# loop
        if {[llength $path] && [bnd_cell_of $d] eq [bnd_cell_of [lindex $path end]]} { continue } ;# retention self loop
        lappend nxt $d
    }

    if {![llength $nxt]} {
        if {[llength $path]} { lappend bnd_chains [list $origin $tports $path] }
        return
    }
    foreach d $nxt {
        set op [bnd_out_pins $d]
        if {$op eq "" || [sizeof_collection $op] == 0} { continue }
        bnd_walk $op [concat $path [list $d]] $origin
    }
}

# ---------------------------------------------------------------
# Phase A - trace every bus and classify each chain
# ---------------------------------------------------------------
array unset grp_ox    ; array unset grp_tx   ; array unset grp_n
array unset slot_cells ; array unset cell_slot ; array unset conflict_pairs
array unset local_cells ; array unset local_grp ; array unset local_max
set n_conflict 0
set n_noterm   0
set n_local    0
set all_cells  ""
set all_chains {}

foreach bus $BUS_DEFS {
    lassign $bus prefix cell_pat port_pats

    array unset bnd_isrep
    set bus_cells [filter_collection [get_flat_cells -quiet $cell_pat] "is_sequential==true"]
    foreach_in_collection c $bus_cells { set bnd_isrep([get_object_name $c]) 1 }
    if {$all_cells eq ""} {
        set all_cells $bus_cells
    } else {
        set all_cells [add_to_collection $all_cells $bus_cells -unique]
    }

    set origin_ports [lsort [get_object_name \
        [filter_collection [get_ports -quiet $port_pats] "direction==in"]]]

    set bnd_chains {}
    set t0 [clock milliseconds]
    foreach p $origin_ports { bnd_walk [get_ports $p] {} $p }
    set el [expr {[clock milliseconds]-$t0}]

    puts [format "  %-5s %5d repeater flops, %4d origin ports -> %5d chains  (%d ms)" \
              $prefix [sizeof_collection $bus_cells] [llength $origin_ports] \
              [llength $bnd_chains] $el]

    foreach ch $bnd_chains {
        lassign $ch origin tports path
        if {![llength $tports]} {
            puts "  WARNING: $prefix chain from $origin reaches no output port - skipped"
            incr n_noterm
            continue
        }
        set ox   [bnd_port_mean_x [list $origin]]
        set tx   [bnd_port_mean_x $tports]
        set N    [llength $path]
        set span [expr {abs($tx - $ox)}]

        # Staging a chain only makes sense if it actually travels in x.  Local
        # relays that enter and leave on the same edge are dropped here so they
        # never form a group and never claim a flop from a real chain.
        if {$span < $BND_MIN_SPAN} {
            incr n_local
            set k "${prefix}_${N}stg"
            incr local_grp($k)
            if {![info exists local_max($k)] || $span > $local_max($k)} { set local_max($k) $span }
            foreach d $path { set local_cells([bnd_cell_of $d]) 1 }
            continue
        }

        set dir [expr {$tx >= $ox ? "l2r" : "r2l"}]
        set grp ${prefix}_${N}stg_${dir}

        set grp_ox($grp) [expr {[info exists grp_ox($grp)] ? $grp_ox($grp)+$ox : $ox}]
        set grp_tx($grp) [expr {[info exists grp_tx($grp)] ? $grp_tx($grp)+$tx : $tx}]
        set grp_n($grp)  [expr {[info exists grp_n($grp)]  ? $grp_n($grp)+1   : 1}]

        # x extent of the port groups, for the wide-bus rule below
        if {![info exists grp_oxmin($grp)] || $ox < $grp_oxmin($grp)} { set grp_oxmin($grp) $ox }
        if {![info exists grp_oxmax($grp)] || $ox > $grp_oxmax($grp)} { set grp_oxmax($grp) $ox }
        if {![info exists grp_txmin($grp)] || $tx < $grp_txmin($grp)} { set grp_txmin($grp) $tx }
        if {![info exists grp_txmax($grp)] || $tx > $grp_txmax($grp)} { set grp_txmax($grp) $tx }

        # y extent, to tell a horizontal port edge from a vertical one
        set oy [bnd_port_mean_y [list $origin]]
        set ty [bnd_port_mean_y $tports]
        if {![info exists grp_oymin($grp)] || $oy < $grp_oymin($grp)} { set grp_oymin($grp) $oy }
        if {![info exists grp_oymax($grp)] || $oy > $grp_oymax($grp)} { set grp_oymax($grp) $oy }
        if {![info exists grp_tymin($grp)] || $ty < $grp_tymin($grp)} { set grp_tymin($grp) $ty }
        if {![info exists grp_tymax($grp)] || $ty > $grp_tymax($grp)} { set grp_tymax($grp) $ty }

        lappend all_chains [list $span $N $origin $grp $path]
    }
}

# ---------------------------------------------------------------
# Phase B - claim order
#
# A flop can sit on several logical chains (muxed pipe segments, multibit
# banking).  First claim wins, so "first" must be deliberate rather than
# whatever order the ports happened to sort in.
#
# Priority: FEWEST STAGES first, then longest span, then name for determinism.
#
# Fewest stages wins because for a given span, fewer stages means a longer hop
# per stage and therefore the tighter timing constraint - that chain has the
# least slack to give up, so it gets to place its flops where it wants them.
# A deeper chain sharing those flops has shorter hops and can absorb sitting
# slightly off its own ideal spacing.
#
# Stage count has to be the PRIMARY key, not a tiebreak under span.  The two
# reconvergent smn *active* bits form a 6 stage group whose span is a couple of
# um LONGER than the 5 stage bus group (their ports sit fractionally further
# apart), so a span-first order let the 6 stage chains claim the shared flops
# and drag them off the 5 stage spacing.
#
# Where stage counts tie, the key must be the GROUP span, not the individual
# chain span.  Chains in one group differ by a few um because the ports are
# spread along the tile edge, which is more than the difference between two
# groups' spans - keying on the chain span would interleave groups and fragment
# every claim.
#
# lsort is stable, so the keys are applied in reverse priority order.
# ---------------------------------------------------------------
array unset grp_span
foreach g [array names grp_n] {
    set grp_span($g) [expr {abs($grp_tx($g)/$grp_n($g) - $grp_ox($g)/$grp_n($g))}]
}
set keyed {}
foreach ch $all_chains {
    lassign $ch span N origin grp path
    lappend keyed [list $grp_span($grp) $N $grp $origin $path]
}
set keyed [lsort -index 3 -ascii $keyed]
set keyed [lsort -index 2 -ascii $keyed]
set keyed [lsort -index 0 -real -decreasing $keyed]
set keyed [lsort -index 1 -integer -increasing $keyed]
set all_chains $keyed

# ---------------------------------------------------------------
# Phase C - assign cells to stage slots
#
# cell_slot / slot_cells are shared across all buses so a cell claimed by one
# bus cannot be re-bounded by another.
# ---------------------------------------------------------------
foreach ch $all_chains {
    lassign $ch gspan N grp origin path
    for {set i 0} {$i < $N} {incr i} {
        set cell [bnd_cell_of [lindex $path $i]]
        set slot [list $grp [expr {$i+1}]]
        if {[info exists cell_slot($cell)]} {
            if {$cell_slot($cell) ne $slot} {
                set key "[lindex $cell_slot($cell) 0] s[lindex $cell_slot($cell) 1] <- [lindex $slot 0] s[lindex $slot 1]"
                incr conflict_pairs($key)
                incr n_conflict
                if {$BND_VERBOSE_CONFLICTS} {
                    puts "  WARNING: conflict $key - keeping existing bound for $cell"
                }
            }
            continue
        }
        set cell_slot($cell) $slot
        lappend slot_cells($slot) $cell
    }
}

# ---------------------------------------------------------------
# Short / local chain summary
# ---------------------------------------------------------------
if {$n_local > 0} {
    puts "  $n_local chains skipped - origin and terminal ports less than ${BND_MIN_SPAN}um apart in x (no staging):"
    foreach k [lsort [array names local_grp]] {
        puts [format "           %-22s max span %8.3f um  %6d chains" $k $local_max($k) $local_grp($k)]
    }
}

# ---------------------------------------------------------------
# Conflict summary
# ---------------------------------------------------------------
if {$n_conflict > 0} {
    puts "  WARNING: $n_conflict stage assignments rejected (cell already bounded elsewhere)"
    puts "           kept slot            <- rejected slot           count"
    foreach k [lsort [array names conflict_pairs]] {
        puts [format "           %-45s %6d" $k $conflict_pairs($k)]
    }
}

# ---------------------------------------------------------------
# Drop any existing bound that shares cells with the repeaters
# ---------------------------------------------------------------
set doomed {}
foreach_in_collection bd [get_bounds -quiet *] {
    set bn     [get_object_name $bd]
    set bcells [get_flat_cells -quiet -of_objects $bd]
    set shared 0
    if {[sizeof_collection $bcells] > 0} {
        set shared [sizeof_collection [remove_from_collection $bcells \
                        [remove_from_collection $bcells $all_cells]]]
    }
    if {$shared > 0} {
        puts "  removing colliding bound '$bn' ([sizeof_collection $bcells] cells, $shared shared with the repeaters)"
        lappend doomed $bn
    } else {
        foreach bus $BUS_DEFS {
            if {[string match [lindex $bus 0]_*stg_* $bn]} { lappend doomed $bn ; break }
        }
    }
}
foreach bn $doomed { remove_bounds -force [get_bounds $bn] }

# ---------------------------------------------------------------
# Create the bounds
# ---------------------------------------------------------------
set die     [get_design_bounds]
set die_llx [lindex $die 0] ; set die_lly [lindex $die 1]
set die_urx [lindex $die 2] ; set die_ury [lindex $die 3]

set n_bounds 0
set n_placed 0
foreach grp [lsort [array names grp_n]] {
    set x0 [expr {$grp_ox($grp) / $grp_n($grp)}]
    set x1 [expr {$grp_tx($grp) / $grp_n($grp)}]
    regexp {_(\d+)stg_} $grp -> N
    # N-1 segments: stage 1 lands on the origin port, stage N on the terminal port.
    set step [expr {$N > 1 ? ($x1 - $x0) / double($N - 1) : 0.0}]
    puts [format "  %-18s %5d chains  origin_x=%9.3f  terminal_x=%9.3f  step=%9.3f  (%2d stages)" \
              $grp $grp_n($grp) $x0 $x1 $step $N]

    for {set i 1} {$i <= $N} {incr i} {
        set slot [list $grp $i]
        set name ${grp}_s${i}
        if {![info exists slot_cells($slot)]} {
            puts [format "    %-24s SKIPPED - all cells already bounded by an earlier group" $name]
            continue
        }
        set cells [get_flat_cells -quiet $slot_cells($slot)]
        set cx  [expr {$N > 1 ? $x0 + ($i - 1) * $step : 0.5 * ($x0 + $x1)}]
        set llx [expr {$cx - $BOUND_HALF_X}]
        set urx [expr {$cx + $BOUND_HALF_X}]

        # Wide-bus rule.  A bound is 2*BOUND_HALF_X across.  If the port group a
        # stage sits against is spread wider than that (TsvIn's 128 origins span
        # 172um of the north edge), a bound centred on the mean cannot cover the
        # bits and squeezes the whole stage into one column.  For the stage
        # adjacent to such a port group, use the port span as the bound instead.
        set widened ""
        if {$i == 1 && [expr {$grp_oxmax($grp) - $grp_oxmin($grp)}] > 2*$BOUND_HALF_X} {
            set llx $grp_oxmin($grp) ; set urx $grp_oxmax($grp)
            set widened "  <-- widened to origin port span"
        }
        if {$i == $N && [expr {$grp_txmax($grp) - $grp_txmin($grp)}] > 2*$BOUND_HALF_X} {
            if {$i == 1} {
                if {$grp_txmin($grp) < $llx} { set llx $grp_txmin($grp) }
                if {$grp_txmax($grp) > $urx} { set urx $grp_txmax($grp) }
            } else {
                set llx $grp_txmin($grp) ; set urx $grp_txmax($grp)
            }
            set widened "  <-- widened to terminal port span"
        }

        if {$llx < $die_llx} { set llx $die_llx }
        if {$urx > $die_urx} { set urx $die_urx }

        # A stage sitting against a top/bottom port edge gets a shallow band
        # hugging that edge instead of the full tile height, with its x range
        # narrowed to the part of the span that actually reaches the edge.
        set band ""
        if {$i == 1 && [bnd_edge_of $grp_oymin($grp) $grp_oymax($grp)] ne "vertical"} {
            set band [bnd_edge_band $llx $urx [bnd_edge_of $grp_oymin($grp) $grp_oymax($grp)]]
            if {$band ne ""} { append widened "  <-- [bnd_edge_of $grp_oymin($grp) $grp_oymax($grp)]-edge band" }
        }
        if {$i == $N && [bnd_edge_of $grp_tymin($grp) $grp_tymax($grp)] ne "vertical"} {
            set b2 [bnd_edge_band $llx $urx [bnd_edge_of $grp_tymin($grp) $grp_tymax($grp)]]
            if {$b2 ne ""} {
                set band $b2
                append widened "  <-- [bnd_edge_of $grp_tymin($grp) $grp_tymax($grp)]-edge band"
            }
        }

        if {$band ne ""} {
            lassign $band llx urx blly bury
        } else {
            lassign [bnd_y_range $llx $urx] blly bury
        }
        if {$blly eq "" || $bury eq "" || $bury <= $blly} {
            puts "    WARNING: $name - no valid tile height over x=$llx..$urx, skipped"
            continue
        }
        create_bound -name $name -type hard \
            -boundary [list [list $llx $blly] [list $urx $bury]] $cells
        incr n_bounds
        incr n_placed [sizeof_collection $cells]
        puts [format "    %-24s centre=%9.3f  x=%9.3f -> %9.3f  y=%7.3f -> %7.3f  cells=%d%s" \
                  $name $cx $llx $urx $blly $bury [sizeof_collection $cells] $widened]
    }
}

# ---------------------------------------------------------------
# Coverage
# ---------------------------------------------------------------
set unbounded [remove_from_collection $all_cells [get_flat_cells -quiet [array names cell_slot]]]

# Split the leftovers: flops that only ever appeared on a short local chain are
# deliberately unconstrained; anything else was never reached at all.
set n_localonly 0
set never {}
foreach_in_collection c $unbounded {
    if {[info exists local_cells([get_object_name $c])]} {
        incr n_localonly
    } else {
        lappend never [get_object_name $c]
    }
}
puts [format "  coverage: %d bounds, %d of %d repeater flops bounded (local-only=%d, unreached=%d, rejected assignments=%d, short chains skipped=%d, chains w/o terminal port=%d)" \
          $n_bounds $n_placed [sizeof_collection $all_cells] \
          $n_localonly [llength $never] $n_conflict $n_local $n_noterm]
if {$n_localonly > 0} {
    puts "  NOTE: $n_localonly flops sit only on short local chains - left unbounded on purpose"
}
if {[llength $never] > 0} {
    puts "  WARNING: [llength $never] repeater flops not reached by any traced chain:"
    set shown 0
    foreach n $never {
        puts "    $n"
        if {[incr shown] >= 20} { puts "    ... and [expr {[llength $never]-20}] more" ; break }
    }
}

puts "REPEATER-BOUNDS: done"
