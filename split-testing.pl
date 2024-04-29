#! /usr/bin/env perl
use Modern::Perl '2015';
###
use utf8;
use Path::Tiny;
binmode(STDOUT, ':encoding(UTF-8)');

my $file = './test.txt';
my $entries = [grep {length $_} split /^%\n/m, path($file)->slurp_utf8()] ;

for my $entry (@$entries) {
    say ">>>";
    print $entry;
    say "<<<";
      
}
