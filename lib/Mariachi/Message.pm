use strict;
package Mariachi::Message;
use Email::Simple;
use Class::Accessor::Fast;
use Digest::MD5 qw(md5_hex);
use Date::Parse qw(str2time);
use Memoize;

use base qw(Class::Accessor::Fast);
__PACKAGE__->mk_accessors(qw( body _header next prev root
                              epoch_date day month year ymd linked
                            ));

=head1 NAME

Mariachi::Message - representation of a mail message

=head1 METHODS

=head2 ->new($message)

C<$message> is a rfc2822 compliant message body

your standard constructor

=cut

sub new {
    my $class = shift;
    my $source = shift;

    my $self = $class->SUPER::new;
    my $mail = Email::Simple->new($source) or return;

    $self->linked({});
    $self->_header({});
    $self->header_set( $_, $mail->header($_) ) for
      qw( message-id from subject date references in-reply-to );
    $self->body( $mail->body );

    $self->header_set('message-id', $self->_make_fake_id)
      unless $self->header('message-id');

    # this is a bit ugly to be here but much quicker than making it a
    # memoized lookup
    my @date = localtime $self->epoch_date(str2time( $self->header('date') )
                                             || 0);
    my @ymd = ( $date[5] + 1900, $date[4] + 1, $date[3] );
    $self->ymd(\@ymd);
    $self->day(   sprintf "%04d/%02d/%02d", @ymd );
    $self->month( sprintf "%04d/%02d", @ymd );
    $self->year(  sprintf "%04d", @ymd );

    return $self;
}


sub _make_fake_id {
    my $self = shift;
    my $hash = substr( md5_hex( $self->header('from').$self->date ), 0, 8 );
    return "$hash\@made_up";
}

=head2 ->body

=head2 ->header

=head2 ->header_set

C<body>, C<header>, and C<header_set> are provided for interface
compatibility with Email::Simple

=cut

sub header {
    my $self = shift;
    $self->_header->{ lc shift() };
}

sub header_set {
    my $self = shift;
    my $hdr = shift;
    $self->_header->{ lc $hdr } = shift;
}


=head2 ->first_lines

Returns the a number of lines after the first non blank, none quoted
line of the body of the email.

It will guess at attribution lines and skip them as well.

It will return super cited lines. This is the super-citers'
fault, not ours.

It won't catch all types of attribution lines;

It can optionally be passed a number of lines to get.

=cut

sub first_lines {
    my $self = shift;
    my $num  = shift || 1;

    return $self->_significant_signal(lines => $num);
}

*first_line = \&first_lines;

=head2 ->first_paragraph

Returns the first original paragraph of the message

=cut

sub first_paragraph {
    my $self = shift;
    return $self->_significant_signal(para => 1);
}

=head2 ->first_sentence

Returns the first original sentence of the message

=cut

sub first_sentence {
    my $self = shift;
    my $text = $self->first_paragraph();
    $text =~ s/([.?!]).*/$1/s;
    return $text;
}

sub _significant_signal {
    my $self = shift;
    my %opts = @_;

    my $return = "";
    my $lines  = 0;

    # get all the lines from the main part of the body
    my @lines = split /$/m, $self->body_sigless;

    # right, find the start of the original content or quoted
    # content (i.e. skip past the attributation)
    my $not_started = 1;
    while (@lines && $not_started) {
        # next line
        local $_ = shift @lines;
        #print "}}$_";

        # blank lines, euurgh
        next if /^\s*$/;
        # quotes (we don't count quoted From's)
        next if /^\s*>(?!From)/;
        # skip obvious attribution
        next if /^\s*On (Mon|Tue|Wed|Thu|Fri|Sat|Sun)/i;
        next if /^\s*.+=? wrote:/i;

        # skip signed messages
        next if /^\s*-----/;
        next if /^Hash:/;

        # annoying hi messages (this won't work with i18n)
        next if /^\s*(?:hello|hi|hey|greetings|salut
                        |good (?:morning|afternoon|day|evening))
                 (?:\W.{0,14})?\s*$/ixs;

        # snips
        next if m~\s*                          # whitespace
                  [<.=-_*+({\[]*?              # opening bracket
                  (?:snip|cut|delete|deleted)  # snip?
                  [^>}\]]*?                    # some words?
                  [>.=-_*+)}\]]*?              # closing bracket
                 \s*$                          # end of the line
                 ~xi;

        # [.. foo ..] or ...foo.. or so on
        next if m~\s*\[?\.\..*?\.\.]?\s*$~;

        # ... or [...]
        next if m~\s*\[?\.\.\.]?\s*$~;

        # if we got this far then we've probably got past the
        # attibutation lines
        unshift @lines, $_;  # undo the shift
        undef $not_started;  # and say we've started.
    }

    # okay, let's _try_ to build up some content then
    foreach (@lines) {
        # are we at the end of a paragraph?
        last if (defined $opts{'para'}  # paragraph mode?
                 && $opts{'para'}==1
                 && $lines>0            # got some lines aready?
                 && /^\s*$/);           # and now we've found a gap?

        # blank lines, euurgh
        next if /^\s*$/;
        # quotes (we don't count quoted From's)
        next if /^\s*>(?!From)/;

        # if we got this far then the line was a useful one
        $lines++;

        # sort of munged Froms
        s/^>From/From/;
        s/^\n+//;
        $return .= "\n" if $lines>1;
        $return .= $_;
        last if (defined $opts{'lines'} && $opts{'lines'}==$lines);
    }
    return $return;
}

memoize('_significant_signal');

=head2 ->body_sigless

Returns the body with the signature (defined as anything
after "\n-- \n") removed.

=cut

sub body_sigless {
    my $self = shift;
    my ($body, undef) = split /^-- $/m, $self->body, 2;

    return $body;
}

=head2 ->sig

Returns the stripped sig.

=cut

sub sig {
    my $self = shift;
    my (undef, $sig) = split /^-- $/m, $self->body, 2;
    $sig =~ s/^\n// if $sig;
    return $sig;
}



=head2 ->from

A privacy repecting version of the From: header.

=cut

sub from {
    my $self = shift;

    my $from = $self->header('from');
    $from =~ s/<.*>//;
    $from =~ s/\@\S+//;
    $from =~ s/\s+\z//;
    $from =~ s/"(.*?)"/$1/;
    return $from;
}
memoize('from');

=head2 ->subject

=head2 ->date

the C<Subject> and C<Date> headers

=cut

sub subject { $_[0]->header('subject') }
sub date    { $_[0]->header('date') }


=head2 ->filename

the name of the output file

=cut

sub filename {
    my $self = shift;

    my $msgid = $self->header('message-id');

    my $filename = substr( md5_hex( $msgid ), 0, 8 ).".html";
    return $self->day."/".$filename;
}
memoize('filename');

1;

__END__

=head2 ->epoch_date

The date header pared into epoch seconds

=head2 ->ymd

=head2 ->day

=head2 ->month

=head2 ->year

epoch_date formatted in useful ways

=head2 ->linked

hashref of indexes that link to us.  key is the type of index, value
is the filename

=head2 ->next

the next message in the archive, thread-wise

=head2 ->prev

the previous message in the archive, thread-wise

=head2 ->root

the root of the thread you live in

=cut
