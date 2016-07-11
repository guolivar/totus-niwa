#! /bin/bash
#
# load and post process pgRouting data
#

usage () {
  cat <<EOF

NAME
        $(basename $0) - loads OSM data as pgRouting road network data to Totus database

SYNOPSIS
        $(basename $0) -i <OSM input dir> -s <db server> -d <db name> -u <db user> -p <db password> -h

DESCRIPTION

        -i    directory containing OSM data to import as pgRouting road network
        -s    database server (host) [optional]
        -d    database name to import pgRouting road network data to
        -u    database user to connect as 
        -p    password for above user
        -h    help

EOF
}

loadRouteCosts () {
  local server=$1
  local db=$2
  local schema=$3
  local user=$4

  INFO "Loading route costs for OSM road types"

  PGPASSWORD=$passwd psql -q -e -a -h $server -d $db -U $user <<EOF
    \set ON_ERROR_STOP

    SET search_path = $schema, public;

    -- basic costing, assuming it's all relative to one another within each class
    -- the per class cost can be overwritten by using the costing options below
    --
    -- highway class
    UPDATE classes SET cost =   0.1  WHERE name = 'motorway' AND type_id = (SELECT id FROM types WHERE name = 'highway'); 
    UPDATE classes SET cost =   0.1  WHERE name = 'motorway_link' AND type_id = (SELECT id FROM types WHERE name = 'highway'); 
    UPDATE classes SET cost =   0.3  WHERE name = 'motorway_junction' AND type_id = (SELECT id FROM types WHERE name = 'highway'); 
    UPDATE classes SET cost =   0.3  WHERE name = 'trunk' AND type_id = (SELECT id FROM types WHERE name = 'highway'); 
    UPDATE classes SET cost =   0.3  WHERE name = 'trunk_link' AND type_id = (SELECT id FROM types WHERE name = 'highway'); 
    UPDATE classes SET cost =   0.5  WHERE name = 'primary' AND type_id = (SELECT id FROM types WHERE name = 'highway'); 
    UPDATE classes SET cost =   0.5  WHERE name = 'primary_link' AND type_id = (SELECT id FROM types WHERE name = 'highway'); 
    UPDATE classes SET cost =   0.7  WHERE name = 'secondary' AND type_id = (SELECT id FROM types WHERE name = 'highway'); 
    UPDATE classes SET cost =   0.7  WHERE name = 'secondary_link' AND type_id = (SELECT id FROM types WHERE name = 'highway'); 
    UPDATE classes SET cost =   0.8  WHERE name = 'tertiary' AND type_id = (SELECT id FROM types WHERE name = 'highway'); 
    UPDATE classes SET cost =   0.8  WHERE name = 'tertiary_link' AND type_id = (SELECT id FROM types WHERE name = 'highway'); 
    UPDATE classes SET cost =   1.0  WHERE name = 'residential' AND type_id = (SELECT id FROM types WHERE name = 'highway'); 
    UPDATE classes SET cost =   1.0  WHERE name = 'unclassified' AND type_id = (SELECT id FROM types WHERE name = 'highway'); 
    UPDATE classes SET cost =   1.0  WHERE name = 'road' AND type_id = (SELECT id FROM types WHERE name = 'highway'); 
    UPDATE classes SET cost =   1.25 WHERE name = 'living_street' AND type_id = (SELECT id FROM types WHERE name = 'highway'); 
    UPDATE classes SET cost =   1.5  WHERE name = 'service' AND type_id = (SELECT id FROM types WHERE name = 'highway'); 
    UPDATE classes SET cost =   2.0  WHERE name = 'byway' AND type_id = (SELECT id FROM types WHERE name = 'highway'); 
    UPDATE classes SET cost =   2.0  WHERE name = 'subway' AND type_id = (SELECT id FROM types WHERE name = 'highway'); 
    UPDATE classes SET cost =   5.0  WHERE name = 'bridleway' AND type_id = (SELECT id FROM types WHERE name = 'highway'); 
    UPDATE classes SET cost =  15.0  WHERE name = 'turning_circle' AND type_id = (SELECT id FROM types WHERE name = 'highway'); 
    UPDATE classes SET cost =  15.0  WHERE name = 'bus_guideway' AND type_id = (SELECT id FROM types WHERE name = 'highway'); 
    UPDATE classes SET cost =  50.0  WHERE name = 'path' AND type_id = (SELECT id FROM types WHERE name = 'highway'); 
    UPDATE classes SET cost =  50.0  WHERE name = 'track' AND type_id = (SELECT id FROM types WHERE name = 'highway'); 
    UPDATE classes SET cost =  50.0  WHERE name = 'steps' AND type_id = (SELECT id FROM types WHERE name = 'highway'); 
    UPDATE classes SET cost =  50.0  WHERE name = 'pedestrian' AND type_id = (SELECT id FROM types WHERE name = 'highway'); 
    UPDATE classes SET cost =  50.0  WHERE name = 'cycleway' AND type_id = (SELECT id FROM types WHERE name = 'highway'); 
    UPDATE classes SET cost =  50.0  WHERE name = 'footway' AND type_id = (SELECT id FROM types WHERE name = 'highway'); 
    UPDATE classes SET cost = 999.0  WHERE name = 'construction' AND type_id = (SELECT id FROM types WHERE name = 'highway'); 
    UPDATE classes SET cost =  50.0  WHERE name = 'raceway' AND type_id = (SELECT id FROM types WHERE name = 'highway'); 

    -- cycleway class
    UPDATE classes SET cost =   0.5  WHERE name = 'no' AND type_id = (SELECT id FROM types WHERE name = 'cycleway'); 
    UPDATE classes SET cost =   0.3  WHERE name = 'segregated' AND type_id = (SELECT id FROM types WHERE name = 'cycleway'); 
    UPDATE classes SET cost =   1.0  WHERE name = 'shared' AND type_id = (SELECT id FROM types WHERE name = 'cycleway'); 
    UPDATE classes SET cost =   0.3  WHERE name = 'lane' AND type_id = (SELECT id FROM types WHERE name = 'cycleway'); 
    UPDATE classes SET cost =   0.3  WHERE name = 'opposite' AND type_id = (SELECT id FROM types WHERE name = 'cycleway'); 
    UPDATE classes SET cost =   0.4  WHERE name = 'opposite_lane' AND type_id = (SELECT id FROM types WHERE name = 'cycleway'); 
    UPDATE classes SET cost =   0.2  WHERE name = 'track' AND type_id = (SELECT id FROM types WHERE name = 'cycleway'); 

    -- track class
    UPDATE classes SET cost =   2.0  WHERE name = 'grade1' AND type_id = (SELECT id FROM types WHERE name = 'tracktype'); 
    UPDATE classes SET cost =   2.1  WHERE name = 'grade2' AND type_id = (SELECT id FROM types WHERE name = 'tracktype'); 
    UPDATE classes SET cost =   2.2  WHERE name = 'grade3' AND type_id = (SELECT id FROM types WHERE name = 'tracktype'); 
    UPDATE classes SET cost =   2.3  WHERE name = 'grade4' AND type_id = (SELECT id FROM types WHERE name = 'tracktype'); 
    UPDATE classes SET cost =   2.4  WHERE name = 'grade5' AND type_id = (SELECT id FROM types WHERE name = 'tracktype'); 

    -- junction class
    UPDATE classes SET cost =   0.7  WHERE name = 'roundabout' AND type_id = (SELECT id FROM types WHERE name = 'junction'); 

    -- class costing weight per costing option
    INSERT INTO costing_options (option, description)
    VALUES ('distance',   'No road class costing, distance routing only'),
           ('pedestrian', 'Cost road class for pedestrian routing'),
           ('cycling',    'Cost road class for cycling routing'),
           ('vehicle',    'Cost road class for generic vehicle routing');

    -- the cost is apply by scaling the length of the edge in the graph 
    -- therefore pure distance based routing is done by scaling length with cost factor of 1
    -- we use a cost of 100000.00 for specific class of road we would like to avoid, this
    -- cannot be enforced, shortest path will always give a path
    -- by using a huge cost we try and encourage algorithm to avoid them if it has other options
    --
    INSERT INTO class_costs (option_id, class_id, cost)
    SELECT o.id AS option_id,
           c.id AS class_id,
           m.cost 
      FROM (
        VALUES ('distance',    'highway',    'motorway',                 1.0),
               ('distance',    'highway',    'motorway_link',            1.0),
               ('distance',    'highway',    'motorway_junction',        1.0),
               ('distance',    'highway',    'trunk',                    1.0),
               ('distance',    'highway',    'trunk_link',               1.0),
               ('distance',    'highway',    'primary',                  1.0),
               ('distance',    'highway',    'primary_link',             1.0),
               ('distance',    'highway',    'secondary',                1.0),
               ('distance',    'highway',    'secondary_link',           1.0),
               ('distance',    'highway',    'tertiary',                 1.0),
               ('distance',    'highway',    'tertiary_link',            1.0),
               ('distance',    'highway',    'residential',              1.0),
               ('distance',    'highway',    'unclassified',             1.0),
               ('distance',    'highway',    'road',                     1.0),
               ('distance',    'highway',    'living_street',            1.0),
               ('distance',    'highway',    'service',                  1.0),
               ('distance',    'highway',    'byway',                    1.0),
               ('distance',    'highway',    'subway',                   1.0),
               ('distance',    'highway',    'bridleway',                1.0),
               ('distance',    'highway',    'turning_circle',           1.0),
               ('distance',    'highway',    'bus_guideway',             1.0),
               ('distance',    'highway',    'path',                     1.0),
               ('distance',    'highway',    'track',                    1.0),
               ('distance',    'highway',    'steps',                    1.0),
               ('distance',    'highway',    'pedestrian',               1.0),
               ('distance',    'highway',    'cycleway',                 1.0),
               ('distance',    'highway',    'footway',                  1.0),
               ('distance',    'highway',    'construction',             1.0),
               ('distance',    'highway',    'raceway',                  1.0),
               ('distance',    'cycleway',   'no',                       1.0),
               ('distance',    'cycleway',   'segregated',               1.0),
               ('distance',    'cycleway',   'shared',                   1.0),
               ('distance',    'cycleway',   'lane' ,                    1.0),
               ('distance',    'cycleway',   'opposite',                 1.0),
               ('distance',    'cycleway',   'opposite_lane',            1.0),
               ('distance',    'cycleway',   'track',                    1.0),
               ('distance',    'tracktype',  'grade1',                   1.0),
               ('distance',    'tracktype',  'grade2',                   1.0),
               ('distance',    'tracktype',  'grade3',                   1.0),
               ('distance',    'tracktype',  'grade4',                   1.0),
               ('distance',    'tracktype',  'grade5',                   1.0),
               ('distance',    'junction',   'roundabout',               1.0),
               ('pedestrian',  'highway',    'motorway',                 100000.0),
               ('pedestrian',  'highway',    'motorway_link',            100000.0),
               ('pedestrian',  'highway',    'motorway_junction',        100000.0),
               ('pedestrian',  'highway',    'trunk',                    100000.0),
               ('pedestrian',  'highway',    'trunk_link',               100000.0),
               ('pedestrian',  'highway',    'primary',                  1.0),
               ('pedestrian',  'highway',    'primary_link',             1.0),
               ('pedestrian',  'highway',    'secondary',                1.0),
               ('pedestrian',  'highway',    'secondary_link',           1.0),
               ('pedestrian',  'highway',    'tertiary',                 0.75),
               ('pedestrian',  'highway',    'tertiary_link',            0.75),
               ('pedestrian',  'highway',    'residential',              0.75),
               ('pedestrian',  'highway',    'unclassified',             0.75),
               ('pedestrian',  'highway',    'road',                     0.75),
               ('pedestrian',  'highway',    'living_street',            0.75),
               ('pedestrian',  'highway',    'service',                  0.5),
               ('pedestrian',  'highway',    'byway',                    1.0),
               ('pedestrian',  'highway',    'subway',                   100000.0),
               ('pedestrian',  'highway',    'bridleway',                1.0),
               ('pedestrian',  'highway',    'turning_circle',           100000.0),
               ('pedestrian',  'highway',    'bus_guideway',             100000.0),
               ('pedestrian',  'highway',    'path',                     0.2),
               ('pedestrian',  'highway',    'track',                    0.2),
               ('pedestrian',  'highway',    'steps',                    0.25),
               ('pedestrian',  'highway',    'pedestrian',               0.1),
               ('pedestrian',  'highway',    'cycleway',                 0.2),
               ('pedestrian',  'highway',    'footway',                  0.1),
               ('pedestrian',  'highway',    'construction',             100000.0),
               ('pedestrian',  'highway',    'raceway',                  100000.0),
               ('pedestrian',  'cycleway',   'no',                       0.5),
               ('pedestrian',  'cycleway',   'segregated',               0.5),
               ('pedestrian',  'cycleway',   'shared',                   0.5),
               ('pedestrian',  'cycleway',   'lane' ,                    0.5),
               ('pedestrian',  'cycleway',   'opposite',                 0.5),
               ('pedestrian',  'cycleway',   'opposite_lane',            0.5),
               ('pedestrian',  'cycleway',   'track',                    0.5),
               ('pedestrian',  'tracktype',  'grade1',                   0.5),
               ('pedestrian',  'tracktype',  'grade2',                   0.5),
               ('pedestrian',  'tracktype',  'grade3',                   0.5),
               ('pedestrian',  'tracktype',  'grade4',                   0.5),
               ('pedestrian',  'tracktype',  'grade5',                   0.5),
               ('pedestrian',  'junction',   'roundabout',               100000.0),
               ('vehicle',     'highway',    'motorway',                 0.1),
               ('vehicle',     'highway',    'motorway_link',            0.1),
               ('vehicle',     'highway',    'motorway_junction',        0.1),
               ('vehicle',     'highway',    'trunk',                    0.2),
               ('vehicle',     'highway',    'trunk_link',               0.2),
               ('vehicle',     'highway',    'primary',                  0.4),
               ('vehicle',     'highway',    'primary_link',             0.4),
               ('vehicle',     'highway',    'secondary',                0.5),
               ('vehicle',     'highway',    'secondary_link',           0.5),
               ('vehicle',     'highway',    'tertiary',                 0.8),
               ('vehicle',     'highway',    'tertiary_link',            0.8),
               ('vehicle',     'highway',    'residential',              1.0),
               ('vehicle',     'highway',    'unclassified',             1.0),
               ('vehicle',     'highway',    'road',                     1.0),
               ('vehicle',     'highway',    'living_street',            1.2),
               ('vehicle',     'highway',    'service',                  1.5),
               ('vehicle',     'highway',    'byway',                    2.0),
               ('vehicle',     'highway',    'subway',                   2.0),
               ('vehicle',     'highway',    'bridleway',                5.0),
               ('vehicle',     'highway',    'turning_circle',           15.0),
               ('vehicle',     'highway',    'bus_guideway',             100.0),
               ('vehicle',     'highway',    'path',                     100.0),
               ('vehicle',     'highway',    'track',                    100.0),
               ('vehicle',     'highway',    'steps',                    100000.0),
               ('vehicle',     'highway',    'pedestrian',               100000.0),
               ('vehicle',     'highway',    'cycleway',                 100000.0),
               ('vehicle',     'highway',    'footway',                  100000.0),
               ('vehicle',     'highway',    'construction',             100000.0),
               ('vehicle',     'highway',    'raceway',                  100000.0),
               ('vehicle',     'cycleway',   'no',                       100000.0),
               ('vehicle',     'cycleway',   'segregated',               100000.0),
               ('vehicle',     'cycleway',   'shared',                   100000.0),
               ('vehicle',     'cycleway',   'lane' ,                    100000.0),
               ('vehicle',     'cycleway',   'opposite',                 100000.0),
               ('vehicle',     'cycleway',   'opposite_lane',            100000.0),
               ('vehicle',     'cycleway',   'track',                    100000.0),
               ('vehicle',     'tracktype',  'grade1',                   100000.0),
               ('vehicle',     'tracktype',  'grade2',                   100000.0),
               ('vehicle',     'tracktype',  'grade3',                   100000.0),
               ('vehicle',     'tracktype',  'grade4',                   100000.0),
               ('vehicle',     'tracktype',  'grade5',                   100000.0),
               ('vehicle',     'junction',   'roundabout',               100000.0),
               ('cycling',     'highway',    'motorway',                 100000.0),
               ('cycling',     'highway',    'motorway_link',            100000.0),
               ('cycling',     'highway',    'motorway_junction',        100000.0),
               ('cycling',     'highway',    'trunk',                    1.0),
               ('cycling',     'highway',    'trunk_link',               1.0),
               ('cycling',     'highway',    'primary',                  0.50),
               ('cycling',     'highway',    'primary_link',             0.50),
               ('cycling',     'highway',    'secondary',                0.50),
               ('cycling',     'highway',    'secondary_link',           0.50),
               ('cycling',     'highway',    'tertiary',                 0.75),
               ('cycling',     'highway',    'tertiary_link',            0.75),
               ('cycling',     'highway',    'residential',              0.75),
               ('cycling',     'highway',    'unclassified',             0.75),
               ('cycling',     'highway',    'road',                     0.75),
               ('cycling',     'highway',    'living_street',            0.75),
               ('cycling',     'highway',    'service',                  0.5),
               ('cycling',     'highway',    'byway',                    10.0),
               ('cycling',     'highway',    'subway',                   100000.0),
               ('cycling',     'highway',    'bridleway',                10.0),
               ('cycling',     'highway',    'turning_circle',           100000.0),
               ('cycling',     'highway',    'bus_guideway',             100000.0),
               ('cycling',     'highway',    'path',                     2.0),
               ('cycling',     'highway',    'track',                    2.0),
               ('cycling',     'highway',    'steps',                    5.0),
               ('cycling',     'highway',    'pedestrian',               2.0),
               ('cycling',     'highway',    'cycleway',                 0.1),
               ('cycling',     'highway',    'footway',                  2.0),
               ('cycling',     'highway',    'construction',             100000.0),
               ('cycling',     'highway',    'raceway',                  100000.0),
               ('cycling',     'cycleway',   'no',                       0.1),
               ('cycling',     'cycleway',   'segregated',               0.1),
               ('cycling',     'cycleway',   'shared',                   0.5),
               ('cycling',     'cycleway',   'lane' ,                    0.1),
               ('cycling',     'cycleway',   'opposite',                 0.1),
               ('cycling',     'cycleway',   'opposite_lane',            0.1),
               ('cycling',     'cycleway',   'track',                    1.0),
               ('cycling',     'tracktype',  'grade1',                   1.0),
               ('cycling',     'tracktype',  'grade2',                   1.0),
               ('cycling',     'tracktype',  'grade3',                   1.0),
               ('cycling',     'tracktype',  'grade4',                   1.0),
               ('cycling',     'tracktype',  'grade5',                   1.0),
               ('cycling',     'junction',   'roundabout',               100000.0)
           ) AS m (option, type, class, cost)
      JOIN costing_options AS o
           ON m.option = o.option
      JOIN types AS t
           ON m.type = t.name
      JOIN classes AS c
           ON t.id = c.type_id AND
              m.class = c.name;

EOF

  [ $? -ne 0 ] && { ABORT "Failed loading route costs for OSM road types"; }

  return 0
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
schema="network"

OSM2PGROUTING_DIR=$BIN/../thirdparty/osm2pgrouting
OSM2PGROUTING=$OSM2PGROUTING_DIR/osm2pgrouting
OSM2PGROUTING_CONFIG=$OSM2PGROUTING_DIR/mapconfig.xml

[ -e $OSM2PGROUTING ] || {
  # build it
  cd $OSM2PGROUTING_DIR && make
}

# load OSM data to pgRouting
INFO "Loading and converting OSM data: $data/region.osm to pgRouting road network"
$OSM2PGROUTING -file $data/region.osm -conf $OSM2PGROUTING_CONFIG -dbname $db -user $user \
               -host $server -passwd $passwd -schema $schema

[ $? -ne 0 ] && ABORT "Failed loading OSM data to pgRouting road network"

# load route costing matrix
loadRouteCosts $server $db $schema $user

exit $?
