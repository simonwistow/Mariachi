use strict;
package Mariachi::Message;
use Email::Simple;
use Class::Accessor::Fast;
use Digest::MD5 qw(md5_hex);
use Date::Parse qw(str2time);
use Text::Original ();
use Memoize;

use base 'Mariachi::DBI';
__PACKAGE__->set_up_later(
    rawmail         => 'Email::Simple',
    map { $_ => '' } qw(
        hdr_message_id hdr_from hdr_subject hdr_date
        hdr_references hdr_in_reply_to
        body epoch_date day month year ),
   );
__PACKAGE__->add_trigger( before_create => \&pre_create );

#these are just sops
__PACKAGE__->columns( TEMP => qw( prev next root ) );

# copy things out of the email::simple message and into the columns
sub _blat {
    my $thing = shift;
    $thing =~ tr/-/_/;
    return lc $thing;
}

sub pre_create {
    my $data = shift;

    my $mail = $data->{rawmail};
    $data->{ 'hdr_' . _blat( $_ ) } = $mail->header($_) for
      qw( message-id from subject date references in-reply-to );

    $data->{body}       = $mail->body;
    $data->{epoch_date} = str2time( $data->{hdr_date} ) || 0;

    my @date = localtime $data->{epoch_date};
    my @ymd = ( $date[5] + 1900, $date[4] + 1, $date[3] );
    $data->{day}   = sprintf "%04d/%02d/%02d", @ymd;
    $data->{month} = sprintf "%04d/%02d", @ymd;
    $data->{year}  = sprintf "%04d", @ymd;
}

=head1 NAME

Mariachi::Message - representation of a mail message

=head1 METHODS

=head2 ->new($message)

C<$message> is a rfc2822 compliant message body

your standard constructor

=cut

sub new {
    my $class = shift;
    my $mail  = Email::Simple->new(shift) or return;

    my $msgid = $mail->header('message-id') or die "gotta have a message-id";
    my ($old) = $class->search({ hdr_message_id => $msgid });
    return $old if $old;
    return $class->create({ rawmail => $mail });
}


=head2 ->body

=head2 ->header

=head2 ->header_set

C<body>, C<header>, and C<header_set> are provided for interface
compatibility with Email::Simple

=cut

sub header {
    my $self = shift;
    my $meth = "hdr_" . _blat( shift );
    $self->$meth();
}

sub header_set {
    my $self = shift;
    my $meth = "hdr_" . _blat( shift );
    $self->$meth( shift );
}

=head2 ->first_lines

=head2 ->first_paragraph

=head2 ->first_sentence

See L<Text::Original>

=cut

*first_line = \&first_lines;
sub first_lines {
    my $self = shift;
    return Text::Original::first_lines( $self->body, @_ );
}

sub first_paragraph {
    my $self = shift;
    return Text::Original::first_paragraph( $self->body );
}

sub first_sentence {
    my $self = shift;
    return Text::Original::first_sentence( $self->body );
}

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
