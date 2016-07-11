#! /bin/bash
#
# a hack to install python modules into a chroot jail
#
usage () {
  cat <<EOF

NAME
        $(basename $0) - hack to install python modules into a non-connected chroot jail

SYNOPSIS
        $(basename $0) <chroot root directory> <list of eggs to fetch and install>

EOF

}

[ $# -eq 0 ] && { usage; exit 1; }
chrootDir=$1
[ -d $chrootDir ] || { echo "Invalid chroot directory: $chrootDir supplied"; usage; exit 1; }
eggs=$2
[ -n "$eggs" ] || { echo "No eggs supplied"; usage; exit 1; }

(
    cd $chrootDir/tmp

    for egg in $eggs; do
        echo "Installing $egg"
        wget $egg
        module=$(basename $egg)
        chroot $chrootDir easy_install /tmp/$module
        rm $module
    done
)
