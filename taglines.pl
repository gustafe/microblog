#! /usr/bin/env perl

# significant parts of this code is adapted from John Bokma's
# Tumblelog project, available at
# https://github.com/john-bokma/tumblelog

use Modern::Perl '2015';
use CommonMark qw(:opt :node :event);
use Data::Dump qw/dump/;
use Digest::MD5 qw/md5_hex/;
use Encode;
use FindBin qw/$Bin/;
use JSON::XS;
use List::Util qw/min max/;
use Path::Tiny;
use Template;
use Text::Unidecode;
use Time::HiRes qw/gettimeofday tv_interval/;
use Time::Piece;
use Unicode::Normalize;
use XML::Atom::SimpleFeed;

use utf8;
use open qw/ :std :encoding(utf8) /;
binmode( STDOUT, ":encoding(UTF-8)" );

my $debug = 0;

my %config = ( taglines => './Content/taglines.fortune');

my $taglines = read_entries( $config{taglines} );

my $ast = CommonMark->parse(string=>$taglines->[rand @$taglines],smart=>1);

my $entry = $ast->render_html(OPT_UNSAFE);
$entry =~ s/^\<p\>/\<p class=\"tagline\"\>/;
print $entry;
sub read_entries {

    my $filename = shift;
    my $entries
        = [ grep { length $_ } split /^%\n/m, path($filename)->slurp_utf8() ];

    @$entries or die 'No entries found';

    return $entries;
}
