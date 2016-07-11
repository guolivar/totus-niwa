#! /bin/bash
#
# prepare exposure schema
#

usage () {
  cat <<EOF

NAME
        $(basename $0) - loads exposure data to Totus database

SYNOPSIS
        $(basename $0) -i <dummy input dir> -s <db server> -d <db name> -u <db user> -p <db password> -h

DESCRIPTION

        -i    dummy input directory (needed by load API, but unused)
        -s    database server (host) [optional]
        -d    database name to import exposure data to
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
schema="exposure"

# create no2 grid for 100m TIF
PGPASSWORD=$passwd psql -q -e -a -h $server -d $db -U $user <<EOF
  \set ON_ERROR_STOP
  SET search_path = $schema, public;

  -- cache NO2 and TIF, defaults to 100m grid
  INSERT INTO no2_grid (id, tif, no2, year, geom)
  SELECT (n).id, (n).tif, (n).no2, (n).year, (n).geom
    FROM (
      SELECT model_no2 (
            0.00171,
            11.9,
            100,
            10000,
            -0.65,
            10,
            FALSE,
            t.year,
            'AK'
        ) AS n
       FROM (
          SELECT DISTINCT year AS year
            FROM trafficmodel.link_traffic_data
       ) AS t
    ) AS m;

  -- make a copy of 100m grid, to be used for queries
  INSERT INTO grid (id, geom)
  SELECT id, geom
    FROM grid_100m;

  -- make a copy of 100m grid TIF Traffic Model edges, to be used for queries
  INSERT INTO grid_tif_edge (grid_id, edge_id, tif, rank, year)
  SELECT grid_id, edge_id, tif, rank, year
    FROM grid_100m_tif_edge;

  -- prepare the 500m grid used by front end
  SELECT COUNT(*) 
    FROM base_no2();

  -- no need for these anymore (that is until the next model_no2 run)
  DROP TABLE grid_100m_tif_edge;
  DROP TABLE grid_100m;
EOF

[ $? -ne 0 ] && ABORT "Failed loading exposure schema"

exit 0
