use ExtUtils::MakeMaker;
use strict;
use IO::File;

# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.

my ($filehandle, $VERSION_FROM, $NAME, $version, $os, $ext_pl, $install_script);

$VERSION_FROM = 'make_batch.pl';
$NAME = 'WRECK_MP3s';
$os = $^O; 

$ext_pl = ".pl";
$install_script = '/usr/local/bin';

if ((uc($os) ne "LINUX") and (uc($os) ne "MSWIN32")) {
  warn ("\nWARNING:\n\tThis program has been designed for Linux and Windows only.\n\tYour os type: $os is not supported.\n\tProceed at Your Own Risk!\n\n\n");
    
}

if (uc($os) eq "LINUX") {
  $ext_pl = "";
  $install_script = '/usr/local/bin';
}

if (uc($os) eq "MSWIN32") {
  $ext_pl = ".pl";
  $install_script = 'c:\utils';
}

$filehandle = new IO::File("<$VERSION_FROM") || die "Unable to open $VERSION_FROM!\n";
while(<$filehandle>) {
  $version=$1 if (/^\$VERSION = "(.*)";$/);
}
close($filehandle);


WriteMakefile(
    'NAME'		=> $NAME,
    'DISTNAME'		=> "WhyReEnCode-KAM-MP3s",
    'VERSION'		=> $version,
    'PREREQ_PM'		=> { 'MP3::Info'=>"1.01" }, 
    'dist'      => {'COMPRESS'=>'gzip -9f', 'SUFFIX' => 'gz', 'ZIP'=>'/usr/bin/zip','ZIPFLAGS'=>'-rl'},
    'PM'	=> {'make_batch.pl' => '$(INST_SCRIPT)'."/make_batch$ext_pl"},
    'EXE_FILES'	=> 'make_batch',
    'INSTALLSCRIPT' => $install_script,
    'AUTHOR'    => 'Kevin A. McGrail (kmcgrail@peregrinehw.com)',
    'ABSTRACT'  => 'Interface to Catalog and Process MP3 files of Varying Specifications');


print "\nConfigured $NAME for ",uc($os),"\n";
if ($ext_pl ne "") {
  print "\tPerl Executable files will have the file extension \"$ext_pl\" added to them.\n";
} else {
  print "\tPerl Executable files do not need a file extension added to them.\n";
}
print "\tPerl Executable files will be installed in \"$install_script\".\n\n";

print "\n$NAME v$version\n\n'make install' to install the program.\n";
