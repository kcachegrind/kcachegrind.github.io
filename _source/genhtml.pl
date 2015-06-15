#!/usr/bin/perl
#
# Wrapper around format converter to convert a set of files

# local settings
$outdir = "../html";
$picsdir = "/images";
$parser = "./parser.pl";

# Option parsing
#  -d <datadir>          set data directory (default "data")
#  -p <picsdir>          set picture directory (default "images")
#  -o <output dir>       set HTML output directory (default "html")
#  -t <page template>    Use given page as template
#
while ($ARGV[0] =~ /^\-(\w+)/) {
  shift;
  if ($1 eq "d") {
      $datadir = shift;
  }
  elsif ($1 eq "p") {
      $picsdir = shift;
  }
  elsif ($1 eq "o") {
      $outdir = shift;
  }
  elsif ($1 eq "t") {
      $pageTemplate = shift;
  }
  elsif ($1 eq "h") {
      die "Usage: genhtml.pl [options] StartPage\n";
  }
}

if ($datadir eq "") {
    $datadir = "data";
}
if (!($datadir =~ /\/$/)) { $datadir .= "/"; }

if ($picsdir eq "") {
    $picsdir = "images";
}
if (!($picsdir =~ /\/$/)) { $picsdir .= "/"; }

if ($outdir eq "") {
    $outdir = "html";
}
if (!($outdir =~ /\/$/)) { $outdir .= "/"; }

if ($pageTemplate eq "") {
    $pageTemplate = "StaticTemplate";
}

if ($ARGV[0] eq "") {
    push @pages, "Home";
}
else {
    push @pages, shift;
}

while($page = shift @pages) {
    if ($done{$page}) { next; }

    $pfile = $page;
    $pfile =~ s/\//-/g;
    $cmd = "$parser -d $datadir -p $picsdir -t $pageTemplate";
    print "Page '$page': Generating $outdir$pfile.html\n";
    system "$cmd -s $page > $outdir$pfile.html";

    open(IN, "$cmd -l $page|");
    while(<IN>) {
	if (/Missing/) {
	    print $_;
	    next;
	}
	chomp;
	push @pages, $_;
    }
    close IN;

    $done{$page} = 1;
}
