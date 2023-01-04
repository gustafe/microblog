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

my $start_time = [gettimeofday];

my $debug = 0;

my $days_to_show  = 10;
my $now           = gmtime;
my $RE_DATE_TITLE = qr/^(\d{4}-\d{2}-\d{2})(.*?)\n(.*)/s;
my $RE_AT_PAGE_TITLE
    = qr/^@([a-z0-9_-]+)\[(.+)\]\s+(\d{4}-\d{2}-\d{2})(!?)(.*?)\n(.*)/s;

my $filename = shift @ARGV;
die "usage: $0 <filename with entries>" unless defined $filename;

my %config = ( filename => $filename, blog_name => 'µblog' );
$config{output_path} = '/home/gustaf/public_html/m';
$config{blog_url}    = 'https://gerikson.com/m';
$config{blog_author} = 'Gustaf Erikson';
$config{debug}=0;
# read data from input, and convert to HTML

my ( $days, $pages )
    = collect_days_and_pages( read_entries( $config{filename} ) );

convert_articles_to_html($days);
convert_articles_to_html($pages);

# gather all data into year/month pages, and save the newest ones for the frontpage and feeds

my $frontpage;
my $archive;
my $archive_footer;
my $day_count     = 0;
my $article_count = 0;
for my $day (@$days) {
    my $time = Time::Piece->strptime( $day->{date}, "%Y-%m-%d" );
    next if ( $time->ymd gt $now->ymd );
    $day->{year} = $time->year;
    $day->{mon}  = $time->mon;
    $day->{mday} = $time->mday;
    if ( $day_count < $days_to_show ) {
        push @$frontpage, $day;
    }
    push @{ $archive->{ $time->year }{ $time->mon } }, $day;
    $archive_footer->{ $time->year }{ $time->mon } += scalar @{$day->{articles}};
    $article_count += scalar @{ $day->{articles} };
    $day_count++;
}

my %data = (
    meta => {
        author => $config{blog_author},
        site   => $config{blog_url},
        now    => $now->datetime . '+00:00',
    },
    archive_footer => $archive_footer,
    year_range =>
        { min => min( keys %$archive ), max => max( keys %$archive ) },

);

# create feeds, and load them with frontpage data

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

my $atom_feed = XML::Atom::SimpleFeed->new(
    -encoding => 'utf-8',
    title     => $config{blog_name},
    link      => {
        rel  => 'alternate',
        href => $config{blog_url} . 'feed.atom',
        type => 'text/plain'
    },
    updated => $now->datetime . '+00:00',
    id      => 'tag:gerikson.com,2022-05-01:feed-id',
    author  => {
        name => 'Gustaf Erikson',
        url  => 'https://gerikson.com'
    },
);

for my $day ( @{$frontpage} ) {

    for my $art ( @{ $day->{articles} } ) {
        my $url = $config{blog_url}
            . sprintf( '/%04d/%02d/index.html#%s',
            $day->{year}, $day->{mon}, $art->{id} );
        my @post_meta = split( /\_/, $art->{id} );
	my $content = $art->{html};

	# generate a "second" for the timestamp by grabbing the last
	# hex digit from the MD5 hash and modding it by 60
	my $digest_sec = hex(substr(md5_hex(encode_utf8( $content)),-2))%60;
	
        my ( $date_title, $seq ) = ( $post_meta[0], $post_meta[-1] );
        my $publish_date = sprintf(
            '%sT%02d:%02d:%02d+00:00',
            $day->{date},
            $day->{year} % 24,
            ($day->{mon}+$seq) % 60,
            $digest_sec
        );
        push @{ $json_feed->{items} },
            {
            id             => $art->{id},
            url            => $url,
            content_html   => $content,
            date_published => $publish_date,
            };

        $atom_feed->add_entry(
            title => "Entry $seq on $date_title",
            id    => $url,
            link => { rel => 'alternate', href => $url, type => 'text/html' },
            updated => $publish_date,
            content => $content,
        );
    }
}

my $tt = Template->new(
    { INCLUDE_PATH => "$Bin/templates", ENCODING => 'UTF-8' } );

my $feed_json = encode_json($json_feed);
utf8::decode($feed_json);
render_page(
    'feed.tt',
    { content => $feed_json },
    $config{output_path} . '/feed.json'
);
my $xml = $atom_feed->as_string();
utf8::decode($xml);
render_page(
    'feed.tt',
    { content => $xml },
    $config{output_path} . '/feed.atom'
);

exit 0 if $debug;

# create year/month archive pages, and publish them

for my $year ( min( keys %$archive ) .. max( keys %$archive ) ) {
    for my $mon ( 1 .. 12 ) {
        if ( $archive->{$year}{$mon} ) {
            $data{meta}{title} = sprintf( "%s - archive for %04d-%02d",
                $config{blog_name}, $year, $mon );
            $data{days} = $archive->{$year}{$mon};
            render_page(
                'microblog.tt',
                \%data,
                sprintf(
                    "%s/%04d/%02d/index.html",
                    $config{output_path}, $year, $mon
                )
            );
        }
    }
}

### create and publish pages

if (@$pages) {
    for my $page (@$pages) {
        $data{meta}{title}
            = sprintf( "%s - %s", $config{blog_name}, $page->{title} );
        $data{articles} = $page->{articles};
        render_page( 'page.tt', \%data,
            sprintf( "%s/%s.html", $config{output_path}, $page->{name} ) );
    }
}

# create and publish front page (index.html)
$data{meta}->{title} = $config{blog_name};
$data{days} = $frontpage;

$data{meta}->{day_count}     = commify($day_count);
$data{meta}->{article_count} = commify($article_count);
$data{meta}->{rendertime}    = sec_to_hms( tv_interval($start_time) );
render_page( 'microblog.tt', \%data, $config{output_path} . '/index.html' );
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
            my $ast   = CommonMark->parse( string => $article, smart => 1 );
            my $nodes = rewrite_ast($ast);
            my $html = $ast->render_html(OPT_UNSAFE);  # support (inline) HTML
            push @articles, {
                html => $html,

                id => $item->{date}
                    . sprintf( "_%s_%02d",
                    $item->{slug} ? $item->{slug} : 'p', $seq )
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

    for ($str) {
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
	    say $3 if $config{debug};
            push @days,
                {
                date     => $1,
                title    => $title,
                articles => [$3],
                slug     => slugify_unidecode($title),
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

    @days = sort { $b->{date} cmp $a->{date} || $a->{title} cmp $b->{title} }
        @days;
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
    my ( $template, $payload, $output ) = @_;
    $tt->process( $template, $payload, $output, { binmode => ':utf8' } )
        || die $tt->error;
}

sub slugify_unidecode($) {

# https://stackoverflow.com/questions/4009281/how-can-i-generate-url-slugs-in-perl
    my ($input) = @_;
    if ( $input =~ /^tweets/ ) {
        return 'tweets';
    }
    if ( $input =~ /^observations/ ) {
        return 'observations';
    }
    if ( $input =~ /(\S+), \d{2} \S+ \d{4}/ ) {
        return lc($1);
    }
    $input = NFC($input);        # Normalize (recompose) the Unicode string
    $input = unidecode($input)
        ;    # Convert non-ASCII characters to closest equivalents
    $input =~ s/[^\w\s-]//g
        ; # Remove all characters that are not word characters (includes _), spaces, or hyphens
    $input =~ s/^\s+|\s+$//g;    # Trim whitespace from both ends
    $input = lc($input);
    $input =~ s/[-\s]+/_/g
        ; # Replace all occurrences of spaces and hyphens with a single underscore

    return $input;
}

sub sec_to_hms {
    my ($s) = @_;
#    my $milliseconds = ($s - int $s) * 1000;
    return sprintf(
        "%02dh%02dm%02.1fs",
        int( $s / ( 60 * 60 ) ),
        ( $s / 60 ) % 60,
        $s  );
}

sub commify {
    my $text = reverse $_[0];
    $text =~ s/(\d\d\d)(?=\d)(?!\d*\.)/$1;F202x\#\&/g;
    return scalar reverse $text;
}
