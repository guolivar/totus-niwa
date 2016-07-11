#!/bin/bash
#
# live: Init script for TOTUS live image
#
# chkconfig: 345 00 99
# description: Init script for TOTUS live image based on CentOS livesys init script
#
. /etc/init.d/functions

liveDir="LiveOS"

# sanity check
# only run init script if kernel booted with liveimg option
if ! strstr "`cat /proc/cmdline`" liveimg; then
    exit 0
fi

start () {
    # mount live image
    if [ -b `readlink -f /dev/live` ]; then
       mkdir -p /mnt/live
       mount -o ro /dev/live /mnt/live 2>/dev/null || mount /dev/live /mnt/live
    fi

    # enable swaps if needed
    swaps=`blkid -t TYPE=swap -o device`
    if ! strstr "`cat /proc/cmdline`" noswap && [ -n "$swaps" ] ; then
      for s in $swaps ; do
        action "Enabling swap partition $s" swapon $s
      done
    fi
    if ! strstr "`cat /proc/cmdline`" noswap && [ -f /mnt/live/${liveDir}/swap.img ] ; then
      action "Enabling swap file" swapon /mnt/live/${liveDir}/swap.img
    fi

    # overwrite data with restore image
    if [ -s /mnt/live/${liveDir}/restore.img ]; then
        action "Restoring data" dd if=/mnt/live/${liveDir}/restore.img of=/mnt/live/${liveDir}/data.img
    fi

    if [ "$(blkid -o value -s TYPE /mnt/live/${liveDir}/data.img)" = "ext4" ]; then
        # mount data drive
        loopDev=`losetup -f`
        action "Setting up TOTUS data" losetup $loopDev /mnt/live/${liveDir}/data.img
        action "Mounting TOTUS data" mount -rw -t ext4 $loopDev /data
    else
        # if it's not ext4 it's squashed 
        loopDev=`losetup -f`
        losetup $loopDev /mnt/live/${liveDir}/data.img
        [ -d /mnt/data ] || mkdir /mnt/data
        mount -t squashfs $loopDev /mnt/data

        [ -d /mnt/data-ro ] || mkdir /mnt/data-ro
        mount -o loop -t ext4 /mnt/data/data.img /mnt/data-ro

        [ -d /mnt/data-rw ] || mkdir /mnt/data-rw
        chown postgres:postgres /mnt/data-rw
        chmod 700 /mnt/data-rw
        action "Mounting TOTUS data" mount -t fuse funionfs#none -o dirs=/mnt/data-ro=ro:/mnt/data-rw=rw,allow_other,nonempty /data
        [ -s /data/postmaster.opts ] && rm /data/postmaster.opts
    fi

    # do we need this, not using /overlay as disk
    #mount -t tmpfs -o mode=0755 varcacheyum /var/cache/yum
    #mount -t tmpfs tmp /tmp
    #mount -t tmpfs vartmp /var/tmp

    [ -x /sbin/restorecon ] && /sbin/restorecon /var/cache/yum /tmp /var/tmp >/dev/null 2>&1

    # turn off firstboot for livecd boots
    echo "RUN_FIRSTBOOT=NO" > /etc/sysconfig/firstboot

    # turn off mdmonitor by default
    chkconfig --level 345 mdmonitor       off 2>/dev/null

    # turn off setroubleshoot on the live image to preserve resources
    chkconfig --level 345 setroubleshoot  off 2>/dev/null

    # don't start cron/at as they tend to spawn things which are
    # disk intensive that are painful on a live image
    chkconfig --level 345 auditd          off 2>/dev/null
    chkconfig --level 345 crond           off 2>/dev/null
    chkconfig --level 345 atd             off 2>/dev/null
    chkconfig --level 345 readahead_early off 2>/dev/null
    chkconfig --level 345 readahead_later off 2>/dev/null

    # disable kdump service
    chkconfig --level 345 kdump           off 2>/dev/null

    # disable microcode_ctl service
    chkconfig --level 345 microcode_ctl   off 2>/dev/null

    # disable smart card services
    chkconfig --level 345 openct          off 2>/dev/null
    chkconfig --level 345 pcscd           off 2>/dev/null

    # disable postfix service
    chkconfig --level 345 postfix         off 2>/dev/null

    # Stopgap fix for RH #217966; should be fixed in HAL instead
    touch /media/.hal-mtab

    # workaround clock syncing on shutdown that we don't want (#297421)
    sed -i -e 's/hwclock/no-such-hwclock/g' /etc/rc.d/init.d/halt

    # set the LiveCD hostname
    sed -i -e 's/HOSTNAME=localhost.localdomain/HOSTNAME=totus-live/g' /etc/sysconfig/network
    /bin/hostname totus-live
}

stop () {
    umount /data
    umount /mnt/data-ro
    umount /mnt/data
}

case "$1" in
    start)
	    start
    	;;
    stop)
    	stop
    	;;
    restart)
	    stop
    	start
	    ;;
    *)
	    echo $"Usage: $prog {start|stop|restart}"
esac
