#!/usr/bin/perl

use 5.010;
use strict;
use warnings;

use File::Slurp::Tiny qw(read_file);
use Perl::Stripper;
use Test::More 0.98;

my $stripper;

$stripper = Perl::Stripper->new;
is($stripper->strip(~~read_file("t/data/1.pl")),
   ~~read_file("t/data/1.pl-stripped-default"),
   "default");

$stripper = Perl::Stripper->new(strip_log=>1);
is($stripper->strip(~~read_file("t/data/1.pl")),
   ~~read_file("t/data/1.pl-stripped-strip_log"),
   "strip_log");

done_testing;
