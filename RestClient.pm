=pod

=head1 NAME

UEN::RestClient - Local wrapper to abstract implementation details of HTTP client operations

UEN::RestClient::Response - Response object returned by UEN::RestClient methods

UEN::WS::XML::Element - Ultimate ancestor class for all XML elements

=head1 SYNOPSIS

  use UEN::RestClient;
  my $rc = new UEN::RestClient ( service => 'http://uen.org/FooService' );
  my $resp = $rc->get('/resource/list');
  if ($resp->is_success) {
      my($result, $def) = $resp->getObjects( superclass => 'Foo::Base' );
      eval $def; die $@ if $@;
      print $result->toString;
  }

=cut
package UEN::RestClient;

use strict;   ## remove this line under penalty of death :-|
use 5.8.0;
use LWP::UserAgent;
use Carp;

our $AUTOLOAD;

########################################################################################
## Constructor - takes a hash of optional parameters
########################################################################################
sub new {
    my $self = shift;
    my $class = ref($self) || $self;
    my %args = ref($_[0]) eq 'HASH' ? %{$_[0]} : @_;  ## accept bare hash, or hash reference
    croak 'Bad service' unless $args{service} =~ /^(http:.*|)$/; ## full URL or empty ok

    $self = bless { ua => undef, service => undef, %args }, $class;

    my $ua = new LWP::UserAgent ();
    $self->ua($ua);   ## set member object
    return $self;
}

########################################################################################
## HTTP method GET
########################################################################################
sub get {
    my $self = shift;
    my $url = _makeURL($self->service, shift);
    my %args = @_;
    $args{Accept} ||= 'application/xml';  ## default to XML response
    UEN::RestClient::Response->new($self->ua->get($url, %args));
}

########################################################################################
## HTTP method HEAD
########################################################################################
sub head {
    my $self = shift;
    my $url = _makeURL($self->service, shift);
    my %args = @_;
    $args{Accept} ||= 'application/xml';  ## default to XML response
    UEN::RestClient::Response->new($self->ua->head($url, %args));
}

########################################################################################
## HTTP method POST
########################################################################################
sub post {
    my $self = shift;
    carp "POST not yet implemented.";
}

########################################################################################
## HTTP method PUT
########################################################################################
sub put {
    my $self = shift;
    carp "PUT not yet implemented.";
}

########################################################################################
## HTTP method DELETE
########################################################################################
sub delete {
    my $self = shift;
    carp "DELETE not yet implemented.";
}

########################################################################################
## Return a string identifying what sort of entity this is
########################################################################################
sub agent {
    my $self = shift;
    my $uaagent = $self->ua && $self->ua->agent;   ## a slick way of checking for null
    my($rev) = (q($Revision: 1.20 $) =~ / ([\d.]+) /); ## editing of this line is discouraged
    __PACKAGE__."/$rev ($uaagent)";
}

########################################################################################
## Compose a full resource URL based on parts provided
########################################################################################
sub _makeURL {
    my($service, $u) = @_;
    return $u if $u =~ /^http:/;
    croak "Cannot use relative URL $u if no service defined" unless $service;
    $service =~ s#/*$##;  ## remove trailing slashes, to ensure no doubling
    $u =~ s#^/*##;        ## remove leading slashes, to ensure no doubling
    "$service/$u";
}

########################################################################################
## Destructor - called by Perl just before the object is deallocated
########################################################################################
sub DESTROY {
    my $self = shift;
    if ($self->ua) {
        ## $self->ua->??????;
        $self->ua->DESTROY;
    }
}

########################################################################################
## Any method called against this class which is NOT explicitly defined above will cause
## a dispatch to this method. The method name actually called is stored in $AUTOLOAD. In
## other words, this is a catch-all that allows the "wrapper" object (UEN::RestClient)
## to "inherit" and override the behavior of the LWP::UserAgent object that it contains
## (though not strictly in the usual OO sense).
########################################################################################
sub AUTOLOAD {
    my $self = shift;
    croak "$self is not an object!" unless ref $self;

    my $name = $AUTOLOAD;
       $name =~ s/.*://;  ## remove fully-qual package name prefix

    if ($name =~ /^_/) {
        carp "Access to private fields not allowed";
    }
    elsif (exists $self->{$name}) {
        ## Getter/setter for fields of this class - they must already exist in object hash!
        if (@_) {
            $self->{$name} = shift;
        }
        elsif ($name eq 'ua') {
            unless ($self->{ua}) {
                croak "UEN::RestClient object has no LWP::UserAgent object";
            }
        }
        $self->{$name};
    }
    elsif ($self->ua) {
        ## Inheritance: try to call method against contained object
        $self->ua->$name(@_);
    }
    else {
        croak "No such method $name, or no LWP::UserAgent object found";
    }
}

########################################################################################
########################################################################################
########################################################################################
## Response object returned by UEN::RestClient - not (normally) directly instantiated
package UEN::RestClient::Response;

use strict;             ## remove this line under penalty of death :-|
use HTTP::Response;
use XML::Parser;
use Carp;

our $AUTOLOAD;

########################################################################################
## Constructor - takes an HTTP::Response as parameter and "decorates" it
########################################################################################
sub new {
    my $self = shift;
    my $class = ref($self) || $self;
    my($hr) = @_;
    croak "Need an HTTP::Response" unless ref($hr) eq 'HTTP::Response';
    $self = bless { hr => $hr, type => undef, parser => undef }, $class;
    $self->type($hr->request->header('Accept')); ## Set MIME type to what I asked for

    if ($self->type =~ /xml/i) {
        my $parser = new XML::Parser (
                        Style => 'Objects',
                        Pkg => 'UEN::WS::XML', ## a default that's normally not used
                        ErrorContext => 6
                    ) or croak 'Cannot create XML::Parser';
        $self->parser($parser);
    }
    return $self;
}

########################################################################################
##
########################################################################################
sub getObjects {
    my $self = shift;
    croak "Can only make objects from XML" unless $self->type =~ /xml/i;

    my %args = ref($_[0]) eq 'HASH' ? %{$_[0]} : @_;  ## accept bare hash, or hash reference
    my %parser_options;
    $parser_options{Pkg} = $args{superclass} if $args{superclass};
    my $content = $self->decoded_content;
    return (undef, undef) if not $content;

    my($ob, $def);
    eval {
        my $res = $self->parser->parse($content, %parser_options);
        $ob = $res->[0];
        $def = _generateClassDef($ob, $parser_options{Pkg});
    };
    if ($@) {
        croak "Cannot parse response or cannot generate class definitions: $@";
    }
    return ($ob, $def);
}

########################################################################################
## See comment for UEN::RestClient::AUTOLOAD, and s/LWP::UserAgent/HTTP::Response/g
########################################################################################
sub AUTOLOAD {
    my $self = shift;
    croak "$self is not an object!" unless ref $self;

    my $name = $AUTOLOAD;
       $name =~ s/.*://;  ## remove fully-qual package name prefix

    if ($name =~ /^_/) {
        carp "Access to private fields not allowed";
    }
    elsif (exists $self->{$name}) {
        ## Getter/setter for attributes of this class - they must already exist in object hash!
        if (@_) {
            $self->{$name} = shift;
        }
        elsif ($name eq 'hr') {
            unless ($self->{hr}) {
                croak "UEN::RestClient::Response object has no HTTP::Response object";
            }
        }
        $self->{$name};
    }
    elsif ($self->hr) {
        ## Inheritance: try to call method against contained object
        $self->hr->$name(@_);
    }
    else {
        croak "No such method $name, or no HTTP::Response object found";
    }
}

########################################################################################
##
########################################################################################
sub _generateClassDef {
    my($object, $superclass) = @_;
    $superclass ||= 'UEN::WS::XML::Element';  ## default value if not specified
    our %Classes;
    my $code;

    _findClasses($object);
    foreach my $class (sort keys %Classes) {
        $code .= "package $class; our \@ISA = qw($superclass);\n";
    }
    return $code;

    sub _findClasses {
        my $o = shift;
        $Classes{ref($o)} = 1;
        foreach my $kid (@{ $o->{Kids} }) {
            _findClasses($kid);
        }
    }
}

########################################################################################
########################################################################################
########################################################################################
## Ultimate ancestor class for all XML elements - not (normally) directly instantiated
package UEN::WS::XML::Element;

use strict;       ## remove this line under penalty of death :-|
use Carp;

########################################################################################
## Constructor - creates a simple object containing only text data (string)
########################################################################################
sub new {
    my $self = shift;
    my $class = ref($self) || $self;
    bless { Text => shift } , $class;
}

########################################################################################
## Get the element name for this object
########################################################################################
sub getName {
    my $self = shift;
    my $pkg = ref $self;
    $pkg =~ s/.*:://;     # truncate fully-qualified package prefix
    return $pkg;
}

########################################################################################
## Get member sub-objects contained within; can match their names by regex
########################################################################################
sub getMembers {
    my $self = shift;
    my $elname = shift;
    my $pat = $elname ? qr/^$elname$/i : qr/.*/o;

    my @set = grep { $_->getName =~ $pat } @{$self->{Kids}};
    if (not(wantarray) && @set > 1) {
        confess "Multiple members found where only one expected: name pattern=$pat";
    }
    return wantarray ? @set : shift(@set);
}

########################################################################################
## Get text data content from a member
########################################################################################
sub getText {
    my $self = shift;
    if (exists $self->{Text}) {
        return $self->{Text};
    }
    my @mem = $self->getMembers;
    @mem == 1 ? $mem[0]->getText : confess 'Cannot get Text from a ' . ref($self);
}

########################################################################################
## A convenience method to get at the content of a "simple" member/property
########################################################################################
sub getField {
    my $self = shift;
    my $name = shift;
    $self->getMembers($name)->getText;
}

########################################################################################
## Convert object to string form for human-readable output
########################################################################################
sub toString {
    my $self = shift;
    my $level = int(shift);
    my $attrsdisp;
    if (my $attrs = shift) {
        $attrsdisp = join(' ', map { $_.'='.$attrs->{$_} } sort keys %{$attrs});
    }

    my $indent = (' ' x 4) x $level;
    my $str;   ## the eventual output
    eval {
        my $text = $self->getText;  ## This will throw an exception if not an XML leaf node
        $attrsdisp = "[$attrsdisp]" if $attrsdisp;
        $str .= sprintf qq(%s%s%s => "%s"\n), $indent, $self->getName, $attrsdisp, $text;
    };
    if ($@) {
        ## If exception was thrown, this must be a non-leaf (i.e. internal) node
        $attrsdisp = ' '.$attrsdisp if $attrsdisp;
        $str .= sprintf "%s[%s%s]\n", $indent, $self->getName, $attrsdisp;
        foreach my $m ($self->getMembers) {
            $str .= $m->toString($level + 1);
        }
        $str .= sprintf "%s[/%s]\n", $indent, $self->getName;
    }
    return $str;
}

1;
__END__
=pod

=head1 DESCRIPTION

To be written.

=head1 AUTHOR

David J Iannucci <dji@uen.org>

=head1 VERSION

 $Id: RestClient.pm,v 1.20 2011/06/27 20:26:28 dji Exp $

=cut
