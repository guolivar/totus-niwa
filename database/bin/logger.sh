# logger

# well formatted logging [YYYY/MM/DD HH:MM:SS] TYPE    :
LOG () {
  local type=$1
  shift 1
  local msg=$*
  local aligned=8
  local len=${#type}

  [ $len -gt $aligned ] && len=$aligned

  let spaces=$((aligned - len))

  # align log entries on type
  for (( i = 0; i < spaces; i++ )); do
    type="${type} "
  done

  timestamp=`date +%Y"/"%m"/"%d" "%H":"%M":"%S`
  echo "[$timestamp] $type: $msg"
}

WARN () {
  LOG "WARNING" "$*"
}

INFO () {
  LOG "INFO" "$*"
}

DEBUG () {
  LOG "DEBUG" "$*"
}

ERROR () {
  LOG "ERROR" "$*" 1>&2
  return 1
}

ABORT () {
  ERROR "$*"
  exit 1
}
