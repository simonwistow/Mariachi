use strict;
package Mariachi;
use Class::Accessor::Fast;
use Email::Thread;
use Template;
use Time::HiRes qw( gettimeofday tv_interval );
use Data::Dumper qw( Dumper );
use Storable qw( store retrieve );

use base 'Class::Accessor::Fast';

use vars '$VERSION';
$VERSION = 0.1;

__PACKAGE__->mk_accessors( qw( input output messages threader
                               threads_per_page list_title
                               start_time last_time ) );

=head1 NAME

Mariachi - all dancing mail archive generator

=head1 DESCRIPTION

=head1 ACESSORS

=head2 ->input

The source of mail that we're acting on

=head2 ->output

The output directory

=head2 ->messages

The current set of messages

=head2 ->threader

An Email::Thread instance of the threaded C<messages>

=head2 ->threads_per_page

How many top level threads to put on a thread index page.  Used by
C<generate>

=head2 ->list_title

The name of this list.  Used by C<generate>

=head2 ->start_time
=head2 ->last_time

Used interannly by the C<_bench> method


=head1 METHODS

All of these are instance methods, unless stated.

=head2 ->new( %initial_values )

your general class-method constructor

=cut

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

    printf "%-50s %.3f elapsed %.3f total\n",
      $message, tv_interval( $last, $now ), tv_interval( $start, $now );

    $self->last_time($now);
}

=head2 ->load

populate C<messages> from C<input>

=cut

sub load {
    my $self = shift;

    my $folder = Mariachi::Folder->new( $self->input )
      or die "Unable to open ".$self->input;

    $| = 1;
    my $cache;
    $cache = $self->input.".cache" if $ENV{M_CACHE};
    if ($cache && -e $cache) {
        print "pulling in $cache\n";
        $self->messages( retrieve( $cache ) );
        return;
    }

    my $count = 0;
    my @msgs;
    while (my $msg = $folder->next_message) {
        push @msgs, $msg;
        print STDERR "\r$count messages" if ++$count % 100 == 0;
    }
    print STDERR "\n";

    if ($cache) {
        print "caching\n";
        store( \@msgs, $cache );
    }

    $self->messages( \@msgs );
}

=head2 ->dedupe

remove duplicates from C<messages>

=cut

sub dedupe {
    my $self = shift;

    my %seen;
    my @new;
    for my $mail (@{ $self->messages }) {
        my $msgid = $mail->header('message-id');
        if ($seen{$msgid}++) {
            warn "dropping duplicate: $msgid\n";
            next;
        }
        push @new, $mail;
    }
    $self->messages(\@new);
}

=head2 ->sanitise

some messages have been near mail2news gateways, which means that some
message ids in the C<references> and C<in-reply-to> headers get munged
like so: <$group/$message_id>

fix this in C<messages>

=cut

sub sanitise {
    my $self = shift;

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

=head2 ->thread

populate C<threader> with an Email::Thread object created from
C<messages>

=cut

sub thread {
    my $self = shift;

    #$Mail::Thread::nosubject = 1;
    #$Mail::Thread::noprune = 1;
    my $threader = Email::Thread->new( @{ $self->messages } );
    $self->threader($threader);
    $threader->thread;
}

=head2 ->order

order C<threaders> containers by date

=cut

sub order {
    my $self = shift;

    $_->order_children( sub {
                            sort {
                                $a->topmost->message->epoch_date <=>
                                $b->topmost->message->epoch_date
                            } @_
                        }) for $self->threader->rootset;
}

=head2 ->sanity

(in)sanity test - check everything in C<messages> is reachable when
walking C<threader>

=cut

sub sanity {
    my $self = shift;

    my %mails = map { $_ => 1 } @{ $self->messages };
    my $count;
    my $check = sub {
        my $mail = $_[0]->message or return;
        ++$count;
        print STDERR "\rverify $count";
        delete $mails{ $mail || '' };
    };
    $_->iterate_down( $check ) for $self->threader->rootset;
    print "\n";
    undef $check;

    return unless %mails;
    my $sub = sub {
        my ($cont, $depth) = @_;
        print "  " x $depth, $cont->messageid, "\n";
        print "yeep\n" if $mails{$cont->message || ''};
    };
    $_->iterate_down( $sub )
      for $self->threader->rootset;
    undef $sub;
    die "Didn't see ".(scalar keys %mails)." messages";
}

=head2 ->strand

run a strand through all C<messages> - wander over C<threader> setting
the Message ->next and ->prev links

=cut

sub strand {
    my $self = shift;

    my $prev;
    for my $root ($self->threader->rootset) {
        my $sub = sub {
            my $mail = $_[0]->message or return;
            $prev->next($mail) if $prev;
            $mail->prev($prev);
            $mail->root($root);
            $prev = $mail;
        };

        $root->iterate_down( $sub );
        undef $sub;
    }
}

=head2 ->split_deep

wander over C<threader> reparenting subthreads that are
considered too deep

=cut

sub split_deep {
    my $self = shift;

    my @toodeep;
    for my $root ($self->threader->rootset) {
        my $sub = sub {
            my ($cont, $depth) = @_;

            # only note first entries
            if ($depth && ($depth % 14 == 0)
                && $cont->parent->child == $cont) {
                push @toodeep, $cont;
            }
        };

        $root->iterate_down( $sub );
        undef $sub;
    }

    for (@toodeep) {
        print "stranding ", $_->messageid, "\n";

        # the top one needs to be empty, because we're cheating.
        # to keep references straight, we'll move its content
        my $top = $_->topmost;
        my $root = $top->message->root or die "batshit!";
        if ($root->message) {
            my $new = Mail::Thread::Container->new($root->messageid);
            $root->messageid('dummy');
            $new->message($root->message);
            $root->message(undef);
            $new->child($root->child);
            $root->child($new);
            $root = $new;
        }
        $root->add_child( $_ );
    }
}

=head2 ->generate

render thread tree into the directory of C<output>

=cut

sub generate {
    my $self = shift;

    my $tt = Template->new( INCLUDE_PATH => 'templates', RECURSION => 1 );

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
                my $c = shift or return;

                if (my $mail = $c->message) {
                    # let the message know where it's linked from, and
                    # what it's linked to
                    $mail->index($index_file);

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
            };
            $root->iterate_down($sub);
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
        print STDERR "\rindex $page";
    }
    print STDERR "\n";
    $self->_bench("thread indexes");

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
    $self->_bench("date indexes");

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
    $self->_bench("message bodies");
}

=head2 ->perform

do all the right steps

=cut

sub perform {
    my $self = shift;

    $self->_bench("reticulating splines");
    $self->load;            $self->_bench("load ".scalar @{ $self->messages });
    $self->dedupe;          $self->_bench("dedupe");
    #$self->sanitise;        $self->_bench("sanitise");
    $self->thread;          $self->_bench("thread");
    $self->sanity;          $self->_bench("sanity");
    $self->order;           $self->_bench("order");
    $self->sanity;          $self->_bench("sanity");
    $self->strand;          $self->_bench("strand");
    $self->split_deep;      $self->_bench("deep threads split up");
    $self->sanity;          $self->_bench("sanity");
    $self->generate;        $self->_bench("generate");
}


package Mariachi::Folder;
use Mariachi::Message;
use Email::Folder;
use base 'Email::Folder';

sub bless_message { Mariachi::Message->new($_[1]) }

1;
