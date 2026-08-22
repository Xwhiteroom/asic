#!/usr/bin/perl
##################################################
# Copyright (c) 2026 Syed Shakir Iqbal (Xwhiteroom)
# SPDX-License-Identifier: MIT
##################################################
#use strict;
require Term::ANSIColor;
use Term::ANSIColor;
use Term::ANSIColor qw( :constants );
use File::Basename;
use File::Copy; 
use Cwd; 
use Cwd 'abs_path'; 
use File::Temp qw(tempfile tempdir); 
use File::Find;
$Term::ANSIColor::AUTORESET = 0;
use Term::ANSIColor 1.00;
use English;
use Getopt::Long;
use Getopt::Std;
my %argHash=(
            "f=s"            =>\my $files,
            "v=s"            =>\my $verbose,
            "u=s"            =>\my $slack_u,
            "l=s"            =>\my $slack_l,
            "t=s"            =>\my $tag,
            "r=s"            =>\my $rev,
            "n=s"            =>\my $no_sub,
	    "g=s"            =>\my $add_group,
	    "b=s"            =>\my $sort_bucket,
	    "e=s"            =>\my $eco,
	    "c=s"            =>\my $uniq_csv,
	    "h=s"            =>\my $histo_step,	 
	    "x=s"            =>\my $skip_extra_rpt,
	    "gls=s"          =>\my $gen_annotation,	                

            );

GetOptions(%argHash);
## PARSING INPUT ARGUMENTS
if ( !defined $files  ) {
   printf BOLD RED        "\n**ERROR : No files_ speficed !!\n\n";
   printf RESET ""  ;
   print color 'red';
   print "\n\
          USAGE   : perl $0		 \
                                                 -f   <File1>\
						 -u   <max_slack def=0>\
						 -l   <min_slack def=-99999999999999999>\
						 -v   <verbose def=0>\
						 -t   <tag def=my_temp_rca_sum>\
						 -r   <rev def=0, else 1 to switch pin slack  :  r=0  index: slack=1 pin=0 view=2    :  r=1 index: slack=0 pin=1 view=2>\
						 -n   <no_sub  def=0, else 1 to skip any substitution >\
						 -g   <add_group, def=0, user=1 to include groups as corner as well>\
						 -b   <sort_bucket, def=count, user=wns/slack>\
						 -e   <do eco so skip unification and makle pins as cell def=0,else 1 >
						 -c   <delimit attr_index1,index2 value_index worst_is_minmax>
						 -h   <histo bin size default = 0.005>	
						 -x   <skip extra reports and dir default = 0>			
						 -gls <gen_anno default = 0>			

                                                 \n";
   printf RESET ""  ;
   exit;
};

if ($uniq_csv eq "" || !defined $uniq_csv) {$uniq_csv = "";}
if ($histo_step eq "" || !defined $histo_step) {$histo_step = "0.005";};$histo_step = abs($histo_step);
if ($slack_u eq "" || !defined $slack_u) {$slack_u = "0";}
if ($slack_l eq "" || !defined $slack_l) {$slack_l = "-99999999999999999";}
my $slack_index = 0; my $pin_index   = 1;my $view_index = 2;
if ($rev eq "" || !defined $rev  || $rev eq "0" ) {$slack_index = 1;$pin_index   = 0;$view_index = 2; };
if ($rev eq "1" )  				  {$slack_index = 0;$pin_index   = 1;$view_index = 2; };
if ($no_sub eq "" || !defined $no_sub  || $no_sub eq "0" ) {$no_sub = 0; };
if ($add_group eq "" || !defined $add_group) { $add_group = "0";};
if ($sort_bucket eq "" || !defined $sort_bucket) {$sort_bucket = "count";}
if ($eco eq "" || !defined $eco) {$eco = "0";}
if ($tag eq "" || !defined $tag) { $tag = "my_temp_rca_sum";};
if ( $verbose eq "" || !defined $verbose ) { $verbose = 0; print "\n\n**Warn:: Index P=$pin_index S=$slack_index Verbose disabled $verbose! , No sub mode $no_sub, Slack [$slack_u : $slack_l]ps  Bin : $histo_step\n";};
if ($skip_extra_rpt eq "" || !defined $skip_extra_rpt) {$skip_extra_rpt = "0";}
if ($gen_annotation eq "" || !defined $gen_annotation) {$gen_annotation = "0";}


# Uniquify a CSV based on an index and attr 
my %f1;my %f2;my @uniq_csv_data =split(/\s+/,$uniq_csv);

if ( $#uniq_csv_data >= 3) {
	my $delimit = $uniq_csv_data[0];
	my $attr_i  = $uniq_csv_data[1];
	my $value_i = $uniq_csv_data[2];
	my $minmax  = $uniq_csv_data[3];
	my @attr_x = split(/,/,$attr_i);
	my $scale   = "1";
	my $master_key = "";
	if ( $minmax eq "min" ) { $scale = "1";};
	if ( $minmax eq "max" ) { $scale = "-1";};
        print("\n\n**Info:: Parsing file $files using D=$delimit A=$attr_i V=$value_i Worst_Val=$minmax\n\n");
 	foreach my $file1 (glob("$files")) {   
   		if ( -e $file1) {
			open (in,$file1);
			my $file_name = basename($file1);
        		while(my $line = <in>) {
	    			$line =~ s/\n//g; $line =~ s/^\s+//g; $line =~ s/\s+$//g; 
	    			my @line_arr =split(/$delimit/,$line);
				if ( $line_arr[0] =~ /^#/) { $master_key = $line;
				} else {
					my $key ;
					foreach my $attr_temp (@attr_x) { $key = "$key,@line_arr[$attr_temp]";};
					#my $key  = @line_arr[$attr_i];
					my $val  = $scale*@line_arr[$value_i];
					my $data = $line;
					if ( $f1{$key} eq "" or $f1{$key} > $val )  {  $f1{$key} = $val; $f2{$key} = "$data"};
				}
			};
			close(in)
		};
	};
	open (out1,">${tag}.uniq.data_only.rpt");
	open (out2,">${tag}.uniq.data_full.rpt");
	open (out3,">${tag}.uniq.data_keyval.rpt");
    	my $i = 0; 
	print out1 ("$master_key\n");
	print out2 ("#Val($minmax.$scale) #Attr $master_key\n");
	print out3 ("#Val($minmax.$scale) #Attr\n");
    	foreach my $attr (keys %f1) {
		$f1{$attr} = $scale*$f1{$attr};
		print out1 "$f2{$attr}\n";
		print out2 "$f1{$attr} $attr $f2{$attr}\n";
		print out3 "$f1{$attr} $attr\n";
	};
	close(out1);
	close(out2);
	close(out3);
	my $in_his_file = "${tag}.data_keyval.rpt" ;
	my $out_his_file = "${tag}.data_keyval.histogram";	
	get_outfile($in_his_file,$histo_step,"1","1",$out_his_file);
    	print "\n**Info:: Open file \n\t${tag}.uniq.data_only.rpt\n\t${tag}.uniq.data_full.rpt\n\t${tag}.uniq.data_keyval.rpt\n";
        exit;
};

my %f1; my %f2; my %f3;my %f4;my %fstat;my $i = 0;
 foreach my $file1 (glob("$files")) {   
    if ( -e $file1) {
        open (in,$file1);
	my $file_name = basename($file1);
	my $group  = ".noGrp";
        while(my $line = <in>) { 
	    $line =~ s/\n//g; $line =~ s/^\s+//g; $line =~ s/\s+$//g; 
	    if ( $line =~m/=/ || $line =~ m/\*\*\*\*/ || $line =~ /^Report /) { goto skip_line;};	
	    my @line_arr =split(/\s+/,$line);
	    my $corner = "Default";
	    my $slack  = $line_arr[$slack_index];
	    my $pin    = $line_arr[$pin_index];

  	    if ( $line_arr[$view_index] ne "") { $corner = $line_arr[$view_index]};
	    if ( $add_group == "1"  and  $line =~ /.* group\)/) { $group = ".$line_arr[1]"; $group =~ s/\(//g;$group =~ s/'//g; print "$group\n";};
	    
	    if ($pin ne "" && $slack < $slack_u  && $slack >= $slack_l && $slack ne "") {
	    	# Slack within range
		#print "Rev:$rev S:$slack P:$pin C:$corner\n"; exit;
		if ( $f1{$corner.$group}{$pin} > $slack ||  $f1{$corner.$group}{$pin} eq "" ) {
			$f1{$corner.$group}{$pin} 		= $slack;
                        $f3{$corner.$group}{$pin}{"file_name"} 	= $file_name;
                        $f3{$corner.$group}{$pin}{"wns"} 	= $slack;
                } elsif ( $slack < 0 ) {                        
                        $f3{$corner.$group}{$pin}{"tns"} 	= $f3{$corner.$group}{$pin}{"tns"} + $slack;
                        $f3{$corner.$group}{$pin}{"cns"}++;
		}
                
		if ( $f2{"ALL_CORNERS"}{$pin} > $slack ||  $f2{"ALL_CORNERS"}{$pin} eq "" ) {
                        if ($f2{"ALL_CORNERS"}{$pin} eq "" )  {
                            $f3{"ALL_CORNERS"}{$pin}{"tns"}   = $slack;
                            $f3{"ALL_CORNERS"}{$pin}{"cns"}   = 1; 
                        }

			$f2{"ALL_CORNERS"}{$pin} = $slack;
                        $f3{"ALL_CORNERS"}{$pin}{"file_name"} = $file_name;
			$f3{"ALL_CORNERS"}{$pin}{"corner"} = $corner;
			$f3{"ALL_CORNERS"}{$pin}{"wns"}    = $slack;
                        $f3{$corner.$group}{$pin}{"wns"}   = $slack;

                } elsif ( $slack < 0 ) {
                        $f3{$corner.$group}{$pin}{"tns"}   = $f3{$corner.$group}{$pin}{"tns"} + $slack;
                        $f3{$corner.$group}{$pin}{"cns"}   = $f3{$corner.$group}{$pin}{"cns"} + 1;

                        $f3{"ALL_CORNERS"}{$pin}{"tns"}    = $f3{"ALL_CORNERS"}{$pin}{"tns"} + $slack;
                        $f3{"ALL_CORNERS"}{$pin}{"cns"}    = $f3{"ALL_CORNERS"}{$pin}{"cns"} + 1; 
			#print "$corner\n";
		}
	    }
	    $i++;   if ( $i =~ /0000000$/) { print "      - Processed lines $i\n";};
	    skip_line:
	};
        close (in);
	print "      - Processed lines $i\n";
    }   else {
        printf "**Error : File $file1 doesn't exist \n\n";exit;
    }
    printf "**Info:  Found $i lines in file $file1\n";
  }  
    my %corner_data;
    $corner_data{"#Header"}{summary_string}  = sprintf("%20s    %10s   %10s   %10s   %10s   %10s  %s\n","#VIO","#TNS","#WNS","#MEDI","#MEAN","#SIGM","#CORNER");
    my $bucket_header                        = sprintf("%12s %12s %12s %32s %s","#Bunch_Size","#Bunch_WNS","#Bunch_TNS","#Bunch_ID","#Bunch_GRP");
    
    
    mkdir "${tag}_rep";
    my $dump_dir = abs_path("${tag}_rep");
    
    
    open (out1,">${tag}.rpt");
    open (out2,">${tag}_pat.rpt");
    open (out3,">${tag}_pat_gen_rpt.tcl");
    open (out4,">${tag}_anno.tcl");
    print  out4 ("################################################################################################\n"); 
    print  out4 ("proc add_delay_ex { padding slack_compensate pins } { \n");
    print  out4 ("      foreach_in_collection pin [get_pins -quiet \$pins] {\n");
    print  out4 ("         set pin    [get_object_name [get_pins \$pin]]\n");
    print  out4 ("         set driver [get_object_name [get_pins -quiet -filter \"direction==out\" [all_fanin -flat -to [get_pins \$pin]  -pin_level 1]]]\n");
    print  out4 ("         set_annotated_delay -increment  -min -net -to [get_pins \$pin] -from [get_pins \$driver] [expr \$padding + \$slack_compensate]\n");
    print  out4 ("         echo \"set_annotated_delay -increment -min   -net -to \\[get_pins \$pin\\] -from \\[get_pins \$driver\\] \[expr \$padding + \$slack_compensate\]\"\n");
    print  out4 ("      }\n");
    print  out4 ("}\n");
    print  out4 ("set sdf_padding 0.050\n");
    print  out4 ("set anno_log ${tag}_anno.log\n");     
    print  out4 ("################################################################################################\n"); 
    print  out4 ("echo \"Add Anno log for ${tag}_anno.tcl \" > \$anno_log\n"); 
    print  out4 ("set anno_log ${tag}_anno.log\n"); 


    printf out2 ("$bucket_header\n");
    print  out3 ("################################################################################################\n"); 
    print  out3 ("## File to Dump Bucket Reports with associated tags and default rpt cmd\n");
    print  out3 ("################################################################################################\n"); 
    print  out3 ("alias rt_syntax \"rtx -max_paths 100 -nworst 1\"\n");
    print  out3 ("set dump_dir \"${dump_dir}/bucket_reports/sort_by_$sort_bucket\"\n");
    print  out3 ("file mkdir \"\$dump_dir\"\n");
    my @pin_slack_arr ;
    foreach my $corner (keys %f2) {
    	my $tns = 0; my $vio = 0 ; my $wns = $slack_u;	
    	foreach my $pin ( keys %{$f2{$corner}}) {
		if ( $wns > $f2{$corner}{$pin}) { $wns = $f2{$corner}{$pin};};
		$tns = $tns + $f2{$corner}{$pin};
		$vio++;
		push @pin_slack_arr,$f2{$corner}{$pin};
		my $xcorner = $f3{"ALL_CORNERS"}{$pin}{"corner"};
                $f2{$corner}{$pin} = sprintf("%0.3f",$f2{$corner}{$pin});
                my $anno           = -1*$f2{$corner}{$pin};
                my $comment        = "Info";
                if ( $anno < 0 ) { $comment = "Warn";}
		print out1 "$f2{$corner}{$pin} $pin $f3{ALL_CORNERS}{$pin}{corner}\n";
                print  out4 ("catch { add_delay_ex \$sdf_padding $anno {$pin} >> \$anno_log } ; #$comment slack=$f2{$corner}{$pin} view=$f3{ALL_CORNERS}{$pin}{corner} \n");
		my $xpin = $pin ; 
		if ($no_sub eq "0") {    $xpin =~ s/[0-9]+/*/g;};
		$f4{$xpin}{count}--; # setting count as negative for unified sorting
		$f4{$xpin}{wns} = $f2{$corner}{$pin};
		$f4{$xpin}{slack} = $f4{$xpin}{slack} + $f2{$corner}{$pin};
	}
	# for all corners
        my $medNS = median(@pin_slack_arr);	
        my $meaNS = average(\@pin_slack_arr);
        my $sigNS = stdev(\@pin_slack_arr);
        $fstat{"ALL_CORNERS"}{"median"} = $medNS;
        $fstat{"ALL_CORNERS"}{"average"} = $meaNS;
        $fstat{"ALL_CORNERS"}{"sigma"} = $sigNS;
	$corner_data{$corner}{summary_string}  = sprintf("%20d    %10.3f    %10.3f   %10.3f   %10.3f   %10.3f  %s",$vio,$tns,$wns,$medNS,$meaNS,$sigNS,$corner);
    	my $i = 0;
	#foreach my $ypin (sort  keys %f4) {
    	print  out3 ("echo  \"$bucket_header\  #Bucket_File\" > \$dump_dir/../$sort_bucket.with_file_pointers.txt\n");
	foreach my $ypin (sort { $f4{$a}{$sort_bucket} <=> $f4{$b}{$sort_bucket} } keys %f4) {
		
	  $i++;
	  my $id = sprintf("%20s_%05d",$corner,$i); $id =~ s/^\s+//g;
	  # readjusting count to positive : 
    	  my $pdata = sprintf ("%12d %12.3f %12.3f %32s %s",-1*$f4{$ypin}{count},$f4{$ypin}{wns},$f4{$ypin}{slack},$id,$ypin);
	  #print "$pdata\n";
    	  printf out2 ("$pdata\n");
    	  print  out3 ("echo  \"#$bucket_header\" >> \$dump_dir/$id.sort_by_$sort_bucket.rpt\n");
    	  print  out3 ("echo  \"#$pdata\" >> \$dump_dir/$id.sort_by_$sort_bucket.rpt\n");
    	  print  out3 ("echo     \"$pdata \$dump_dir/$id.sort_by_$sort_bucket.rpt\" >> \$dump_dir/../$sort_bucket.with_file_pointers.txt\n");

    	  print  out3 ("rt_syntax -to $ypin >> \$dump_dir/$id.sort_by_$sort_bucket.rpt\n");
    	  print  out3 ("echo  \"#$pdata\" >> \$dump_dir/$id.sort_by_$sort_bucket.rpt\n");

    	}	
    }	
    close (out1);
    close (out2);
    close (out3);
    close (out4);

    if ($skip_extra_rpt eq "1") { system("rm -rf $dump_dir ${tag}_pat.rpt ${tag}_pat_gen_rpt.tcl");};
    if ($gen_annotation ne "1") { system("rm -rf ${tag}_anno.tcl");};

    my $in_his_file  = "${tag}.rpt" ;    
    my $out_his_file = "${tag}.histogram" ;

    get_outfile($in_his_file,$histo_step,"1","1",$out_his_file);

    foreach my $corner (keys %f1) {
        my @pin_slack_arr ;
    	my $tns = 0; my $vio = 0 ; my $wns = $slack_u;	
    	foreach my $pin ( keys %{$f1{$corner}}) {
		if ( $wns > $f1{$corner}{$pin}) { $wns = $f1{$corner}{$pin};};
		$tns = $tns + $f1{$corner}{$pin};
		$vio++;
		push @pin_slack_arr,$f1{$corner}{$pin};

	}
	#$corner_data{$corner}{summary_string}  = sprintf("%20d    %10.3f    %10.3f   %10.3f   %10.3f   %10.3f  %s",$vio,$tns,$wns,$wns,$corner)
        my $medNS = median(@pin_slack_arr);	
        my $meaNS = average(\@pin_slack_arr);
        my $sigNS = stdev(\@pin_slack_arr);
        $fstat{$corner}{"median"}  = $medNS;
        $fstat{$corner}{"average"} = $meaNS;
        $fstat{$corner}{"sigma"}   = $sigNS;
	$corner_data{$corner}{summary_string}  = sprintf("%20d    %10.3f    %10.3f   %10.3f   %10.3f   %10.3f  %s",$vio,$tns,$wns,$medNS,$meaNS,$sigNS,$corner);

    }	

    foreach my $corner (sort keys %corner_data) {
    	print "$corner_data{$corner}{summary_string}\n";
    }
    print "\n**Info:: Open rca_summary file \n\t$tag.rpt\n\t${tag}_pat.rpt\n\t${tag}_pat_gen_rpt.tcl\n";

# ECO bottle neck section
if ($eco ne "0") {
    print "\n**Info:: Performing ECO Operations for Bottleneck ANALYSIS\n";
    open (out,">${tag}_eco.rpt");
    my $i = 0; 
    my $pdata = sprintf ("%12s %12s %12s %50s %s","#Paths","#TotalCost","WorstCost","#Cell_Net","#Pin_Net");print out "$pdata\n"; 
    foreach my $pin (keys %{$f3{"ALL_CORNERS"}}) {
        my $corner = $f3{"ALL_CORNERS"}{$pin}{"corner"};
        my $wns = $f3{"ALL_CORNERS"}{$pin}{"wns"};
        my $tns = $f3{"ALL_CORNERS"}{$pin}{"tns"};
        my $cns = $f3{"ALL_CORNERS"}{$pin}{"cns"};
    	my $pdata = sprintf ("%12d %12.3f %12.3f %50s %s",$cns,$tns,$wns,$corner,$pin);print out "$pdata\n"; 
	$i++;   if ( $i =~ /0000000$/) { print "      - Processed lines $i\n";};

    }
    print "      - Processed lines $i\n";
    close (out);
}
 


sub average{
        my($data) = @_;
        if (not @$data) {
                return 0
        }
        my $total = 0;
        foreach (@$data) {
                $total += $_;
        }
        my $average = $total / @$data;
        return $average;
}
sub stdev{
        my($data) = @_;
        if(@$data == 1){
                return 0;
        }
        my $average = &average($data);
        my $sqtotal = 0;
        foreach(@$data) {
                $sqtotal += ($average-$_) ** 2;
        }
        my $std = ($sqtotal / (@$data-1)) ** 0.5;
        return $std;
}
sub median {
  my @sorted = sort { $a <=> $b } @_;
  my $med = ($sorted[$#sorted/2 + 0.1] + $sorted[$#sorted/2 + 0.6])/2;
  return $med;
}






sub get_histogram {
    my $file      = $_[0];
    my $step_size = $_[1];
    my $col       = $_[2];
    my $rev_sort  = $_[3];
    my $out       = $_[4];    
    my $precision = length((split(/\./,$step_size))[1]);

    $col--;

    my (%bucket_bins,@bucket, @bucket_neg, $index1, $index2, $num);

    open(IN, $file);
    while (<IN>)
    {
       s/^\s+//; s/\s+$//;
       next if (/^$/ || /^\#/);
       my @line = split (/\s+/, $_);
       my $val = $line[$col];
    
       if ( ! defined $val ) {
           die "File $file does not have column no. $col\n";
       }
    
       if ($val =~ /^-$/ || $val =~ /^INF$/i) {next;}
       
       if ($val >= 0)
       {
          $num = sprintf("%0.${precision}f",$val/$step_size);
          $bucket[$num]++;
       }
       else
       {
          $num = sprintf("%0.${precision}f",abs($val)/$step_size);
	  #print("$num \n");
          $bucket_neg[$num]++;
       }
    }
    close(IN);



    my $cum  = 0 ;
    my %data_out;
    my $i = 0;
    $data_out{head} = sprintf ("%11s : %11s : %10s : %20s\n", "From", "To", "Bin_Count", "Cumulative");
    # negative buckets
    for ($num = $#bucket_neg; $num >= 0; $num--)
    {
       $cum = $cum + $bucket_neg[$num] ;
       $index1 = (-1) * $num * $step_size;
       $index2 = (-1) * ($num + 1) * $step_size;
       $data_out{main}{$i++} = sprintf ("%11.3f : %11.3f : %10d : %20d\n", $index1, $index2, $bucket_neg[$num], $cum);
    }
    # positive buckets
    foreach $num (0 .. $#bucket)
    {
       $cum = $cum + $bucket[$num] ;
       $index1 = $num * $step_size;
       $index2 = ($num + 1) * $step_size;
       $data_out{main}{$i++} = sprintf ("%11.3f : %11.3f : %10d : %20d\n", $index2, $index1, $bucket_neg[$num], $cum);
    }
    return %data_out;
};

sub get_outfile {
    my $file      = $_[0];
    my $step_size = $_[1];
    my $col       = $_[2];
    my $rev_sort  = $_[3];
    my $out       = $_[4];
    my %data_out  = get_histogram($file,$step_size,$col,$rev_sort);
    open (OUT, ">$out");
    printf OUT ($data_out{head});
    if ( $rev_sort eq "1" ) {
	printf("**Info:: Sorting + to -\n");  
        foreach my $index (sort { $b <=> $a } keys %{$data_out{main}}) {
    		printf OUT ($data_out{main}{$index});	
	};
    } else {
	printf("**Info:: Sorting - to +\n");  
        foreach my $index (sort { $a <=> $b } keys %{$data_out{main}}) {
    		printf OUT ($data_out{main}{$index});	
	};

    }
    close (OUT);
};


