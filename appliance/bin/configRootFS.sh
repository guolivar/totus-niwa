#! /bin/bash
#
# script to configure the root fs of the totus-live image in a chroot jail
# this is done prior to installing any user packages
#

error () {
    echo "ERROR: $1"
    exit -1
}

createDevices () {
    # create /dev
    for f in urandom random ptmx null full zero tty; 
        do MAKEDEV -x $f;
    done

    cd /dev
    ln -s /proc/self/fd/1 stdout
    ln -s /proc/self/fd/0 stdin
    ln -s /proc/self/fd/2 stderr
    ln -s /proc/self/fd fd
    mkdir pts shm
}

prepareMounts () {
    # create mount file /etc/fstab
    cat <<EOF > /etc/fstab
/dev/root  /         ext4    defaults,noatime 0 0
devpts     /dev/pts  devpts  gid=5,mode=620   0 0
tmpfs      /dev/shm  tmpfs   defaults         0 0
proc       /proc     proc    defaults         0 0
sysfs      /sys      sysfs   defaults         0 0
EOF

    # make mount points
    mkdir /data
}

# main

# check that we are running in a chroot jail
[ -x /proc/1/root/. ] && error "$0 should only be run on a live TOTUS image within a chroot jail"

# config system
createDevices
prepareMounts
