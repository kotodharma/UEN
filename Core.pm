=pod

=head1 NAME

UEN::Core - Interface to CCSERV and superclass for all Core Curriculum objects

=cut
package UEN::Core;

use strict;    ## remove this line under penalty of death :-|
use 5.8.0;
use UEN::RestClient;
use UEN::Lib qw(domain_host);
use Exporter;
use Carp;

our @ISA = qw(UEN::WS::XML::Element Exporter);  ## "extends UEN::WS::XML::Element"
our @EXPORT = qw(&cacheGrab);
our @EXPORT_TYPICAL = qw(&setCoreSort &coreSort);
our @EXPORT_EXPERT = qw(&_getCoreData &_getCoreObject);
our @EXPORT_OK = (@EXPORT_TYPICAL, @EXPORT_EXPERT);
our %EXPORT_TAGS = ( 'all' => [@EXPORT, @EXPORT_TYPICAL],
                     'expert' => [@EXPORT, @EXPORT_EXPERT] );

## Class attributes (Not specific to an object, but global to the class)
our %Cache;  ## The indexed cache of core curriculum objects
our $rc;     ## The UEN::RestClient object
our($sort_field, $sort_direc, $sort_type);  ## Sorting parameters

my $ccserv_host = domain_host('ccserv');
my $standard_service = "http://$ccserv_host:8080/CoreCurriculumService";

##################### Constructor/initializers #####################

sub new {
    my $class = shift;
    $class->SUPER::new(@_);  ## just call parent constructor
}

sub initialize {
    my $class = shift;
    croak 'initialize: not an instance method' if ref($class);
    my %args = @_;
    croak 'initialize: no service specified' unless $args{service};
    return if ref($rc) eq 'UEN::RestClient'; ## already initialized
    $args{service} = $standard_service if $args{service} eq ':standard';

    eval {
        $rc = new UEN::RestClient( service => $args{service} );
        die "unknown error" unless ref($rc) eq 'UEN::RestClient';
    };
    if ($@) {
        croak "initialize: Failed to create UEN::RestClient: $@";
    }
}

##################### Instance methods #####################

sub parent {
    my $self = shift;
    my $name = $self->getName;
    if (@_) {
        croak "$name cannot have a parent" unless $name =~ /standard|objective|indicator/i;
        $self->{parent} = shift;
        return $self;  ### allow setter chaining!
    }
    $self->{parent};
}

sub grades {
    my $self = shift;
    my $name = $self->getName;
    if (@_) {
        croak "$name does not have grades" unless $name =~ /course/i;
        push(@{$self->{Kids}}, shift);  ## make it a "Kid", to look like it came from CCSERV!
        return $self;  ### allow setter chaining!
    }
    $self->getMembers(qr/grades?(lite)?/);
}

sub isEmpty {
    my $self = shift;
    if (@_) {
        $self->{empty} = shift() ? 1 : 0;
        return $self;  ### allow setter chaining!
    }
    $self->{empty};
}

sub isLite {
    my $self = shift;
    $self->getName =~ /lite/i;
}

sub toString {
    my $self = shift;
    my $level = int(shift);
    my %attrs;
    ### Set attributes in hash only if properties "have content"
    $self->parent  && ($attrs{parent} = $self->parent);
    $self->isEmpty && ($attrs{empty} = 'true');
    $self->isLite  && ($attrs{lite} = 'true');

    $self->SUPER::toString($level, \%attrs);
}

##################### Class methods #####################

sub populateGradesByCourse {
    my $class = shift;
    croak 'populateGradesByCourse: not an instance method' if ref($class);
    my($course) = @_;
    my @grade_objs;
    if ($course->grades) {
        @grade_objs = $course->grades->getMembers;
    }
    else {
        my $number = $course->getField('number');
        my $uri = "/grade/list/course/$number";
        eval {
            my $container = _getCoreObject($uri); ## 'grades' container object
            @grade_objs = $container->getMembers; ## might be empty
            $course->grades($container);  ## add as child to Course
        };
        if ($@) {
            croak "Failure in loading/caching core uri $uri: $@";
        }
    }
    map { $_->getField('gradeId') } @grade_objs;
}

## Gets/caches all of some small category: subjects, grades, etc?
sub populateAll {
    my $class = shift;
    croak 'populateAll: not an instance method' if ref($class);
    my($cat) = @_;
    unless ($Cache{all}{$cat}) {
        my $uri = "/$cat/lite/list";
        eval {
            my $container = _getCoreObject($uri);
            my @things = $container->getMembers;
            die "No ${cat}s found!" if @things < 1;  ## we fully expect these to exist
            map { _addToCache($_) } @things;
            $Cache{all}{$cat} = 1;
        };
        if ($@) {
            croak "Failure in loading/caching core uri $uri: $@";
        }
    }
    my @things = values %{ $Cache{$cat} };
    return wantarray ? @things : scalar(@things);
}

## Gets/caches courses associated with member of some other category: subject, grade, etc?
sub populateCoursesBy {
    my $class = shift;
    croak 'populateCoursesBy: not an instance method' if ref($class);
    my($cat, $id, $lite) = @_;
    my $c_list = $Cache{courses_by}{$cat}{$id};
    unless ($c_list) {
        my $uri = $lite ? "/course/lite/list/$cat/$id" : "/course/list/$cat/$id";
        eval {
            my $container = _getCoreObject($uri);
            my @courses = $container->getMembers;  ## might well be empty
            map { _addToCache($_) } @courses;
            $c_list = $Cache{courses_by}{$cat}{$id} =
                    [ map { $_->getField('number') } @courses ];
        };
        if ($@) {
            croak "Failure in loading/caching core uri $uri: $@";
        }
    }
    my @courses = map { $Cache{course}{$_} } @{ $c_list };
    return wantarray ? @courses : scalar(@courses);
}

sub populateCourseAndReturn {
    my $class = shift;
    croak 'populateCourseAndReturn: not an instance method' if ref($class);
    my($item, $id) = @_;
    my $index = ($item eq 'course') ? 'course' : 'soi';
    my $ci = $Cache{$index}{$id};  ## This core item object's location in the Cache
    unless ($ci) {
        my $uri = ($item eq 'course') ? "/course/$id" : "/course/$item/$id";
        eval {
            my $course = _getCoreObject($uri);
            if ($course->isEmpty) {
                $ci = $course; ## one empty Core object's as good as another
            }
            else {
                _addToCache($course);
                $ci = $Cache{$index}{$id} || die "$item=$id not found after adding Course!";
            }
        };
        if ($@) {
            croak "Failure in loading/caching core uri $uri: $@";
        }
    }
    return $ci;
}

## Pull stuff out of the cache - just "walk" the hash of hashes
sub cacheGrab {
    my $index = shift;
    croak 'cacheGrab: not an instance method' if ref($index);
    my $loc = $index;
    my $r = $Cache{$index};
    while (defined(my $next = shift)) {
        $loc .= "->$next";
        eval {
            $r = $r->{$next};
        };
        confess "Bad cache address $loc" if $@;
    }
    defined($r) ? $r : confess "Expected item not found at cache address $loc";
}

## Set parameter values (which are persistent class attributes) to be used by coreSort()
## Default values dir => asc, type => lex are reset each time this function is called, so
## no worries about residual (unspecified default) settings causing trouble.
sub setCoreSort {
    my %args = @_;
    $sort_field = $args{field} || croak 'setCoreSort: no field specified';
    $sort_direc = $args{dir} || 'asc';
    $sort_type = $args{type} || 'lex';
}

## Universal comparator routine for sorting Core objects - prototype ($$) required!
sub coreSort ($$) {
    my($a, $b) = ($sort_direc eq 'desc') ? ($_[1], $_[0]) : ($_[0], $_[1]);
    my $comp = ($sort_type eq 'num') ? sub { $_[0] <=> $_[1] } : sub { $_[0] cmp $_[1] };
    $comp->($a->getField($sort_field), $b->getField($sort_field));
}

##################### "Private" internal functions #####################

sub _getCoreData {
    my($resource) = @_;
    croak "_getCoreData: not an instance method!" if ref($resource);
    my $resp = $rc->get($resource);
    croak "_getCoreData ($resource): " . $resp->message if not $resp->is_success;
    return $resp;
}

sub _getCoreObject {
    my($resource) = @_;
    croak "_getCoreObject: not an instance method!" if ref($resource);
    my $emptyobj = UEN::Core->new('No data')->isEmpty('true');

    my $resp = _getCoreData($resource);
    if ($resp->code == 204) {
        return $emptyobj;
    }
    my($result, $def) = $resp->getObjects( superclass => 'UEN::Core' );
    eval $def; ## import into execution context the class def'ns for objects retrieved
    croak $@ if $@;
    return ($result || $emptyobj);
}

sub _addToCache {
    my($obj, $parent) = @_;
    return if $obj->isEmpty; ## don't cache empty objects
    my $class = ref($obj) || 'non-object';
    $class =~ s/.*:://;      ## strip off fully-qualified package prefix
    $obj->parent($parent) if $parent;

    if ($class =~ /(grade|subject)s?(lite)?/i) {
        my $cat = $1;
        my $lite = $2;
        my $id = $obj->getField($cat.'Id');
        unless ($Cache{$cat}{$id} && $lite) {
            $Cache{$cat}{$id} = $obj;  ## Assign Cache pointer to object
        }
    }
    elsif ($class =~ /courses?(lite)?/i) {
        my $lite = $1;
        my $id = $obj->getField('number');
        unless ($Cache{course}{$id} && $lite) {
            $Cache{course}{$id} = $obj;  ## Assign Cache pointer to object
        }
        ## Index its subject(s?)
        map { _addToCache($_) } $obj->getMembers(qr/subjects?(lite)?/);

        ## Index its standards, recursively
        map { _addToCache($_, $id) } $obj->getMembers(qr/standards?(lite)?/);
    }
    elsif ($class =~ /standards?(lite)?/i) {
        my $lite = $1;
        my $id = $obj->getField('standardId');
        unless ($Cache{soi}{$id} && $lite) {
            $Cache{soi}{$id} = $obj;  ## Assign Cache pointer to object
        }
        ## Index its objectives, recursively
        map { _addToCache($_, $id) } $obj->getMembers(qr/objectives?(lite)?/);
    }
    elsif ($class =~ /objectives?(lite)?/i) {
        my $lite = $1;
        my $id = $obj->getField('objectiveId');
        unless ($Cache{soi}{$id} && $lite) {
            $Cache{soi}{$id} = $obj;  ## Assign Cache pointer to object
        }
        ## Index its indicators, recursively
        map { _addToCache($_, $id) } $obj->getMembers(qr/indicators?(lite)?/);
    }
    elsif ($class =~ /^indicators?(lite)?/i) {
        my $lite = $1;
        my $id = $obj->getField('indicatorId');
        unless ($Cache{soi}{$id} && $lite) {
            $Cache{soi}{$id} = $obj;  ## Assign Cache pointer to object
        }
        ## Index its subindicators, recursively
        map { _addToCache($_, $id) } $obj->getMembers(qr/subindicators?(lite)?/);
    }
    elsif ($class =~ /subindicators?(lite)?/i) {
        my $lite = $1;
        my $id = $obj->getField('subindicatorId');
        unless ($Cache{soi}{$id} && $lite) {
            $Cache{soi}{$id} = $obj;  ## Assign Cache pointer to object
        }
        ## Recursion stops here :-)
    }
    else {
        croak "add to Cache: class $class unknown";
    }
}

1;
__END__
=pod 

=head1 DESCRIPTION

This class has two different but related purposes. First, it is the abstract interface to the Core
Curriculum web service. In this role it queries the web service and caches and indexes the results.
The API for these operations is accessed strictly through the class methods, the internal state in
support of which is initialized using initialize().

Additionally, UEN::Core is also the parent class (immediate superclass) for all of the objects
returned from the web service. Every XML element in the output of the web service becomes an object.
Objects that are simple "properties", such as subjectId, are contained as children within enclosing
objects (e.g. subjectLite), but their respective classes (e.g. UEN::Core::subjectId, UEN::Core::subjectLite)
all extend UEN::Core, regardless of the hierarchical (has-a) relationship of the objects themselves.
In this capacity, only the instance methods of UEN::Core are relevant. Also new(), which can create a new
such object, although it is not normally needed for this purpose, as the objects are physically created
within UEN::RestClient by XML::Parser.

The class exports an API (as part of :all) to allow easy sorting of Core objects on a given simple
object member (call it a "property", such as objectiveId or title). The method setCoreSort() is used
to set the parameters for sorting: sort field (property), direction (asc or desc), and sort type
(lex or num). Ascending and lexical are the defaults and need not be explicitly given. After parameters
have been set, the method coreSort() is then simply passed, naked, to Perl's sort primitive as its comparator.
Sort parameters should normally be reset on each sort call, unless you're darn sure nothing has changed
since the last one.

In its function as superclass, UEN::Core merely provides inherited methods to the objects created by
UEN::RestClient.  Note well: methods called `in the wild' will often be those inherited from UEN::Core's
parent, UEN::WS::XML::Element.

The functions whose names begin with underscore (_) are private to the module and not meant to be
called from outside. Perl, of course, doesn't enforce this, so you're expected to respect it (with the
usual disclaimer of "unless you are an :expert and know WTH you're doing" :-)

The initialize() method requires a service parameter to be specified, however in order to handle
the usual case, and to help avoid extensive mods to CGI apps, the following is accepted:

  UEN::Core->initialize( service => ":standard" );

Here, the string :standard means use the predictable service URL based on the serving environment
the code is running in, which is hard-coded in the module.

=head1 SYNOPSIS

As the interface to the CCSERV web service:

  use UEN::Core qw(:all);
  UEN::Core->initialize( service => 'http://ccserv.uen.org/CoreCurriculumService' );

  my @subjs = UEN::Core->populateAll('subject');
  setCoreSort( field => 'subjectId', dir => 'desc', type => 'num' );
  my @sorted_subjs = sort coreSort @subjs;

  ....etc....

=head1 EXAMPLES

The best examples of how this class is used are found in the CurrTie.pm module in Lessonplan.

=head1 AUTHOR

David J Iannucci <dji@uen.org>

=head1 VERSION

 $Id: Core.pm,v 1.22 2011/07/15 18:19:35 dji Exp $

=cut
