use strict;
package Mariachi::Message;
use Email::Simple;
use Class::Accessor::Fast;
use Digest::MD5 qw(md5_base64);

use base qw(Email::Simple Class::Accessor::Fast);
__PACKAGE__->mk_accessors(qw( filename from walkedover page));

sub subject { $_[0]->header('subject') }
sub date    { $_[0]->header('date') }

sub walkover {
    my $self = shift;
    $self->walkedover( $self->walkedover + 1 );
    return;
}

sub _filename {
    my $self = shift;

    my $filename = md5_base64( $self->header('message-id') ).".html";
    $filename =~ tr{/+}{_-}; # + isn't as portably safe as -
    # This isn't going to create collisions as the 64 characters used are:
    # ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/
    return $filename;
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

    $self->walkedover(0);

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

1;
