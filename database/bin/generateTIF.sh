#! /bin/bash
#
# Generate TIF for input coordinates:
# - segment CSV file of coordinates into multiple parts
# - submits file to http://totus.uat.niwa.co.nz/totus-server/cumulative_tif
# - merge output files into one
#

usage () {
  cat <<EOF


NAME
        $(basename $0) - Generate TIF for input coordinates

SYNOPSIS
        $(basename $0) -i <CSV file> -n <number of coordinates> -h

DESCRIPTION

        -i    CSV file containing x, y coordinates
        -n    Number of coordinates to submit at a time
        -h    help

EOF
}

TIF_URL=http://totus.uat.niwa.co.nz/totus-server/cumulative_tif

while getopts "i:n:h" opt; do
  case $opt in
    i):
      inputFile=$OPTARG
      ;;
    n):
      numberOfCoords=$OPTARG
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

[ $# -eq 0 ] && { usage; exit 1; }

[ "$inputFile" ] && [ -s $inputFile ] || {
  echo "ERROR: Invalid input file: $inputFile provided"
  exit 1
}

[ "$numberOfCoords" ] && [ $numberOfCoords -gt 0 ] || {
  echo "ERROR: Invalid number of coordinates: $numberOfCoords provided"
  exit 1
}

tempFile=$(mktemp)
outputFile=${inputFile%%.csv}"_out.csv"

# sort on longitude and latitude
cat $inputFile | sort > $tempFile
mv $tempFile $inputFile

# remove dos line endings
dos2unix $inputFile

# split on number of coordinates into multiple parts
split -l $numberOfCoords $inputFile $tempFile

# process each part, merge them when done
(
  for f in $tempFile*; do
    coords=$(cat $f | grep -e "[0-9]" | tr -s "," " " | tr -s "\n" ",")
    len=${#coords}
    let len-=1

    # strip of last comma from coordinates and URL encode
    coords="$(perl -MURI::Escape -e 'print uri_escape($ARGV[0]);' "${coords:0:$len}")"

    params="dispersion_factor=-0.65&road_count=20&inclusion_distance=10&format=csv&coordinates=$coords"

    # fetch the output TIF
    curl -G -d "$params" $TIF_URL 

    [ $? -ne 0 ] && { echo "Curl error: $? submitting $f as $params"; exit 1; }
  done
) | grep -e "[0-9]" \
  | gawk -F"," '{ print $3, $2, $4 }' OFS="," \
  | sort \
  | gawk -F"," 'BEGIN { print "x,y,tif" } { print $1, $2, $3 }' OFS="," > $outputFile

rm -f $tempFile*
