use strict;
package Mariachi;
use Class::Accessor::Fast;
use Email::Thread;
use Mariachi::Folder;
use Template;
use Date::Parse qw(str2time);
use Time::HiRes qw( gettimeofday tv_interval );
use Data::Dumper;
use base 'Class::Accessor::Fast';

use vars '$VERSION';
$VERSION = 0.1;

__PACKAGE__->mk_accessors( qw( messages threader input output threads_per_page ) );

sub new {
    my $class = shift;
    $class->SUPER::new({@_});
}

sub load_messages {
    my $self = shift;

    my $folder = Mariachi::Folder->new( $self->input )
      or die "Unable to open ".$self->input;

    $self->messages( [ @{ $self->messages || [] }, $folder->messages ] );
}

sub sanitise_messages {
    my $self = shift;

    # some messages have been near mail2news gateways, which means that
    # some message ids get munged like so: <$group/$message_id>
    for my $mail (@{ $self->messages }) {
        for (qw( references in_reply_to )) {
            my $hdr = $mail->$_() or next;
            my $before = $hdr;
            $hdr =~ s{<[^>]*?/}{<}g or next;
            #print "$_ $before$_: $hdr";
            $mail->$_($hdr);
        }
    }
}

sub thread {
    my $self = shift;

    my $threader = Email::Thread->new( @{ $self->messages } );
    $self->threader($threader);
    $threader->thread;

    my %date;
    $threader->order( sub {
                          # cache the dates
                          $date{$_} = str2time $_->topmost->message->date
                            for @_;
                          sort { $date{$a} <=> $date{$b} } @_;
                      } );

    # (in)sanity test
    if (1) {
        my %mails = map { $_ => 1 } @{ $self->messages };
        $_->recurse_down( sub { delete $mails{ $_[0]->message || '' } } )
          for $threader->rootset;
        die "Didn't see ".Dumper [ keys %mails ]
          if %mails;
    }
}

sub generate {
    my $self = shift;

    my $tt = Template->new( INCLUDE_PATH => 'templates', RECURSION => 1 );

    my $page = 0;
    my @threads = $self->threader->rootset;
    my $pages = int(scalar(@threads)/$self->threads_per_page);
    while (scalar(@threads)) {
        warn "Index page ".($page+1)."\n";
        my @page = splice(@threads, 0, $self->threads_per_page);
        $tt->process('index.tt2',
                     { threads => \@page,
                       page => $page,
                       pages => $pages,
                     },
                     $self->output . ($page ? "/index_$page.html" : "/index.html") )
            or die $tt->error;
        $page++;
    }
    # tt (in) sanity test
    if (1) {
        my @unwalked = grep { $_->walkedover != 1 } @{ $self->messages };
        my @ids = map { [ $_->header('message-id'), $_->from, $_->subject, $_->walkedover ] } @unwalked;
        die "Stange walk for ".(Dumper \@ids) . @ids . " messages"
          if @ids;
    }

    warn "Message pages\n";
    for my $mail (@{ $self->messages }) {
        $tt->process('message.tt2',
                     { thread  => $self->_find_root_thread($mail),
                       message => $mail,
                       headers => [ 'Subject', 'Date' ],
                     },
                     $self->output."/".$mail->filename) or die $tt->error;
    }
}


sub perform {
    my $self = shift;

    my $start = [gettimeofday];

    $self->load_messages;
    $self->sanitise_messages;

    print scalar @{ $self->messages }, " messages loaded in ",
      tv_interval( $start )," seconds\n";
    $start = [gettimeofday];

    $self->thread;

    print "and threaded in ", tv_interval( $start ), " seconds\n";
    $start = [gettimeofday];

    $self->generate;

    print "output generation took ", tv_interval( $start ), " seconds\n";
}


# given a message, find the root of the thread that it's in
sub _find_root_thread {
    my $self = shift;
    my $mail = shift;
    my $id   = $self->threader->_msgid($mail);
    for my $cont ($self->threader->rootset) {
        my $in;
        $cont->recurse_down( sub { $_[0]->messageid eq $id and $in = 1 } );
        return $cont if $in;
    }
}

1;
