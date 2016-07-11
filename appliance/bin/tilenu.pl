#! /usr/bin/perl
#

use strict;
use warnings;

use Math::Trig;

use constant SPHERE_MERCATOR             => 20037508.34;
use constant SPHERE_MERCATOR_GROUND_SIZE => (SPHERE_MERCATOR*2);
use constant GRID_ORIG_X                 => (-1. * SPHERE_MERCATOR);
use constant GRID_ORIG_Y                 => (+1. * SPHERE_MERCATOR);
use constant M_PI                        => 3.141593;

sub mercX2lon ($) {
  my $x = shift;

  return $x / SPHERE_MERCATOR * 180.;
}

sub mercY2lat ($) {
  my $y = shift;

  my $l = $y / SPHERE_MERCATOR * 180.;

  return 180. / M_PI * ( 2. * atan( exp ( $l * M_PI / 180 ) ) - M_PI / 2 );
}

sub lon2mercX ($) {
  my $lon = shift;

  return $lon * SPHERE_MERCATOR / 180.;
}

sub lat2mercY ($) {
  my $lat = shift;

  my $y = log( tan( (90. + $lat ) * M_PI / 360.) ) / ( M_PI / 180.);

  return $y * SPHERE_MERCATOR / 180.;
}

sub lon2tileX ($$) {
  my ($lon, $tilesz) = @_;

  return int ((lon2mercX($lon) - GRID_ORIG_X) / $tilesz);
}

sub lat2tileY ($$) {
  my ($lat, $tilesz) = @_;

  return int ((GRID_ORIG_Y - lat2mercY($lat)) / $tilesz);
}

if (scalar @ARGV != 3) {
  print "ERROR: Supply longitude, latitude and zoom level\n";
  exit (1);
}

my ($lon, $lat, $zoom) = @ARGV;

my $tilesz = SPHERE_MERCATOR_GROUND_SIZE / ( 1 << $zoom);

print lon2tileX ($lon, $tilesz) . "," .  lat2tileY ($lat, $tilesz) . "\n";
