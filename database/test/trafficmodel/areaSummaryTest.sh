#!/bin/bash
#
# run functional test for Traffic Model area summary

usage () {
  cat <<EOF

NAME
        $(basename $0) - TOTUS Traffic Model summary test script

SYNOPSIS
        $(basename $0) -s <database server> -d <database name> -u <database user> -p <database password> -h

DESCRIPTION

        -s    database server (host)
        -d    database name to import all data to
        -u    database user to connect as 
        -p    password for above user
        -h    help

EOF
}

waterviewCycleWayAreaSummaryTest () {
  local server=$1
  local database=$2
  local user=$3
  local passwd=$4

  INFO "Area summary test: part of cycle way in waterview, expect no results"

  expected=",0"

  # area summary: part of cycle way in waterview, expect no results
  got=$(
  PGPASSWORD=$passwd psql -h $server -d $database -U $user -q <<EOF
    \t
    \a
    \f ,
    SELECT unnest(attributes) AS attribute,
           unnest(aggregates) AS total
      FROM trafficmodel.area_aggregate ('POLYGON((174.70329049598 -36.883774341577,174.70382693779 -36.883920227099,174.70429900658 -36.883997460498,174.70452431213 -36.884109019715,174.70456722748 -36.88432355621,174.70441702377 -36.884555254949,174.70436337959 -36.884598162046,174.7044277526 -36.884829859952,174.70447066796 -36.884967162082,174.7045135833 -36.885104463966,174.70440629493 -36.885035813056,174.70423463356 -36.88479553438,174.70418098938 -36.88458099921,174.7042453624 -36.884417952078,174.70429900658 -36.884254904597,174.70430973541 -36.884186252923,174.70384839546 -36.884160508529,174.70365527642 -36.884040367908,174.70336559784 -36.883928808592,174.70330122482 -36.883911645605,174.70319393646 -36.883885901119,174.70318320763 -36.883860156623,174.70318320763 -36.883808667607,174.70322612297 -36.883774341577,174.70329049598 -36.883774341577))');
EOF
)

  if [ "$got" != "$expected" ]; then
    ERROR "Waterview Cycle Way Area Summary test has failed: "
    ERROR "Expected:
$expected"
    ERROR "Got:
$got"

    return 1
  fi

  return 0
}

waterviewCycleWayAreaFluxTest () {
  local server=$1
  local database=$2
  local user=$3
  local passwd=$4

  INFO "Area flux test: part of cycle way in waterview, expect no results"

  expected=",0,0"

  # area flux: part of cycle way in waterview, expect no results
  got=$(
  PGPASSWORD=$passwd psql -h $server -d $database -U $user -q <<EOF
    \t
    \a
    \f ,
    SELECT unnest(attributes) AS attribute,
           unnest(influx) AS influx,
           unnest(outflux) AS outflux
      FROM trafficmodel.area_flux ('POLYGON((174.70329049598 -36.883774341577,174.70382693779 -36.883920227099,174.70429900658 -36.883997460498,174.70452431213 -36.884109019715,174.70456722748 -36.88432355621,174.70441702377 -36.884555254949,174.70436337959 -36.884598162046,174.7044277526 -36.884829859952,174.70447066796 -36.884967162082,174.7045135833 -36.885104463966,174.70440629493 -36.885035813056,174.70423463356 -36.88479553438,174.70418098938 -36.88458099921,174.7042453624 -36.884417952078,174.70429900658 -36.884254904597,174.70430973541 -36.884186252923,174.70384839546 -36.884160508529,174.70365527642 -36.884040367908,174.70336559784 -36.883928808592,174.70330122482 -36.883911645605,174.70319393646 -36.883885901119,174.70318320763 -36.883860156623,174.70318320763 -36.883808667607,174.70322612297 -36.883774341577,174.70329049598 -36.883774341577))');
EOF
)

  if [ "$got" != "$expected" ]; then
    ERROR "Waterview Cycle Way Area Flux test has failed: "
    ERROR "Expected:
$expected"
    ERROR "Got:
$got"

    return 1
  fi

  return 0
}

waterviewGTNorthRoadOnRampAreaSummaryTest () {
  local server=$1
  local database=$2
  local user=$3
  local passwd=$4

  INFO "Area summary test: the motorway onramp at Great North Road heading towards CBD"

  expected="Link HCV vehicular flow travelled < 5km (veh/2hrs),57.85
Total link HCV vehicular flow (veh/2hrs),239.53
Total link vehicular flow (veh/2hrs),6794.61
Total link LV vehicular flow (veh/2hrs),6555.08
Link LV vehicular flow travelled < 5km (veh/2hrs),2749.16
Time to traverse the link (mins),1.44"

  # area summary: the motorway onramp at Great North Road heading towards CBD
  got=$(
  PGPASSWORD=$passwd psql -h $server -d $database -U $user -q <<EOF
    \t
    \a
    \f ,
    SELECT unnest(attributes) AS attribute,
           unnest(aggregates) AS total
      FROM trafficmodel.area_aggregate ('POLYGON((174.70444395265 -36.872276982626,174.70458879194 -36.872272691225,174.70475508889 -36.87225981702,174.70486774167 -36.872251234217,174.70494820795 -36.872225485799,174.70496966562 -36.872212611587,174.70502330979 -36.872178280344,174.70504476747 -36.872118200633,174.7050554963 -36.872066703699,174.70505013189 -36.872019498146,174.70502867422 -36.871950835471,174.70501258096 -36.871882172736,174.70498039445 -36.871817801364,174.70495893678 -36.871714807057,174.70489456377 -36.871650435545,174.70473899564 -36.871405823304,174.70424010476 -36.870925179426,174.70352663716 -36.870620483973,174.7029097291 -36.87049173905,174.70220699033 -36.870560403035,174.70149352273 -36.870856515768,174.70118775091 -36.871410114754,174.70132722577 -36.871920795532,174.70192804059 -36.872251234217,174.70260395727 -36.872328479418,174.70331206045 -36.872362810592,174.70379485807 -36.872345645007,174.7045780631 -36.872281274026,174.70444395265 -36.872276982626))');
EOF
)

  if [ "$got" != "$expected" ]; then
    ERROR "Waterview Cycle Great North Road On Ramp Area Summary test has failed: "
    ERROR "Expected:
$expected"
    ERROR "Got:
$got"

    return 1
  fi

  return 0
}

waterviewGTNorthRoadPrimarySchoolFluxTest () {
  local server=$1
  local database=$2
  local user=$3
  local passwd=$4

  INFO "Area flux test: Great North Road at Waterview Primary School"

    expected="Link HCV vehicular flow travelled < 5km (veh/2hrs),153.60,87.67
Total link HCV vehicular flow (veh/2hrs),604.86,351.64
Total link vehicular flow (veh/2hrs),18731.37,16829.82
Total link LV vehicular flow (veh/2hrs),18126.50,16478.12
Link LV vehicular flow travelled < 5km (veh/2hrs),6070.97,7315.68
Time to traverse the link (mins),4.15,9.39
Number of Public Transport routes,93.24,60.02
Number of Public Transport vehicles per hour,75.09,42.18
Number of Public Transport passengers per hour,2805.81,1515.36
Public Transport transit time (mins),23.31,29.19"

  # area flux: the two roads leading in/out of the motorway onramp at Great North Road heading towards CBD
  got=$(
  PGPASSWORD=$passwd psql -h $server -d $database -U $user -q <<EOF
    \t
    \a
    \f ,
    SELECT unnest(attributes) AS attribute,
           unnest(influx) AS influx,
           unnest(outflux) AS outflux
      FROM trafficmodel.area_flux ('POLYGON((174.70113478789 -36.875161121157,174.70714293609 -36.876602963759,174.70250807891 -36.886077252269,174.6966715921 -36.884086376152,174.70113478789 -36.875161121157))');
EOF
)

  if [ "$got" != "$expected" ]; then
    ERROR "Waterview Cycle Great North Road On Ramp Area Flux test has failed: "
    ERROR "Expected:
$expected"
    ERROR "Got:
$got"

    return 1
  fi

  return 0
}

BIN=`cd $(dirname $0); pwd`

# import common functions
. $BIN/../../bin/common.sh
. $BIN/../../bin/logger.sh

# dummy data directory
DUMMY="-i /tmp"
# 
parseOptions $DUMMY $*
#

server=$SERVER
database=$DB
user=$USER
passwd=$PASSWD

#
INFO "Running Traffic Model summary functional tests"

ret=0

waterviewCycleWayAreaSummaryTest $server $database $user $passwd
[ $? -ne 0 -a $ret -eq 0 ] && ret=1

waterviewGTNorthRoadOnRampAreaSummaryTest $server $database $user $passwd
[ $? -ne 0 -a $ret -eq 0 ] && ret=1

waterviewCycleWayAreaFluxTest $server $database $user $passwd
[ $? -ne 0 -a $ret -eq 0 ] && ret=1

waterviewGTNorthRoadPrimarySchoolFluxTest $server $database $user $passwd
[ $? -ne 0 -a $ret -eq 0 ] && ret=1

exit $ret
