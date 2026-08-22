#!/usr/bin/perl
##################################################
# Copyright (c) 2026 Syed Shakir Iqbal (Xwhiteroom)
# SPDX-License-Identifier: MIT
# Author : Syed Shakir Iqbal
# Usage  : For unique line by line diff
##################################################
use strict;
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
            "F1=s"            =>\my $file1,
            "F2=s"            =>\my $file2,
            "o=s"             =>\my $out,
            "R=s"             =>\my $rpat,

            );

GetOptions(%argHash);
## PARSING INPUT ARGUMENTS
if ( !defined $file1 || !defined $file2 ) {
   printf BOLD RED        "\n**ERROR : No files_ speficed !!\n\n";
   printf RESET ""  ;
   print color 'blue';
   print "\n\
          USAGE   : perl $0		 \
                                                 -F1      <File1>\
                                                 -F2      <File2>\
                                                 -o       <out_dir/optional>\
                                                 -R       <0 default, setting to 1 does a grep -f f1 f2>\                                                 

   \n";
   printf RESET ""  ;
   exit;
};
if (!defined $rpat || $rpat eq "") { 
  $rpat = "0";
}


if (!defined $out || $out eq "") { 
    $out = ".";
} else {    
	system ("mkdir -p $out");
    printf "**Info:  Creating output dir $out\n\n";
}


my %f1; my %f2;
    my $i = 0;
    if ( -e $file1) {
        open (in,$file1);
        while(my $line = <in>) { $line =~ s/\n//g; $line =~ s/^\s+//g; $line =~ s/\s+$//g; if ( $line ne "") { $f1{$line} = $line;}; $i++;};
        close (in)
    }   else {
        printf "**Error : File $file1 doesn't exist \n\n";exit;
    }
    printf "**Info:  Found $i lines in file $file1\n\n";
    
    
    $i = 0;
    if ( -e $file2) {
        open (in,$file2);
        while(my $line = <in>) { $line =~ s/\n//g; $line =~ s/^\s+//g; $line =~ s/\s+$//g; if ( $line ne "") { $f2{$line} = $line;}; $i++;};
        close (in)
    }   else {
        printf "**Error : File $file2 doesn't exist \n\n";exit;
    }
    printf "**Info:  Found $i lines in file $file2\n\n"   ;
    my $base_1 = basename($file1);
    my $base_2 = basename($file2);

    open (out1,">$out/extra_points_in_$base_1.txt");
    open (out2,">$out/extra_points_in_$base_2.txt");
    open (out3,">$out/common_points_in_${base_1}-$base_2.txt");
    $i = 0; my $extra_base1 = 0;
    foreach my $key1 (sort keys (%f1)) {      
        if ( $f2{$key1} ne "") {
            printf out3 "$key1\n";
            $i++;
        } else {
            printf out1 "$key1\n";$extra_base1++;
       }
    }
    my  $j = 0;my $extra_base2 = 0;

    foreach my $key2 (sort keys (%f2)) {      
        if ( $f1{$key2} ne "") {
            $j++;
        } else {
            printf out2 "$key2\n"; $extra_base2++;
       }
    }

    my $extra_base3 = 0;
    if ( $rpat eq "1" ) { 
        open (out4,">$out/grep_${base_1}_in_$base_2.txt");
        foreach my $key1 (sort keys (%f1)) {  
            foreach my $key2 (sort keys (%f2)) { 
                if ( $key2 =~ m/$key1/) {
                    printf out4 "$key2\n"; $extra_base3++;
                }
            }
        }

    };
    


    printf "**Info: Found Common points $i <--> $j \n";
    printf ("\t\t Open files :\n\t\t\t\t%6d $out/extra_points_in_$base_1.txt\n\t\t\t\t%6d $out/extra_points_in_$base_2.txt\n\t\t\t\t%6d $out/common_points_in_${base_1}-$base_2.txt\n\n",$extra_base1,$extra_base2,$i);

    
close(out1);
close(out2);
close(out3);

if ( $rpat eq "1" ) {  close(out4)}
    print RESET "\n";
