=pod

=head1 NAME

UEN::Session - authentication and session maintenance class

=head1 SYNOPSIS

  use UEN::Session;
  my $session = new UEN::Session ( %args );
  print $session->header;

=cut
package UEN::Session;

use strict; ## remove this line under penalty of death :-|
use UEN::Database;
use UEN::Lib qw(app_name);
use CGI::Session;
use SOAP::Lite;
use Carp;
our %Apps;
require "sessionsconf.pl";  ## Look here for config parameters

our $AUTOLOAD;

########################################################################################
##
########################################################################################
sub new {
    my $self = shift;
    my $class = ref($self) || $self;
    my %args = ref($_[0]) eq 'HASH' ? %{$_[0]} : @_;
    my $user = delete $args{user};
    my $pass = delete $args{pass};
    my($thisapp) = app_name();  ## caveat codor: app_name returns a list
    ## copy any params out of $self (into %params) before reassigning it?
    my %params = %{ $Apps{$thisapp} || $Apps{default} };

    $self = bless { cs => undef, is_logged_in => 0, status => undef, error => 0 }, $class;

    my $dbh;
    eval {
        $dbh = UEN::Database->connect('cgisessions', 'sessions', { RaiseError => 1 });
    };
    if ($@) {
        croak "Session store db connect: $@";
    }
    $self->{_dbh} = $dbh;  ## store dbh as "pseudo-private" attribute

    my $cookie = delete $params{cookie};
    my $cs;
    eval {
        $cs = CGI::Session->load("driver:mysql;serializer:storable", undef,
                 { Handle => $dbh }, { name => $cookie })
            or croak CGI::Session->errstr;
    };

    ## The following sequence of condition blocks is a "cascade"
    my %uinfo;
    if ($user || $pass) {
        ## Remove any existing authenticated session on explicit login attempt
        $cs->delete;  ## delete causes $cs->is_empty == true
        $cs->flush;
        %uinfo = _check_user($user, $pass);
        if (delete $uinfo{authenticated}) {
            $self->is_logged_in(1);
        }
        else {
            $self->error(1);
            $self->status('Login incorrect.');
        }
    }
    if ($cs->is_expired) {
        ## In current testing, it seems this block is never entered, although session
        ## cookies *are* being expired properly. -dji
        $cs->delete;
        $cs->flush;
        $self->status('Login session expired.');
    }
    if ($cs->is_empty) {
        if ($self->is_logged_in) {
            ## Recreate with same specs used in load call above
            $cs = $cs->new or croak $cs->errstr;

            ## Set parameters for the session
            foreach my $method (keys %params) {
                $cs->$method($params{$method});
            }
            ## Copy user data returned by _check_user() into the session
            foreach my $key (keys %uinfo) {
                $cs->param($key, $uinfo{$key});
            }
            $cs->flush;
            $self->status('Login succeeded.');
        }
    }
    else {
        ## Valid session cookie was found
        $self->is_logged_in(1);
    }
    $self->cs($cs);  ## set member object
    return $self;
}

########################################################################################
##
########################################################################################
sub param {
    my $self = shift;
    my $v = $self->cs->param(@_);
    $self->cs->flush;
    return $v;
}

########################################################################################
##
########################################################################################
sub logout {
    my $self = shift;
    if ($self->cs) {
        $self->cs->delete;
        $self->cs->flush;
    }
    $self->is_logged_in(0);
    $self->status('You have been logged out.');
    return $self;
}

########################################################################################
##
########################################################################################
sub _check_user {
    my($u, $p) = @_;

    my $ws = SOAP::Lite->service(_getWsdl());  ## see sessionsconf.pl
    my $cid = $ws->getCompanyId('my.uen.org');
    my $authd = $ws->authenticateByScreenName($cid, $u, $p);
    my $tid = $ws->getTeacherIdByScreenName($cid, $u) if $authd;

    my $salt = join '', ('.', '/', 0..9, 'A'..'Z', 'a'..'z')[rand 64, rand 64];
    my $pwhash = crypt($p, $salt);  ## crypt is a Perl primitive - c.f. man perlfunc
    return (authenticated => $authd, username => $u, password => $pwhash, teacher_id => $tid);
}

########################################################################################
##
########################################################################################
sub DESTROY {
    my $self = shift;
    ## This method is called just before the object is deallocated
    if ($self->cs) {
        $self->cs->flush;
        $self->cs->DESTROY;
    }
    $self->{_dbh}->disconnect if ref $self->{_dbh};
}

########################################################################################
##
########################################################################################
sub AUTOLOAD {
    my $self = shift;
    ## Any method called against this class which is NOT explicitly defined above will cause
    ## a dispatch to this method. The method name actually called is stored in $AUTOLOAD. In
    ## other words, this is a catch-all that easily allows the "wrapper" object (UEN::Session)
    ## to "inherit" and override the behavior of the CGI::Session object that it contains
    ## (though not in the usual OO sense of that word).
    croak "$self is not an object!" unless ref $self;

    my $name = $AUTOLOAD;
       $name =~ s/.*://;  ## remove fully-qual package name prefix

    if ($name =~ /^_/) {
        carp "Access to private attributes not allowed";
    }
    elsif (exists $self->{$name}) {
        ## Getter/setter for attributes of this class - they must already exist in object!
        if (@_) {
            $self->{$name} = shift;
        }
        elsif ($name eq 'cs') {
            unless ($self->{cs}) {
                croak "UEN::Session has no CGI::Session object";
            }
        }
        $self->{$name};
    }
    elsif ($self->cs) {
        ## Inheritance: try to call method against contained CGI::Session object
        $self->cs->$name(@_);
    }
    else {
        croak "No such method $name, or no CGI::Session object found";
    }
}

1;
__END__
=pod

=head1 DESCRIPTION

This class "has-a" (i.e. "wraps" a) CGI::Session, which takes care of the nitty-gritties of
session management, while the present class handles authentication and any other UEN-specific details.

Whenever a session is accessed, its expiration timer is reset to the full timeout value.

=head1 METHODS

new (%args)

  Arguments may be given either as a hash, or hash reference. The creation of a session object finds
  and initializes in the new object any currently valid session that may exist, however if login
  credentials (user/pass) are given, any existing session is lost (regardless of whether credentials
  are good or not).

  Currently recognized arguments (all optional):

   user    a UEN username
   pass    password for the above username

header

  Inherited from CGI::Session - outputs HTTP headers (notably Content-Type and Set-Cookie).
  You should be using this to generate HTTP headers, and as long as you are, you shouldn't
  need to worry about what's going on underneath. Use of this method is necessary to ensure
  the session is kept alive!

is_logged_in

  Returns true if session object is currently valid and logged in, else false.

logout

  Terminate any existing session.

This class inherits all the other methods of CGI::Session (version 4.42 at the time of this writing).
See documentation for that class for what methods are available and what the calling conventions are:

 http://search.cpan.org/search?query=CGI::Session

=head1 EXAMPLES

Typically, use of this module will appear near the top of a CGI script, for what
should be obvious reasons.

In a script which receives form data containing login credentials, you'll have something
like this:

  my $session = new UEN::Session ( user => $myform{username}, pass => $myform{password} );
  print $session->header;

In case a valid session is expected to exist and there are no login credentials
available in the present script, call new() with no parameters:

  my $session = new UEN::Session ();
  print $session->header;
  if (not $session->is_logged_in) {
     ## take appropriate action
  }

If a user-generated logout event can be expected, you may have something like the following.
Note that logout() and header() are always safe to call on a UEN::Session object, regardless
of whether there is an existing session or not. In particular, header() will always generate 
appropriate HTTP headers.

  my $session = new UEN::Session ();
  if ( logout_button_was_pressed() ) {
      $session->logout;
  }
  print $session->header;
  if (not $session->is_logged_in) {
     ## take appropriate action
  }

And if the goal is to force a logout:

  my $session = new UEN::Session ();
  $session->logout;
  print $session->header;
  print "You are now logged out.";

Get the idea? :-) For examples of the use of methods inherited from CGI::Session, see the documentation
for that class (referenced above).

=head1 TODO

 * see about having cgi apps bypass login screens if they find a session (review how my.uen
    "SSO" works)

=head1 AUTHOR

David J Iannucci <dji@uen.org>

=head1 VERSION

 $Id: Session.pm,v 1.3 2011/02/07 21:59:02 dji Exp $

=cut
