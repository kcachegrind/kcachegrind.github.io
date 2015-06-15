#!/usr/bin/perl
#
# Converts a wiki page from a file database to HTML.
#
# Usage: $0 [<options>] [Page]
#
# If Page is not given, create a virtual page "stdin", read from stdin.
#
# Conversion is done in 3 steps:
#
# (1) Flatten a page content with transclusion into one without.
#
#     - a page name optionally has a namespace and a path, given
#       as "[<namespace>:][<path>/]Page". Default is the empty namespace/path.
#     - the actual file used is "$datadir/<namespace>/<path>/Page". Note that
#       both a namespace and the path are allowed to have slashes in the
#       middle. If the actual file does not exist, it is searched in the
#       parent directory. This allows for specialisation of pages in
#       subpaths and subnamespaces.
#     - in the page content, "{{Page}}" is replaced by the content of "Page".
#       Page names are relative to the namespace/path of the current page,
#       unless explicitly specified. Transclusions can have parameters,
#       given as "{{Page|<par1>|<par2>|...}}", where each parameter can
#       be named: "pName=pValue". Parameters can be referenced with
#       {{$1}} or {{$pName}}.
#     - if a template page exists (can be specified with -t), this page is
#       used instead. The special transclusion "{{This}}" includes the
#       original page.
#
# (2) For the default section, resolve section transclusions and functions.
#
#    - a wiki page can consist of named section definitions. Section names
#      start with a "$". Default name is just "$". Each line starting with
#      "$<name>=" starts a new section. 
#    - defining multiple sections with the same name is allowed; they are
#      internally numbered, and are referenced with $name1, $name2, ..
#    - To continue a section after interim section definitions, these have
#      to be put into lines with $+ and $-. This is automatically done in
#      step (1) for page transclusion to allow for section definitions at
#      the end of included pages, yet continue with the old section afterwards
#    - section transclusions "{{$<name>}} are replaced with their content.
#      Functions are called with {{#<fname>}}, and are directly defined as
#      an external Perl subroutine, potentially from a plugin.
#      Similar to page transclusions, section transclusions and functions
#      can have parameters.
#
# (3) Conversion of default section "$" to HTML. This produces the final
#     output to stdout.
#
#   - supported wiki syntax:    
#    
#     Empty Line            New Paragraph, flush item environment
#     =, ==, ===            Titles
#     *, **, ***            Items
#     [[Page|link text]]    Links to other pages
#


#
# Option parsing
#  -d <datadir>          set wiki data directory (path on local file system)
#  -p <picsdir>          set images directory (path for images)
#  -e                    enable edit mode (provides links to edit interface)
#  -t <page template>    Use given page as template
#  -s                    Generate static HTML
#  -l                    Output links found in given page instead of HTML
#  -                     Append stdin to page

while ($ARGV[0] =~ /^\-(\w*)/) {
  shift;
  if ($1 eq "") {
      $appendStdin = 1;
  }
  elsif ($1 eq "d") {
      $datadir = shift;
  }
  elsif ($1 eq "p") {
      $picsdir = shift;
  }
  elsif ($1 eq "e") {
      $editMode = 1;
  }
  elsif ($1 eq "s") {
      $editMode = 0;
      $staticMode = 1;
  }
  elsif ($1 eq "t") {
      $pageTemplate = shift;
  }
  elsif ($1 eq "l") {
      $onlyLinks = 1;
  }
}

if ($datadir eq "") { $datadir = "data"; }
if (!($datadir =~ /\/$/)) { $datadir .= "/"; }

if ($pageTemplate eq "") {
    if ($editMode) {
	$pageTemplate = "EditTemplate";
    }
    elsif ($staticMode) {
	$pageTemplate = "StaticTemplate";
    }
    else {
	$pageTemplate = "Template";
    }
}

if ($picsdir eq "") { $picsdir = "/images"; }
if (!($picsdir =~ /\/$/)) { $picsdir .= "/"; }

if ($staticMode) {
    $scriptPath = "";
    $refEnding = ".html";
}
else {
    $scriptName = $ENV{"SCRIPT_NAME"};
    $scriptPath = $scriptName."/";
    $refEnding = "";
}

if ($ARGV[0] ne "") {
    $pageName = shift;
    $pageName =~ s/^$datadir//;
    $pageName =~ s/^\///;
}
else {
    $pageName = "stdin";
    while(<>) { $stdin .= $_; }
    $pageLoaded{$pageName} = 1;
    $loadedPage{$pageName} = $stdin;
    $appendStdin = 0;
}

if ($pageName =~ /\//) {
    $baseName = $pageName;
    $baseName =~ s/\/[^\/]+$/\//;
}

#print "PageName: $pageName, BaseName: $baseName, PageTemplate: $pageTemplate\n";

#
# Functions for conversion to unnested HTML
#

# loads a file (relative to $datadir)
sub loadPage
{
    my $fname, $text;
    ($fname) = @_;

    #print "LoadPage($fname)\n";

    if ($pageLoaded{$fname}) {
	return $loadedPage{$fname};
    }
    $pageLoaded{$fname} = 1;

    open(INFILE, "<$datadir$fname") or return "";
    $text = "";
    while(<INFILE>) { $text .= $_; }
    close INFILE;
    chomp $text;
    $loadedPage{$fname} = $text;

    return $text;
}

sub getPage
{
  my $pname, $ptext;
  ($pname) = @_;

  if ($pname =~ /^\//) {
      $pname =~ s/^\///;
  }
  else {
      $pname = $baseName . $pname;
  }

  $ptext = loadPage($pname);
  while(($ptext eq "") && ($pname =~ s/^[^\/]+\///)) {
      $ptext = loadPage($pname);
  }

  return $ptext;
}

sub pageExists
{
  my $pname;
  ($pname) = @_;

  if ($pname =~ /^\//) {
      $pname =~ s/^\///;
  }
  else {
      $pname = $baseName . $pname;
  }

  #print "PageExists($pname) [Check $datadir$pname]\n";

  if (-f "$datadir$pname") {
      return $pname;
  }
  while($pname =~ s/^[^\/]+\///) {
      if (-f "$datadir$pname") { return $pname; }
  }

  return "";
}

sub replaceName {
  my $pname, $elseStr, $fpage;
  my ($pname) = @_;

  #print "REPLACE NAME $tag $fname\n";

  if ($pname =~ /^([A-Za-z0-9_\/]+)(|\|.*)$/) {
    $elseStr = $2;
    $pname = $1;
    if (!$isTemplate) {
	$pname =~ s/This/$pageName/g;
    }
    $fpage = getPage($pname);
    if ($fpage ne "") {
	return "\$+\n$fpage\n\$-\n";
    }
    if ($elseStr ne "") { return $elseStr; }
  }

  return "[[$pname]]";
}



#
# Functions for unnesting sections
#

sub realSectionName {
  my $secname;

  ($secname) = @_;
  if ($secname =~ /^(.*)-(\d+)$/) {
    $n = $counter{$1}-$2;
    return "$1$n";
  }
  elsif ($secname =~ /\d+$/) {
    return $secname;
  }
  $n = $counter{$secname};
  return "$secname$n";
}


sub replaceSection {
  my $section, $elseStr;

  ($section) = @_;
  $elseStr = "";

  if ($section =~ s/\|([^\|]*)//) {
    $elseStr = $1;
  }

  # limit number of recursive replacements
  if ($depth > 3) { return ""; }

  $rsection = realSectionName($section);
  $r = $section{$rsection};
  # cut white space at section end
  $r =~ s/[\s\n]+$//;

  #print "\nREPLACE SECTION $section (d $depth, real $rsection): '$r'\n";

  if ($r eq "") { return $elseStr; }
  return $r;
}

#
# Functions for conversion to HTML
#

sub picLink {
  my $picname, $picattr;

  ($picname,$picattr) = @_;

  $linkCounter++;
  $pseudoLink = "\@$linkCounter\@";

  $rname = "<img border=0 src=\"$picsdir$picname\">";
  if ($picattr =~ /center|left|right/) {
      $rname = "<div align=".$picattr.">".$rname."</div>";
  }
  if ($picattr eq "raw") {
      $rname = "$picsdir$picname";
  }
  #print "Matching PicLink: '$picname', real '$rname', attr '$picattr'\n";

  if ($editMode &&
      ($picname =~ /^[A-Z][a-z]+[A-Z][A-Za-z0-9]+\.(jpg|jpeg|gif|png)$/)) {
      #print "Checking for picture '$picname'\n";
      if (!pageExists($picname)) {
	  $rname =~ s/src=\S*\.(jpg|jpeg|gif|png)/src=NoPicture.png/;
      }
  }
  $link[$linkCounter] = "$rname";
  return $pseudoLink;
}


sub wikiLink {
  my $name;

  ($name,$rname) = @_;

  #print "Matching Link: '$name', real '$rname'\n";
  if ($rname =~ /^([A-Za-z0-9_]+\.(jpg|jpeg|gif|png))(|\|([^\]]*))$/) {
      $picname = $1;
      $picattr = $4;
      if ($picattr =~ /left|right/) {
	  $rname = "<img border=0 align=$picattr src=\"$picsdir$picname\">";
      } else {
	  $rname = "<img border=0 src=\"$picsdir$picname\">";
	  if ($picattr =~ /center/) {
	      $rname = "<div align=".$picattr.">".$rname."</div>";
	  }
      }
  }

  $linkCounter++;
  $pseudoLink = "\@$linkCounter\@";

  if ($rname eq "") { $rname = $name; }

  if ($rname =~ /\.(jpg|jpeg|gif|png)$/) {
    $rname = "<img src=$rname>";
  }

  $realName = pageExists($name);
  if ($realName ne "") {
    if ($rname =~ /\.(jpg|jpeg|gif|png)/) {
      # local pic?
      if ($rname =~ /src=([^\/]+\.(jpg|jpeg|gif|png))/) {
	$picname = $1;
	#print "Checking for picture '$picname'\n";
	if (!pageExists($picname)) {
	  $rname =~ s/src=\S*\.(jpg|jpeg|gif|png)/src=NoPicture.png/;
	}
      }
    }
    push @links, $realName;
    if ($staticMode) {
	$realName =~ s/\//-/g;
    }
    $link[$linkCounter] = "<a href=\"$scriptPath$realName$refEnding\">$rname</a>";
  }
  else {
      if ($editMode) {
	  if ($rname =~ /\.(jpg|jpeg|gif|png)/) {
	      $rname =~ s/src=\S*\.(jpg|jpeg|gif|png)/src=NoPage.png/;
	      $link[$linkCounter] = "<a href=\"$scriptName?edit=true&page=$name\">$rname</a>";
	  }
	  else {
	      $link[$linkCounter] = "$rname<a href=\"$scriptName?edit=true&page=$name\">?</a>";
	  }
      }
      else {
	  $link[$linkCounter] = $rname;
	  push @links, "Missing: $name";
      }
  }
  return $pseudoLink;
}

sub parout {
  ($printP) = @_;

  if ($html eq "") { return; }
  if ($printP) { $html .= "<p>\n"; }

  if ($section eq "") {
      if ($onlyLinks) { return; }
      print "$html";
  } else {
    $html{$section} .= $html;
  }
  $html = "";
}

# output the table
sub writeTable {	

  print "<center><table><tr>\n";
  foreach $i (1 .. $tableColumns) {
    $sName = $tableSection[$i];
    $head =  $tableHead[$i];
    if ($head eq "") { $head = $sName; }
    $c = $counter{$sName};
    print "<th>$head</td>\n";
    $tableCounter{$sName} = 0;
  }
  print "</tr>";

  $firstName = $tableSection[1];
  while( $tableCounter{$firstName} < $counter{$firstName}) {
    $tableCounter{$firstName}++;
    $entry = $tableCounter{$firstName};

    $sName = $firstName.$entry;
    $s = $section{$sName};
    print "<tr><td>$s</td>";

    foreach $i (2 .. $tableColumns) {
      $rowSection = $tableSection[$i];
      $relNo = $relation{$sName.$rowSection};

      if (($relNo eq "") && ($tableCounter{$rowSection} > 0)) {
	$relNo = $counter{$rowSection};
      }
      $tableCounter{$rowSection} = $relNo;

      $s = $section{$rowSection.$relNo};
      print "<td>$s</td>";
    }
    print "</td>\n";
  }

  print "</table></center>\n";

  $tableColumns = 0;
  @tableDef = ();
}

# Uses global var $depth.
# Returns HTML code needed to adjust to new depth
sub changeIndent {
  ($newDepth,$tag) = @_;

  $ihtml = "";

  $new = $newDepth;
  if ($new<0) { $new = 0; }

  if ($inPRE) { $ihtml .= "</pre>"; $inPRE = 0; }

  while ($depth > $new) {
    $depth--;
    if ($indentTag[$depth] eq "") { $indentTag[$depth] = "ul"; }
    $ihtml .= "</$indentTag[$depth]>\n";
  }

  while ($depth < $new) {
    if ($tag eq "") { $tag = "ul"; }
    $indentTag[$depth] = $tag;
    $ihtml .= "<$tag>\n";
    $depth++;
  }

  if ($newDepth< 0) {
    # close tables
    #parout;
    if ($tableColumns>0) {
      writeTable;
    }
  }
  return $ihtml;
}

sub runMyParser {

  # the current paragraph
  $html = "";
  $newline = 0;
  $depth = 0;
  $startDepth = 0;
  $tableColumns = 0;
  $tableCount = 0;

  foreach (@wikiLines) {
    #if (/^\#.*$/) { next; }
    if (/^\s*$/) {
	$newline++;
	if ($newline == 1) {
	    $html .= changeIndent(-1);
	    parout(1);
	}
	next;
    }
    if (/^\+\s*$/) {
	$newline++;
	if ($newline == 1) {
	    parout(1);
	}
	next;
    }
    $newline = 0;

    $linkCounter = 0;

    # only for local pics with Wiki name (for remote use HTML)
    # [[pic.png]], [[pic.png|attribute]]
    s/\[\[([A-Za-z0-9_\/]+\.(jpg|jpeg|gif|png))(|\|([^\]]*))\]\]/picLink($1,$4)/eg;

    s/\[\[([A-Za-z0-9_\/]+)\s*([^\]]*)\]\]/wikiLink($1,$2)/eg;

    if ($linkCounter >0) { s/\@(\d)+\@/$link[$1]/g; s/\@(\d)+\@/$link[$1]/g; }

    s/'''(.*?)'''/<b>$1<\/b>/g;
    s/''(.*?)''/<i>$1<\/i>/g;

    #print "Tmp: '$_'\n";
    #s/(<img )(.*?src=)([^\/]*)>/$1border=0 $2\"$picsdir$3\">/g;

    if (/^(\.+)\s*(.*)$/) {
      $rest = $2;
      $spaces = length $1;
      $html .= "<br>" . ("&nbsp;" x $spaces) . $rest;
      next;
    }

    if (/^(\t*\*+|\t*\#+)\s*(.*)$/) {
      $rest = $2;
      $ind = $1;
      if ($ind =~ /\#$/) { $tag = "ol"; } else { $tag = "ul"; }
      $newDepth = length $ind;
      if ($depth == 0) {
	$startDepth = $newDepth-1;
      }
      $newDepth -= $startDepth;
      if ($newDepth <1) {
	$newDepth = 1;
      }
      $html .= changeIndent($newDepth,$tag);
      $html .= "<li>$rest\n";
      next;
    }

    if (/^(\t*;+)\s*(.*)$/) {
      $rest = $2;
      $newDepth = length $1;
      if ($depth == 0) {
	$startDepth = $newDepth-1;
      }
      $newDepth -= $startDepth;
      if ($newDepth <1) {
	$newDepth = 1;
      }
      $change = changeIndent($newDepth);
      if ($change eq "") { $change = "<br>"; }
      $html .= "$change$rest\n";
      next;
    }

    if (/^\|\s*(\S*)\s*(.*)/) {
      $tableColumns++;
      $tableSection[$tableColumns] = $1;
      $tableHead[$tableColumns] = $2;
      if ($1 eq "") {
	writeTable;
      }
      next;
    }

    if (/^=([^=].*)$/) {
      $html .= "<h2>$1<\/h2>\n";
      $newline = 2;
      next;
    }

    if (/^==([^=].*)$/) {
      $html .= "<h3>$1<\/h3>\n";
      next;
    }

    if (/^===([^=].*)$/) {
      $html .= "<h4>$1<\/h4>\n";
      next;
    }
	
    if (/^----+$/) {
      $html .= changeIndent(-1);
      $html .= "<hr>\n";
      next;
    }

    if (/^ /) {
      if (!$inPRE) {
	$inPRE=1; $html .= "<pre>\n";
      }
    }
    elsif ($inPRE) {
      $inPRE=0; $html .= "</pre>";
    }

    $html .= "$_\n";
  }
  $html .= changeIndent(-1);
  parout(0);
}



#
# Main
#

if ($pageName eq $pageTemplate) {
  $isTemplate = 1;
}
else {
  $page = getPage($pageTemplate);
}
if ($page eq "") { $page = getPage($pageName); }

if ($appendStdin) {
    $page .= "\n";
    while(<>) { $page .= $_; }
}

#print "==========\n= Page 1 =\n==========\n$page\n==========\n";


# unnest loop
$depth = 0;
while( ($page =~ s/{{([A-Za-z0-9_\/]*)}}/replaceName($1)/mge) ) {
  $depth++;
}

#print "Page2: '$page'\n";

# extract sections
@sectionStack = ();
$sectionName = "";
$fullSectionName = "1";
$page = "\n$page";
@sectionList = split /\n\$/, $page;
foreach $s (@sectionList) {
    $s .= "\n";
    if ($s =~ s/^\+\n//s) {
	# remember section name on stack, but do not start new section
	push @sectionStack, $fullSectionName;
	$section{$fullSectionName} .= $s;
	#print "========= Append to section $fullSectionName: '$s'\n";
	next;
    }
    if ($s =~ s/^-\n//s) {
	# restore section name from stack, and append to that section
	$fullSectionName = pop @sectionStack;
	$section{$fullSectionName} .= $s;
	#print "========= Append to section $fullSectionName: '$s'\n";
	next;
    }
    if ($s =~ s/^([A-Za-z0-9_]+)\s*=?\s*//s) {
	$sectionName = $1;
    }

  $counter{$sectionName}++;
  $n = $counter{$sectionName};
  $fullSectionName = "$sectionName$n";
  $section{$fullSectionName} = $s;
  #print "========= Section $fullSectionName: '$s'\n";

  if ($n == 1) { push @sections, $sectionName; }
  else {
    # store relation of last entry
    $n--;
    foreach $s (@sections) {
      if ($s eq $sectionName) { next; }
      $relation{"$fullSectionName$s"} = $counter{$s};
    }
  }
}

# unnest sections: concat body sections
$page = "{{\$1}}";
$depth = 0;
while( ($page =~ s/{{\$([^{}]+)}}/replaceSection($1)/mge) ) {
  $depth++;
}

# cut white space at section end
$page =~ s/[\s\n]+$//s;

#print "Page3: '$page'\n";

@wikiLines = split "\n", $page;
runMyParser;

if ($onlyLinks) {
    $links = join "\n", @links;
    print "$links\n";
}
