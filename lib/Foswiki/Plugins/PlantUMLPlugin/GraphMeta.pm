# Copyright 2015 Applied Research Laboratories, the University of
# Texas at Austin.
#
#    This file is part of DoxygenPlugin.
#
#    DoxygenPlugin is free software: you can redistribute it and/or
#    modify it under the terms of the GNU General Public License as
#    published by the Free Software Foundation, either version 3 of
#    the License, or (at your option) any later version.
#
#    DoxygenPlugin is distributed in the hope that it will be
#    useful, but WITHOUT ANY WARRANTY; without even the implied
#    warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
#    See the GNU General Public License for more details.
#
#    You should have received a copy of the GNU General Public License
#    along with DoxygenPlugin.  If not, see <http://www.gnu.org/licenses/>.
#
# Author: John Knutson
#
# Provide a mechanism for linking to Doxygen-generated diagrams.

package Foswiki::Plugins::PlantUMLPlugin::GraphMeta;

# Always use strict to enforce variable scoping
use strict;
use warnings;

use Foswiki::Func ();    # The plugins API
use Foswiki::Contrib::XMLStoreContrib::Element;

our $nodeName = "dia";           # name of diagram node
our $childNN  = "attachment";    # name of generated file info node

use vars qw(@ISA);
@ISA = ('Foswiki::Contrib::XMLStoreContrib::Element');

# constructor
sub new {
    my ( $class, $params ) = @_;
    my $self;

    $self = $class->SUPER::new($nodeName);
    $self->{'node'}->setAttribute( "web", $params->{'web'} )
      if defined $params->{'web'};
    $self->{'node'}->setAttribute( "topic", $params->{'topic'} )
      if defined $params->{'topic'};
    $self->{'node'}->setAttribute( "id", $params->{'id'} )
      if defined $params->{'id'};

    return bless( $self, $class );
}

# construct a new PlantUMLPlugin::GraphMeta from an XML::LibXML::Element
sub fromXML {
    my ( $class, $node ) = @_;
    my $self;

   #Foswiki::Func::writeDebug("Application::fromXML $node->getAttribute('id')");
    $self = $class->SUPER::fromXML($node);
    return bless( $self, $class );
}

# add attachment child nodes
sub attach {
    my ( $self, %opts ) = @_;
    my $childNode = new XML::LibXML::Element($childNN);
    $childNode->setAttribute( "name",  $opts{'name'} );
    $childNode->setAttribute( "web",   $opts{'PLANTweb'} );
    $childNode->setAttribute( "topic", $opts{'PLANTtopic'} );
    $childNode->setAttribute( "type",  $opts{'PLANTtype'} );
    $self->{'node'}->addChild($childNode);
}

1;
