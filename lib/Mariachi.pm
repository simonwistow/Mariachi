use strict;
package Mariachi;
use Class::Accessor::Fast;
use Email::Thread;
use Mariachi::Folder;
use Template;
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


    my $sub = sub {
        sort {
            $a->topmost->message->epoch_date <=> $b->topmost->message->epoch_date
        } @_;
    };
    $threader->order( $sub );

    # (in)sanity test - is everything in the original mbox in the
    # thread tree?
    if (0) {
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

    # okay, so we want to walk the containers in the following order,
    # so that Message->next and Message->prev are easy to find
    #
    # -- 1
    #    |-- 2
    #    |-- 3
    #    |   \-- 4
    #    |-- 5
    #    \-- 6
    # -- 7
    # I hate ascii art

    # we actually want the root set to be ordered latest first
    my @threads = sort {
        $b->topmost->message->epoch_date <=> $a->topmost->message->epoch_date
    } $self->threader->rootset;
    my $pages = int(scalar(@threads) / $self->threads_per_page);
    my $page = 0;
    my %touched_threads;
    my %date_indexes;
    my $prev;
    while (@threads) {
        # @chunk is the chunk of threads on this page
        my @chunk = splice @threads, 0, $self->threads_per_page;
        my $index_file = $page ? "index_$page.html" : "index.html";
        for my $root (@chunk) {
            my $sub;
            $sub = sub {
                my $c = shift or return;

                if (my $mail = $c->message) {
                    # let the message know where it's linked from, and
                    # what it's linked to

                    $mail->index($index_file);
                    $mail->last($prev);
                    $prev->next($mail) if $prev;
                    $prev = $mail;

                    # and mark the thread dirty, if the message is new
                    $touched_threads{ $root } = $root
                      unless -e $self->output."/".$mail->filename;

                    # And mark date indexes for building
                    my @date = localtime $mail->epoch_date;
                    push @{$date_indexes{sprintf("%04d", $date[5]+1900)}}, $mail;
                    push @{$date_indexes{sprintf("%04d/%02d", $date[5]+1900, $date[4]+1)}}, $mail;
                    push @{$date_indexes{sprintf("%04d/%02d/%02d", $date[5]+1900, $date[4]+1, $date[3])}}, $mail;
                }
                $sub->($c->child);
                $sub->($c->next);
            };
            $sub->($root);
        }

        $tt->process('index.tt2',
                     { threads => \@chunk,
                       page => $page,
                       pages => $pages,
                     },
                     $self->output . "/$index_file" )
          or die $tt->error;
        $page++;
    }


    warn "Date indexes..\n";

    for (keys(%date_indexes)) {
        my @depth = split(m!/!, $_);
        my $depth = scalar(@depth);
        $tt->process('date.tt2',
                     { archive_date => $_,
                       mails => $date_indexes{$_},
                       base => "../" x $depth,
                     },
                     $self->output . "/$_/index.html" )
          or die $tt->error;
    }


    # figure out adjacent dirty threads
    @threads = $self->threader->rootset;
    for my $i (grep { $touched_threads{ $threads[$_] } } 0..$#threads) {
        $touched_threads{ $threads[$i-1] } = $threads[$i-1] if $i > 0;
        $touched_threads{ $threads[$i+1] } = $threads[$i+1] if $i+1 < @threads;
    }

    # and then render all the messages in the dirty threads
    for my $root (values %touched_threads) {
        my $sub = sub {
            my $mail = $_[0]->message or return;

            $tt->process('message.tt2',
                         { base      => '../../../',
                           thread    => $root,
                           message   => $mail,
                           container => $_[0],
                         },
                         $self->output . "/" . $mail->filename)
              or die $tt->error;
        };
        $root->recurse_down( $sub );
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


1;
