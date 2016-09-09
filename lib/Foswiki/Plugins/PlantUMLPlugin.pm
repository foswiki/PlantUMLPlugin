# Plugin for Foswiki - The Free and Open Source Wiki, http://foswiki.org/
#
# Copyright (C) 2004-2005 Cole Beck, cole.beck@vanderbilt.edu
# Copyright (C) 2006-2008 TWiki Contributors
# Copyright (C) 2009-2010 George Clark and other Foswiki Contributors
# Copyright (C) 2015      Applied Research Laboratories, the University of Texas
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details, published at
# http://www.gnu.org/copyleft/gpl.html
#
# =========================
#
# This plugin creates an image file or files using PlantUML.
# See http://plantuml.sourceforge.net/ for more information.
# Note that attachments created by this plugin can only be deleted manually;
# it stays there even after the plantuml tags are removed.

# Tests:
# 1) single graph on a topic.
#    ? Does it render only once
# 2) 2+ graphs on a topic
#    ? Do they render only once
#    ? Do they render properly (correct graph in correct location)
# 3) Topic rename / delete
#    ? Do the graphs get moved
#    ? Does the data store remove references to the old topic
#    ? Does the data store now have references to the new topic
# 4) Remove a graph from a topic with multiple graphs
#    ? Do the excess attachments get trashed
# 5) test various options, output formats, embedded format...

package Foswiki::Plugins::PlantUMLPlugin;

# =========================
use strict;
use warnings;

use Foswiki::Func ();

our $VERSION = '1.0.0';
our $RELEASE = '1.0.0';

# Short description of this plugin
# One line description, is shown in the %SYSTEMWEB%.TextFormattingRules topic:
our $SHORTDESCRIPTION = 'Draw UML diagrams using PlantUML';

# You must set $NO_PREFS_IN_TOPIC to 0 if you want your plugin to use
# preferences set in the plugin topic. This is required for compatibility
# with older plugins, but imposes a significant performance penalty, and
# is not recommended. Instead, leave $NO_PREFS_IN_TOPIC at 1 and use
# =$Foswiki::cfg= entries set in =LocalSite.cfg=, or if you want the users
# to be able to change settings, then use standard Foswiki preferences that
# can be defined in your %USERSWEB%.SitePreferences and overridden at the web
# and topic level.
our $NO_PREFS_IN_TOPIC = 1;

our $pluginName = "PlantUMLPlugin";

#
#  General plugin information
#
my $web;           # Current web being processed
my $usWeb;         # Web name with subwebs delimiter changed to underscore
my $topic;         # Current topic
my $user;          # Current user
my $installWeb;    # Web where plugin topic is installed

#
# Plugin settings passed in URL or by preferences
#
my $debugDefault;          # Debug mode
my $antialiasDefault;      # Anti-alias setting
my $densityDefault;        # Density for Postscript document
my $formatsDefault;        # Types of images to be generated
my $hideAttachDefault;     # Should attachments be shown in the attachment table
my $inlineAttachDefault;   # Image type that will be shown inline in the topic

# Should other file types have links shown under the inline image
my $linkAttachmentsDefault;

# File graphics type attached as fallback for browsers without svg support
my $svgFallbackDefault;
my $svgLinkTargetDefault;    #

#
# Locations of the commands, etc. passed in from LocalSite.cfg
#
my $plantJar;         # Location of the "plantuml" command
my $magickPath;       # Location of ImageMagick
my $toolsPath;        # Location of the Tools directory for helper script
my $attachPath;       # Location of attachments if not using Foswiki API
my $attachUrlPath;    # URL to find attachments
my $perlCmd;          # perl command
my $javaCmd;          # java command

#
# Module storage
#
my %grNum;             # graph number within a single page (hash from web.topic)
my %tmpDirs;           # hash from web.topic to array of temporary directories
my %renderAttachments; # hash from web.topic to array of rendered attachments

my $HASH_CODE_LENGTH = 32;

#
# Documentation on the sandbox command options taken from Foswiki/Sandbox.pm
#
# '%VAR%' can optionally take the form '%VAR|FLAG%', where FLAG is a
# single character flag.  Permitted flags are
#   * U untaint without further checks -- dangerous,
#   * F normalize as file name,
#   * N generalized number,
#   * S simple, short string,
#   * D rcs format date

my $antialiasCmd =
  'convert -density %DENSITY|N% -geometry %GEOMETRY|S% %INFILE|F% %OUTFILE|F%';
my $identifyCmd = 'identify %INFILE|F%';

my $errFmtStart = "<nop>PlantUMLPlugin Error: ";
my $errFmtEnd   = "";

=begin TML

---++ macroError($session, $message) -> $text
   * =$session= - a reference to the Foswiki session object
   * =$message= - the contents of the error message
Return: a formatted error message for macros

=cut

sub macroError {
    my $message = shift;
    return $Foswiki::Plugins::SESSION->inlineAlert( 'alerts', 'generic',
        $errFmtStart . $message . $errFmtEnd );
}

sub isRenderContext {

    #  "Disable" the plugin if a topic revision is requested in the query.
    my $query;
    if ( $Foswiki::Plugins::VERSION >= 2.1 ) {
        $query = Foswiki::Func::getRequestObject();
    }
    else {
        $query = Foswiki::Func::getCgiQuery();
    }

    if ( $query && $query->param('rev') ) {
        if ( !$Foswiki::cfg{Plugins}{PlantUMLPlugin}{generateRevAttachments} ) {
            _writeDebug('PlantUMLPlugin - Disabled  - revision provided');
            return 0;
        }
    }

    #  Disable the plugin if comparing two revisions (context = diff
    my $context = Foswiki::Func::getContext();
    if ( $context->{'diff'} ) {
        if ( !$Foswiki::cfg{Plugins}{PlantUMLPlugin}{generateDiffAttachments} )
        {
            _writeDebug('PlantUMLPlugin - Disabled  - diff context');
            return 0;
        }
    }
    return 1;
}

# =========================
sub initPlugin {
    ( $topic, $web, $user, $installWeb ) = @_;

    #SMELL: topic and web are tainted when using Locales
    $topic = Foswiki::Sandbox::untaintUnchecked($topic);
    $web   = Foswiki::Sandbox::untaintUnchecked($web);

    $grNum{"$web.$topic"} = 0;

    if ( !isRenderContext() ) {
        return 1;
    }

    $usWeb = $web;
    $usWeb =~ s/\//_/g;    #Convert any subweb separators to underscore

    # check for Plugins.pm versions
    if ( $Foswiki::Plugins::VERSION < 1 ) {
        Foswiki::Func::writeWarning(
            'Version mismatch between PlantUMLPlugin and Plugins.pm');
        return 0;
    }

    # path to plantuml.jar
    $plantJar = $Foswiki::cfg{Plugins}{PlantUMLPlugin}{plantJar}
      || '/usr/local/bin/plantuml.jar';

    # path to imagemagick convert routine
    $magickPath = $Foswiki::cfg{Plugins}{PlantUMLPlugin}{magickPath} || '';

    # path to Plugin helper script
    $toolsPath = $Foswiki::cfg{Plugins}{PlantUMLPlugin}{toolsPath}
      || $Foswiki::cfg{ToolsDir};

    # If toolsPath is not set, guess the current directory.
    if ( !$toolsPath ) {
        use Cwd;
        $toolsPath = getcwd;
        $toolsPath =~ s/\/[^\/]+$/\/tools/;
    }

    # Fix the various paths - trim whitespace and add a trailing slash
    # if none is provided.

    $toolsPath =~ s/\s+$//;
    $toolsPath .= '/' unless ( substr( $toolsPath, -1 ) eq '/' );
    if ($magickPath) {
        $magickPath =~ s/\s+$//;
        $magickPath .= '/' unless ( substr( $magickPath, -1 ) eq '/' );
    }

    # path to store attachments - optional.  If not provided, Foswiki
    # attachment API is used
    $attachPath = $Foswiki::cfg{Plugins}{PlantUMLPlugin}{attachPath} || '';

    # URL to retrieve attachments - optional.  If not provided,
    # Foswiki pub path is used.
    $attachUrlPath = $Foswiki::cfg{Plugins}{PlantUMLPlugin}{attachUrlPath}
      || '';

    # path to perl interpreter
    $perlCmd = $Foswiki::cfg{Plugins}{PlantUMLPlugin}{perlCmd} || 'perl';

    # path to java VM
    $javaCmd = $Foswiki::cfg{Plugins}{PlantUMLPlugin}{javaCmd} || 'java';

    # Get plugin debug flag
    $debugDefault = Foswiki::Func::getPreferencesFlag('PLANTUMLPLUGIN_DEBUG');

    _writeDebug(' >>> initPlugin Entered');

    # Get plugin antialias default
    $antialiasDefault =
      Foswiki::Func::getPreferencesValue('PLANTUMLPLUGIN_ANTIALIAS')
      || 'off';

    # Get plugin density default
    $densityDefault =
      Foswiki::Func::getPreferencesValue('PLANTUMLPLUGIN_DENSITY')
      || '300';

    # Get plugin formats default
    $formatsDefault =
      Foswiki::Func::getPreferencesValue('PLANTUMLPLUGIN_FORMATS')
      || 'none';

    # Get plugin hideattachments default
    $hideAttachDefault =
      Foswiki::Func::getPreferencesValue('PLANTUMLPLUGIN_HIDEATTACHMENTS')
      || 'on';

    # Get the default inline  attachment default
    $inlineAttachDefault =
      Foswiki::Func::getPreferencesValue('PLANTUMLPLUGIN_INLINEATTACHMENT')
      || 'png';

    # Get the default fallback format for SVG output
    $svgFallbackDefault =
      Foswiki::Func::getPreferencesValue('PLANTUMLPLUGIN_SVGFALLBACK')
      || 'png';

    # Get the default for overriding SVG link target.
    $svgLinkTargetDefault =
      Foswiki::Func::getPreferencesValue('PLANTUMLPLUGIN_SVGLINKTARGET')
      || 'on';

    # Get the default link file attachment default
    $linkAttachmentsDefault =
      Foswiki::Func::getPreferencesValue('PLANTUMLPLUGIN_LINKATTACHMENTS')
      || 'on';

    # Tell WyswiygPlugin to protect <plantuml>...</plantuml> markup.
    # Should this be using UNIVERSAL::can() instead?
    if ( defined &Foswiki::Plugins::WysiwygPlugin::addXMLTag ) {

        # Check if addXMLTag is defined, so that PlantUMLPlugin
        # continues to work with older versions of WysiwygPlugin
        _writeDebug(" DISABLE the plantuml tag in WYSIWYIG ");
        Foswiki::Plugins::WysiwygPlugin::addXMLTag( 'plantuml', sub { 1 } );
    }

    _writeDebug("javaCmd=$javaCmd  plantJar=$plantJar");

    # Plugin correctly initialized
    _writeDebug( "- Foswiki::Plugins::PlantUMLPlugin::initPlugin( $web.$topic )"
          . " initialized OK" );

    return 1;
}    ### sub initPlugin

=begin TML

---++ finishPlugin()

Called when Foswiki is shutting down, this handler can be used by the plugin
to release resources - for example, shut down open database connections,
release allocated memory etc.

Note that it's important to break any cycles in memory allocated by plugins,
or that memory will be lost when Foswiki is run in a persistent context
e.g. mod_perl.

=cut

sub finishPlugin {
    _writeDebug(" >>> finishPlugin Entered");
    _writeDebug(" <<< EXIT finishPlugin");
}

# =========================
sub commonTagsHandler {

    # do not uncomment, use $_[0], $_[1]... instead
    ### my ( $text, $topic, $web ) = @_;

    return if $_[3];    # Called in an include; do not process PLANTUML macros

    if ( !isRenderContext() ) {
        return;
    }

    _writeDebug(' >>> commonTagsHandler Entered');

    $topic = $_[1];     # Can't trust globals
    $web   = $_[2];
    my $meta = $_[4];

    _writeDebug("- PlantUMLPlugin::commonTagsHandler no meta")
      unless defined $meta;

    #SMELL: topic and web are tainted when using Locales
    $topic = Foswiki::Sandbox::untaintUnchecked($topic);
    $web   = Foswiki::Sandbox::untaintUnchecked($web);

    $usWeb = $web;
    $usWeb =~ s/\//_/g;    #Convert any subweb separators to underscore

    _writeDebug("- PlantUMLPlugin::commonTagsHandler( $_[2].$_[1] )");

    # Reset our graph number so that when the engine inevitably calls
    # this method again, we'll be able to use the cached stuff and not
    # clutter up attachments.
    $grNum{"$web.$topic"} = 0;

    #pass everything within <plantuml> tags to _handlePlantUML function

    ( $_[0] =~
s/<PLANTUML(.*?)>(.*?)<\/(PLANTUML)>/&_handlePlantUML($2,$1,$meta)/gise
    );

    # $3 will be left set if any matches were found in the topic.  If
    # found, do cleanup processing
    my $endtag = $3;
    if ( $endtag && ( $endtag =~ /^plantuml$/i ) ) {
        _writeDebug("PlantUMLPlugin - FOUND MATCH  -  $endtag");
        wrapupTagsHandler();
    }

    _writeDebug(' <<< EXIT  commonTagsHandler  ');

}    ### sub commonTagsHandler

# =========================
sub _handlePlantUML {
    use File::Temp qw(tempdir tempfile);
    use File::Basename;
    use Digest::MD5 qw( md5_hex );
    use Foswiki::Plugins::PlantUMLPlugin::GraphMetaStore;

    _writeDebug(' >>> _handlePlantUML Entered ');

    my $attr = $_[1] || '';    # Attributes from the <plantuml ...> tag
    my $desc = $_[0] || '';    # PlantUML input between the <plantuml> tags
    my $meta = $_[2];

    return macroError("_handlePlantUML: undefined Meta object")
      unless defined $meta;

    # extract all parms into a hash array
    my %params = Foswiki::Func::extractParameters($attr);

    # parameters with defaults set in the PlantUMLPlugin topic.
    my $antialias       = $params{antialias}       || $antialiasDefault;
    my $density         = $params{density}         || $densityDefault;
    my $formats         = $params{formats}         || $formatsDefault;
    my $hideAttach      = $params{hideattachments} || $hideAttachDefault;
    my $inlineAttach    = $params{inline}          || $inlineAttachDefault;
    my $linkAttachments = $params{linkattachments} || $linkAttachmentsDefault;
    my $svgFallback     = $params{svgfallback}     || $svgFallbackDefault;
    my $svgLinkTarget   = $params{svglinktarget}   || $svgLinkTargetDefault;

    _writeDebug("- _handlePlantUML options: $attr");

    #_writeDebug("- _handlePlantUML contents: $desc");

    # parameters with hardcoded defaults
    my $outFilename = $params{file} || '';

#<<< Tidy makes a mess here
# Strip all trailing white space on any parameters set by set statements - WYSIWYG seems to pad it.
    $antialias           =~ s/\s+$//;
    $density             =~ s/\s+$//;
    $formats             =~ s/\s+$//;
    $hideAttach          =~ s/\s+$//;
    $inlineAttach        =~ s/\s+$//;
#>>>

    # Make sure outFilename is clean
    if ( $outFilename ne '' ) {
        $outFilename = Foswiki::Sandbox::sanitizeAttachmentName($outFilename);

        # Validate the filename if the Sandbox *can* validate filenames
        # (older Foswikis cannot) otherwise just untaint
        my $validator =
          defined(&Foswiki::Sandbox::validateAttachmentName)
          ? \&Foswiki::Sandbox::validateAttachmentName
          : sub { return shift @_; };
        $outFilename = Foswiki::Sandbox::untaint( $outFilename, $validator );
    }

    # clean up parms
    if ( $antialias =~ m/off/ ) {
        $antialias = 0;
    }

    #
    ###  Validate all of the <plantuml ...> input parameters
    #

    unless ( $density =~ m/^\d+$/ ) {
        return macroError( "density parameter should be given as a number"
              . " (was: $density)" );
    }

    unless ( $hideAttach =~ m/^(on|off)$/ ) {
        return macroError( "hideattachments  must be either \"off\" or \"on\""
              . " (was: $hideAttach)" );
    }

    unless ( $linkAttachments =~ m/^(on|off)$/ ) {
        return macroError( "links  must be either \"off\" or \"on\""
              . " (was: $linkAttachments)" );
    }

    unless ( $inlineAttach =~ m/^(png|jpg|svg)$/ ) {
        return macroError( "inline  must be either \"jpg\", \"png\" or \"svg\""
              . " (was: $inlineAttach)" );
    }

    unless ( $svgFallback =~ m/^(png|jpg|none)$/ ) {
        return macroError( "svg fallback must be either \"png\" or \"jpg\", or"
              . " set to \"none\" to disable (was: $svgFallback)" );
    }

    unless ( $svgLinkTarget =~ m/^(on|off)$/ ) {
        return macroError( "svg Link Target must either be \"on\" or \"off\""
              . " (was: $svgLinkTarget)" );
    }

    my $hide = undef;
    if ( $hideAttach =~ m/off/ ) {
        $hide = 0;
    }
    else {
        $hide = 1;
    }

    # compute the MD5 hash of this string.  This used to detect
    # if any parameters or input change from run to run
    # Attachments recreated if the hash changes

    # Hash is calculated against the <plantuml> command parameters and
    # input, along with any parameters that are set in the Default
    # topic which would modify the results.  Parameters that are only
    # set as part of the <plantuml> command do not need to be
    # explicitly coded, as they are include in $attr.

    my $hashCode =
      md5_hex( 'PlantUML'
          . $desc
          . $attr
          . $antialias
          . $density
          . $formats
          . $hideAttach
          . $inlineAttach );

    _writeDebug("- _handlePlantUML formats=$formats");

    # If a filename is not provided, set it to a name, with incrementing number.
    if ( $outFilename eq '' ) {    #no filename?  Create a new name
        $grNum{"$web.$topic"}++;    # increment graph number.
        $outFilename = 'PlantUMLPlugin_' . $grNum{"$web.$topic"};
        $outFilename = Foswiki::Sandbox::untaintUnchecked($outFilename);
    }

    # Make sure formats includes all required file types
    $formats =~ s/,/ /g;    #Replace any comma's in the list with spaces.
                            # whatever specified inline is mandatory
    $formats .= ' ' . $inlineAttach
      if !( $formats =~ m/$inlineAttach/ );

    # Generate png if SVG is inline - for browser fallback
    $formats .= ' ' . "$svgFallback"
      if ( $inlineAttach =~ m/svg/ && $svgFallback ne 'none' );
    $formats =~ s/none//g;    # remove the "none" if set by default

    # Hash to store attachment file names - key is the file type.
    my %attachFile;

    # open the data store
    my $store = Foswiki::Plugins::PlantUMLPlugin::GraphMetaStore->new();

    # get original contents; may be undef
    my $oldNodeList = $store->getNodeList(
        "[\@web='$web' and \@topic='$topic' and \@id='$hashCode']");
    my $oldNode = undef;
    $oldNode = $oldNodeList->get_node(1)
      if defined $oldNodeList;

    # copy XML tag (<plantuml>) attribute hash for modification/reuse
    my %graphMetaOpts = %params;
    $graphMetaOpts{'web'}   = $web;
    $graphMetaOpts{'topic'} = $topic;
    $graphMetaOpts{'id'}    = $hashCode;

    # create the new metadata object
    my $newElem =
      Foswiki::Plugins::PlantUMLPlugin::GraphMeta->new( \%graphMetaOpts );
    my %attachOpts = (
        name       => $outFilename . ".txt",
        dontlog    => 1,
        comment    => "<nop>$pluginName: UML graph",
        hide       => 1,
        PLANTweb   => $web,
        PLANTtopic => $topic,
        PLANTtype  => "txt"
    );

    # generate a child node for the PlantUML source file
    # $newElem->attach(%attachOpts);
    # $renderAttachments{"$web.$topic"}{"$outFilename.txt"} = 1;
    # $attachFile{'plantuml'} = "$outFilename.txt";

    # generate a chlid node for each of the generated output files
    my $root = $store->{'doc'}->documentElement();
    foreach my $format ( split( ' ', $formats ) ) {
        $attachOpts{'name'} = $outFilename . ".$format";
        $attachOpts{'name'} .= '.txt' if ( $format eq 'plantuml' );
        $attachOpts{'PLANTtype'} = $format;
        $renderAttachments{"$web.$topic"}{"$outFilename.$format"} = 1;
        $attachFile{$format} = "$outFilename.$format";
        $newElem->attach(%attachOpts);

        my $staleNodeList =
          $store->getNodeList( "[\@id!='$hashCode' and attachment/\@name='"
              . $attachOpts{'name'}
              . "']" );

        foreach my $staleNode ( $staleNodeList->get_nodelist() ) {
            _writeDebug( "- _handlePlantUML stale attachments in "
                  . $staleNode->getAttribute("id") );
            $root->removeChild($staleNode);
            $store->{'changed'} = 1;
        }
    }

    # check to see all attachments already exist
    my $allExist = 1;
    if ( $newElem->{'node'}->hasChildNodes() ) {
        foreach my $child ( $newElem->{'node'}->childNodes() ) {
            if (
                !Foswiki::Func::attachmentExists(
                    $web, $topic, $child->getAttribute("name")
                )
              )
            {
                $allExist = 0;
                last;
                _writeDebug( "- _handlePlantUML attachment "
                      . $child->getAttribute("name")
                      . " DOES NOT EXIST" );
            }
            else {
                _writeDebug( "- _handlePlantUML attachment "
                      . $child->getAttribute("name")
                      . " exists" );
            }
        }
    }

    _writeDebug("- _handlePlantUML all attachments exist") if $allExist;

    if ( $store->updateDocFromNodes( $oldNode, $newElem->{'node'} )
        || !$allExist )
    {
        _writeDebug("- _handlePlantUML document has changed") unless $allExist;

        # create a temporary file and directory for the PlantUML files
        my $dir = tempdir( CLEANUP => 1 );
        my ( $fh, $filename ) = tempfile(
            DIR    => $dir,
            SUFFIX => '.plantuml'
        );
        push @{ $tmpDirs{"$web.$topic"} }, $dir;

        # save the PlantUML source into the temp file
        print $fh "\@startuml\n" . $desc . "\n\@enduml\n";
        _writeDebug("- _handlePlantUML temp file name: $filename");
        _writeDebug("- _handlePlantUML $outFilename hash: $hashCode");

        # attach the PlantUML source to the wiki page with a cleaner name
        $attachOpts{'name'}      = $outFilename . ".txt";
        $attachOpts{'file'}      = $filename;
        $attachOpts{'PLANTtype'} = "txt";
        _writeDebug( "- _handlePlantUML old attach txt name="
              . $attachOpts{'name'}
              . "  file="
              . $attachOpts{'file'}
              . "  PLANTtype="
              . $attachOpts{'PLANTtype'} );

        # $meta->attach(%attachOpts);

        # FIX is anyone using this on Windows? because the line below
        # probably won't work.
        my $basename =
          dirname($filename) . '/' . basename( $filename, ".plantuml" );

        # generate graphs for each of the requested formats
        foreach my $format ( keys %attachFile ) {
            my $sourcefile = "$basename.$format";
            if ( $format ne 'plantuml' ) {    # can't generate a "plantuml"
                    # SECURITY:
                    # 1) $plantJar is set by the wiki admin
                    # 2) $filename is generated using perl's File::Temp package
                    # 3) $format MUST BE SANITIZED
                my $cmdline = "$javaCmd -jar $plantJar -t$format $filename";
                my $output  = `$cmdline 2>&1`;
                my ( $rc, $errmsg ) = ( $?, $! );
                if ( $rc != 0 ) {

                    # remove the invalid node from the DB
                    $root->removeChild( $newElem->{'node'} );
                    if ( length($output) == 0 ) {
                        $output = $errmsg;
                    }
                    elsif ( $output =~ /Error line ([0-9]+) in file: (.*)/ ) {
                        my ( $line, $errfile ) = ( $1, $2 );
                        $output .= "\n\n";
                        _writeDebug("- _handlePlantUML open $errfile");

                        # try to add the errored line to the message
                        if ( open ERRFILE, "<$errfile" ) {
                            my $findline = 0;
                            while (<ERRFILE>) {
                                $findline++;
                                if ( $findline == $line ) {
                                    $output .= "\nText:\n";
                                    $output .= $_;
                                    last;
                                }
                            }
                            close(ERRFILE);
                        }
                    }
                    $errmsg = "failed to execute \"$cmdline\","
                      . " RC=$rc<br/>output:\n<pre>$output</pre>\n";
                    _writeDebug("- _handlePlantUML $errmsg");
                    return macroError($errmsg);
                }
            }

            # attach the PlantUML images to the wiki page with a cleaner name
            $attachOpts{'name'} = $outFilename . ".$format";
            $attachOpts{'name'} .= '.txt' if ( $format eq 'plantuml' );
            $attachOpts{'file'}      = $sourcefile;
            $attachOpts{'PLANTtype'} = $format;
            _writeDebug( "- _handlePlantUML new attach $format name="
                  . $attachOpts{'name'}
                  . "  file="
                  . $attachOpts{'file'}
                  . "  PLANTtype="
                  . $attachOpts{'PLANTtype'} );
            $meta->attach(%attachOpts);
        }

        _writeDebug("- _handlePlantUML copy $filename to $outFilename");
    }

    my $urlPath    = Foswiki::Func::getPubUrlPath();
    my $loc        = $urlPath . "/$web/$topic";
    my $src        = Foswiki::urlEncode("$loc/$outFilename.$inlineAttach");
    my $returnData = '';

    # If not a SVG, fallback image becomes the primary image.
    my $fbtype = $inlineAttach;

    #  Build a manual link for each specified file type except for
    #  The "inline" file format, and any image map file

    my $fileLinks = '';
    if ( Foswiki::Func::isTrue($linkAttachments) ) {
        $fileLinks = '<br />';
        foreach my $format ( keys(%attachFile) ) {
            if ( $format ne $inlineAttach ) {
                my $fname = $attachFile{$format};
                $fname .= '.txt' if ( $format eq 'plantuml' );
                $fileLinks .=
                    '<a href='
                  . $urlPath
                  . Foswiki::urlEncode("/$web/$topic/$fname")
                  . ">[$format]</a> ";
            }    # if (($format ne
        }    # foreach my $format
    }    # if ($linkAttachments

    $returnData = "<noautolink>\n";

    if ( $inlineAttach eq 'svg' ) {
        $fbtype = "$svgFallback";
        $returnData .=
          "<object data=\"$src\" type=\"image/svg+xml\" border=\"0\" ";
        $returnData .= " alt=\"$outFilename.$inlineAttach diagram\"";
        $returnData .= "> \n";
    }

    # This is either the fallback image, or the primary image if not
    # generating an inline SVG
    if (   ( $inlineAttach eq 'svg' && $svgFallback ne 'none' )
        || ( $inlineAttach ne 'svg' ) )
    {
        my $srcfb = Foswiki::urlEncode("$loc/$outFilename.$fbtype");

        # Embedded img tag for fallback
        $returnData .= "<img src=\"$srcfb\" type=\"image/$fbtype\" ";
        $returnData .= " alt=\"$outFilename.$inlineAttach diagram\"";
        $returnData .= "> \n";
    }

    $returnData .= "</object>\n" if ( $inlineAttach eq "svg" );

    $returnData .= "</noautolink>";
    $returnData .= $fileLinks;

    _writeDebug(' <<< EXIT  _handlePlantUML');
    return $returnData;

}    ### sub _handlePlantUML

### sub _writeDebug
#
#   Writes a common format debug message if debug is enabled

sub _writeDebug {
    &Foswiki::Func::writeDebug( 'PlantUMLPlugin - ' . $_[0] )
      if $debugDefault;
}    ### SUB _writeDebug

### sub afterRenameHandler
#
#   This routine will rename or delete any workarea files.  If topic is renamed
#   to the Trash web, then the workarea files are simply removed, otherwise they
#   are renamed to the new Web and topic name.

sub afterRenameHandler {
    my ( $oldWeb, $oldTopic, $oldAttachment,
        $newWeb, $newTopic, $newAttachment ) = @_;

    if ( !isRenderContext() ) {
        return;
    }

    _writeDebug(
" >>> afterRenameHandler($oldWeb.$oldTopic $oldAttachment,$newWeb.$newTopic $newAttachment) Entered"
    );

    # don't do anything if we're just renaming/trashing attachments
    return if $oldAttachment;

    my $store = Foswiki::Plugins::PlantUMLPlugin::GraphMetaStore->new();
    $store->moveWikiPage( $oldWeb, $oldTopic, $newWeb, $newTopic );

    _writeDebug(" <<< EXIT afterRenameHandler");
}    ### sub afterRenameHandler

#
#  sub wrapupTagsHandler
#   - Find any files or file types that are no longer needed
#     and move to Trash with a unique name.
#
sub wrapupTagsHandler {
    use File::Path;
    _writeDebug(" >>> wrapupTagsHandler  entered web=$web topic=$topic ");

    if ( exists $renderAttachments{"$web.$topic"} ) {
        _writeDebug("- wrapupTagsHandler renderAttachments exists");
    }
    else {
        _writeDebug("- wrapupTagsHandler renderAttachments DOES NOT EXIST");
    }

    if ( exists $renderAttachments{"$web.$topic"} ) {

        #_writeDebug("- wrapupTagsHandler renderAttachments:");
        #_writeDebug(Data::Dumper->Dump([ $renderAttachments{"$web.$topic"} ]));

        # changes were made, look for attachments no longer in use
        my $store = Foswiki::Plugins::PlantUMLPlugin::GraphMetaStore->new();
        my $nodelist = $store->getAttachmentsByTopic( $web, $topic );
        my %storedAttach;

        # make a hash of attachments in XML store
        $storedAttach{ $_->getAttribute("name") } = $_
          foreach ( $nodelist->get_nodelist() );

        _writeDebug("- wrapupTagsHandler OLD attachment $_")
          foreach ( keys %storedAttach );

        delete( $storedAttach{$_} )
          foreach ( keys %{ $renderAttachments{"$web.$topic"} } );

        if ( keys %storedAttach ) {
            _writeDebug("- wrapupTagsHandler attachment $_ no longer exists")
              foreach ( keys %storedAttach );

            _writeDebug("- wrapupTagsHandler removing stale attachments");
            Foswiki::Func::moveAttachment( $web, $topic, $_,
                $Foswiki::cfg{TrashWebName},
                "TrashAttachment", undef )
              foreach ( keys %storedAttach );

            _writeDebug("- wrapupTagsHandler updating XML");
            $storedAttach{$_}->parentNode->removeChild( $storedAttach{$_} )
              foreach ( keys %storedAttach );

            # We've changed the store but the store isn't aware.  Make it aware.
            $store->{'changed'} = 1;
        }
        rmtree( \@{ $tmpDirs{"$web.$topic"} }, 0, 0 );

        # delete $tmpFiles{"$web.$topic"};
        delete $tmpDirs{"$web.$topic"};
        delete $renderAttachments{"$web.$topic"};
    }

    _writeDebug(' <<< EXIT wrapupTagsHandler');
}    ### sub wrapupTagsHandler

1;

