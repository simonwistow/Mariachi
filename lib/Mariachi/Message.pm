use strict;
package Mariachi::Message;
use Email::Simple;
use Class::Accessor::Fast;
use Digest::MD5 qw(md5_hex);
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

	return $self->_get_context(lines => $num);
}


=head2 ->first_para 

Returns 

=cut

sub first_para {
	my $self = shift;
	return $self->_get_context(para => 1);
}

sub _get_context {
	my $self = shift;
	my %opts = @_;

	my $return = "";
	my $lines  = 0;

    # get all the lines of the sigless body
    foreach (split /$/m, $self->body_sigless) {
		last if (defined $opts{'para'} && $opts{'para'}==1 && $lines>0 && /^\s*$/);

        # blank lines, euurgh
        next if /^\s*$/;
        # quotes (we don't count quoted From's)
        next if /^\s*>(?!From)/;
        # skip obvious attribution
        next if /^\s*On (Mon|Tue|Wed|Thu|Fri|Sat|Sun)/i;
        next if /^\s*.+=? wrote:/i;

        # skip signed messages
        next if /^\s*-----/;

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

memoize('_get_context');

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

=head2 ->index

=head2 ->next

the next message in the archive, thread-wise

=head2 ->prev

the previous message in the archive, thread-wise

=head2 ->root

the root of the thread you live in

=cut
