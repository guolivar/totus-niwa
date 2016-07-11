#!/bin/bash
#
# Get NZ OSM data
# Extract OSM data for Auckland
# Create OSM simple data schema, load with data
# Import OSM data to PG routing
# 

usage () {
  cat <<EOF

NAME
        $(basename $0) - TOTUS loader

SYNOPSIS
        $(basename $0) -i <data> -r <region> -s <database server> -d <database name> -u <database user> -p <database password> -b -h

DESCRIPTION

        -i    directory to hold OSM/TrafficModel data
        -r    region to set the data up for
        -s    database server (host) [optional]
        -d    database name to import all data to
        -u    database user to connect as 
        -p    password for above user [optional]
        -h    help

EOF
}

# globals
export BIN=`cd $(dirname $0); pwd`
#

# main
#
# import common functions
. $BIN/common.sh

# 
parseOptions $*
#

data=$DATA
server=$SERVER
database=$DB
user=$USER
passwd=$PASSWD
region=$RGN

# mandatory
[ "$database" -o "$passwd" ] || { 
  ERROR "Require database name and user password to import data"
  usage
  exit 1
}

# prepare OSM schema
[ -d $data/osm ] || mkdir $data/osm
$BIN/loadOSM.sh -i $data/osm -r $region -s $server -d $database -u $user -p $passwd
[ $? -ne 0 ] && { 
  ABORT "Error occurred preparing OSM data schema"
}

# prepare pgRouting schema
$BIN/loadPGRouting.sh -i $data/osm -s $server -d $database -u $user -p $passwd
[ $? -ne 0 ] && { 
  ABORT "Error occurred preparing pgRouting data schema"
}

# prepare Traffic Model schema
$BIN/loadTrafficModel.sh -i $data/traffic -r $region -s $server -d $database -u $user -p $passwd
[ $? -ne 0 ] && { 
  ABORT "Error occurred preparing Traffic Model data schema"
}

# prepare Exposure schema
$BIN/loadExposure.sh -i $data/traffic -s $server -d $database -u $user -p $passwd
[ $? -ne 0 ] && { 
  ABORT "Error occurred preparing Exposure data schema"
}

# prepare Census schema
$BIN/loadCensus.sh -i $data/census -s $server -d $database -u $user -p $passwd
[ $? -ne 0 ] && { 
  ABORT "Error occurred preparing Census data schema"
}

# prepare Energy schema
$BIN/loadEnergy.sh -i /tmp -s $server -d $database -u $user -p $passwd
[ $? -ne 0 ] && { 
  ABORT "Error occurred preparing Energy data schema"
}

exit 0
