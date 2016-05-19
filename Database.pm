
package UEN::Database;

use strict;    ## remove this line under penalty of death :-|
use Carp;
use DBI;
our @ISA = qw(Exporter);
our @EXPORT = qw(&connect $errstr);
our @EXPORT_OK = qw();
our %EXPORT_TAGS = (
    'all' => [@EXPORT_OK]
);

my %Creds = (
    cgisessions => {
        sessions => {
            prod => ['dbi:mysql:host=*****.uen.org;port=3306;database=sessions', '***', '********'],
            dev => ['dbi:mysql:host=*****.uen.org;port=3306;database=sessions', '***', '********'],
        }
    },
    districts => {
        utahlink => {
            prod => ['dbi:Sybase:server=homersyb_310;database=utahlink', '***', '********'],
            dev => ['dbi:Sybase:server=matersyb_310;database=utahlink', '***', '********'],
        }
    },
    erate_techplan => {
        erate => {
            prod => ['dbi:Sybase:server=homersyb_310;database=erate', '***', '******'],
            dev => ['dbi:Sybase:server=matersyb_310;database=erate', '***', '******'],
        }
    },
    lessonplan => {
        lesson => {
            prod => ['dbi:Sybase:server=homersyb_310;database=lesson', '***', '******'],
            dev => ['dbi:Sybase:server=matersyb_310;database=lesson', '***', '******'],
        }
    },
    news => {
        news => {
            prod => ['dbi:Sybase:server=homersyb_310;database=news', '***', '*******'],
            dev => ['dbi:Sybase:server=matersyb_310;database=news', '***', '*******'],
        }
    },
    pdms => {
        evals => {
            prod => ['dbi:mysql:host=*****.uen.org;port=3306;database=pdms', '***', '********'],
                ## Re: dev creds below: updating this based on happening across forgotten-about creds in
                ## a file left for me by Dan C. Tried to find justification for these being the right ones
                ## in JIRA ticket history - couldn't. Don't know that I've ever needed these particular ones
                ## for testing eval_reports.pl, and maybe never will, but FYI - they might be wrong. -dji
            dev => ['dbi:mysql:host=*****.uen.org;port=3306;database=pdms', '***', '********'],
        }
    },
    pmt => {
        lportal => {
            prod => ['dbi:Sybase:server=homersyb_310;database=prod_lportal', '***', '******'],
            dev => ['dbi:Sybase:server=matersyb_310;database=prod_lportal', '***', '******'],
        },
        utahlink => {
            prod => ['dbi:Sybase:server=homersyb_310;database=utahlink', '***', '******'],
            dev => ['dbi:Sybase:server=matersyb_310;database=utahlink', '***', '******'],
        }
    },
    rubric => {
        rubric => {
            prod => ['dbi:Sybase:server=homersyb_310;database=rubric', '***', '*********'],
            dev => ['dbi:Sybase:server=matersyb_310;database=rubric', '***', '*********'],
        }
    },
    tours_acts => {
        tour => {
            prod => ['dbi:Sybase:server=homersyb_310;database=tour', '***', '*********'],
            dev => ['dbi:Sybase:server=matersyb_310;database=tour', '***', '*********'],
        }
    },
    utahlink => {
        utahlink => {
            prod => ['dbi:Sybase:server=homersyb_310;database=utahlink', '***', '***********'],
            dev => ['dbi:Sybase:server=matersyb_310;database=utahlink', '***', '***********'],
        }
    },
);

#############################################################################
##
#############################################################################
sub connect {
    my $self = shift;
    my($app, $service, @other) = @_;
    my $mode = $ENV{RUN_MODE} or croak "Unable to determine RUN_MODE";
    if ($mode eq 'stg' && not $Creds{$app}->{$service}->{$mode}) {
        $mode = 'prod';
    }
    my $creds = $Creds{$app}->{$service}->{$mode} or
        croak "No db credentials for app=$app, service=$service, mode=$mode";

    my $h = DBI->connect(@{ $creds }, @other) or croak $DBI::errstr;
    $UEN::Database::errstr = $DBI::errstr;
    return $h;
}

1;
__END__
=pod

=head1 NAME

UEN::Database - wrapper for local database authentication

=head1 AUTHOR

  David J Iannucci <dji@uen.org>

=head1 VERSION

 $Id: Database.pm,v 1.8 2011/04/12 00:33:00 dji Exp $

=cut
