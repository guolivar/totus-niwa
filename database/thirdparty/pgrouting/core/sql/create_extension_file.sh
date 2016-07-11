#! /bin/bash

BIN=`cd $(dirname $0); pwd`
FILES=(routing_core.sql routing_core_wrappers.sql routing_topology.sql matching.sql)

usage () {
    cat <<EOF

NAME $(basename $0)

DESCRIPTION
    -v Provide version of output extension file, eg. 1.06
    -h This message

EOF
}

while getopts "v:h" opt; do
    case $opt in
        v):
            version=$OPTARG
            ;;
        h):
            usage && exit 0
            ;;
    esac
done

[ "$version" ] || { usage && exit 1; }

(
    for f in ${FILES[*]}; do
        cat $BIN/$f
    done
) > $BIN/pgrouting--${version}.sql

(
    cat <<EOF
# pgrouting extension
comment =  'PGRouting functions'
default_version = '$version'
module_pathname = '\$libdir/librouting'
relocatable = true
EOF
) > $BIN/pgrouting.control
