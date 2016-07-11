#! /bin/bash
#
# deploy TOTUS system
#
BIN=`cd $(dirname $0); pwd`
AUCKLAND_BOUNDS="174.1437 -37.3059 175.6234 -35.8754"

usage () {
  cat <<EOF

NAME
        $(basename $0) - deploy the TOTUS system

SYNOPSIS
        $(basename $0) <totus root file system mount point>

EOF
}

cloneTotusData () {
    local rootfsDir=$1

    (
        # clone roles
        PGPASSWORD=$dbaPassword pg_dumpall -r -h $totusHost -U $dbaUser | grep "totus"

        # clone data
        PGPASSWORD=$dbaPassword pg_dump -h $totusHost -U $dbaUser -C -F p $totusDatabase 

        cat <<EOF
        GRANT SELECT ON geography_columns TO PUBLIC;
        GRANT SELECT ON geometry_columns TO PUBLIC;
        GRANT SELECT ON raster_columns TO PUBLIC;
        GRANT SELECT ON raster_overviews TO PUBLIC;
        GRANT SELECT ON spatial_ref_sys TO PUBLIC;
        GRANT REFERENCES (srid) ON spatial_ref_sys TO PUBLIC;

        VACUUM ANALYZE VERBOSE; VACUUM VERBOSE;
EOF
    ) | sed -e "s/$totusDatabase/$liveDatabase/g" \
            -e "s/CREATE EXTENSION IF NOT EXISTS pgrouting WITH SCHEMA public;/CREATE EXTENSION IF NOT EXISTS postgis WITH SCHEMA public;CREATE EXTENSION IF NOT EXISTS pgrouting WITH SCHEMA public;/" \
            -e "s/CREATE RULE geometry_columns/--CREATE RULE geometry_columns/" \
      | gzip > $rootfsDir/tmp/data.gz

    # chroot into root filesystem
    chroot $rootfsDir <<EOF
        echo "\set ON_ERROR_STOP" > ~/.psqlrc

        . /etc/profile
        /etc/rc.d/init.d/postgresql-9.2 start || exit 1
        gzip -d -c /tmp/data.gz | psql -U postgres -q -e -a
        /etc/rc.d/init.d/postgresql-9.2 stop
EOF
    [ $? -ne 0 ] && error "Could not load TOTUS data"

    rm -vf $rootfsDir/tmp/data.gz
}

deployTiles () {
    local rootfsDir=$1

    # deploy to /var/www/vhosts/tiles
    [ -d $rootfsDir/var/www/vhosts/tiles ] || mkdir $rootfsDir/var/www/vhosts/tiles
    $BIN/getTiles.sh $AUCKLAND_BOUNDS $rootfsDir/var/www/vhosts/tiles
}

deployServer () {
    local rootfsDir=$1

    [ -z "$totusServiceSourceURL" -o -z "$totusServiceDeploymentDir " ] && {
        echo "Missing either totusServiceSourceURL or totusServiceDeploymentDir from params.sh"
        exit
    }

    cd /tmp
    [ -d totusService ] || svn export $totusServiceSourceURL totusService
    cd totusService

    cat <<EOF | xargs tar cfz /tmp/service.tgz
favicon.ico
totus.py
TotusServer/
config/
thirdparty/featureserver/FeatureServer/
thirdparty/featureserver/LICENSE.txt
thirdparty/featureserver/vectorformats/
thirdparty/featureserver/web_request/
EOF

    deployDir=$rootfsDir/$totusServiceDeploymentDir
    [ -d $deployDir ] || mkdir -p $deployDir
    cd $deployDir || { echo "Invalid deploy dir: $deployDir"; exit 1; }

    echo "Deploying service to $deployDir"
    tar xzf /tmp/service.tgz
    cd config
    cat totus-dev.cfg | sed -e "s/dev_totus/totus/g" > /tmp/totus.cfg
    rm *.cfg *.conf
    mv /tmp/totus.cfg ./

    cd ../
    cd TotusServer/DataSource;
    for f in *; do
        file=$(basename $f);
        if [ $file != '__init__.py' ]; then
            (
                cd ../../thirdparty/featureserver/FeatureServer/DataSource;
                ln -s ../../../../TotusServer/DataSource/$f ./;
                if [ $? -ne 0 ]; then exit 1; fi;
            )
        fi;
    done;

    rm -r /tmp/totusService /tmp/service.tgz
}

deployWeb () {
    local rootfsDir=$1

    [ -z "$totusWebSourceURL" -o -z "$totusWebDeploymentDir " ] && {
        echo "Missing either totusWebSourceURL or totusWebDeploymentDir from params.sh"
        exit
    }

    cd /tmp
    [ -d totusWeb ] || svn export $totusWebSourceURL totusWeb
    cd totusWeb

    cat <<EOF | xargs tar cfz /tmp/web.tgz
favicon.ico
index.html
images/
css/
js/
config/
EOF

    deployDir=$rootfsDir/$totusWebDeploymentDir
    [ -d $deployDir ] || mkdir -p $deployDir
    cd $deployDir || { echo "Invalid deploy dir: $deployDir"; exit 1; }

    echo "Deploying web to $deployDir"
    tar xzf /tmp/web.tgz
    cat config/totus_web-dev.conf \
    | sed -e "s/dev_totus/totus/g" \
          -e "s/totus-dev/totus/g" \
          -e "s/totus\.dev\.localhost/totus-live/" \
    > $rootfsDir/etc/httpd/conf.d/totus.conf

    cat <<EOF >> $rootfsDir/etc/httpd/conf.d/totus.conf

  Alias /tiles/ "/srv/www/vhosts/tiles/"

  <Directory /srv/www/vhosts/tiles>
        Options None
        AllowOverride None
        Allow from all
        Order allow,deny
  </Directory>
EOF

    cat $rootfsDir/etc/httpd/conf.d/totus.conf | grep -v "</VirtualHost>" > $rootfsDir/tmp/totus.conf
    echo "</VirtualHost>" >> $rootfsDir/tmp/totus.conf
    mv $rootfsDir/tmp/totus.conf $rootfsDir/etc/httpd/conf.d/totus.conf

    cat js/totus.js | sed -e "s/http:\/\/tile.openstreetmap.org\//http:\/\/localhost\/tiles\//" > js/totus.js.new
    mv js/totus.js.new js/totus.js

    rm -r config
    rm -r /tmp/totusWeb /tmp/web.tgz
}

[ $# -eq 0 ] && { usage; exit 1; }

rootfsDir=$1

[ -d $rootfsDir ] || { echo "Invalid totus system directory: $rootfsDir"; usage; exit 1; }

# source the params needed to setup the TOTUS system
. $BIN/params.sh

# clone data
cloneTotusData $rootfsDir

# deploy tiles
deployTiles $rootfsDir

# deploy feature server
deployServer $rootfsDir

# deploy UI
deployWeb $rootfsDir
