use strict;
package Mariachi::DBI;
use base 'Class::DBI::SQLite';

# create table, for slackers
sub slacker_table {
    my $self = shift;

    # id goes without saying, so don't make me say it
    my $sql = "CREATE TABLE ".$self->moniker. " ( "
      . join(", ", "id INTEGER PRIMARY KEY", @_ ) . " )";
    #warn $sql;
    $self->db_Main->do( $sql )
}
1;
