# ---+ Extensions
# ---++ PlantUML Plugin 

# Settings for the PlantUML Plugin.  This plugin generates
# graphs using the &lt;PlantUML&gt; language.  Note that <b>Expert
# Settings</b> are available to override the storage location for
# attachments. Press the button at the top of this page to access
# expert settings.

# **PATH M**
# Path to plantuml.jar.
$Foswiki::cfg{Plugins}{PlantUMLPlugin}{plantJar} = '/opt/plantuml/plantuml.jar';

# **PATH**
# Path to the GraphViz executable.  On many systems this is not
# required if the GraphViz executables are on the default path
$Foswiki::cfg{Plugins}{PlantUMLPlugin}{dotPath} = '';

# **PATH**
# Path to the ImageMagick convert utility.  <br>
#   -  This is used to support antialias output <br> 
#      (Required if GraphViz doesn't have Cairo rendering support.)
$Foswiki::cfg{Plugins}{PlantUMLPlugin}{magickPath} = '';

# **PATH**
# Path to the Foswiki tools directory . <br>
# The PlantUMLPlugin.pl helper script is found in this directory.
# Typically found in the web server root along with bin, data, pub, etc.
# If not provided the plugin will guess based upon the current working directory
$Foswiki::cfg{Plugins}{PlantUMLPlugin}{toolsPath} = '';

# **PATH M**
# Perl command used on this system <br>
#  On many systems this can just be the "perl" command
$Foswiki::cfg{Plugins}{PlantUMLPlugin}{perlCmd} = 'perl';

# **PATH M**
# Java VM command used on this system <br>
#  On many systems this can just be the "java" command
$Foswiki::cfg{Plugins}{PlantUMLPlugin}{javaCmd} = 'java';

# **BOOLEAN EXPERT**
# Flag specifying if the plugin should generate graphs when viewing
# previous topic revisions<br/>
#  If the plugin generates attachments when viewing old revisions,
#  this can result in out of date attachments, and significant
#  overhead regenerating the attachments.  Enable this flag to restore
#  previous behavior of the plugin Note that by default, old revisions
#  of attachments can be viewed using the attach dialog.
$Foswiki::cfg{Plugins}{PlantUMLPlugin}{generateRevAttachments} = '0';

# **BOOLEAN EXPERT**
# Flag specifying if the plugin should generate graphs when comparing
# two topic revisions <br/>
#  If the plugin generates attachments during compare operations, this
#  can result in out of date attachments, and significant overhead
#  regenerating the attachments Enable this setting to restore the
#  prior behavior of the plugin.
$Foswiki::cfg{Plugins}{PlantUMLPlugin}{generateDiffAttachments} = '0';

# **PATH EXPERT**
# Path for plugin to store generated attachments<br>
#  Optional.  If not provided, plugin will manage attachments using the standard Foswiki attachment functions.<br />
#  If not provided, first visit to System.PlantUMLPlugin will require admin / sudo login so that the plugin can save the example attachments.
#  If set to the full path to the pub directory, generated attachments will be stored along with regular attachments but will be invisible to Foswiki topics.
#  This directory must be web readable.  <b>If not set to the "General Path Settings" {PubDir} path web server changes will be required to enable access.</b>
$Foswiki::cfg{Plugins}{PlantUMLPlugin}{attachPath} = '';

# **PATH EXPERT**
# URL Path for generated attachments <br>
#  Optional.  Only required if attachPath is provided, and is not the same as the "General Path settings" {PubDir} path.
# If not provided, plugin will use the value of "General Path Settings" {PubUrlPath} for linking to attachments.
# If the attachPath is not provided, then this parameter will be ignored.
$Foswiki::cfg{Plugins}{PlantUMLPlugin}{attachUrlPath} = '';

