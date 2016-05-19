=pod

=head1 NAME

sessionsconf.pl - configuration info for UEN::Session

=head1 AUTHOR

David J. Iannucci <dji@uen.org>

=head1 VERSION

 $Id: sessionsconf.pl,v 1.4 2011/02/10 18:13:10 dji Exp $

=cut

use UEN::Lib qw(domain_host);

## Stuff needed for SOAP web services calls to the my.uen portal
##
sub SOAP::Transport::HTTP::Client::get_basic_credentials { return 'username', '************'; }
sub _getWsdl {
    my $domain = domain_host('my');
    sprintf 'http://%s:%s@%s/tunnel-web/secure/axis/Portlet_UEN_ExternalUserService?wsdl',
        SOAP::Transport::HTTP::Client::get_basic_credentials(), $domain;
}

## To force an independent session, with different parameters, for a given app,
## add it to this hash. The app name (outermost key) MUST be the same value
## that is returned by UEN::Lib::app_name().  Unspecified apps will use the default
## session 'default', shared by all remaining UEN Perl/CGI apps (aka poor man's SSO).
##
%Apps = (
    default => { cookie => 'uencgisess', expire => '+60m' },
    pmt => { cookie => 'uenpmtsess', expire => '+9h' },
);

1;
__END__
