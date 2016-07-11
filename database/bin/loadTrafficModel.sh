#! /bin/bash
#
# load and post process Traffic Model data
#

usage () {
  cat <<EOF

NAME
        $(basename $0) - loads Traffic Model data to Totus database

SYNOPSIS
        $(basename $0) -i <trafficmodel input dir> -r <region> -s <db server> -d <db name> -u <db user> -p <db password> -h

DESCRIPTION

        -i    directory containing Traffic Model data to import
        -r    region identifier for traffic data extraction
        -s    database server (host) [optional]
        -d    database name to import Traffic Model data to
        -u    database user to connect as 
        -p    password for above user [optional]
        -h    help

EOF
}

#
# prepare all statements that loads data to work and Traffic Model tables
#
# params:
#  $1 - the data directory that holds the trafficmodel data, must have YYYY/(AM|IM|PM) sub directories
#  $2 - database schema
#
prepareLoadSQL () {
  local trafficmodelDir=$1
  local schema=$2

  # Get the TRAFFIC years
  local FILES=$trafficmodelDir/[0-9][0-9][0-9][0-9]

  for xyear in $FILES; do
    year=${xyear: -4}
    # convert all Traffic Model data to SQL load statements

    for file in $ATM_FILES $TRAFFIC_FILES; do
      infile=$trafficmodelDir/$year/${file}.shp
      layer=${file}_4326
      shpfile=$trafficmodelDir/$year/${layer}.shp
      table=${file}_${year}

      if [ -s $infile ]; then 
        echo "DROP TABLE IF EXISTS ${schema}.${table};"

        # reproject to geographical coordinates
        ogr2ogr -f "ESRI Shapefile" $shpfile -s_srs EPSG:2193 -t_srs EPSG:4326 $infile

        # convert shape file to PG SQL COPY statements
        shp2pgsql -c -s 4326 -I -D -g geom $trafficmodelDir/$year/$layer ${schema}.${table}
        rm -f $trafficmodelDir/$year/${layer}.*
      else
        ABORT "Shape file: $infile not found"
      fi
    done

    # load Traffic Model link traffic information
    for peak in $TRAFFIC_PEAKS; do
      dataDir=$trafficmodelDir/$year/$peak
      dataFile=$dataDir/${year}${peak}_Link_Info.csv
      
      # statement to create and load tmp work tables
      cat <<EOF
        DROP TABLE IF EXISTS $schema.Link_Info_${peak}_${year};

        CREATE TABLE $schema.Link_Info_${peak}_${year} (
          gid              INTEGER NOT NULL,
          inode            INTEGER NOT NULL,
          jnode            INTEGER NOT NULL,
          LkSpd            NUMERIC,
          LkTime           NUMERIC,
          LkVehTotal       NUMERIC,
          LkVehHCV_ALL     NUMERIC,
          LkVehLV_ALL      NUMERIC,
          LkVehHCV_COLD    NUMERIC,
          LkVehLV_COLD     NUMERIC
        );

        COPY $schema.Link_Info_${peak}_${year} FROM STDIN WITH DELIMITER AS ',' CSV HEADER;
EOF
      cat $dataFile
      echo "\."

      dataFile=$dataDir/${year}${peak}_PT_Link_Info.csv
      
      # statement to create and load tmp work tables (public transport)
      cat <<EOF
        DROP TABLE IF EXISTS $schema.PT_Link_Info_${peak}_${year};

        CREATE TABLE $schema.PT_Link_Info_${peak}_${year} (
          gid              INTEGER NOT NULL,
          inode            INTEGER NOT NULL,
          jnode            INTEGER NOT NULL,
          NoPTLines        SMALLINT,
          PTVehPerHr       VARCHAR(32),
          PTPersonPerHr    NUMERIC,
          PTLkTime         NUMERIC
        );

        COPY $schema.PT_Link_Info_${peak}_${year} FROM STDIN WITH DELIMITER AS ',' CSV HEADER;
EOF

      cat $dataFile
      echo "\."

      echo "UPDATE $schema.PT_Link_Info_${peak}_${year} SET PTVehPerHr = (REGEXP_SPLIT_TO_ARRAY (PTVehPerHr, ' '))[1];"
    done
  done

 [ $? -ne 0 ] && return 1;
}

# prepare SQL to load temp Traffic Model tables
# load Traffic Model data to work tables
# create Traffic Model tables
# load Traffic Model AM, IP, PM work tables to Traffic Model schema
loadRawData () {
  local server=$1
  local db=$2
  local user=$3
  local schema=$4
  local trafficmodelDir=$5

  INFO "Loading temporary Traffic Model tables"
  psql -q -e -a -h $server -d $db -U $user <<EOF
    \set ON_ERROR_STOP
    $(prepareLoadSQL $trafficmodelDir $schema)
EOF

  [ $? -ne 0 ] && { ABORT "Failed importing Traffic Model data"; }

  return 0
}

cleanupSQL () {
  local trafficmodelDir=$1
  local schema=$2

  local FILES=$trafficmodelDir/[0-9][0-9][0-9][0-9]

  for xyear in $FILES; do
    year=${xyear: -4}
    # clean up core Traffic Model tables
    for file in $ATM_FILES $TRAFFIC_FILES; do
      table=$(echo "${file}_${year}" | gawk '{ print tolower ($0) '})
      echo "DROP TABLE ${schema}.${table};"
    done

    # clean up PEAK traffic information
    for peak in $TRAFFIC_PEAKS; do
      # Traffic Model link info
      for file in Link_Info PT_Link_Info; do
        table=$(echo ${file}_${peak}_${year} | gawk '{ print tolower ($0) }')
        echo "DROP TABLE ${schema}.${table};"
      done
    done
  done
}
 
# get traffic attributes, these correspond to individual data fields in raw Traffic Model data
getTrafficAttributes () {
  # hard coded list of traffic attributes 
  # cannot retrieve it from database in a session when another session is holding the transaction
  # and/or commit hasn't been flushed

  cat <<EOF
LkTime      
LkVehTotal    
LkVehHCV_ALL  
LkVehLV_ALL   
LkVehHCV_COLD 
LkVehLV_COLD  
NoPTLines     
PTVehPerHr    
PTPersonPerHr 
PTLkTime      
EOF

  return $?
}

# get route attributes, these correspond to fields in public transport line data
getRouteAttributes () {
  # hard coded list of traffic attributes 
  # cannot retrieve it from database in a session when another session is holding the transaction
  # and/or commit hasn't been flushed

  cat <<EOF
HDWY
SPD
EOF

  return $?
}

# extract columns names for given table
getTableColumns () {
  local server=$1
  local db=$2
  local user=$3
  local schema=$4
  local table=$5

  psql -q -h $server -d $db -U $user <<EOF
    \t
    \a

    SELECT column_name 
      FROM information_schema.columns 
     WHERE table_schema = '$schema' AND
           table_name = LOWER ('$table')
  ORDER BY ordinal_position;
EOF

  return $?
}

# prepare the SQL that converts the set of work tables to Traffic Model schema
#
# params:
#  $1 - database server to connect to
#  $2 - database to connect to
#  $3 - database schema
#  $4 - user to connect as
#  $5 - the data directory that holds the trafficmodel data, must have YYYY/(AM|IM|PM) sub directories
#
prepareConvertSQL () {
  local server=$1
  local db=$2
  local user=$3
  local schema=$4
  local trafficmodelDir=$5

  # load lookup table
  cat <<EOF
    BEGIN;

    SET search_path = $schema, public;

    -- traffic peaks
    INSERT INTO traffic_peak (type, description)
    VALUES ('AM', 'Morning Peak: 7am - 9am'),
           ('IP', 'Inter Peak: 9am - 3pm and 6pm - 7am'),
           ('PM', 'Afternoon Peak: 4pm - 6pm')
    EXCEPT
    SELECT type, description
      FROM traffic_peak;

    ANALYZE traffic_peak;

    -- congestion modelling functions
    INSERT INTO congestion_function (id, function)
    VALUES (0,  'Congestion function 0'),
           (2,  'Congestion function 2'),
           (12, 'Congestion function 12'),
           (22, 'Congestion function 22')
    EXCEPT
    SELECT id, function
      FROM congestion_function;

    ANALYZE congestion_function;

    -- link road type classification
    INSERT INTO link_type (id, type)
    VALUES (1,  'Road class 1'),
           (2,  'Road class 2'),
           (3,  'Road class 3'),
           (4,  'Road class 4'),
           (5,  'Road class 5'),
           (6,  'Road class 6'),
           (7,  'Road class 7'),
           (11, 'Road class 11'),
           (12, 'Road class 12'),
           (13, 'Road class 13'),
           (14, 'Road class 14'),
           (15, 'Road class 15'),
           (16, 'Road class 16'),
           (17, 'Road class 17'),
           (18, 'Road class 18'),
           (19, 'Road class 19'),
           (20, 'Road class 20'),
           (21, 'Road class 21'),
           (22, 'Road class 22'),
           (23, 'Road class 23'),
           (24, 'Road class 24'),
           (25, 'Road class 25'),
           (26, 'Road class 26'),
           (27, 'Road class 27')
    EXCEPT
    SELECT id, type
      FROM link_type;

    ANALYZE link_type;

    -- transport mode
    INSERT INTO transport_mode (mode, description)
    VALUES ('a', 'Mode a'),
           ('b', 'Bus'),
           ('f', 'Ferry'),
           ('o', 'Other'),
           ('p', 'Private'),
           ('r', 'Rail'),
           ('s', 'Mode s'),
           ('w', 'Mode w'),
           ('x', 'Mode x'),
           ('z', 'Mode z')
    EXCEPT
    SELECT mode, description
      FROM transport_mode;

    ANALYZE transport_mode;

    -- public transport route attributes
    INSERT INTO route_attribute (attribute, data_type, description)
    VALUES ('HDWY', 'NUMERIC', ''),
           ('SPD',  'NUMERIC', 'Allocated travel speed')
    EXCEPT 
    SELECT attribute, data_type, description
      FROM route_attribute;

    ANALYZE route_attribute;

    COMMIT;
    BEGIN;
EOF

  # load core tables for each data year
  local FILES=$trafficmodelDir/[0-9][0-9][0-9][0-9]

  for xyear in $FILES; do
    year=${xyear: -4}

    cat <<EOF
      INSERT INTO version (traffic_model, transport_model, data_year)
      VALUES ('$TRAFFIC_INFO', '$ATM_INFO', $year)
      EXCEPT
      SELECT traffic_model, transport_model, data_year
        FROM version;

      ANALYZE version;

      -- Traffic Model link attributes
      INSERT INTO traffic_attribute (attribute, data_type, description, version_id)
      VALUES ('LkTime',        'NUMERIC', 'Time to traverse the link (mins)',                   (SELECT id FROM version WHERE data_year = '$year')),
             ('LkVehTotal',    'NUMERIC', 'Total link vehicular flow (veh/2hrs)',               (SELECT id FROM version WHERE data_year = '$year')),
             ('LkVehHCV_ALL',  'NUMERIC', 'Total link HCV vehicular flow (veh/2hrs)',           (SELECT id FROM version WHERE data_year = '$year')),
             ('LkVehLV_ALL',   'NUMERIC', 'Total link LV vehicular flow (veh/2hrs)',            (SELECT id FROM version WHERE data_year = '$year')),
             ('LkVehHCV_COLD', 'NUMERIC', 'Link HCV vehicular flow travelled < 5km (veh/2hrs)', (SELECT id FROM version WHERE data_year = '$year')),
             ('LkVehLV_COLD',  'NUMERIC', 'Link LV vehicular flow travelled < 5km (veh/2hrs)',  (SELECT id FROM version WHERE data_year = '$year'))
      EXCEPT
      SELECT attribute, data_type, description, version_id
        FROM traffic_attribute;

      -- Public Transport route Traffic Model link attributes
      INSERT INTO traffic_attribute (attribute, data_type, description, version_id)
      VALUES ('NoPTLines',     'SMALLINT',    'Number of Public Transport routes',              (SELECT id FROM version WHERE data_year = '$year')),
             ('PTVehPerHr',    'NUMERIC',     'Number of Public Transport vehicles per hour',   (SELECT id FROM version WHERE data_year = '$year')),
             ('PTPersonPerHr', 'NUMERIC',     'Number of Public Transport passengers per hour', (SELECT id FROM version WHERE data_year = '$year')),
             ('PTLkTime',      'NUMERIC',     'Public Transport transit time (mins)',           (SELECT id FROM version WHERE data_year = '$year'))
      EXCEPT
      SELECT attribute, data_type, description, version_id
        FROM traffic_attribute;

      ANALYZE traffic_attribute;

      -- add any Traffic Model congestion modelling functions missing from lookup
      INSERT INTO congestion_function (id, function)
      SELECT vdf, 'Congestion function ' || vdf::VARCHAR
        FROM (
          SELECT DISTINCT vdf
            FROM links_${year}
          EXCEPT
          SELECT id AS vdf
            FROM congestion_function
        ) AS m;

      ANALYZE congestion_function;

      -- add any Traffic Model link classification missing from lookup
      INSERT INTO link_type (id, type)
      SELECT type, 'Road type number: ' || type::VARCHAR
        FROM (
          SELECT DISTINCT
                 type::INTEGER AS type
            FROM links_${year}
          EXCEPT
          SELECT id AS type
            FROM link_type
        ) AS m;

      ANALYZE link_type;

      -- add any transport mode missing from lookup
      INSERT INTO transport_mode (mode, description)
      SELECT mode, 'Mode ' || mode::VARCHAR
        FROM (
          SELECT DISTINCT
                 SUBSTRING (modes, i, 1) AS mode
            FROM (
              SELECT GENERATE_SERIES (1, LENGTH (modes)) AS i,
                     modes
                FROM (
                  SELECT modes AS modes
                    FROM links_${year}
                   UNION
                  SELECT mode AS modes
                    FROM tlines_${year}
                ) AS m
            ) AS c
          EXCEPT
          SELECT mode
            FROM transport_mode
        ) AS m;

      ANALYZE transport_mode;

      COMMIT;
      BEGIN;

      -- Auckland Regional Council Transport Model zones
      INSERT INTO zone (traffic_id, version_id, sector, sector_name, area_sqm, geom)
      SELECT z.zone AS traffic_id,
             v.id AS version_id,
             z.atm2_secto AS sector,
             z.sector_nam AS sector_name,
             z.area_sqm,
             z.geom
        FROM zones_${year} AS z
        JOIN version AS v
             ON v.traffic_model = '$TRAFFIC_INFO' AND
                v.transport_model = '$ATM_INFO' AND 
                v.data_year = $year
   LEFT JOIN zone AS zz
             ON z.zone = zz.traffic_id AND
                v.id = zz.version_id
       WHERE zz.traffic_id IS NULL;
          
      ANALYZE zone;

      -- Traffic Model node
      INSERT INTO node (traffic_id, version_id, x, y, geom)
      SELECT n.traffic_id,
             v.id AS version_id,
             ST_X (n.geom) AS x,
             ST_Y (n.geom) AS y,
             n.geom
        FROM (
          SELECT inode AS traffic_id,
                 ST_StartPoint (ST_LineMerge (geom)) AS geom
            FROM links_${year}
           UNION
          SELECT jnode AS traffic_id,
                 ST_EndPoint (ST_LineMerge (geom)) AS geom
            FROM links_${year}
          ) AS n
        JOIN version AS v
             ON v.traffic_model = '$TRAFFIC_INFO' AND
                v.transport_model = '$ATM_INFO' AND 
                v.data_year = $year
   LEFT JOIN node AS nn
             ON n.traffic_id = nn.traffic_id AND
                v.id = nn.version_id
       WHERE n.traffic_id > 1000 AND
             nn.traffic_id IS NULL;

      ANALYZE node;

      -- Traffic Model links
      INSERT INTO link (traffic_id, version_id, start_node_id, end_node_id,
                        length, type_id, number_of_lanes, function_id,
                        geom)
      SELECT DISTINCT
             l.id AS traffic_id,
             v.id AS version_id,
             n1.id AS start_node_id,
             n2.id AS end_node_id,
             l.length,
             l.type::INTEGER AS type_id,
             l.lanes AS number_of_lanes,
             l.vdf AS function_id,
             ST_Multi (ST_MakeLine (n1.geom, n2.geom)) AS geom
        FROM links_${year} AS l
        JOIN version AS v
             ON v.traffic_model = '$TRAFFIC_INFO' AND
                v.transport_model = '$ATM_INFO' AND 
                v.data_year = $year
        JOIN node AS n1
             ON l.inode = n1.traffic_id AND
                v.id = n1.version_id
        JOIN node AS n2
             ON l.jnode = n2.traffic_id AND
                v.id = n2.version_id
   LEFT JOIN link AS ll
             ON l.id = ll.traffic_id AND
                v.id = ll.version_id
       WHERE l.inode > 1000
         AND l.jnode > 1000
         AND ll.traffic_id IS NULL 
         AND (($year = 2006 AND l.type::INTEGER >= 10) OR $year <> 2006);

      ANALYZE link;

      -- link transport modes
      -- split the modes string into individual mode code
      INSERT INTO link_transport_mode (link_id, mode_id)
      SELECT l.id AS link_id,
             m.id AS mode_id
        FROM (
          SELECT GENERATE_SERIES (1, LENGTH (modes)) AS i,
                 modes
            FROM (
              SELECT DISTINCT
                     modes AS modes
                FROM links_${year}
            ) AS m
        ) AS c
        JOIN links_${year} AS el
             ON c.modes = el.modes
        JOIN version AS v
             ON v.traffic_model = '$TRAFFIC_INFO' AND
                v.transport_model = '$ATM_INFO' AND 
                v.data_year = $year
        JOIN link AS l
             ON el.id = l.traffic_id AND
                v.id  = l.version_id
        JOIN transport_mode AS m
             ON SUBSTRING (c.modes, c.i, 1) = m.mode
      EXCEPT
      SELECT link_id, mode_id
        FROM link_transport_mode;

      ANALYZE link_transport_mode;

      --
      -- public transport routes
     
      -- transport type for public transport routes
      INSERT INTO transport_type (type, mode_id, vehicle)
      SELECT DISTINCT
             'Public Transport' AS type,
             m.id AS mode_id,
             CASE WHEN tl.mode = 'b'
                  THEN 'Bus'
                  WHEN tl.mode = 'r'
                  THEN 'Train'
                  WHEN tl.mode = 'f'
                  THEN 'Ferry'
            END AS vehicle
        FROM tlines_${year} AS tl
   LEFT JOIN transport_mode AS m
             ON tl.mode = m.mode
      EXCEPT
      SELECT type, mode_id, vehicle
        FROM transport_type;

      ANALYZE transport_type;

      -- public transport route information
      INSERT INTO transport_route (route_identifier, transport_type_id, description)
      SELECT tl.id AS route_identifier,
             tt.id AS transport_type_id,
             tl.desc AS description
        FROM tlines_${year} AS tl
        JOIN transport_mode AS tm
             ON tl.mode = tm.mode
        JOIN transport_type AS tt
             ON tt.type = 'Public Transport' AND
                tm.id = tt.mode_id
      EXCEPT
      SELECT route_identifier, transport_type_id, description
        FROM transport_route;

      ANALYZE transport_route;

      -- public transport route Traffic Model links
      --
      -- subquery g: iterate through line string geometries in mutli-line string
      -- subquery p: iterate through segments of individual line string
      -- main query: match start/end point of segment to start/end node geometry of Traffic Model links
      --
      INSERT INTO transport_route_link (route_id, link_id, sequence)
      SELECT r.id AS route_id,
             l.id AS link_id, 
             p.p AS sequence
        FROM (
          SELECT id, ST_GeometryN (geom, g) AS geom, GENERATE_SERIES (1, ST_NumPoints (ST_GeometryN (geom, g)) - 1) AS p
            FROM (
              SELECT id, geom, GENERATE_SERIES (1, ST_NumGeometries (geom)) AS g
                FROM tlines_${year}
            ) AS g
          ) AS p
        JOIN link AS l
             ON l.geom && ST_PointN (p.geom, p.p) AND
                l.geom && ST_PointN (p.geom, p.p + 1) AND
                ST_DWithin (ST_StartPoint (ST_LineMerge (l.geom)), ST_PointN (p.geom, p.p), 0.00001) AND
                ST_DWithin (ST_EndPoint (ST_LineMerge (l.geom)), ST_PointN (p.geom, p.p + 1), 0.00001)
        JOIN transport_route AS r
             ON p.id = r.route_identifier
      EXCEPT
      SELECT route_id, link_id, sequence
        FROM transport_route_link
    ORDER BY 1, 3;

      ANALYZE transport_route_link;

EOF

    # add transport route attribute data
    for table in tlines_${year}; do
      # now load each traffic attribute from $table to traffic_data
      columns=$(getTableColumns $server $db $user $schema $table | tr -s "\n" " ")

      for a in $(getRouteAttributes $server $db $user $schema $year); do
        if echo $columns | grep -E -i "\<$a\>" &> /dev/null; then
          cat <<EOF
            -- public transport route attribute instances
            INSERT INTO route_data (attribute_id, value)
            SELECT DISTINCT
                   ra.id AS attribute_id,
                   r.$a::TEXT AS value
              FROM $table AS r
              JOIN route_attribute AS ra
                   ON ra.attribute = '$a'
            EXCEPT
            SELECT attribute_id, value
              FROM route_data;

            ANALYZE route_data;

            -- link public transport route to normalised attribute instance
            INSERT INTO transport_route_data (route_id, data_id)
            SELECT rt.id AS route_id,
                   rd.id AS data_id
              FROM $table AS r
              JOIN transport_route AS rt
                   ON r.id = rt.route_identifier
              JOIN route_attribute AS ra
                   ON ra.attribute = '$a'
              JOIN route_data AS rd
                   ON r.$a::TEXT = rd.value
            EXCEPT
            SELECT route_id, data_id
              FROM transport_route_data;
 
EOF
        fi
      done
    done
 
    for peak in $TRAFFIC_PEAKS; do
      # normalise attribute instances
      for table in link_info_${peak}_${year} pt_link_info_${peak}_${year}; do
        # now load each traffic attribute from $table to traffic_data
        columns=$(getTableColumns $server $db $user $schema $table | tr -s "\n" " ")

        for a in $(getTrafficAttributes $server $db $user $schema $year); do
          if echo $columns | grep -E -i "\<$a\>" &> /dev/null; then
            # found field in table, insert as traffic attribute
            cat <<EOF
              INSERT INTO traffic_data (attribute_id, value)
              SELECT DISTINCT
                     ta.id AS attribute_id,
                     t.$a::NUMERIC AS value
                FROM $table AS t
                JOIN traffic_attribute AS ta
                     ON ta.attribute = '$a'
              EXCEPT
              SELECT attribute_id, value
                FROM traffic_data;

              ANALYZE traffic_data;

              INSERT INTO link_traffic_data (link_id, data_id, peak, year)
              SELECT l.id AS link_id,
                     td.id AS data_id,
                     '$peak',
                     $year
                FROM $table AS t
                JOIN links_${year} AS ll
                     ON t.inode = ll.inode AND
                        t.jnode = ll.jnode
                JOIN version AS v
                     ON v.traffic_model = '$TRAFFIC_INFO' AND
                        v.transport_model = '$ATM_INFO' AND 
                        v.data_year = $year
                JOIN link AS l
                     ON ll.id = l.traffic_id AND
                        v.id = l.version_id
                JOIN traffic_attribute AS ta
                     ON ta.attribute = '$a'
                JOIN traffic_data AS td
                     ON ta.id = td.attribute_id AND
                        td.value = t.$a::NUMERIC
              EXCEPT
              SELECT link_id, data_id, peak, year
                FROM link_traffic_data;

              ANALYZE link_traffic_data;

EOF
          fi
        done
      done
    done
  done

  echo "COMMIT;"
}

convertToSchema () {
  local server=$1
  local db=$2
  local user=$3
  local schema=$4
  local trafficmodelDir=$5

  # prepare SQL to convert temp Traffic Model to Traffic Model schema
  # requires temp tables to be loaded already
  # convert Traffic Model AM, IM, PM to Traffic Model schema
  INFO "Loading Traffic Model schema from work tables"
  psql -q -e -a -h $server -d $db -U $user <<EOF
    \set ON_ERROR_STOP
    $(prepareConvertSQL $server $db $user $schema $trafficmodelDir)
EOF

  [ $? -ne 0 ] && { ABORT "Failed loading Traffic Model schema"; }

  return 0
}

linkToNetwork () {
  local server=$1
  local db=$2
  local user=$3
  local schema=$4

  INFO "Converting Traffic Model shape nodes to shape points"
  psql -q -e -a -h $server -d $db -U $user <<EOF
    \set ON_ERROR_STOP
    \i $sqldir/convert_shape_nodes.sql
EOF

  [ $? -ne 0 ] && { ABORT "Failed converting Traffic Model shape nodes to shape points"; }

  INFO "Linking Traffic Model to road network"
  psql -q -e -a -h $server -d $db -U $user <<EOF
    \set ON_ERROR_STOP
    \i $sqldir/link_network.sql
EOF

  [ $? -ne 0 ] && { ABORT "Failed linking Traffic Model schema to TOTUS road network"; }

  return 0;
}

cleanTempTables () {
  local server=$1
  local db=$2
  local user=$3
  local schema=$4
  local trafficmodelDir=$5

  INFO "Cleaning up temporary tables"

  psql -q -e -a -h $server -d $db -U $user <<EOF
    \set ON_ERROR_STOP
    $(cleanupSQL $trafficmodelDir $schema)
EOF

  [ $? -ne 0 ] && { ABORT "Failed cleaning up temporary tables"; }

  return 0;
}

#
# globals
#
[ "$BIN" ] || BIN=`cd $(dirname $0); pwd`

# import common functions
. $BIN/common.sh

# 
# parse command line options
parseOptions $*

# assign global command line parameters
trafficmodelDir=$DATA
server=$SERVER
db=$DB
user=$USER
passwd=$PASSWD
clean=$CLEANDB
region=$RGN

INFO "Configured for region: $region"

if [ $region == "AK" ]; then
    # AKL Transport Model files
    ATM_INFO="ATM2"
    # trafficmodel model info
    TRAFFIC_INFO="TrafficModel2"
fi

if [ $region == "CH" ]; then
    # Chch Transport Model files
    ATM_INFO="CTM"
    # trafficmodel model info
    TRAFFIC_INFO="ICE"
fi

# trafficmodel files to import
ATM_FILES="zones"
TRAFFIC_FILES="links tlines"
# trafficmodel peaks for morning, inter peak and afternoon
TRAFFIC_PEAKS="AM IP PM"

# database schema name
schema="trafficmodel"
sqldir=$BIN/../schema/$schema

#
# verify data directory
#
ls -1 $trafficmodelDir/[0-9][0-9][0-9][0-9] &> /dev/null

[ $? -ne 0 ] && { WARN "No Traffic Model year data available, skipping Traffic Model load"; exit 0; }

(
    # load raw data to staging table
    PGPASSWORD=$passwd loadRawData $server $db $user $schema $trafficmodelDir
    [ $? -ne 0 ] && exit 1

    # convert raw tables to Traffic Model schema
    PGPASSWORD=$passwd convertToSchema $server $db $user $schema $trafficmodelDir
    [ $? -ne 0 ] && exit 1

    # cleanup work tables
    PGPASSWORD=$passwd cleanTempTables $server $db $user $schema $trafficmodelDir
    [ $? -ne 0 ] && exit 1

    # link Traffic Model to road network
    PGPASSWORD=$passwd linkToNetwork $server $db $user $schema
    [ $? -ne 0 ] && exit 1

    exit 0
)

exit $?
