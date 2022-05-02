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
use JSON::XS;
use Encode;
use XML::Atom::Feed;
use XML::Atom::Entry;
use utf8;
use open qw/ :std :encoding(utf8) /;

#binmode STDOUT, ':utf8';
binmode( STDOUT, ":encoding(UTF-8)" );
my $debug         = 0;
my $days_to_show  = 17;
my $now           = gmtime;
my $RE_DATE_TITLE = qr/^(\d{4}-\d{2}-\d{2})(.*?)\n(.*)/s;
my $RE_AT_PAGE_TITLE
    = qr/^@([a-z0-9_-]+)\[(.+)\]\s+(\d{4}-\d{2}-\d{2})(!?)(.*?)\n(.*)/s;

my $filename = shift @ARGV;
die "usage: $0 <filename with entries>" unless defined $filename;

my %config = ( filename => $filename, blog_name => 'µblog' );
$config{output_path} = '/home/gustaf/public_html/m';
$config{blog_url}    = 'https://gerikson.com/m/';
$config{blog_author} = 'Gustaf Erikson';

my ( $days, $pages )
    = collect_days_and_pages( read_entries( $config{filename} ) );

convert_articles_to_html($days);
convert_articles_to_html($pages);

my $frontpage;
my $archive;
my $archive_footer;
my $count = 0;
for my $day (@$days) {
    my $time = Time::Piece->strptime( $day->{date}, "%Y-%m-%d" );
    if ( $count < $days_to_show ) {
        push @$frontpage, $day;
    }
    push @{ $archive->{ $time->year }{ $time->mon } }, $day;
    $archive_footer->{ $time->year }{ $time->mon }++;

    $count++;
}
#create_pages( $pages );
#dump $pages;
my $tt = Template->new(
    { INCLUDE_PATH => "$Bin/templates", ENCODING => 'UTF-8' } );

my %data = (
    meta => {
        title  => $config{blog_name},
        author => $config{blog_author},
        site   => $config{blog_url},
        now    => $now->datetime . '+00:00',
    },
    days           => $frontpage,
    archive_footer => $archive_footer,
);

render_page( 'microblog.tt', \%data, $config{output_path}.'/index.html');

#$tt->process(    'microblog.tt', \%data,    $config{output_path} . '/index.html',    { binmode => ':utf8' }) || die $tt->error;

# JSON feed

my $json_feed = {
    version       => "https://jsonfeed.org/version/1.1",
    title         => $config{blog_name},
    home_page_url => $config{blog_url},
    feed_url      => $config{blog_url} . 'feed.json',
    authors       => [
        {   name => $config{blog_author},
            url  => $config{blog_url},
        }
    ]
};

# Atom

my $atom_feed = XML::Atom::Feed->new();
$atom_feed->title( $config{blog_name} );
$atom_feed->id('tag:gerikson.com/m,2022:feed-id');

for my $day ( @{$frontpage} ) {
    my $td = Time::Piece->strptime( $day->{date}, "%Y-%m-%d" );
    for my $art ( @{ $day->{articles} } ) {
        push @{ $json_feed->{items} },
            {
            id  => $art->{id},
            url => $config{blog_url}
                . sprintf(
                '%04d/%02d/index.html#%s',
                $td->year, $td->mon, $art->{id}
                ),
            content_html => $art->{html},
            date_published =>
                sprintf( '%sT%02d:%02d:%02d+00:00', $day->{date}, $td->year%24, $td->mon%60, $td->mday%60 ),
            };
        my $entry = XML::Atom::Entry->new();
        $entry->content( $art->{html} );
        $atom_feed->add_entry($entry);
    }
}

my $feed_json = encode_json($json_feed);
utf8::decode($feed_json);
render_page('feed.tt', {content=>$feed_json}, $config{output_path}.'/feed.json');
#$tt->process(    'feed.tt',    { content => $feed_json },    $config{output_path} . '/feed.json',    { binmode => ':utf8' }) || die $tt->error;
my $xml = $atom_feed->as_xml;
utf8::decode($xml);
render_page('feed.tt', {content=>$xml}, $config{output_path}.'/feed.atom');
#$tt->process(    'feed.tt',    { content => $xml },    $config{output_path} . '/feed.atom',    { binmode => ':utf8' }) || die $tt->error;

exit 0 if $debug;

# archives

for my $year ( min( keys %$archive ) .. max( keys %$archive ) ) {
    for my $mon ( 1 .. 12 ) {
        if ( $archive->{$year}{$mon} ) {

            #	    say "generating for $year $mon...";
            $data{meta}{title} = sprintf( "%s - archive for %04d-%02d",
                $config{blog_name}, $year, $mon );
            $data{days} = $archive->{$year}{$mon};
	    render_page('microblog.tt', \%data, sprintf( "%s/%04d/%02d/index.html",
				   $config{output_path}, $year, $mon ));
        }
    }
}

### pages

if (@$pages) {
    for my $page (@$pages ) {
	$data{meta}{title} = sprintf("%s - %s", $config{blog_name}, $page->{title});
	$data{articles} = $page->{articles};
	render_page('page.tt',\%data, sprintf("%s/%s.html", $config{output_path}, $page->{name}));
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
            while ($sibling) {
                my $next = $sibling->next();
                $figcaption->append_child($sibling);
                $sibling = $next;
            }
            my $figure = CommonMark->create_custom_block(
                on_enter => '<figure>',
                on_exit  => '</figure>',
                children => [ $child, $figcaption ]
                ,    # append_child unlinks for us
            );

            $node->replace($figure);
            push @nodes, $node;
        }
    }

    return \@nodes;
}

sub convert_articles_to_html {

    my $items = shift;
    for my $item (@$items) {
        my @articles;
        my $seq = 1;
        for my $article ( @{ $item->{articles} } ) {
            my $ast   = CommonMark->parse_document($article);
            my $nodes = rewrite_ast($ast);
            my $html  = $ast->render_html(OPT_UNSAFE);    # support (inline) HTML
            push @articles,
                {
                html => $html,
                id   => $item->{date} . sprintf( "_%02d", $seq )
                };
            $seq++;
        }
        $item->{articles} = \@articles;
    }
    return;
}

sub strip {

    my $str = shift;
    $str =~ s/^\s+//;
    $str =~ s/\s+$//;
    return $str;
}
sub escape {

    my $str = shift;

    for ( $str ) {
        s/&/&amp;/g;
        s/</&lt;/g;
        s/>/&gt;/g;
        s/"/&quot;/g;
        s/'/&#x27;/g;
    }
    return $str;
}

sub collect_days_and_pages {

    my $entries = shift;

    my @days;
    my @pages;
    my $state = 'unknown';
ENTRY:
    for my $entry (@$entries) {
        if ( $entry =~ $RE_DATE_TITLE ) {
            my $title = strip($2);
            $title ne '' or die "A day must have a title ($1)\n";
            push @days,
                {
                date     => $1,
                title    => $title,
                articles => [$3],
                };
            $state = 'date-title';
            next ENTRY;
        }
        if ( $entry =~ $RE_AT_PAGE_TITLE ) {
            my $title = strip($5);
            $title ne '' or die "A page must have a title (\@$1)\n";
            push @pages,
                {
                name        => $1,
                label       => strip($2),
                date        => $3,
                'show-date' => $4 eq '!',
                title       => $title,
                articles    => [$6],
                };
            $state = 'at-page-title';
            next ENTRY;
        }

        if ( $state eq 'date-title' ) {
            push @{ $days[-1]{articles} }, $entry;
            next ENTRY;
        }

        if ( $state eq 'at-page-title' ) {
            push @{ $pages[-1]{articles} }, $entry;
            next ENTRY;
        }

        die 'No date or page specified for first tumblelog entry';
    }

    @days  = sort { $b->{date} cmp $a->{date} } @days;
    @pages = sort { $b->{date} cmp $a->{date} } @pages;

    return ( \@days, \@pages );
}

sub read_entries {

    my $filename = shift;
    my $entries
        = [ grep { length $_ } split /^%\n/m, path($filename)->slurp_utf8() ];

    @$entries or die 'No entries found';

    return $entries;
}

sub render_page {
    my ($template, $payload, $output ) = @_;
    $tt->process($template, $payload, $output, { binmode=>':utf8' }) || die $tt->error;
}
