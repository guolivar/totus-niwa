#!/bin/bash
#
# Prepare TOTUS build scripts
#

usage () {
    cat <<EOF

NAME
        $(basename $0) - Prepare TOTUS build

SYNOPSIS
        $(basename $0) -c <config file>

DESCRIPTION

        -c    configuration file for TOTUS
        -h    help

EOF
}

# source common functions
init () {
    . $BIN/database/bin/logger.sh &> /dev/null
    . $BIN/database/bin/common.sh &> /dev/null
    return $?
}

BIN=`cd $(dirname $0); pwd`

prepareDatabaseBuild () {
    local config=$1

    [ -s $config ] || {
        ERROR "No INI configuration file provided"
        return 1
    }

    # get the profile to build
    profile=$(parseINI $config "profile" "name");

    [ -z "$profile" ] && {
        ERROR "Invalid INI file: $config, section: profile missing name parameter"
        return 1
    }

    INFO "Prepare $profile database build scripts"

    # prepare build script
    template=$BIN/database/build/build-template.xml
    [ -s $template ] || {
        ERROR "Invalid TOTUS workspace, the database build configuration template: $template is missing"
        return 1
    }

    # fetch the database build params from INI file
    server=$(parseINI $config "database" "server")
    db=$(parseINI $config "database" "name")

    [ -z "$server" -o -z "$db" ] && {
        ERROR "Invalid INI file: $config, section: database missing name and/or server parameters"
        return 1
    }

    driverVersion=$(parseINI $config "database" "jdbc4_driver_version")

    [ -z "$driverVersion" ] && {
        ERROR "Invalid INI file: $config, section: database missing jdbc4_driver_version parameter"
        return 1
    }

    dbaUser=$(parseINI $config "database" "dba_user")
    dbaPassword=$(parseINI $config "database" "dba_password")

    if [ "$profile" = "UAT" -o "$profile" = "uat" ]; then
        # UAT profile means it may be cloned from another server, usually production
        masterServer=$(parseINI $config "database" "master_server")
        masterDB=$(parseINI $config "database" "master_database")

        [ -z "$masterServer" -o -z "$masterDB" ] && {
            ERROR "Invalid INI file: $config, section: database missing master_host and/or master_database parameters"
            return 1
        }
    fi

    datadir=$(parseINI $config "workspace" "datadir")
    configfile=$(parseINI $config "workspace" "configfile")

    [ -z "$datadir" -o -z "$configfile" ] && {
        ERROR "Invalid INI file: $config, section: workspace missing datadir and/or configfile parameters"
        return 1
    }
        
    cat $template | \
    sed -e "s/Ant environment deployment configuration template/$profile environment deployment configuration/" | \
    sed -e "s/TOTUS-DATABASE/TOTUS-DATABASE-${profile}/" | \
    sed -e "s/<server>/$server/g" | \
    sed -e "s/<database>/$db/g"   | \
    sed -e "s/<dba>/$dbaUser/g"   | \
    sed -e "s/<jdbc4_version>/$driverVersion/g" | \
    sed -e "s|<datadir>|$datadir|g" | \
    sed -e "s|<configfile>|$configfile|g" | \
    ( [ "$profile" = "UAT" -o "$profile" = "uat" ] && sed -e "s/master_server/$masterServer/g" -e "s/master_database/$masterDB/g" || grep -v "master_" ) \
    > $BIN/database/build/${profile}.xml

    # prepare INI file
    extractINISection $config "region" > $BIN/database/$configfile
    extractINISection $config "osm" >> $BIN/database/$configfile
    extractINISection $config "traffic">> $BIN/database/$configfile

    peopleDatasets=$(parseINI $config "census" "people_spreadsheets")
    familyDatasets=$(parseINI $config "census" "family_spreadsheets")
    householdDatasets=$(parseINI $config "census" "household_spreadsheets")
    dwellingDatasets=$(parseINI $config "census" "dwelling_spreadsheets")

    [ -z "$peopleDatasets" -o -z "$familyDatasets" -o -z "$householdDatasets" -o -z "$dwellingDatasets" ] && {
        ERROR "Invalid INI file: $config, section: census missing people_spreadsheets, family_spreadsheets, household_spreadsheets and/or dwelling_spreadsheets parameters"
        return 1
    }

    template=$BIN/database/bin/census-template.ini
    cat $template | \
    sed -e "s/<people_spreadsheets>/$peopleDatasets/g" | \
    sed -e "s/<family_spreadsheets>/$familyDatasets/g" | \
    sed -e "s/<household_spreadsheets>/$householdDatasets/g" | \
    sed -e "s/<dwelling_spreadsheets>/$dwellingDatasets/g" \
    > $BIN/database/bin/census.ini
 
    return $?
}

prepareServiceBuild () {
    local config=$1

    [ -s $config ] || {
        ERROR "No INI configuration file provided"
        return 1
    }

    # get the profile to build
    profile=$(parseINI $config "profile" "name");

    [ -z "$profile" ] && {
        ERROR "Invalid INI file: $config, section: profile missing name parameter"
        return 1
    }

    INFO "Prepare $profile service build scripts"

    # prepare build script
    template=$BIN/service/build/build-template.xml
    [ -s $template ] || {
        ERROR "Invalid TOTUS workspace, the service build configuration template: $template is missing"
        return 1
    }

    # fetch the service build params from INI file
    server=$(parseINI $config "service" "server")
    user=$(parseINI $config "service" "user")

    [ -z "$server" -o -z "$user" ] && {
        ERROR "Invalid INI file: $config, section: service missing server and/or user parameters"
        return 1
    }

    cat $template | \
    sed -e "s/Ant environment deployment configuration template/$profile environment deployment configuration/g" | \
    sed -e "s/TOTUS-SERVER/TOTUS-SERVER-${profile}/" | \
    sed -e "s/<server>/$server/g" | \
    sed -e "s/<user>/$user/g" \
    > $BIN/service/build/${profile}.xml

    # feature server config template
    template=$BIN/service/config/featureserver-template.cfg
    [ -s $template ] || {
        ERROR "Invalid TOTUS workspace, the service feature server configuration template: $template is missing"
        return 1
    }

    # fetch the database build params from INI file
    server=$(parseINI $config "database" "server")
    db=$(parseINI $config "database" "name")
    user="totus"
    password=$(parseINI $config "database" "readonly_password")

    [ -z "$server" -o -z "$db" -o -z "$password" ] && {
        ERROR "Invalid INI file: $config, section: database missing name, server and/or readonly_password parameters"
        return 1
    }

    # create feature server layer configuration file
    cat $template | \
    sed -e "s/<profile>/$profile/g" | \
    sed -e "s/<server>/$server/g" | \
    sed -e "s/<database>/$db/g" | \
    sed -e "s/<user>/$user/g" | \
    sed -e "s/<password>/$password/g" \
    > $BIN/service/config/totus-${profile}.cfg

    return $?
}

prepareWebBuild () {
    local config=$1

    [ -s $config ] || {
        ERROR "No INI configuration file provided"
        return 1
    }

    # get the profile to build
    profile=$(parseINI $config "profile" "name");

    [ -z "$profile" ] && {
        ERROR "Invalid INI file: $config, section: profile missing name parameter"
        return 1
    }

    INFO "Prepare $profile web build scripts"

    # prepare build script
    template=$BIN/web/build/build-template.xml
    [ -s $template ] || {
        ERROR "Invalid TOTUS workspace, the web build configuration template: $template is missing"
        return 1
    }

    # fetch the web build params from INI file
    server=$(parseINI $config "web" "server")
    user=$(parseINI $config "web" "user")
    url=$(parseINI $config "web" "url")

    [ -z "$server" -o -z "$user" -o -z "$url" ] && {
        ERROR "Invalid INI file: $config, section: web missing server, user and/or url parameters"
        return 1
    }

    cat $template | \
    sed -e "s/Ant environment deployment configuration template/$profile environment deployment configuration/" | \
    sed -e "s/TOTUS-WEB/TOTUS-WEB-${profile}/" | \
    sed -e "s/<server>/$server/g" | \
    sed -e "s/<user>/$user/g" | \
    sed -e "s/<url>/$url/g" \
    > $BIN/web/build/${profile}.xml

    # web apache config template
    template=$BIN/web/config/apache-template.conf
    [ -s $template ] || {
        ERROR "Invalid TOTUS workspace, the web apache configuration template: $template is missing"
        return 1
    }

    # create feature server apache configuration file
    cat $template | \
    sed -e "s/<profile>/$profile/g" | \
    sed -e "s/<url>/$url/g" \
    > $BIN/web/config/totus_web-${profile}.conf

    return $?
}

prepare () {
    init
    [ $? -ne 0 ] && {
        echo "Failed to load common functions"
        return 1
    }

    # parse command line
    while getopts "c:h" opt; do
        case $opt in
            c):
                config=$OPTARG
                ;;
            h):
                usage
                exit 0
                ;;
            *):
                echo "Invalid option, see help:"
                usage
                exit 1
                ;;
        esac
    done

    [ $# -eq 0 ] && {
        usage
        exit 0
    }

    INFO "Preparing database build configuration"
    prepareDatabaseBuild $config
    [ $? -ne 0 ] && return 1

    INFO "Preparing feature server build configuration"
    prepareServiceBuild $config

    INFO "Preparing web demo build configuration"
    prepareWebBuild $config

    return 0
}

prepare $*
exit $?
