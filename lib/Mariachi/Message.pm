use strict;
package Mariachi::Message;
use Email::Simple;
use Class::Accessor::Fast;
use Digest::MD5 qw(md5_base64);
use Date::Parse qw(str2time);

use base qw(Email::Simple Class::Accessor::Fast);
__PACKAGE__->mk_accessors(qw( filename from index next last epoch_date year_index month_index day_index ymd));

sub subject { $_[0]->header('subject') }
sub date    { $_[0]->header('date') }

sub _filename {
    my $self = shift;

    my $msgid =  $self->header('message-id') || $self->_make_fake_id();
    my $filename = substr( md5_base64( $msgid ), 0, 8 ).".html";
    $filename =~ tr{/+}{_-}; # + isn't as portably safe as -
    # This isn't going to create collisions as the 64 characters used are:
    # ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/

    my @date = localtime $self->epoch_date;
    my @ymd = ($date[5]+1900, $date[4]+1, $date[3]);
    my $path = sprintf("%04d/%02d/%02d/", @ymd);
    $self->year_index(sprintf("%04d/index.html", @ymd));
    $self->month_index(sprintf("%04d/%02d/index.html", @ymd));
    $self->day_index(sprintf("%04d/%02d/%02d/index.html", @ymd));
    $self->ymd(\@ymd);
    return $path.$filename;
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

sub new {
    my $class = shift;
    my $source = shift;
    my $self = $class->SUPER::new($source) or return;

    $self->epoch_date(str2time $self->header('date'));
    $self->filename($self->_filename);
    $self->from($self->_from);
    return $self;
}

sub references {
    my $self = shift;
    @_ ? $self->header_set('references', @_) : $self->header('references');
}

sub in_reply_to {
    my $self = shift;
    @_ ? $self->header_set('in-reply-to', @_) : $self->header('in-reply-to');
}

sub _make_fake_id {
    my $self = shift;
    my ($from,$domain) = split /\@/, $self->_from();
    my $date           = $self->epoch_date();
    my $hash           = md5_base64("$from$date");
    return "$hash\@$domain";
}
1;
