use strict;
package Mariachi::Message;
use Email::Simple;
use Class::Accessor::Fast;
use Digest::MD5 qw(md5_base64);
use Date::Parse qw(str2time);
use Memoize;

use base qw(Class::Accessor::Fast);
__PACKAGE__->mk_accessors(qw( body _header index next prev root
                              epoch_date day month year ymd
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

    $self->_header({});
    $self->header_set( $_, $mail->header($_) ) for
      qw( message-id from subject date references in-reply-to );
    $self->body( $mail->body );

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

=head2 ->from

A privacy repecting version of the From: header.

=cut

sub from {
    my $self = shift;

    my $from = $self->header('from');
    $from =~ s/<.*>//;
    $from =~ s/\@\S+//;
    $from =~ s/\s+\z//;
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
    $msgid = $self->header_set('message-id', $self->_make_fake_id)
      unless $msgid;

    my $filename = substr( md5_base64( $msgid ), 0, 8 ).".html";
    $filename =~ tr{/+}{_-}; # + isn't as portably safe as -
    # This isn't going to create collisions as the 64 characters used are:
    # ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/

        # then lc for appearences sake
    return $self->day."/".lc($filename);
}
memoize('filename');

sub _make_fake_id {
    my $self = shift;
    my ($from,$domain) = split /\@/, $self->_from;
    my $date           = $self->epoch_date;
    my $hash           = md5_base64("$from$date");
    return "$hash\@$domain";
}

1;

__END__

=head2 ->epoch_date

The date header pared into epoch seconds

=head2 ->ymd

=head2 ->day

=head2 ->month

=head2 ->year

epoch_date formatted in useful ways

=head2 ->index

=head2 ->next

the next message in the archive, thread-wise

=head2 ->prev

the previous message in the archive, thread-wise

=head2 ->root

the root of the thread you live in

=cut
