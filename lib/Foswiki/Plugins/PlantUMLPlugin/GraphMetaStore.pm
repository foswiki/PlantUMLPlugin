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

package Foswiki::Plugins::PlantUMLPlugin::GraphMetaStore;

# Always use strict to enforce variable scoping
use strict;
use warnings;

use Foswiki::Func ();    # The plugins API
use Foswiki::Contrib::XMLStoreContrib;
use Foswiki::Plugins::PlantUMLPlugin::GraphMeta;

use vars qw(@ISA);
@ISA = ('Foswiki::Contrib::XMLStoreContrib');

my $rootName = "umlindex";        # root node name
my $xmlFile  = "umlindex.xml";    # name of file containing config
my $childNN = $Foswiki::Plugins::PlantUMLPlugin::GraphMeta::childNN;

sub new {
    my $class = shift;

    # FIX surely there's a way to get the plugin name?
    return $class->SUPER::new( "PlantUMLPlugin", $xmlFile, $rootName,
        $Foswiki::Plugins::PlantUMLPlugin::GraphMeta::nodeName );
}

sub updateDocFromParams {
    my ( $self, $params, $hashCode, $web, $topic ) = @_;

  #Foswiki::Func::writeDebug("GraphMetaStore::updateDocFromParams $web $topic");
  # copy for modification
    my %opts = %{$params};
    $opts{'web'}   = $web;
    $opts{'topic'} = $topic;
    $opts{'id'}    = $hashCode;
    my $newObj  = Foswiki::Plugins::PlantUMLPlugin::GraphMeta::->new( \%opts );
    my $newNode = $newObj->{'node'};
    my $oldNode = undef;
    my $oldNodeList = $self->getNodeList(
        "[\@web='$web' and \@topic='$topic' and \@id='$hashCode']");
    $oldNode = $oldNodeList->get_node(1)
      if defined $oldNodeList;
    return $self->SUPER::updateDocFromNodes( $oldNode, $newNode );
}

# Move nodes using the given oldWeb.oldTopic to newWeb.newTopic
sub moveWikiPage {
    my ( $self, $oldWeb, $oldTopic, $newWeb, $newTopic ) = @_;
    my $rv = 0;

    # move top-level elements
    $rv = $self->SUPER::moveWikiPage( $oldWeb, $oldTopic, $newWeb, $newTopic );

    # move child elements
    $rv =
      $self->SUPER::moveWikiPage( $oldWeb, $oldTopic, $newWeb, $newTopic,
        "/$childNN" )
      || $rv;
    return $rv;
}

sub getAttachmentsByTopic {
    my ( $self, $web, $topic ) = @_;
    return $self->getNodeList(
        "/" . $childNN . "[\@web='$web' and \@topic='$topic']" );
}

1;
