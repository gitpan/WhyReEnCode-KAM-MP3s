#!/usr/bin/perl 

use warnings;
no warnings 'uninitialized';
$|++;
use strict;
use Getopt::Long;
use IO::File;
use File::Find;
use MP3::Info;
use File::Basename;

BEGIN {
  if (uc($^O) eq "MSWIN32") {
    require Win32::File;
    Win32::File->import();
  }
}

our ($VERSION, $TITLE, %FORM, @filelist, $COPYRIGHT, $DEFAULT_BITRATE);

$VERSION = "1.24";
$TITLE = "WinReEnCode-KAM-MP3s (WRECK MP3s)";
$COPYRIGHT = "Copyright (C) 2003 Peregrine Hardware, Inc.";
$DEFAULT_BITRATE = 128;

&process_arguments(\%FORM);
&main(\%FORM);
exit;

sub main {
  my ($FORM) = @_;

  my ($i, $rv, $mono, $vbr, $badsize, $infohash, $taghash, $j);

  $FORM->{'output'} = "";
  &main::set_rvs($FORM);
  $mono = 0;
  $vbr = 0;
  $badsize = 0;
  $j = 1;

  #BUILD THE LIST
  print "Building list of files to check: ";
  &File::Find::find(\&wanted, $FORM->{'path-to-mp3s'});
  print "Done!\n\n"; 

  print "\t",$#filelist+1, " MP3 File(s) Found to Check: ";
  for ($i = 0; $i < $#filelist + 1; $i++) {
    if (($i % 100) == 0) {
      print $i,"...";
    }
    ($rv, $infohash) = &id_mp3($FORM, file=>$filelist[$i]);
    #print "DEBUG: ",($rv == $FORM->{'MONO_RV'}), "$rv, $FORM->{'MONO_RV'}\n";
    #print "DEBUG: ",($rv == $FORM->{'VBR_RV'}), "$rv, $FORM->{'VBR_RV'}\n";
    #print "DEBUG: ",($rv == $FORM->{'BADSIZE_RV'}), "$rv, $FORM->{'BADSIZE_RV'}\n";

    $mono += ($rv == $FORM->{'MONO_RV'});
    $vbr += ($rv == $FORM->{'VBR_RV'});
    $badsize += ($rv == $FORM->{'BADSIZE_RV'});

    if ($rv > 0 and $rv != $FORM->{'BADSIZE_RV'}) {
      ($taghash) = &MP3::Info::get_mp3tag($filelist[$i]);
      &build_command($FORM, $filelist[$i], $taghash, $infohash, number=>$j);
      $j++;
    } elsif ($rv == $FORM->{'BADSIZE_RV'}) {
      print "0 Frame File: $filelist[$i]\n";
    }

    undef($taghash);
    undef($infohash);

  }  

  print "\n\t\t", $mono, " Monoaural CBR/VBR MP3 File(s) Found that needed ReEncoding\n";
  print "\n\t\t", $vbr, " Stereo VBR MP3 File(s) Found that needed ReEncoding\n";
  print "\n\t\t", $badsize, " MP3 File(s) Found that have no valid MP3 frames and\n\t\tshould be Removed or Replaced\n";

  print "\n\t", ($mono + $vbr + $badsize), " Total Problematic MP3 File(s)\n\n";

  if ($mono + $vbr + $badsize > 0) {
    &create_batch_file($FORM, total=>($mono + $vbr + $badsize));
  }
}

sub create_batch_file {
  my ($FORM, %params) = @_;

  my ($filehandle);

  if (uc($^O) eq "MSWIN32") {
    #BATCH FILES USE % FOR VARIABLES SO WE HAVE TO ESCAPE THAT
    $FORM->{'output'} =~ s/%/%%/g;
    $FORM->{'output'} = "\@ECHO OFF\n\n$FORM->{'output'}";
  }

  $FORM->{'output'} =~ s/:::total:::/$params{'total'}/g;

  if ($FORM->{'batch-file'} eq "-") {
    print $FORM->{'output'};
  } else {
    print "\nWriting to Batch File: $FORM->{'batch-file'}...";
    $filehandle = new IO::File ">$FORM->{'batch-file'}" or
      die("Error creating file \"$FORM->{'batch-file'}\": $!");
    print $filehandle ($FORM->{'output'});
    close ($filehandle);
    print "Done!\n\n";
  }
}

sub select_lowest_bitrate {
  my ($avg_bitrate) = @_;

  my (@good_bitrates, $bitrate, $i);

  @good_bitrates = (32, 40, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320);

  $i = 0;
  $bitrate = $good_bitrates[$i];

  if ($avg_bitrate > $good_bitrates[$#good_bitrates]) {
    $avg_bitrate = $good_bitrates[$#good_bitrates];
  }
  if ($avg_bitrate < $good_bitrates[0]) {
    $avg_bitrate = $good_bitrates[0];
  }

  while ($i < ($#good_bitrates + 1)) {
    #print "$i - $avg_bitrate - $good_bitrates[$i]\n";
    if ($avg_bitrate >= $good_bitrates[$i]) {
      $bitrate = $good_bitrates[$i];
    }
    $i++;
  }

  return $bitrate;

}

sub build_command {
  my ($FORM, $file, $taghash, $infohash, %params) = @_;

  my ($mode, $bitrate, $name, $path, $suffix, $i, $quality, $bakfile, $command, $output, $wavfile, $bakfile_nopath, $tmp_wavfile);
  my ($mp3tag_info, $sox, $cbrvbr);

  $mode = $params{'mode'} || "j";
  $bitrate = $params{'bitrate'} || $DEFAULT_BITRATE;
  $quality = $params{'quality'} || "2";
  $sox = 1;
  $cbrvbr = "--cbr";

  if ($infohash->{STEREO}) {
    $sox = 0;
  }

  if ($infohash->{VBR}) {
    $bitrate = $params{'bitrate'} || $infohash->{BITRATE};

    if (!$infohash->{STEREO}) {
      $bitrate = $bitrate * 2;
    }
  } else {
    $bitrate = $params{'bitrate'} || ($infohash->{BITRATE} * 2);
  }

  if ($bitrate == 0) {
    $bitrate = $DEFAULT_BITRATE;
  }
  $bitrate = &select_lowest_bitrate($bitrate);

  if (uc($^O) eq "MSWIN32") {
    &File::Basename::fileparse_set_fstype("MSWIN32");
    #$file =~ s/\//\\/g;
  }
  ($name, $path, $suffix) = &File::Basename::fileparse($file,'\.(\w)*$');
  
  $i = 1;
  while (-e "$path$name.$i$suffix.old" or -e "$path$name.$i$suffix") {
    $i++;
  }
  $bakfile = "$path$name.$i$suffix";
  $bakfile_nopath = "$name.$i$suffix";

  $i = 1;
  while (-e "$path$name.$i.wav") {
    $i++;
  }
  $wavfile = "$path$name.$i.wav";

  $i = 1;
  while (-e "$path$name.tmp.$i.wav") {
    $i++;
  }
  $tmp_wavfile = "$path$name.tmp.$i.wav";

  if (!$sox) {
    #no need for tmp wavfile if not processing with sox
    $tmp_wavfile = $wavfile;
  }

  $mp3tag_info = "--tt \"$taghash->{TITLE}\" --ta \"$taghash->{ARTIST}\" --tl \"$taghash->{ALBUM}\" --ty \"$taghash->{YEAR}\" --tc \"$taghash->{COMMENT}\" --tn \"$taghash->{TRACKNUM}\" --tg \"$taghash->{GENRE}\"";

  if (uc($^O) eq "LINUX") {  
    $FORM->{'output'} .= "echo \"### File $params{'number'}/:::total::: ReEnCoding \"$file\"\"\n";
    $FORM->{'output'} .= "echo\n";
    $FORM->{'output'} .= "mv \"$file\" \"$bakfile\"\n";
    $FORM->{'output'} .= "notlame --decode \"$bakfile\" \"$tmp_wavfile\"\n";
    if ($sox) {
      $FORM->{'output'} .= "sox -t WAV \"$tmp_wavfile\" -c 2 -t WAV \"$wavfile\"\n";
    }
    $FORM->{'output'} .= "notlame $mp3tag_info -m $mode -b$bitrate -q $quality $cbrvbr \"$wavfile\" \"$file\"\n";
    $FORM->{'output'} .= "rm -f \"$wavfile\" \"$tmp_wavfile\"\n";
    $FORM->{'output'} .= "mv \"$bakfile\" \"$bakfile.old\"\n";
    $FORM->{'output'} .= "echo \"###\"\n";
    $FORM->{'output'} .= "\n";
  }
  
  if (uc($^O) eq "MSWIN32") {
    $FORM->{'output'} .= "echo ### File $params{'number'}/:::total::: ReEnCoding \"$file\"\n";
    $FORM->{'output'} .= "ren \"$file\" \"$bakfile_nopath\"\n";
    $FORM->{'output'} .= "lame.exe --decode \"$bakfile\" \"$tmp_wavfile\"\n";
    if ($sox) {
      $FORM->{'output'} .= "sox -t WAV \"$tmp_wavfile\" -c 2 -t WAV \"$wavfile\"\n";
    }
    $FORM->{'output'} .= "lame.exe $mp3tag_info -m $mode -b$bitrate -q $quality $cbrvbr \"$wavfile\" \"$file\"\n";
    $FORM->{'output'} .= "del \"$wavfile\"\n";
    $FORM->{'output'} .= "del \"$tmp_wavfile\"\n";
    $FORM->{'output'} .= "ren \"$bakfile\" \"$bakfile_nopath.old\"\n";
    $FORM->{'output'} .= "echo ###\n";
    $FORM->{'output'} .= "\n";
  }

}

sub set_rvs {
  my ($FORM) = @_;

  $FORM->{'VBR_RV'} = 1;
  $FORM->{'MONO_RV'} = 2;
  $FORM->{'BADSIZE_RV'} = 4;

}

sub id_mp3 {
  my ($FORM, %params) = @_;
 
  my ($info, $name, $path, $suffix, $tag, $rv);

  $tag = 0;
  $rv = 0;
  if ($params{'file'} ne "") {
    ($name, $path, $suffix) = &File::Basename::fileparse($params{'file'},'\.(\w)*$');
    $info = &MP3::Info::get_mp3info($params{'file'});

    if ($info->{VBR}) {
      $tag=1;
      $rv = $FORM->{'VBR_RV'};
    }

    if (!$info->{STEREO}) {
      $tag=1;
      $rv = $FORM->{'MONO_RV'};
    }

    if ($info->{SIZE} == 0) {
      $tag=0;
      $rv = $FORM->{'BADSIZE_RV'};
    }

   
    if ($tag && $FORM->{'VERBOSE'}) {
      print "\n\t\t\tFAILED: $path$name$suffix\n\t\t\t\tSIZE:",($info->{SIZE}+0)," VBR:",&int_to_truefalse($info->{VBR})," FREQ:$info->{FREQUENCY}kHz VERSION:$info->{VERSION} LAYER:$info->{LAYER} STEREO:",&int_to_truefalse($info->{STEREO})," TIME:$info->{MM}m$info->{SS}s\n";
    }
  }

  #print "DEBUG: $rv\n";
  return ($rv, $info);
}

sub wanted {
  my ($file);

  my ($hidden, $attr, $name, $path, $suffix);
  $file = $File::Find::name;

  $hidden = 0;
  #NOTE Win32::File seems buggy and can't ID a hidden file without a full path 02-12-03 Build 633 5.6.1

  if (uc($^O) eq "MSWIN32") {
    $file =~ s/\//\\/g;
    #($name, $path, $suffix) = &File::Basename::fileparse($file,'\.(\w)*$');
    #&Win32::File::GetAttributes($file, $attr);
    #$hidden = ($attr & HIDDEN);
    #print "DEBUG: HIDDEN $hidden\n";
  }


  if (!-d $file && $file =~ /\.mp3$/i &! $hidden) {
    #print $#filelist+1," ";
    if ((($#filelist+1) % 100) == 0) {
      print $#filelist+1,"...";
    }
    push (@filelist, $file);
  }
}

sub process_arguments {
  my ($FORM) = @_;
  my ($result, $error, @error_msg, $i, $command, $output, $REQARGS);
  
  $REQARGS = 2;
  
  $error = 0;
  
  print "\n$TITLE v$VERSION\n$COPYRIGHT\n\n";
  $result = GetOptions('path-to-mp3s=s' => \$FORM->{'path-to-mp3s'}, 
                       'batch-file=s' => \$FORM->{'batch-file'},
                       'verbose' => \$FORM->{'VERBOSE'},
                       'overwrite' => \$FORM->{'OVERWRITE'});
  
  if ($result < 1) {
    push (@error_msg, "There was an error processing your command line options.");
    $error++;
  }
  
  if (($#ARGV+1) > 0) {
    push (@error_msg, "Getopt::Long could not process all the command line options or there are extra options on the command line.");
    $error++;
  }
 
  #TEST THE REQUIRED ARGUMENTS FOR EXISTENCE  AND MAKE ANY CHANGES
  $result = $REQARGS;
  if ($FORM->{'path-to-mp3s'} eq "") {
    $FORM->{'path-to-mp3s'} = "Missing!";
    $result--;
  } else {
    if (uc($^O) eq "MSWIN32") {
      #ADD A TRAILING BACKSLASH FOR DRIVE LETTERS FOR COMPATIBILITY WITH ALL MODULES
      unless ($FORM->{'path-to-mp3s'} =~ /(\w):\/$/) {
        $FORM->{'path-to-mp3s'} .= "\\";
      }
    }
  }

  $result = $REQARGS;
  if ($FORM->{'batch-file'} eq "") {
    $FORM->{'batch-file'} = "Missing!";
    $result--;
  } else {
    unless ($FORM->{'batch-file'} =~ /\.bat$/i) {
      $FORM->{'batch-file'} .= ".bat";
    }
  }
  
  #ARGUMENTS NOT MET, GIVE GENERIC ERROR 
  if ($result < $REQARGS) {
    push (@error_msg, "This program requires a path to the mp3s to catalog and the batch-file to create.");
    $error++;
  } else {
    #ARGUMENTS MET, TEST THEM
    if (!-d $FORM->{'path-to-mp3s'}) {
      push (@error_msg, "Path to MP3s \"$FORM->{'path-to-mp3s'}\" does not exist or is not a directory.");
      $error++;
    }

    #TEST IF BATCH FILE EXISTS AND WHETHER OVERWRITE WAS SPECIFIED IF IT DOES
    if (-d $FORM->{'batch-file'}) {
      push (@error_msg, "The batch file \"$FORM->{'batch-file'}\" to create already exists as a directory.");
      $error++;
    } elsif (-e $FORM->{'batch-file'} and (!$FORM->{'OVERWRITE'})) {
      push (@error_msg, "The batch file \"$FORM->{'batch-file'}\" to create already exists and --overwrite was not specified.");
      $error++;
    }

  }
  
  if ($error > 0) {
    for ($i=0; $i < ($#error_msg+1); $i++) {
      print "Error: $error_msg[$i]\n";
    }
    print "\n";

  }

  if ($error > 0 or $FORM->{'VERBOSE'} ) {
    print "Argument Information:\n";
    print "\t--path-to-mp3s: $FORM->{'path-to-mp3s'}\n";
    print "\t--batch-file: $FORM->{'batch-file'}\n";
    print "\t--verbose: ", &int_to_truefalse($FORM->{'VERBOSE'}),"\n";
    print "\t--overwrite: ", &int_to_truefalse($FORM->{'OVERWRITE'}),"\n\n";
  }

  if ($error > 0) {
    print "\n\nSample Command:  perl make_batch --verbose --overwrite --path-to-mp3s=/home/mp3s/ --batch-file=temp.sh\n";
    die ("\nExiting...\n\n");
  }
}
 
sub int_to_truefalse {
  my ($int) = @_;

  if ($int) {
    return "True";
  } else {
    return "False";
  }
}
