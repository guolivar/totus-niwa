# create database schema, if none exists
initSchema () {
  local server=$1
  local db=$2
  local user=$3
  local schema=$4

  psql -q -e -a -h $server -d $db -U $user <<EOF
    \set ON_ERROR_STOP
    CREATE FUNCTION init_schema()
    RETURNS int
    AS \$init_schema\$
    BEGIN 
      IF ( NOT EXISTS ( SELECT * FROM information_schema.schemata
                         WHERE schema_name = '$schema' ) )
      THEN
        CREATE SCHEMA $schema AUTHORIZATION totus_admin;
        GRANT USAGE ON SCHEMA $schema TO totus_ingester;
        GRANT USAGE ON SCHEMA $schema TO totus;
        REVOKE ALL ON SCHEMA $schema FROM www;
        RETURN 1;
      ELSE
        RETURN 0;
      END IF;
    END;
    \$init_schema\$
    LANGUAGE plpgsql;

    SELECT init_schema();
    DROP FUNCTION init_schema();
EOF
}

[ "$BIN" ] || BIN=`cd $(dirname $0); pwd`

# source common logging functions
initLogger () {
  . $BIN/logger.sh &> /dev/null
}

DATA=
SERVER=
DB=
USER=
PASSWD=
RGN=

parseOptions () {
  # parse command line
  while getopts "i:s:d:u:p:r:ch" opt; do
    case $opt in
      i):
        DATA=$OPTARG
        ;;
      s):
        SERVER=$OPTARG
        ;;
      d):
        DB=$OPTARG
        ;;
      u):
        USER=$OPTARG
        ;;
      p):
        PASSWD=$OPTARG
        ;;
      r):
        RGN=$OPTARG
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

  # setup logging functions
  initLogger

  # validate mandatory command line params
  [ "$DATA" ] || { 
    usage 
    ABORT "Require input data directory"
  }
  [ -d $DATA ] || ABORT "Invalid input data directory: $DATA"

  [ "$DB" ] || { 
    usage
    ABORT "Require database name to import data"
  }

  # defaults
  [ "$SERVER" ] || SERVER="localhost"
  [ "$USER"   ] || USER="totus"
}
