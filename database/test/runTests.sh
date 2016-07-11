#!/bin/bash
#
# top level wrapper script to run test scripts in all schema directories
#
usage () {
  cat <<EOF

NAME
        $(basename $0) - TOTUS test script wrapper

SYNOPSIS
        $(basename $0) -s <database server> -d <database name> -u <database user> -p <database password> -h

DESCRIPTION

        -s    database server (host)
        -d    database name containing test data set
        -u    database user to connect as 
        -p    password for above user
        -h    help

EOF
}

BIN=`cd $(dirname $0); pwd`

# import common functions
. $BIN/../bin/common.sh
. $BIN/../bin/logger.sh

# dummy data directory
DUMMY="-i /tmp"
# 
parseOptions $DUMMY $*
#

server=$SERVER
database=$DB
user=$USER
passwd=$PASSWD

# mandatory
[ "$database" -o "$passwd" ] || { 
  ERROR "Require database name and user password to run test"
  usage
  exit 1
}

let pass=0
let fail=0

# run the individual tests
for f in $BIN/*/*Test.sh; do
  $f -s $server -d $database -u $user -p $passwd
  if [ $? -eq 0 ]; then
    let pass+=1
  else
    let fail+=1
  fi
done

INFO "Test summary: "
INFO "  $pass test suites passed"
INFO "  $fail test suites failed"

exit $fail
