use strict;
package Mariachi::Message;
use Email::Simple;
use Class::Accessor::Fast;
use Digest::MD5 qw(md5_base64);

use base qw(Email::Simple Class::Accessor::Fast);
__PACKAGE__->mk_accessors(qw(filename from walkedover));

sub subject { $_[0]->header('subject') }
sub date    { $_[0]->header('date') }

sub new {
    my $class = shift;
    my $source = shift;
    my $self = $class->SUPER::new($source) or return;

    my $filename = md5_base64( $source ).".html";
    $filename =~ tr{/+}{_-}; # + isn't as portably safe as -
    # This isn't going to create collisions as the 64 characters used are:
    # ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/
    $self->filename($filename);

    # from is a sanitised mail address
    my $from = $self->header('from');
    $from =~ s/<.*>//;
    $from =~ s/\@\S+//;
    $from =~ s/\s+\z//;
    $self->from($from);

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
