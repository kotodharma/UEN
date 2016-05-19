=pod

=head1 NAME

DBlibAdaptor - adaptor class to convert Sybase::DBlib client code into DBI method calls

=cut
package UEN::DBlibAdaptor;

use strict;
use UEN::Database;
use Carp;
our $AUTOLOAD;

sub AUTOLOAD {
    my $self = shift;
    croak "$self is not an object!" unless ref $self;

    my $name = $AUTOLOAD;
       $name =~ s/.*://;  ## remove fully-qual package name prefix

    if (exists $self->{$name}) {
        ## we're just a local getter/setter for this class
        if (@_) {
            $self->{$name} = shift;
        }
        $self->{$name};
    }
    else {
        ## "Inheriting" adaptor: call any DBI methods against DBI handle,
        ##   (in case there are any used in the code)
        $self->h->$name(@_);
    }
}

sub connect {
    my $self = shift;
    my $class = ref($self) || $self;
    my $con = UEN::Database->connect(@_);
    bless { h => $con, st => undef, err => $UEN::Database::errstr }, $class;
}

sub dbcmd {
    my $self = shift;
    if (ref $self->st) {
        $self->st->finish;
    }
    my $sth = $self->h->prepare(@_);
    $self->st($sth);
}

sub dbuse {
    my $self = shift;
    my($dbname) = @_;
    $self->h->do('use ?', undef, $dbname);
}

sub dbsqlexec {
    my $self = shift;
    $self->st->execute;
}

sub dbresults { }  ## do nothing

sub dbnextrow {
    my $self = shift;
    $self->st->fetchrow_array;
}

sub DESTROY {
    my $self = shift;
    $self->h->disconnect;
}

1;
__END__
=pod
=head1 DESCRIPTION

Beware: This class assumes that a db handle will only have one statement handle at a time!
In other words, each time dbcmd() is called, it will create a new statement handle, which
will obliterate any statement handle that may have been existing, so you CANNOT (e.g.) have
a loop which reads result rows from one query, and for each row, execute a new "sub" query
based on values in that row.  The inner query will kill the outer query's results the
first time it is called.

This means that to implement the aforementioned kind of logic, you need to create a whole
new database handle/connection (dbh2 or whatever) for the inner query (although you probably
should do it OUTSIDE the loop, not inside).  It is because the code that I have found using
Sybase::DBlib is implemented in precisely this way already (for all I know it may be the
only way to do it in DBlib) that I have taken the easy way out and allowed this limitation
to be intrinsic to the adaptor.

=head1 AUTHOR

David J. Iannucci <dji@uen.org>

=head1 VERSION

 $Id: DBlibAdaptor.pm,v 1.4 2010/11/10 23:46:59 dji Exp $

=cut
