#! /bin/bash
#
# copies Traffic Model data from project folder into correct directory structure for loader
#
[ "$BIN" ] || BIN=`cd $(dirname $0); pwd`

# source common logging functions
initLogger () {
  . $BIN/logger.sh
}

usage () {
  cat <<EOF

NAME
        $(basename $0) - copies Traffic Model data from project folder into required directory structure

SYNOPSIS
        $(basename $0) -p <directory> -e <directory> -y <year>

DESCRIPTION

        -p    project directory to hold OSM/TrafficModel data, eg. /mnt/projects/TOTU101
        -e    output directory to hold the Traffic Model data for loader, eg. ~/data/traffic
        -y    year of the Traffic Model model run, eg. 2006


EOF
}

while getopts "p:e:y:" opt; do
  case $opt in
    p):
      projectDir=$OPTARG
      ;;
    e):
      trafficDir=$OPTARG
      ;;
    y):
      year=$OPTARG
      ;;
    h):
      usage
      exit 0
      ;;
    *):
      echo "Invalid option, see help:"
      usage
      exit 1
      ;;
  esac
done

# get logging functions
initLogger

[ "$projectDir" -a "$trafficDir" -a "$year" ] || { ERROR "Missing parameters."; usage; exit 1; }

[ -d $trafficDir ] || { 
  INFO "Creating Traffic Model directory: $trafficDir"
  mkdir $trafficDir || {
    ABORT "Failed creating Traffic Model directory: $trafficDir"
  }
}

[ -d $trafficDir/$year ] || { 
  INFO "Creating Traffic Model directory: $trafficDir/$year"
  mkdir $trafficDir/$year || {
    ABORT "Failed creating Traffic Model directory: $trafficDir/$year"
  }
}

aspDir=$projectDir/RawData/ASP_ART3

# copy non-peak data
INFO "Copying Traffic Model core data"

find $aspDir/02\ ShapeFiles -name "ATM2_Zones.*"  -exec cp {} $trafficDir/$year \;
find $aspDir/02\ ShapeFiles -name "traffic_links.*"  -exec cp {} $trafficDir/$year \;
find $aspDir/02\ ShapeFiles -name "traffic_tlines.*" -exec cp {} $trafficDir/$year \;

# copy peak data
for peak in AM IP PM; do
  INFO "Copying $peak Traffic Model data"

  [ -d $trafficDir/$year/$peak ] || { 
    INFO "Creating Traffic Model directory: $trafficDir/$year/$peak"
    mkdir $trafficDir/$year/$peak || {
      ABORT "Failed creating Traffic Model directory: $trafficDir/$year/$peak"
    }
  }

  cp $aspDir/06\ TrafficInfoOnRoadNetwork/${year}${peak}*Link_Info.csv $trafficDir/$year/$peak 
  cp $aspDir/07\ PTInfoOnRoadNetwork/${year}${peak}*PT_Link_Info.csv $trafficDir/$year/$peak
done

exit 0
