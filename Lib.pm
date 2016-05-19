=pod

=head1 NAME

UEN::Lib - library of useful functions

=cut

package UEN::Lib;

use strict;    ## remove this line under penalty of death :-|
use Carp;
use FindBin ();
use File::Spec::Functions qw(splitdir catdir catfile rootdir);
our @ISA = qw(Exporter);
our @EXPORT_OK =
    qw(&strnorm &month_atoi
       &untaint &scrubFormData &scrubEnvironment
       &valid_email &valid_domain &valid_ipv4 &valid_ipv6
       &pathup2 &app_name &app_upload_path &domain_host
       &upload_user_file);

our %EXPORT_TAGS = (
    'all' => [@EXPORT_OK]
);

#############################################################################
##
#############################################################################
=item I<strnorm>([ \%cmds ], @strings)

"Normalize" character strings. Leading and trailing whitespace are always
removed.  Other operations are done as per (optional) command hash:

   compress_internal   Reduce all internal strings of consecutive whitespace
                       to a single space character, including newlines in the
                       case of multiline strings

  strip_line_initial   For multiline strings, remove whitespace appearing
                       at the beginning of each logical line

                  lc   Convert to lower-case

                  uc   Convert to upper-case

Improve this documentation at some point.

=cut
sub strnorm {
    my @strings = @_;
    my $cmd = ref($strings[0]) ? shift(@strings) : {};

    map {
        s/^\s*//s;
        s/\s*$//s;
        s/\s+/ /gs if $cmd->{compress_internal};
        s/^\s*//gm if $cmd->{strip_line_initial};
        $_ = lc($_) if $cmd->{'lc'};
        $_ = uc($_) if $cmd->{'uc'};
    } @strings;
    return wantarray ? @strings : $strings[0];
}

#############################################################################
##
#############################################################################
=item I<month_atoi>(monthname)

Takes a month name and returns integer 0-11, as required by many
date manipulation routines.

=cut
sub month_atoi {
    my $mon = shift;
    my %Months = qw(jan 0 feb 1 mar 2 apr 3 may 4
                    jun 5 jul 6 aug 7 sep 8 oct 9
                    nov 10 dec 11);
    $mon = lc(substr($mon, 0, 3));
    return $Months{$mon};
}

#############################################################################
##
#############################################################################
sub scrubEnvironment {
    $ENV{PATH} = '/bin:/usr/bin';
    $ENV{SHELL} = '/bin/sh' if exists $ENV{SHELL};
    delete @ENV{qw(IFS CDPATH ENV BASH_ENV)};
}

#############################################################################
##
#############################################################################
=item I<scrubFormData>(\%fieldhash, key1, val1, key2, val2[, ...])

    Write this documentation!

=cut
sub scrubFormData {
    my($fh, %data) = @_;
    my %results;

    ## OK, the following is much more esoteric than I normally let myself
    ## write... but why make something more complicated than need be? :-)
    my @matches = grep /^\(\?-/, keys %{$fh};
       @matches = map { [ qr/$_/, delete $fh->{$_} ] } @matches;

    foreach my $name (keys %data) {
        if (exists $fh->{$name}) {
            ## the name itself appears in the field hash
            $results{$name} = untaint($fh->{$name}, $data{$name});
        }
        elsif (my($m) = grep { $name =~ $_->[0] } @matches) {
            ## the name matches one of the regex-type entries
            $results{$name} = untaint($m->[1], $data{$name});
        }
        elsif (exists $fh->{-ELSE}) {
            ## use the catch-all, if there is one
            $results{$name} = untaint($fh->{-ELSE}, $data{$name});
        }
    }
    return %results;
}

#############################################################################
##
#############################################################################
=item I<untaint>(type, data [, ...])

Untaint a variety of different data types.  Currently implemented
pre-defined types are:

  int          (integer)
  float        (floating point)
  number       (either integer or float)
  word         (alphanumeric, underscore and hyphen)
  ipv4         (IPv4 address)
  ipv6         (IPv6 address)
  ipaddr       (either IPv4 or v6)
  filename     (dot, hyphen, underscore allowed)
  filepath     (filename plus slash and backslash and dot)
  hostname     (host part of a domain name)
  domainname   (as per RFC)
  email        (email address as per RFC)
  ip_or_domain (matches host/domain name or IP address)

Alternatively, the type can be given as:

 * A qr// quoted regular expression to be used as the untainting
   pattern. Regex MUST include at least one (outermost) pair of
   parens () marking off untainted value which will be returned
   to the caller. Further embedded parens are ignored.

 * A subroutine reference. The sub MUST return undef in the
   case of failure (i.e. data cannot be untainted). Compare
   valid_email() or other routines defined in this file for
   examples.

Following the type spec, a list of one or more data are untainted
and returned, either as a scalar (if only one datum), or as a list
(if > 1). If data is tainted (i.e. doesn't conform to expected
character content or type format), undef is returned.  This
routine does not do syntax checking of most types of data - it
only determines that they are made up of the right sort
of characters.

=cut
sub untaint {
    my $type = shift;
    my %Dators = (
        word => qr/([-\w]+)/,
        'int' => qr/(-?\d+)/,
        float => qr/(-?\d*\.\d+)/,
        ipv4 => \&valid_ipv4,
        ipv6 => \&valid_ipv6,
        filepath => qr/([-\w\\\/.]+)/,
        filename => qr/([-\w.]+)/,
        username => qr/([-\w.]+)/,
        hostname => qr/([-a-z0-9]+)/,
        domainname => \&valid_domain,
        email => \&valid_email,
    );
    ## Add some combination types and aliases
    $Dators{number} = qr/($Dators{int}|$Dators{float})/;
    $Dators{ipaddr} = sub { valid_ipv4($_[0]) || valid_ipv6($_[0]) };
    $Dators{ip_or_domain} = sub { valid_domain($_[0]) || valid_ipv4($_[0]) || valid_ipv6($_[0]) };

    my $dator = $Dators{$type} || $type;

    my @ret;
    while (my $item = shift) {
        my $untainted;
        if (ref($dator) eq 'CODE') {
            ($untainted) = $dator->($item);
             $untainted =~ /^(.*)$/;     ## a trick, to make sure Perl knows we've untainted
        }
        else {
            ($untainted) = $item =~ /^${dator}$/i ? $1 : undef;
        }
        push(@ret, $untainted);
    }
    return wantarray ? @ret : shift @ret;
}

#############################################################################
##
#############################################################################
sub valid_email {
    ## returns addresses normalized to lower-case unless $nonorm is true
    my($addr, $nonorm) = @_;
    my $u_label = qr/([a-z0-9]|([_a-z0-9][-_a-z0-9]*[_a-z0-9]))/io;
    my $userpart = qr/^$u_label([.+]$u_label)*$/i;

    my($left, $right) = split /[@]/, $addr, 2;
    if ($left =~ $userpart && valid_domain($right)) {
       return $nonorm ? $addr : lc($addr);
    }
    return undef;
}

#############################################################################
##
#############################################################################
sub valid_domain {
    ## this will NOT recognize domains that are only a single label ("foo");
    ##   there must be at least two levels (e.g. "foo.com") to pass.
    my($dom, $nonorm) = @_;
    my $d_label = qr/([a-z0-9]|([a-z0-9][-a-z0-9]*[a-z0-9]))/io;
    my $domain = qr/^$d_label\.($d_label\.?)+$/i;
    if ($dom =~ $domain) {
        return $nonorm ? $dom : lc($dom);
    }
    return undef;
}

#############################################################################
##
#############################################################################
sub valid_ipv4 {
    my($ip, $nonorm) = @_;
    ### improve this!
    $ip =~ /^((\d{1,3}\.){3}\d{1,3})$/ ? $1 : undef;
}

#############################################################################
##
#############################################################################
sub valid_ipv6 {
    my($ip, $format) = @_;
    ## if $format eq "long", returns full-length, no-wildcard address,
    ##    otherwise returns abbreviated address (using wildcard)

    $ip = lc($ip);                      # lowercase our characters (at least for now)
    my @chunks = split /:/, $ip, -1;    # -1 means don't drop trailing empties

    ## The following is kinda ugly, but meant to allow initial and final wildcards
    ## by temporarily setting aside one of the 2 empties created by split.
    my $head = shift @chunks if $chunks[0] eq '' && $chunks[1] eq '';
    my $tail =  pop @chunks if $chunks[-1] eq '' && $chunks[-2] eq '';

    my $num_wildcards = scalar(grep { $_ eq '' } @chunks);
    my $invalid = 0;    # so far so good :-)

    ## Cannot have more than 8 fields in the address
    $invalid ||= (@chunks > 8);

    ## Cannot have more than one wildcard '::'
    $invalid ||= ($num_wildcards > 1);

    ## If less than 8 fields, must have a wildcard
    $invalid ||= (@chunks < 8 && $num_wildcards < 1);

    ## All fields must be either empty or a valid 2-byte hex value
    $invalid ||= (grep { $_ ne '' && !/^[\da-f]{1,4}$/ } @chunks) ? 1 : 0;

    return undef if $invalid;

    map { s/^0*([\da-f]+)/$1/ } @chunks;    # strip leading zeroes

    if ($format eq 'long') {
        my $fillin = 8 - scalar(grep { $_ ne '' } @chunks);
        for (my $i = 0; $i < @chunks; $i++) {
            next if $chunks[$i] ne '';
            splice @chunks, $i, 1, ((0) x $fillin);
            last;
        }
        undef $head;
        undef $tail;
    }
    unshift(@chunks, $head) if defined $head;   # put 'em back for output
       push(@chunks, $tail) if defined $tail;

    return join(':', @chunks);
}

#############################################################################
##
#############################################################################
sub pathup2 {
    my($todir) = @_;
    my @dirs = splitdir($FindBin::Bin);
    while ($dirs[-1] ne $todir) {
        pop @dirs;
    }
    catdir(@dirs);
}

#############################################################################
##
#############################################################################
sub app_name {
    my %Path_parse = ( wwwuen => \&_wwwuen_path, 'wwwuen-ssl' => \&_wwwuen_path );
    my @dirs = splitdir($FindBin::Bin);
    my $instance;

    while (@dirs) {
        my $dir = shift @dirs;
        if ($dir eq 'web') {
            $instance = shift @dirs;
            last;
        }
    }
    unless ($instance) {
        croak 'Unable to determine instance';
    }
    my $parser = $Path_parse{$instance};
    if (ref($parser) ne 'CODE') {
        ## Simple case: instance only has one app, of the same name
        return ($instance, $instance);
    }
    my $appname = $parser->(@dirs);
    unless ($appname) {
        croak 'Unable to determine application name';
    }
    return ($appname, $instance);
}

#############################################################################
##
#############################################################################
sub app_upload_path {
    my($app, $instance) = app_name();
    my $path = catdir(rootdir(), 'web', $instance, 'uploads', $app);
    return (@_ ? catfile($path, @_) : $path);
}

#############################################################################
##
#############################################################################
sub domain_host {
    my %Exceptions = (
        ## Try to eliminate these!
        'my.dev' => 'my-uat.dev.uen.org',
        'my.stg' => 'my.uen.org',
    );
    my $host = shift || 'www';
    my $mode = $ENV{RUN_MODE} or croak 'Cannot determine RUN_MODE';
    if (my $e = $Exceptions{"$host.$mode"}) {
        return $e;
    }
    my $d = { dev => '.dev', stg => '.stage' }->{$mode};  ## slick, eh? :)
    return "$host$d.uen.org";
}

#############################################################################
##
#############################################################################
sub upload_user_file {
    my($element, $filepath_templ, $cgi) = @_;
    my($thisscript) = $main::thisscript || app_name();
    $cgi ||= $main::query;  ## if $cgi not specified, use $query from calling context

    my $file = $cgi->param($element);
       $file =~ s#^.*[\\/]##;        ## remove any path that might be included

    unless ($file) {
        print $cgi->font({ color=>'red' }, 'Files cannot be larger than 1MB');
        exit;
        ## EXECUTION ABORTED
    }
    unless ($file = untaint('filename', $file)) {
        print $cgi->font({ color=>'red' }, 'Bad filename format or illegal char');
        exit;
        ## EXECUTION ABORTED
    }

    my $fh = $cgi->upload($element);
    unless ($fh) {
        if (my $err = $cgi->cgi_error()) {
            print $cgi->header(-status => $err);
            print $cgi->h2($err);
            die "$thisscript: Upload interrupted or other major problem";
            ## EXECUTION ABORTED
        }
        print $cgi->font({ color=>'red' }, 'Cannot open uploaded file');
        warn "$thisscript: Cannot open uploaded file: $element => $file";
        exit;
        ## EXECUTION ABORTED
    }

    my $outfile = sprintf $filepath_templ, $file;

    eval {
        local $/ = undef;
        my $content = <$fh>;
        close $fh;
        open(FH, ">$outfile") or die "Cannot open output file for write\n";
        binmode FH;
        print FH $content;
        close(FH) or die "Cannot close output file\n";
    };
    if ($@) {
        print $cgi->font({ color=>'red' }, "$@ - please report");
        warn "$thisscript: $outfile: $@";   ## goes to the server log
        exit;
        ## EXECUTION ABORTED
    }
    return $file;  ## calling code often needs to know the file name
}

#############################################################################
##
#############################################################################
sub _wwwuen_path {
    my $app;
    while (@_) {
        my $dir = shift;
        if ($dir eq 'htdocs') {
            $app = shift;
            if ($app eq 'utahlink') {
                $app = shift;
            }
            last;
        }
    }
    return $app;
}

1;
__END__
=pod

=head1 SYNOPSIS

A library of various useful functions.  Exports nothing by default.
Either specify in the export list exactly the function(s) you want

   use UEN::Lib qw(strnorm untaint);

or, if that's too much trouble, use tag ":all" to get all of them

   use UEN::Lib qw(:all);

=head1 AUTHOR

    Originally by David J Iannucci <dji@uen.org>

=head1 VERSION

 $Id: Lib.pm,v 1.26 2011/04/13 18:21:23 dji Exp $

=cut
