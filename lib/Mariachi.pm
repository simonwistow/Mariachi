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

    my $page = 0;
    my @threads = $self->threader->rootset;
    my $pages = int(scalar(@threads) / $self->threads_per_page);
    while (@threads) {
        warn "Index page " . ($page + 1) . "\n";
        # @chunk is the chunk of threads on this page
        my @chunk = splice(@threads, 0, $self->threads_per_page);
        $_->recurse_down(sub { eval {
            $_[0]->message->page( $page );
            $_[0]->message->root( $_ );
        } })
          for @chunk;

        $tt->process('index.tt2',
                     { threads => \@chunk,
                       page => $page,
                       pages => $pages,
                     },
                     $self->output . ($page ? "/index_$page.html" : "/index.html") )
          or die $tt->error;
        $page++;
    }

    # tt (in) sanity test - we should have walked over everything in
    # the mbox once and only once in generating the thread index
    if (0) {
        my @unwalked = grep { $_->walkedover != 1 } @{ $self->messages };
        my @ids = map { [ $_->header('message-id'), $_->from, $_->subject, $_->walkedover ] } @unwalked;
        die "Stange walk for ".(Dumper \@ids) . @ids . " messages"
          if @ids;
    }

    warn "Message pages\n";
    my $count = 0;
	my %threads;
    for my $mail (@{ $self->messages }) {

		unless (-e $self->output."/".$mail->filename or !defined $mail->root) {
			$threads{ $mail->root } = $mail->root; 
        	warn "$count\n" if ++$count % 20 == 0;
		}
	}

	$self->{tt} = $tt;
	$_->recurse_down( sub { $self->render($_[0]->message) } ) for values %threads

}


sub render {
     my $self = shift;
	 my $mail = shift || return;


 	 $self->{tt}->process('message.tt2',
                     { thread  => $mail->root,
                       message => $mail,
                       headers => [ 'Subject', 'Date' ],
                     },
                     $self->output."/".$mail->filename) or die $self->{tt}->error;
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
