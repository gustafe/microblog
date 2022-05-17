#! /usr/bin/env perl
use Modern::Perl '2015';
###
use utf8;
use Path::Tiny;
use open qw/ :std :encoding(utf8) /;
binmode(STDOUT, ':encoding(UTF-8)');
my $RE_DATE_TITLE = qr/^(\d{4}-\d{2}-\d{2})(.*?)\n(.*)/s;
my @dirs = ('/home/gustaf/microblog/Content');
my @files;
for my $d (@dirs) {
    push @files, path($d)->children(qr/\.md|\.txt/);
}
my %dates;
for my $file (@files) {
    my @lines =$file->lines_utf8;
    for my $line (@lines) {
	if ($line =~ $RE_DATE_TITLE) {
	 #   my $title = $2;
	    push @{$dates{$1}}, $2;
	}
    }
}
for my $date (sort {$a cmp $b} keys %dates) {
    if (scalar @{$dates{$date}}>1) {
	say "$date: ", join('|',@{$dates{$date}});
    }
}
