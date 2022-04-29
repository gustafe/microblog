#! /usr/bin/env perl
# significant parts of this code is adapted from John Bokma's Tumblelog project, available at https://github.com/john-bokma/tumblelog
use Modern::Perl '2015';
use Path::Tiny;
use CommonMark qw(:opt :node :event);
use Data::Dump qw/dump/;
use Template;
use FindBin qw/$Bin/;
use Time::Piece;
use List::Util qw/min max/;
use utf8;
use open qw/ :std :encoding(utf8) /;
#binmode STDOUT, ':utf8';
binmode(STDOUT, ":encoding(UTF-8)");
my $debug =1;
my $days_to_show = 17;

my $RE_DATE_TITLE    = qr/^(\d{4}-\d{2}-\d{2})(.*?)\n(.*)/s;
my $RE_AT_PAGE_TITLE =
    qr/^@([a-z0-9_-]+)\[(.+)\]\s+(\d{4}-\d{2}-\d{2})(!?)(.*?)\n(.*)/s;

my $filename = shift @ARGV;
die "usage: $0 <filename with entries>" unless defined $filename;

my %config = ( filename => $filename );
$config{output_path}='/home/gustaf/public_html/m';
$config{blog_name}='μblog';
my ( $days, $pages ) = collect_days_and_pages ( read_entries($config{filename}));


convert_articles_to_html( $days );
my $frontpage;
my $archive;
my $archive_footer;
my $count = 0;
for my $day (@$days) {
    my $time = Time::Piece->strptime($day->{date}, "%Y-%m-%d");
    if ($count <$days_to_show) {
	push @$frontpage, $day;
    }
    push @{$archive->{$time->year}{$time->mon}}, $day;
    $archive_footer->{$time->year}{$time->mon}++;
    
    $count++;
}
#dump $archive_footer;
my $tt = Template->new({INCLUDE_PATH=>"$Bin/templates", ENCODING=>'UTF-8' });

my %data = (meta=>{title=>$config{blog_name}},
	    days=>$frontpage,
	   archive_footer=>$archive_footer);

$tt->process( 'microblog.tt', \%data, $config{output_path}.'/index.html',{binmode=>':utf8'}) || die $tt->error;

# archives

for my $year (min(keys %$archive) .. max(keys %$archive )) {
    for my $mon (1 .. 12) {
	if ($archive->{$year}{$mon}) {
#	    say "generating for $year $mon...";
	    %data = ( meta => {title => sprintf("%s - archive for %04d-%02d",$config{blog_name},$year ,$mon)},
		      days => $archive->{$year}{$mon},
		    archive_footer=>$archive_footer);
	    $tt->process('microblog.tt', \%data, sprintf("%s/%04d-%02d.html",$config{output_path}, $year, $mon), {binmode=>':utf8'}) || die $tt->error;
	}
    }
}

### SUBS

sub rewrite_ast {

    # Rewrite an image at the start of a paragraph followed by some text
    # to an image with a figcaption inside a figure element

    my $ast = shift;

    my @nodes;
    my $it = $ast->iterator;
    while ( my ( $ev_type, $node ) = $it->next() ) {
        if ( $node->get_type() == NODE_PARAGRAPH && $ev_type == EVENT_EXIT ) {
            my $child = $node->first_child();
            next unless defined $child && $child->get_type() == NODE_IMAGE;
            next if $node->last_child() == $child;

            my $sibling = $child->next();
            if ( $sibling->get_type() == NODE_SOFTBREAK ) {
                # remove this sibling
                $sibling->unlink();
            }

            my $figcaption = CommonMark->create_custom_block(
                on_enter => '<figcaption>',
                on_exit  => '</figcaption>',
            );

            $sibling = $child->next();
            while ( $sibling ) {
                my $next = $sibling->next();
                $figcaption->append_child($sibling);
                $sibling = $next;
            }
            my $figure = CommonMark->create_custom_block(
                on_enter => '<figure>',
                on_exit  => '</figure>',
                children => [$child, $figcaption], # append_child unlinks for us
            );

            $node->replace( $figure );
            push @nodes, $node;
        }
    }

    return \@nodes;
}

sub convert_articles_to_html {

    my $items = shift;
    for my $item ( @$items ) {
        my @articles;
        for my $article ( @{ $item->{ articles } } ) {
            my $ast = CommonMark->parse_document( $article );
            my $nodes = rewrite_ast( $ast );
            my $html = qq(<article>\n)
                . $ast->render_html( OPT_UNSAFE )  # support (inline) HTML
                . "</article>\n";
            push @articles, { html => $html };
        }
        $item->{ articles } = \@articles;
    }
    return;
}


sub strip {

    my $str = shift;
    $str =~ s/^\s+//;
    $str =~ s/\s+$//;
    return $str;
}

sub collect_days_and_pages {

    my $entries = shift;

    my @days;
    my @pages;
    my $state = 'unknown';
 ENTRY:
    for my $entry ( @$entries ) {
        if ($entry =~ $RE_DATE_TITLE ) {
            my $title = strip( $2 );
            $title ne '' or die "A day must have a title ($1)\n";
            push @days, {
                date     => $1,
                title    => $title,
                articles => [ $3 ],
            };
            $state = 'date-title';
            next ENTRY;
        }
        if ( $entry =~ $RE_AT_PAGE_TITLE ) {
            my $title = strip( $5 );
            $title ne '' or die "A page must have a title (\@$1)\n";
            push @pages, {
                name        => $1,
                label       => strip($2),
                date        => $3,
                'show-date' => $4 eq '!',
                title       => $title,
                articles    => [ $6 ],
            };
            $state = 'at-page-title';
            next ENTRY;
        }

        if ( $state eq 'date-title' ) {
            push @{ $days[ -1 ]{ articles } }, $entry;
            next ENTRY;
        }

        if ( $state eq 'at-page-title' ) {
            push @{ $pages[ -1]{ articles } }, $entry;
            next ENTRY;
        };

        die 'No date or page specified for first tumblelog entry';
    }

    @days  = sort { $b->{ date } cmp $a->{ date } } @days;
    @pages = sort { $b->{ date } cmp $a->{ date } } @pages;

    return ( \@days, \@pages );
}


sub read_entries {

    my $filename = shift;
    my $entries = [ grep { length $_ } split /^%\n/m,
                    path( $filename )->slurp_utf8() ];

    @$entries or die 'No entries found';

    return $entries;
}
