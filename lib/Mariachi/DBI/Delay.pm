use strict;
package Mariachi::DBI::Delay;
use base 'Mariachi::DBI';
use Class::Delay
  methods => [qw( slacker_table set_up_table has_a has_many )],
  release => [qw( set_db )],
  reorder => sub { sort { $b->is_trigger <=> $a->is_trigger } @_ };

1;
