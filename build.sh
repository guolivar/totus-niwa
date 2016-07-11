#!/bin/bash
#
# Run TOTUS build scripts
#

usage () {
    cat <<EOF

NAME
        $(basename $0) - Build and deploy TOTUS

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

buildDatabase () {
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

    INFO "Building $profile database"

    createDB=$(parseINI $config "database" "create_database")
    firstRun=$(parseINI $config "database" "first_run")
    adminPassword=$(parseINI $config "database" "admin_password")
    ingesterPassword=$(parseINI $config "database" "ingester_password")
    readOnlyPassword=$(parseINI $config "database" "readonly_password")
    options=$(parseINI $config "database" "extra_options" | sed -e "s/:/=/g")

    [ -z "$adminPassword" ] && {
        ERROR "Invalid INI file: $config, section: database missing admin_password parameter"
        return 1
    }

    if [ -n "$createDB" -a $createDB = "true" ]; then
        [ -z "$ingesterPassword" -o -z "$readOnlyPassword" ] && {
            ERROR "Invalid INI file: $config, section: database missing ingester_password and/or readonly_password parameters"
            return 1
        }

        # first time build is run, create database first
        (
            cd $BIN/database
            ant $options \
                -DPROFILE=$profile \
                -DDBA_PASSWORD=$dbaPassword \
                -DADMIN_PASSWORD=$adminPassword \
                -DINGESTER_PASSWORD=$ingesterPassword \
                -DREAD_ONLY_PASSWORD=$readOnlyPassword \
                $([ -n "$firstRun" -a $firstRun = "true" ] && echo "-DFIRST_RUN=true" || echo "") \
                create-database
            exit $?
        )
        [ $? -ne 0 ] && {
            ERROR "Failed to create the $profile TOTUS database"
            return 1
        }
    fi

    (
        # now build the database
        cd $BIN/database
        ant $options \
            -DPROFILE=$profile \
            -DPASSWORD=$adminPassword \
            $([ -n "$firstRun" -a $firstRun = "true" ] && echo "-DFIRST_RUN=true" || echo "")
        exit $?
    )
    [ $? -ne 0 ] && {
        ERROR "Failed to build the $profile TOTUS database"
        return 1
    }

    return 0
}

deployService () {
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

    INFO "Deploying $profile service"

    user=$(parseINI $config "service" "user")
    password=$(parseINI $config "service" "password")

    [ -z "$user" -o -z "$password" ] && {
        ERROR "Invalid INI file: $config, section: service missing user and/or password parameters"
        return 1
    }

    (
        cd $BIN/service
        ant -DPROFILE=$profile -Ddeployuser=$user -Ddeploypasswd=$password deploy
        exit $?
    )
    [ $? -ne 0 ] && {
        ERROR "Failed to deploy the $profile TOTUS feature service"
        return 1
    }

    return 0
}

deployWeb () {
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

    INFO "Deploying $profile web demo"

    user=$(parseINI $config "service" "user")
    password=$(parseINI $config "service" "password")

    [ -z "$user" -o -z "$password" ] && {
        ERROR "Invalid INI file: $config, section: web missing user and/or password parameters"
        return 1
    }

    (
        cd $BIN/web
        ant -DPROFILE=$profile -Ddeployuser=$user -Ddeploypasswd=$password deploy
        exit $?
    )
    [ $? -ne 0 ] && {
        ERROR "Failed to deploy the $profile TOTUS web demo"
        return 1
    }

    return 0
}

build () {
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

    INFO "Building TOTUS database"
    buildDatabase $config
    [ $? -ne 0 ] && {
        ERROR "Failed building TOTUS database"
        return 1
    }

    INFO "Deploying feature server"
    deployService $config
    [ $? -ne 0 ] && {
        ERROR "Failed deploying TOTUS service"
        return 1
    }

    INFO "Deploying web demo"
    deployWeb $config
    [ $? -ne 0 ] && {
        ERROR "Failed deploying TOTUS web demo"
        return 1
    }

    return 0
}

build $*
exit $?
