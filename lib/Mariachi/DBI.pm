use strict;
package Mariachi::DBI;
use base 'Class::DBI::SQLite';

sub set_db {
    my $class = shift;
    $class->SUPER::set_db(@_);
    $class->create_later;
}

my @create_later;
sub create_later {
    my $self = shift;
    for my $table ( @create_later ) {
        my $sql = "CREATE TABLE ".$table->{name}. " ( "
          . join(", ",
                 # id goes without saying, so don't make me say it
                 "id INTEGER PRIMARY KEY",
                 keys %{ $table->{fields} },
                ) . " ) ";
        #warn $sql;
        $self->db_Main->do( $sql );
    }

    # and now set up the tables and the has_a's
    for my $table ( @create_later ) {
        # ??? this next line seems to segv.  badness
        $table->{class}->set_up_table( $table->{name} );
        while ( my ($k, $v) = each %{ $table->{fields} }) {
            next unless $v;
            $table->{class}->has_a( $k => $v );
        }
    }
}

# I want to have my cake, and eat it.  Maybe if I eat it *later*... :)
sub set_up_later {
    my $class   = shift;

    push @create_later, {
        name   => $class->moniker,
        class  => $class,
        fields => { @_ },
    };
}

1;
