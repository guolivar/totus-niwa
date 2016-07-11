#! /bin/bash
#

usage () {
    cat <<EOF

NAME     
        getTiles.sh
SYNOPSIS 
        getTiles.sh <minx miny maxx maxy tile-directory>

DESCRIPTION
        Fetch OSM files. The tiles created can be limited to geographic area by its bounding box.

EOF
}

gettile () {
    local tiledir=$1
    local x=$2
    local y=$3
    local z=$4

    url="http://tile.openstreetmap.org/$z/$x/$y.png"
    outfile=$tiledir/$z/$x/$y.png

    [ -s $outfile ] ||
    (
        export http_proxy=http://www-proxy.niwa.co.nz:80
        cd $tiledir/$z/$x
        wget -q $url
    )
}

validate_lon () {
    if [ $1 -ge -18000000 -a $1 -le 18000000  ]; then
        return 0
    else
        ERROR "Invalid longitude: $1, out of range"
        return 1
    fi
}

validate_lat () {
    if [ $1 -ge -9000000 -a $1 -le 9000000 ]; then
        return 0
    else
        ERROR "Invalid latitude: $1, out of range"
        return 1
    fi
}

validate_mbr () {
    local minx=$(echo $1 | gawk '{ printf ("%d", $1 * 1e5); }')
    local miny=$(echo $2 | gawk '{ printf ("%d", $1 * 1e5); }')
    local maxx=$(echo $3 | gawk '{ printf ("%d", $1 * 1e5); }')
    local maxy=$(echo $4 | gawk '{ printf ("%d", $1 * 1e5); }')

    if [ $minx -ge $maxx ]; then
        ERROR "minx should be less than maxx"
        return 1
    elif [ $miny -ge $maxy ]; then
        ERROR "miny should be less than maxy"
        return 1
    fi

    validate_lon $minx
    [ $? -ne 0 ] && return 1
    validate_lat $miny
    [ $? -ne 0 ] && return 1
    validate_lon $maxx
    [ $? -ne 0 ] && return 1
    validate_lat $maxy
    [ $? -ne 0 ] && return 1

    return 0
}

BIN=`cd $(dirname $0); pwd`

# import logging functions
. $BIN/logger.sh

[ $# -eq 5 ] || { usage; exit 1; }

minx=$1
miny=$2
maxx=$3
maxy=$4
tiledir=$5
filter=

[ -d $tiledir ] || mkdir $tiledir

# determine where tile x/y is
# see if it overlaps with bounds, then do it
# only create directories and tiles for range of NZ

if [ $# -eq 5 ]; then
    validate_mbr $minx $miny $maxx $maxy
    [ $? -ne 0 ] && {
        ERROR "Invalid bounding box supplied: [$minx, $miny $maxx, $maxy]"
        exit 1
    }
    filter=1
    INFO "Geographic filter enabled"
    INFO "Tiles will only be generated for area [$minx, $miny $maxx, $maxy]"
fi

# for TOTUS live we only use up to zoom 15
for (( z = 0; z <= 15; z++ )); do
    INFO "Processing layer $z "
    [ -d $tiledir/$z ] || mkdir $tiledir/$z
    nutiles=$(gawk -v z=$z 'BEGIN { print 2^z; }')

    startx=0
    endx=$nutiles
    starty=0
    endy=$nutiles
    tiles=0

    if [ "$filter" ]; then
        startxy=$(./tilenu.pl $minx $miny $z)
        endxy=$(./tilenu.pl $maxx $maxy $z)

        startx=${startxy%%,*}
        endy=${startxy##*,}

        endx=${endxy%%,*}
        starty=${endxy##*,}

        (( endx++ ))
        (( endy++ ))
    fi
          
    for (( x = $startx; x < $endx; x++ )); do
        [ -d $tiledir/$z/$x ] || mkdir $tiledir/$z/$x
        for (( y = $starty; y < $endy; y++ )); do
            gettile $tiledir $x $y $z
            (( tiles++ ))
        done
    done

    INFO "Copied $tiles tiles"
done
