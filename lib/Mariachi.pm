use strict;
package Mariachi;
use Class::Accessor::Fast;
use Email::Thread;
use Template;
use Time::HiRes qw( gettimeofday tv_interval );
use Data::Dumper;
use base 'Class::Accessor::Fast';

use vars '$VERSION';
$VERSION = 0.1;

__PACKAGE__->mk_accessors( qw( messages threader input output
                               threads_per_page list_title
                               start_time last_time ) );

# $before, $after should map to
# sub recursive_walk {
#    my $self = shift;
#    $before->($self);
#    $self->child->recursive_walk if $self->child;
#    $self->next->recursive_walk if $self->next;
#    $after->($self);
# }

sub iterative_walk_down {
    my $self = shift;
    my ($before, $after) = @_;

    my $next;
    my $depth = 0;
    my %seen;
    for (my $walk = $self; $walk; $walk = $next) {
        $before->($walk, $depth) if $before;

        # spot/break loops
        $seen{$walk}++;
        $walk->child(undef) if $seen{ $walk->child || '' };
        $walk->next(undef)  if $seen{ $walk->next  || '' };

        # go down, or across
        if ($walk->child) { $next = $walk->child; ++$depth }
        else              { $next = $walk->next }

        # no next?  wander back up
        if (!$next) {
            while ($depth) {
                $next = $walk->parent->next;
                $after->($walk, $depth) if $after;
                --$depth;
                last if $next;
            }
        }
    }
    $after->($self, 0) if $after;
}

sub new {
    my $class = shift;
    $class->SUPER::new({@_});
}

sub _bench {
    my $self = shift;
    my $message = shift;

    my $now = [gettimeofday];
    my $start = $self->start_time;
    my $last  = $self->last_time || $now;
    $start = $self->start_time($now) unless $start;

    printf "%-20s elapsed %.3f total %.3f\n",
      $message, tv_interval( $last, $now ), tv_interval( $start, $now );

    $self->last_time($now);
}

sub load_messages {
    my $self = shift;

    my $folder = Mariachi::Folder->new( $self->input )
      or die "Unable to open ".$self->input;

    $| = 1;
    my $count = 0;
    my @msgs;
    while (my $msg = $folder->next_message) {
        push @msgs, $msg;

        print "\r$count messages" if ++$count % 100 == 0;
    }
    print "\n";
    $self->messages( \@msgs );
}

sub sanitise_messages {
    my $self = shift;

    # some messages have been near mail2news gateways, which means that
    # some message ids get munged like so: <$group/$message_id>
    for my $mail (@{ $self->messages }) {
        for (qw( references in_reply_to )) {
            my $hdr = $mail->header($_) or next;
            my $before = $hdr;
            $hdr =~ s{<[^>]*?/}{<}g or next;
            #print "$_ $before$_: $hdr";
            $mail->header_set($_, $hdr);
        }
    }
}

sub thread {
    my $self = shift;

    $Mail::Thread::nosubject = 1;
    my $threader = Email::Thread->new( @{ $self->messages } );
    $self->threader($threader);
    $threader->thread;
}

sub order {
    my $self = shift;

    $_->order_children( sub {
                            sort {
                                $a->topmost->message->epoch_date <=>
                                $b->topmost->message->epoch_date
                            } @_
                        }) for $self->threader->rootset;
}

sub thread_check {
    my $self = shift;

    # (in)sanity test - is everything in the original mbox in the
    # thread tree?
    my %mails = map { $_ => 1 } @{ $self->messages };
    $_->recurse_down( sub { delete $mails{ $_[0]->message || '' } } )
      for $self->threader->rootset;
    die "Didn't see ".Dumper [ keys %mails ]
      if %mails;
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
    my %touched_dates;
    my %dates;
    my $prev;
    while (@threads) {
        # @chunk is the chunk of threads on this page
        my @chunk = splice @threads, 0, $self->threads_per_page;
        my $index_file = $page ? "index_$page.html" : "index.html";
        for my $root (@chunk) {
            my $sub;
            $sub = sub {
                my $c = shift;

                if (my $mail = $c->message) {
                    # let the message know where it's linked from, and
                    # what it's linked to
                    $mail->index($index_file);
                    $mail->prev($prev);
                    $prev->next($mail) if $prev;
                    $prev = $mail;

                    # and mark the thread dirty, if the message is new
                    unless (-e $self->output."/".$mail->filename) {
                        $touched_threads{ $root } = $root;
                        # dirty up the date indexes
                        $touched_dates{ $mail->year } = 1;
                        $touched_dates{ $mail->month } = 1;
                        $touched_dates{ $mail->day } = 1;
                    }

                    # add things to the date indexes
                    push @{ $dates{ $mail->year } }, $mail;
                    push @{ $dates{ $mail->month } }, $mail;
                    push @{ $dates{ $mail->day } }, $mail;
                }
                $sub->($c->child) if $c->child;
                $sub->($c->next)  if $c->next;
            };
            $sub->($root);
            undef $sub; # since we closed over ourself, we'll have to
                        # be specific
        }

        $tt->process('index.tt2',
                     { threads => \@chunk,
                       page => $page,
                       pages => $pages,
                       list_title => $self->list_title,
                     },
                     $self->output . "/$index_file" )
          or die $tt->error;
        $page++;
    }

    for ( keys %touched_dates ) {
        my @mails = sort {
            $a->epoch_date <=> $b->epoch_date
        } @{ $dates{$_} };

        # TODO paginate these too
        my @depth = split m!/!;
        $tt->process('date.tt2',
                     { archive_date => $_,
                       mails        => \@mails,
                       base         => "../" x @depth,
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
        undef $sub;
    }
}


sub perform {
    my $self = shift;

    $self->_bench("startup");

    $self->load_messages;
    $self->_bench("load");
    $self->sanitise_messages;
    $self->_bench("sanitise");

    $self->thread;
    $self->_bench("thread");

    iterative_walk_down($_, sub {
                            my ($c, $depth) = @_;
                            print " " x $depth;
                            print "$c before\n";
                        },
                        sub {
                            my ($c, $depth) = @_;
                            print " " x $depth;
                            print "$c after\n";
                        },
                       ) for $self->threader->rootset;
    $self->order;
    $self->_bench("order");
    #$self->thread_check;
    #$self->_bench("sanity");

    $self->generate;
    $self->_bench("generate");
}


package Mariachi::Folder;
use Mariachi::Message;
use Email::Folder;
use base 'Email::Folder';

sub bless_message { Mariachi::Message->new($_[1]) }

1;
