use strict;
package Mariachi::Message;
use Email::Simple;
use Class::Accessor::Fast;
use Digest::MD5 qw(md5_base64);
use Date::Parse qw(str2time);

use base qw(Class::Accessor::Fast);
__PACKAGE__->mk_accessors(qw( filename from index next prev epoch_date
                              year month day ymd _header body ));

sub subject { $_[0]->header('subject') }
sub date    { $_[0]->header('date') }

sub _filename {
    my $self = shift;

    my $msgid = $self->header('message-id');
    $msgid = $self->header_set('message-id', $self->_make_fake_id)
      unless $msgid;

    my $filename = substr( md5_base64( $msgid ), 0, 8 ).".html";
    $filename =~ tr{/+}{_-}; # + isn't as portably safe as -
    # This isn't going to create collisions as the 64 characters used are:
    # ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/

    my @date = localtime $self->epoch_date;
    my @ymd = ($date[5]+1900, $date[4]+1, $date[3]);
    $self->year(sprintf "%04d", @ymd);
    $self->month(sprintf "%04d/%02d", @ymd);
    my $path = $self->day(sprintf "%04d/%02d/%02d", @ymd);
    $self->ymd(\@ymd);
    return "$path/$filename";
}

sub _from {
    my $self = shift;

    # from is a sanitised mail address
    my $from = $self->header('from');
    $from =~ s/<.*>//;
    $from =~ s/\@\S+//;
    $from =~ s/\s+\z//;

    return $from;
}

sub header {
    my $self = shift;
    $self->_header->{ lc shift() };
}

sub header_set {
    my $self = shift;
    my $hdr = shift;
    $self->_header->{ lc $hdr} = shift;
}

sub new {
    my $class = shift;
    my $source = shift;

    my $self = $class->SUPER::new;
    my $mail = Email::Simple->new($source) or return;

    $self->_header({});
    $self->header_set( $_, $mail->header($_) ) for
      qw( message-id from subject date references in-reply-to );

    $self->body( $mail->body );

    $self->epoch_date(str2time $self->header('date'));
    $self->filename($self->_filename);
    $self->from($self->_from);
    return $self;
}

sub _make_fake_id {
    my $self = shift;
    my ($from,$domain) = split /\@/, $self->_from;
    my $date           = $self->epoch_date;
    my $hash           = md5_base64("$from$date");
    return "$hash\@$domain";
}
1;
