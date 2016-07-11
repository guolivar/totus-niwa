#! /bin/bash
#
# load and post process OSM data
#

usage () {
  cat <<EOF

NAME
        $(basename $0) - loads OSM data to Totus database

SYNOPSIS
        $(basename $0) -i <OSM input dir> -r <region> -s <db server> -d <db name> -u <db user> -p <db password> -h

DESCRIPTION

        -i    directory containing OSM data to import
        -r    region identifier for osm data extraction
        -s    database server (host) [optional]
        -d    database name to import OSM data to
        -u    database user to connect as 
        -p    password for above user
        -h    help

EOF
}

[ "$BIN" ] || BIN=`cd $(dirname $0); pwd`

# import common functions
. $BIN/common.sh

# 
parseOptions $*
#

# assign global command line parameters
data=$DATA
server=$SERVER
db=$DB
user=$USER
passwd=$PASSWD
schema="osm"
region=$RGN

OSMOSIS=$BIN/../thirdparty/osmosis
OSM_NZ_URL="http://download.geofabrik.de/australia-oceania/new-zealand-latest.osm.bz2"

[ -d $data ]  || mkdir $data

# fetch NZ planet file
[ -s $data/new_zealand.osm.bz2 ] || {
  (
    cd $data
    wget -O new_zealand.osm.bz2 $OSM_NZ_URL
    [ $? -ne 0 ] && ABORT "Unable to download: $OSM_NZ_URL"
    exit 0
  )
  [ $? -ne 0 ] && ABORT "OSM: Planet file download failed for New Zealand"
}

if [ $region == "AK" ]
then
    # extract AKL
    bzcat $data/new_zealand.osm.bz2 \
    | $OSMOSIS/bin/osmosis \
        --read-xml enableDateParsing=no file=/dev/stdin \
        --bounding-box top=-35.8754 left=174.1437 bottom=-37.3059 right=175.6234 --write-xml file=$data/region.osm
fi

if [ $region == "CH" ]
then
    # extract Christchurch
    bzcat $data/new_zealand.osm.bz2 \
    | $OSMOSIS/bin/osmosis \
        --read-xml enableDateParsing=no file=/dev/stdin \
        --bounding-box top=-41.718 left=168.931 bottom=-45.170 right=176.237 --write-xml file=$data/region.osm
fi
# import the OSM data
(
  cd $data

  $OSMOSIS/bin/osmosis --read-xml file=region.osm --write-pgsimp-dump directory="./"
  [ $? -ne 0 ] && { ABORT "Failed convert OSM planet file to PG import format"; }

  PGPASSWORD=$passwd psql -q -e -a -h $server -d $db -U $user <<EOF
    \set ON_ERROR_STOP
    SET search_path = $schema, public;

    -- load data primitives
    \copy users FROM 'users.txt'
    \copy nodes FROM 'nodes.txt'
    \copy node_tags FROM 'node_tags.txt'
    \copy ways (id, version, user_id, tstamp, changeset_id) FROM 'ways.txt'
    \copy way_tags FROM 'way_tags.txt'
    \copy way_nodes FROM 'way_nodes.txt'
    \copy relations FROM 'relations.txt'
    \copy relation_tags FROM 'relation_tags.txt'
    \copy relation_members FROM 'relation_members.txt'

    -- add unknown user
    INSERT INTO users (id, name) VALUES(-1, 'Unknown');

    -- trim nodes not present in data extract, eg outside bounds
    DELETE FROM way_nodes WHERE node_id IN (
      SELECT wn.node_id 
        FROM way_nodes wn
    LEFT JOIN nodes n
          ON wn.node_id = n.id
      WHERE n.id IS NULL);
EOF
  [ $? -ne 0 ] && { ABORT "Failed loading OSM schema"; }

  \rm -vf *.txt

  exit 0
)

exit $?
