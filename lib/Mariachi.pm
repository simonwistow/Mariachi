use strict;
package Mariachi;
use Class::Accessor::Fast;
use Email::Thread;
use Template;
use Time::HiRes qw( gettimeofday tv_interval );
use Data::Dumper qw( Dumper );
use Storable qw( store retrieve );
use List::Util qw( max );

use base 'Class::Accessor::Fast';

use vars '$VERSION';
$VERSION = 0.31;

__PACKAGE__->mk_accessors( qw( input output messages rootset
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

=head2 ->rootset

The rootset of threaded messages

=head2 ->threads_per_page

How many top level threads to put on a thread index page.  Used by
C<generate>

=head2 ->list_title

The name of this list.  Used by C<generate>

=head2 ->start_time

=head2 ->last_time

Used internally by the C<_bench> method


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

    my (%seen, @new, $dropped);
    $dropped = 0;
    for my $mail (@{ $self->messages }) {
        my $msgid = $mail->header('message-id');
        if ($seen{$msgid}++) {
            $dropped++;
            next;
        }
        push @new, $mail;
    }
    print "dropped $dropped duplicate messages\n";
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

populate C<rootset> with an Email::Thread::Containers created from
C<messages>

=cut

# the Fisher-Yates shuffle from perlfaq4
sub _shuffle {
    my $array = shift;
    my $i;
    for ($i = @$array; --$i; ) {
        my $j = int rand ($i+1);
        @$array[$i,$j] = @$array[$j,$i];
    }
}

sub thread {
    my $self = shift;
    #_shuffle $self->messages;
    my $threader = Email::Thread->new( @{ $self->messages } );
    $threader->thread;
    $self->rootset( [ grep { $_->topmost } $threader->rootset ] );
}

=head2 ->order

order C<rootset> by date

=cut

sub order {
    my $self = shift;

    my @rootset = @{ $self->rootset };
    $_->order_children(
        sub {
            sort {
                eval { $a->topmost->message->epoch_date } <=>
                eval { $b->topmost->message->epoch_date }
              } @_
          }) for @rootset;

    # we actually want the root set to be ordered latest first
    @rootset = sort {
        $b->topmost->message->epoch_date <=> $a->topmost->message->epoch_date
    } @rootset;
    $self->rootset( \@rootset );
}

=head2 ->sanity

(in)sanity test - check everything in C<messages> is reachable when
walking C<rootset>

=cut

sub sanity {
    my $self = shift;

    my %mails = map { $_ => $_ } @{ $self->messages };
    my $count;
    my $check = sub {
        my $cont = shift or return;
        my $mail = $cont->message or return;
        ++$count;
        #print STDERR "\rverify $count";
        delete $mails{ $mail || '' };
    };
    $_->iterate_down( $check ) for @{ $self->rootset };
    undef $check;
    #print STDERR "\n";

    return unless %mails;
    die "\nDidn't see ".(scalar keys %mails)." messages";
    print join "\n", map {
        my @ancestors;
        my $x = $_->container;
        my %seen;
        my $last;
        while ($x) {
            if ($seen{$x}++) { push @ancestors, "$x ancestor loop!\n"; last }
            my $extra = $x->{id};
            $extra .= " one-way"
              if $last && !grep { $last == $_ } $x->children;
            push @ancestors, $x." $extra";
            $last = $x;
            $x = $x->parent;
        }
        $_->header("message-id"), @ancestors
    } values %mails;

}

=head2 ->time_thread

return a new structure, like the time-based threading of Lurker

=cut

# identify the co-ordinates of something
sub _cell {
    my $cells = shift;
    my $find = shift;
    for (my $y = 0; $y < @$cells; ++$y) {
        for (my $x = 0; $x < @{ $cells->[$y] }; ++$x) {
            my $here = $cells->[$y][$x];
            return [$y, $x] if ref $here && $here == $find;
        }
    }
    return;
}

sub _draw_cells {
    my $cells = shift;
    # and again in their new state
    for my $row (@$cells) {
        my $this;
        for (@$row) {
            $this = $_ if ref $_;
            print ref $_ ? '*' : $_ ? $_ : ' ';
        }
        print "\t", $this->messageid, "\n";
    }
    print "\n";
}

sub time_thread {
    my $self = shift;

    my @results;
    for my $thread (@{ $self->rootset }) {
        # show them in th old order, and take a copy of the messages
        # while we're at it
        my @messages;
        $thread->iterate_down(
            sub {
                my ($c, $d) = @_;
                print '  ' x $d, $c->messageid, "\n" if 0;
                push @messages, $c if $c->message;
            } );

        # cells is the 2-d representation, row, col.  the first
        # message will be at [0][0], it's first reply, [0][1]
        my @cells;

        # okay, wander them in date order
        @messages = sort { $a->message->epoch_date <=>
                           $b->message->epoch_date } @messages;
        ROW: for (my $row = 0; $row < @messages; ++$row) {
            my $c = $messages[$row];
            # and place them in cells

            # the first one - [0][0]
            unless (@cells) {
                $cells[$row][0] = $c;
                next;
            }

            # look up our parent
            my $first_parent = $c->parent;
            while ($first_parent && !$first_parent->message) {
                $first_parent = $first_parent->parent;
            }

            unless ($first_parent && $first_parent->message &&
                      _cell(\@cells, $first_parent) ) {
                # just drop it randomly to one side, since it doesn't
                # have a clearly identifiable parent
                my $col = (max map { scalar @$_ } @cells );
                $cells[$row][$col] = $c;
                next ROW;
            }
            my $col;
            my ($parent_row, $parent_col) = @{ _cell( \@cells, $first_parent ) };
            if ($first_parent->child == $c) {
                # if we're the first child, then we directly beneath
                # them
                $col = $parent_col;
            }
            else {
                # otherwise, we have to shuffle accross into the first
                # free column, but we have to not cross the streams.
                # if given this tree:
                # a + +
                # b | |
                #   c |
                #     d
                #
                # e arrives, and is a reply to b, we can't just go:
                # a + +
                # b - - +
                #   c | |
                #     d |
                #       e
                #
                # it's messy and confusing.  instead we have to do
                # extra work so we end up at
                # a - + +
                # b + | |
                #   | c |
                #   |   d
                #   e

                # okay, figure out what the max col is
                my $max_col = (max map { scalar @$_ } @cells );
                # would drawing the simple horizontal line cross the streams?
                if (grep { $cells[$parent_row][$_] } $parent_col+1..$max_col) {
                    # we want to end up in $parent_col + 1 and
                    # everything in that column needs to get shuffled
                    # over one
                    $col = $parent_col + 1;
                    for my $r (@cells[0 .. $row - 1]) {
                        next if @$r < $col;
                        my $here = $r->[$col] || '';
                        splice(@$r, $col, 0, $here eq '+' ? '-' : undef);
                    }
                    $col = $parent_col + 1;
                }
                else {
                    $col = $max_col;
                }

                # the path is now clear, add the line in
                for ($parent_col..$col) {
                    $cells[$parent_row][$_] ||= '-';
                }
                $cells[$parent_row][$col] = '+';
            }
            # would drawing the vertical line cross the streams?
            if (grep { $cells[$_][$col] } $parent_row+1..$row) {
                print "Crossing the streams!\n";
                # a +
                #   b
                # c +
                #   d

                # C<e> comes as a late response to C<e>.  after
                # stretching it looks like this:

                # a + +
                #     b
                # c - +
                #     d
                #   e
                # to draw the vertical would cross the c -> d path

            }

            # place the message
            $cells[$row][$col] = $c;
            # link with vertical dashes
            for ($parent_row..$row) {
                $cells[$_][$col] ||= '|';
            }
        }

        # pad the rows with undefs
        my $maxcol = max map { scalar @$_ } @cells;
        for my $row (@cells) {
            $row->[$_] ||= ' ' for (0..$maxcol-1);
        }

        push @results, \@cells;
        _draw_cells(\@cells) if 1;
    }
    return @results;
}

=head2 ->strand

run a strand through all C<messages> - wander over C<threader> setting
the Message ->next and ->prev links

=cut

sub strand {
    my $self = shift;

    my $prev;
    for my $root (@{ $self->rootset }) {
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

wander over C<rootset> reparenting subthreads that are
considered too deep

=cut

sub split_deep {
    my $self = shift;

    my @toodeep;
    for my $root (@{ $self->rootset }) {
        my $sub = sub {
            my ($cont, $depth) = @_;

            # only note first entries
            if ($depth && ($depth % 6 == 0)
                && $cont->parent->child == $cont) {
                push @toodeep, $cont;
            }
        };

        $root->iterate_down( $sub );
        undef $sub;
    }

    print "splicing threads in ", scalar @toodeep, " places\n";
    for (@toodeep) {
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

=head2 ->generate_lurker

=cut

sub generate_lurker {
    my $self = shift;
    my $data = shift;

    my $tt = Template->new(
        INCLUDE_PATH => 'templates:/usr/local/mariachi/templates',
        RECURSION => 1
       );

    $tt->process('lurker.tt2',
                 { threads => $data,
                   list_title => $self->list_title,
               },
                 $self->output . "/lurker.html" ) or die $tt->error;
}

=head2 ->generate

render thread tree into the directory of C<output>

=cut

# XXX this seems to have just passed the stage of being too big
sub generate {
    my $self = shift;

    my $tt = Template->new(
        INCLUDE_PATH => 'templates:/usr/local/mariachi/templates',
        RECURSION => 1
       );

    my @threads = @{ $self->rootset };
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
    @threads = @{ $self->rootset };
    for my $i (grep { $touched_threads{ $threads[$_] } } 0..$#threads) {
        $touched_threads{ $threads[$i-1] } = $threads[$i-1] if $i > 0;
        $touched_threads{ $threads[$i+1] } = $threads[$i+1] if $i+1 < @threads;
    }

    # and then render all the messages in the dirty threads
    my $count  = 0;
    for my $root (values %touched_threads) {
        my $sub = sub {
            my $mail = $_[0]->message or return;
            print STDERR "\rmessage $count" if ++$count % 100 == 0;

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
    print STDERR "\n";

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
    my @data = $self->time_thread;     $self->_bench("lurker format thread reworking");
    $self->generate_lurker( \@data ); $self->_bench("lurker output");
    $self->strand;          $self->_bench("strand");
    $self->split_deep;      $self->_bench("deep threads split up");
    $self->sanity;          $self->_bench("sanity");
    $self->order;           $self->_bench("order");
    $self->generate;        $self->_bench("generate");
}

package Mariachi::Folder;
use Mariachi::Message;
use Email::Folder;
use base 'Email::Folder';

sub bless_message { Mariachi::Message->new($_[1]) }

1;

__END__

=head1 AUTHORS

This code was written as part of the Siesta project and includes code
from:

Richard Clamp <richardc@unixbeard.net>
Simon Wistow <simon@thegestalt.org>
Tom Insam <tom@jerakeen.org>

More information about the Siesta project can be found online at
http://siesta.unixbeard.net/

=head1 COPYRIGHT

Copyright 2003 The Siesta Project

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
