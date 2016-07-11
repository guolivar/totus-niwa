#! /bin/bash
# 
# loads Census demographic data to Census schema
# loads Meshblock and Area geometry to temporary table
# and attach to census geoographies
#

usage () {
  cat <<EOF

NAME
        $(basename $0) - loads Census data to Totus database

SYNOPSIS
        $(basename $0) -i <Census input dir> -s <db server> -d <db name> -u <db user> -p <db password> -h

DESCRIPTION

        -i    directory containing Census data to import
        -s    database server (host) [optional]
        -d    database name to import Census data to
        -u    database user to connect as 
        -p    password for above user [optional]
        -h    help

EOF
}

#
# load Census administrative area and meshblock demographic data
loadCensusData () {
  local server=$1
  local db=$2
  local user=$3
  local passwd=$4
  local schema=$5
  local data=$6

  INFO "Loading census data from $data"

  $BIN/loadCensus.pl -i $data -s $server -d $db -u $user -p $passwd -c $BIN/census.ini
  [ $? -ne 0 ] && { 
    ABORT "Error occurred populating Census data"
  }
}

#
# load Census administrative area geometry
loadAdminAreaGeometry () {
  local server=$1
  local db=$2
  local user=$3
  local passwd=$4
  local schema=$5
  local data=$6

  INFO "Loading temporary Census geography tables"
  for file in $RC_GEOM_LAYERS; do
    infile=$data/${file}.shp
    layer=${file}_4326
    shpfile=$data/${layer}.shp
    table=$(echo "${file}" | gawk '{ print tolower ($0) '})

    if [ -s $infile ]; then 
      echo "DROP TABLE IF EXISTS ${schema}.${table};"

      # reproject to geographical coordinates
      ogr2ogr -f "ESRI Shapefile" $shpfile -s_srs EPSG:27200 -t_srs EPSG:4326 $infile

      [ $? -ne 0 ] && { ABORT "Reprojecting shapefile: $shpfile from NZMG to WGS84 failed"; }

      # convert shape file to PG SQL COPY statements
      PGPASSWORD=$passwd psql -q -e -a -h $server -d $db -U $user <<EOF
      \set ON_ERROR_STOP
      SET search_path = $schema, public;
      DROP TABLE IF EXISTS $table;

      $(shp2pgsql -c -s 4326 -I -D -g geom $data/$layer $table)

      UPDATE ${schema}.admin_area SET geom = ${table}.geom
        FROM ${table}
       WHERE $(echo $table | gawk '/^(AU|au)/ { print $0".au_no"; } /^(MB|mb)/ { print $0".mb06"; }') = census_identifier;

      DROP TABLE census.${table};
EOF
      rm -f $data/${layer}.*
    else
      ABORT "Shape file: $infile not found"
    fi
  done


  [ $? -ne 0 ] && { ABORT "Failed importing Census geography data"; }

  return 0
}

#
# globals
#
[ "$BIN" ] || BIN=`cd $(dirname $0); pwd`

# define the Regional Council geometry layers to import
RC_GEOM_LAYERS="AU_RC MB_RC";

# import common functions
. $BIN/common.sh

# 
# parse command line options
parseOptions $*

# assign global command line parameters
data=$DATA
server=$SERVER
db=$DB
user=$USER
passwd=$PASSWD
clean=$CLEANDB
schema="census"

ls -1 $data/*.xls &> /dev/null

[ $? -ne 0 ] && { WARN "No census data found, skipping census data load"; exit 0; }

# load Census data first
loadCensusData $server $db $user $passwd $schema $data

# load Admin area geometry next, it updates the admin areas loaded above
loadAdminAreaGeometry $server $db $user $passwd $schema $data

exit 0;
