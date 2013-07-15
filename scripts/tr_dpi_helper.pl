#! /usr/bin/env perl

use IO::Handle;
use IO::Socket;
use IO::File;

use strict;
use warnings;

no utf8;

{
  my ($odd);
  my ($even);
  my ($dpi);
  if ($#ARGV >= 0) {
    $odd = $ARGV[0];
  } else {
    printf("Give line length of ODD pages in pixels\n");
    $odd =  <STDIN>;
  }
  $odd = 0 + $odd;
  if ($odd < 50 || $odd > 10000) {
    die "Invalid value."
  }

  if ($#ARGV >= 1) {
    $even = $ARGV[1];
  } else {
    printf("Give line length of EVEN pages in pixels\n");
    $even = <STDIN>;
  }
  $even = 0 + $even;
  if ($even < 50 || $even > 10000) {
    die "Invalid value."
  }

  if ($#ARGV >= 2) {
    $dpi = $ARGV[2];
  } else {
    printf("Give nominal DPI of scan\n");
    $dpi = <STDIN>;
  }
  $dpi = int(0 + $dpi);
  if ($dpi < 100 || $dpi > 900) {
    die "Invalid value."
  }

  my ($avg) = ($odd + $even) / 2.0;
  my ($r1) = 1.0 + ((1.0 * ($avg - $odd)) / $odd);
  my ($r2) = 1.0 + ((1.0 * ($avg - $even)) / $even);
  my ($odpi) = $dpi / $r1;
  my ($edpi) = $dpi / $r2;
  my ($ocdpi) =  $odpi / 1.07;
  my ($ecdpi) =  $edpi / 1.07;

  printf("Odd pages line length %d pixels\n", $odd);
  printf("Even pages line length %d pixels\n", $even);
  printf("Even pages line length %d pixels\n", $even);
  printf("Average line length %d pixels\n", $avg);
  printf("Multiplier for odd-to-average %.4f\n", $r1);
  printf("Multiplier for even-to-average %.4f\n", $r2);
  printf("Nominal DPI %d pixels per inch\n", $dpi);
  printf("Odd pages DPI %d pixels per inch\n", $odpi);
  printf("Even pages DPI %d pixels per inch\n", $edpi);
  printf("Odd cover pages DPI %d pixels per inch\n", $ocdpi);
  printf("Even cover pages DPI %d pixels per inch\n", $ecdpi);
  printf("\n");

  printf('for i in pg-???[13579].jpg ; do convert -density %d "$i" dens/"$i"; done' . "\n", $odpi);
  printf('for i in pg-???[02468].jpg ; do convert -density %d "$i" dens/"$i"; done' . "\n", $edpi);
  printf('for i in cover-???[13579].jpg ; do convert -density %d "$i" dens/"$i"; done' . "\n", $ocdpi);
  printf('for i in cover-???[02468].jpg ; do convert -density %d "$i" dens/"$i"; done' . "\n", $ecdpi);
  printf("\n");
}

sub max ($$) { $_[$_[0] < $_[1]] }
sub min ($$) { $_[$_[0] > $_[1]] }
