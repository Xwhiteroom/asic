# Copyright (c) 2026 Syed Shakir Iqbal (Xwhiteroom)
# SPDX-License-Identifier: MIT
# --- Build ASCII tree + collect level->object map (per node's subtree) ---
#
#  Usage:

#  set root_node   "u_top/CLK_ROOT"
#  set tree_data   [ssi_build_cts_tree_levels $root_node]
#  ssi_dump_tree_dict_csv $tree_data "/tmp/cts_tree.csv"

#  To merge multiple clock roots into one CSV:

#  set all_trees [dict create]
#  foreach root $clock_roots { set all_trees [dict merge $all_trees [ssi_build_cts_tree_levels $root]]}
#  ssi_dump_tree_dict_csv $all_trees "/tmp/cts_all_trees.csv"
#
#
proc ssi_build_cts_csv {csv_file roots} {
      set all_trees [dict create]

      foreach_in_collection oroot $roots {
          set root [get_object_name $oroot]
          puts "Building CTS tree for: $root"
          set all_trees [dict merge $all_trees [ssi_build_cts_tree_levels $root]]
      }

      ssi_dump_tree_dict_csv $all_trees $csv_file
      puts "CTS tree data written to: $csv_file"

      return $all_trees
}

proc ssi_build_cts_ascii_tree {node  {prefix ""} {visited {}} {level 0}} {
      set result [dict create]
      dict lappend result $level $node

      lappend visited $node
      set clk_cond "is_clock_used_as_clock==true"
      set fanouts [lsort [get_object_name [filter_collection  [all_fanout -flat -pin_level 1 -from $node] "$clk_cond" ]]]
      set fanouts [lsearch -all -inline -not -exact $fanouts $node]
      set count [llength $fanouts]

      set idx 0
      foreach child $fanouts {
          incr idx
          set is_last  [expr {$idx == $count}]
          set branch   [expr {$is_last ? "└── " : "├── "}]
          set nextpref [expr {$is_last ? "$prefix    " : "$prefix│   "}]

          if {[lsearch -exact $visited $child] >= 0} {
              puts "${prefix}${branch}${child} (loop)"
              dict lappend result [expr {$level + 1}] $child
          } else {
              puts "${prefix}${branch}${child}"
              set childResult [ssi_build_cts_ascii_tree $child $nextpref $visited [expr {$level + 1}]]
              dict for {lvl objs} $childResult {
                  foreach obj $objs {
                      dict lappend result $lvl $obj
                  }
              }
          }
      }
      return $result
}

# --- Wrap into node->level->object_list ---
proc ssi_build_cts_tree_levels {node} {
      return [dict create $node [ssi_build_cts_ascii_tree $node]]
}

# --- CSV field escaping ---
proc ssi_csv_quote {val} {
      if {[string match "*\[,\"\n\]*" $val]} {
          return "\"[string map {\" \"\"} $val]\""
      }
      return $val
}

# --- Dump node->level->object_list dict to CSV ---
proc ssi_dump_tree_dict_csv {tree_data filename} {
      set fh [open $filename w]
      puts $fh "root,level,object"

      dict for {root levels} $tree_data {
          foreach level [lsort -integer [dict keys $levels]] {
              foreach obj [dict get $levels $level] {
                  puts $fh "[ssi_csv_quote $root],${level},[ssi_csv_quote $obj]"
              }
          }
      }
      close $fh
}
