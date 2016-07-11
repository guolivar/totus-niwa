#! /bin/bash
#
# loads supporting data for Energy schema in TOTUS
#

usage () {
  cat <<EOF

NAME
        $(basename $0) - loads Energy meta data to Totus database

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
schema="energy"

# load supporting data
PGPASSWORD=$passwd psql -q -e -a -h $server -d $db -U $user <<EOF
  \set ON_ERROR_STOP
  SET search_path = $schema, public;

  INSERT INTO scenario (code, description)
  VALUES ('CONTINUITY', 'Continuity'),
         ('CURRENT', 'Current accounts');

  INSERT INTO activity (code, description)
  VALUES ('HEATING', 'Household heating'),
         ('ALL', 'All energy activities');

  -- create default model
  SELECT * 
    FROM energy.configure_model_run (
      'TOTAL_RESIDENTS_MODEL', 
      'Energy intensity is 10 times the number of people in the selected area',
      'ALL',
      'CURRENT',
      ARRAY [ ('T 88', '', 10.0)::energy.definition_part ]
    );

  -- call stored procedure to create default energy intensity data set for 1996, 2001 and 2011
  SELECT *
    FROM energy.model_intensity (
      'TOTAL_RESIDENTS_MODEL'::VARCHAR,
      1996::SMALLINT
    )
   LIMIT 1;

  SELECT *
    FROM energy.model_intensity (
      'TOTAL_RESIDENTS_MODEL'::VARCHAR,
      2001::SMALLINT
    )
   LIMIT 1;

  SELECT *
    FROM energy.model_intensity (
      'TOTAL_RESIDENTS_MODEL'::VARCHAR,
      2006::SMALLINT
    )
   LIMIT 1;
EOF

[ $? -ne 0 ] && { ABORT "Failed preparing Energy intensity data"; }

exit 0;
