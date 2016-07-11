#! /bin/bash
#
# Creates the TOTUS Appliance
#
# dvd
# - read-only squashed rootfs
# - read-only data image, squashed if greater than dvd size
# - no restore image
# - the data image is mounted as read-write at run time, but is only read-only on disk
# usb
# - read-only squashed rootfs
# - read-write data image
# - hidden restore image to restore the data image to it's original state
#   (when forcefully squashed it is the same as the live DVD)
#
BIN=`cd $(dirname $0); pwd`
MAX_DVD_SIZE_MB=4500

usage () {
  cat <<EOF

NAME
        $(basename $0) - creates TOTUS live appliance

SYNOPSIS
        $(basename $0) <options>

DESCRIPTION
        -c    create target ISO only, do not create root and user file systems
        -t    target to create, eg. dvd or usb
        -u    usb device partition, eg. /dev/sdb1, if target is usb
        -s    squash the TOTUS database to ensure the smallest live image (no need for restore image), the output size is ~2.5G
        -b    only burn ISO to live USB (do not create ISO)
        -h    help

NOTE
        When the TOTUS data partition is compressed it limits the amount of live editing that
        can be done inside the TOTUS system, but allows creating smaller DVD or USB targets.
        Uncompressed it has 25% free disk space to allow live editing and an restore image
        to recover the initial state upon bootup. When the database is compressed read-write
        access is allowed in-memory and there is no need for the restore image because the
        filesystem is read-only.

EOF
}

error () {
    echo "ERROR: $1"
    exit -1
}

createImage () {
    local imageFile=$1
    local imageSize=$2
    local imageMountDir=$3

    imageDir=$(dirname $imageFile)

    [ -d $imageDir ] || mkdir -p $imageDir
    [ -d $imageMountDir ] || mkdir -p $imageMountDir

    dd if=/dev/zero of=$imageFile bs=1M count=$imageSize || error "Unable to create image: $imageFile of size: $imageSize"
    loopDev=$(losetup -f)
    losetup $loopDev $imageFile || error "Unable to setup loop device $loopDev on $imageFile"
    mkfs -t ext4 $loopDev
    fdisk -cul $loopDev
    losetup -d $loopDev

    [ -d $imageMountDir ] || mkdir -p $imageMountDir

    mount -o loop $imageFile $imageMountDir
}

createRootFS () {
    local rootfsDir=$1

    [ -d $rootfsDir ] || { error "Invalid rootfs directory: $rootfsDir"; }

    cd /var/tmp

    export http_proxy=http://www-proxy.niwa.co.nz:80
    export https_proxy=$http_proxy

    [ -n "$centosReleaseURL" -a -n "$centosReleaseRPM" ] || error "Provide the URL and RPM for installing CentOS Release in params.sh"

    wget $centosReleaseURL/$centosReleaseRPM

    mkdir -p $rootfsDir/var/lib/rpm
    rpm --rebuilddb --root=$rootfsDir || error "Could not initialise rpm db for $rootfsDir"
    rpm --root=$rootfsDir -ivh --nodeps $centosReleaseRPM || error "Installing CentOS release"

    # install mandatory packages needed to setup system
    yum --installroot=$rootfsDir install rpm-build MAKEDEV passwd -y

    # chroot setup
    cp $BIN/configRootFS.sh $rootfsDir/tmp
    chroot $rootfsDir /tmp/configRootFS.sh || error "configRootFS.sh failed"

    if [ -n "$groupInstall" ]; then
        # group installs
        yum --installroot=$rootfsDir groupinstall -y $groupInstall || error "Installing groups: $groupInstall"
    fi

    [ -n "$epelReleaseURL" -a -n "$epelReleaseRPM" ] || error "Provide the URL and RPM for installing EPEL Release in params.sh"

    wget $epelReleaseURL/$epelReleaseRPM || error "Installing EPEL release"
    yum install --installroot=$rootfsDir -y $epelReleaseRPM 
    yum --installroot=$rootfsDir update

    if [ -n "$packageInstall" ]; then
        yum --installroot=$rootfsDir install -y $packageInstall || error "Installing packages: $packageInstall"
    fi

    # chroot setup
    cp $BIN/configSystem.sh $BIN/totusInitScript.sh $rootfsDir/tmp
    chroot $rootfsDir /tmp/configSystem.sh

    rm -fv $rootfsDir/tmp/*.sh
}

initPostgreSQL () {
    local rootfsDir=$1

    chroot $rootfsDir <<EOF
        echo "export PGDATA=/data" >> /etc/profile
        export PGDATA=/data
        chown postgres:postgres /data
        su - postgres -c "/usr/pgsql-9.2/bin/initdb -D /data -E utf8"
        passwd -d postgres > /dev/null

        # fix the postgresql init script to read PGDATA from enviroment
        cat /etc/rc.d/init.d/postgresql-9.2 | sed -e 's/^PGDATA=/[ -z "\$PGDATA" ] \&\& PGDATA=/' -e 's/PGLOG=\/var\/lib\/pgsql\/9.2\/data/PGLOG=\/var\/log\/pgstartup.log/' > /tmp/postgresql-9.2
        mv /tmp/postgresql-9.2 /etc/rc.d/init.d/postgresql-9.2
        chmod 755 /etc/rc.d/init.d/postgresql-9.2

        # trust all local access
        echo "local   all             all                                     trust"  > /data/pg_hba.conf
        echo "host    all             all             127.0.0.1/32            trust" >> /data/pg_hba.conf
        echo "host    all             all             ::1/128                 trust" >> /data/pg_hba.conf

        chkconfig postgresql-9.2 on

        rm -rf /var/lib/pgsql/9.2/data
        ln -s /data /var/lib/pgsql/9.2/data
EOF
    [ $? -ne 0 ] && error "Could not initialise postgreSQL"
}

installPGRouting () {
    local rootfsDir=$1

    cd /var/tmp

    svn export $pgRoutingURL

    mv pgrouting $rootfsDir/tmp || error "Unable to copy pgrouting source to chroot tmp: $rootfsDir/tmp"

    chroot $rootfsDir <<EOF
        ln -s /usr/pgsql-9.2/bin/postgres /usr/bin/
        ln -s /usr/pgsql-9.2/bin/pg_config /usr/bin/
        cd /tmp
        cd pgrouting
        cmake .
        make || exit 1
        make install
        rm -rf /tmp/pgrouting
EOF
    [ $? -ne 0 ] && error "Could not install PGRouting"
}

initApache () {
    local rootfsDir=$1

    chroot $rootfsDir <<EOF
        [ -d /srv ] || mkdir /srv
        ln -s /var/www /srv
        ln -s /etc/httpd /etc/apache2
        mkdir -p /var/log/apache2

        chkconfig httpd on
EOF
}

# mount image inside root fs
mountDataImageAsPartition () {
    local rootfsDir=$1
    local dataDir=$2
    local dataImage=$3

    # remount data image as chroot /data
    umount $dataDir || error "Could not unmount $dataDir"

    [ -d $rootfsDir/data ] || mkdir $rootfsDir/data
    mount -o loop $dataImage $rootfsDir/data || error "Could not re-mount $dataImage on $rootfsDir/data"
    [ -d $rootfsDir/data/lost+found ] && rm -rf $rootfsDir/data/lost+found
}

# unmount /data 
unmountDataPartition () {
    local rootfsDir=$1
    local dataDir=$2
    local dataImage=$3

    umount $rootfsDir/data

    mount -o loop -t ext4 $dataImage $dataDir
}

# a hack to allow us to have enough local storage to run data import
# the restore image is dd'd with the data image later
mountRestoreImageAsTmp () {
    local rootfsDir=$1
    local restoreDir=$2
    local restoreImage=$3

    # remount restore image as chroot /restore
    umount $restoreDir || error "Could not unmount $restoreDir"

    mount -o loop $restoreImage $rootfsDir/tmp || error "Could not re-mount $restoreImage on $rootfsDir/tmp"
    [ -d $rootfsDir/tmp/lost+found ] && rm -rf $rootfsDir/tmp/lost+found
}

unmountTmpPartition () {
    local rootfsDir=$1
    local restoreDir=$2
    local restoreImage=$3

    umount $rootfsDir/tmp

    mount -o loop -t ext4 $restoreImage $restoreDir
}

# install and setup user applications needed by the totus user and system
setupUserApplications() {
    local rootfsDir=$1

    [ -d $rootfsDir ] || { error "Invalid rootfs directory: $rootfsDir"; }

    cd /var/tmp

    export http_proxy=http://www-proxy.niwa.co.nz:80
    export https_proxy=$http_proxy

    [ -n "$pgdgReleaseURL" -a -n "$pgdgReleaseRPM" ] || error "Provide the URL and RPM for installing PostgreSQL repo in params.sh"

    wget $pgdgReleaseURL/$pgdgReleaseRPM || error "Installing PostgreSQL repo"
    yum install --installroot=$rootfsDir -y $pgdgReleaseRPM 

    [ -n "$elgisReleaseURL" -a -n "$elgisReleaseRPM" ] || error "Provide the URL and RPM for installing Enterprise Linux GIS repo in params.sh"

    wget $elgisReleaseURL/$elgisReleaseRPM || error "Installing Enterprise Linux GIS repo"
    yum install --installroot=$rootfsDir -y $elgisReleaseRPM 

    yum --installroot=$rootfsDir update

    # install user aplications
    yum install --installroot=$rootfsDir -y $applicationInstall --nogpgcheck

    # non yum install, manual installs
    [ -n "$extraInstallScripts" ] && $extraInstallScripts

    if [ -n "$applicationInstall" ]; then
        initPostgreSQL $rootfsDir
        installPGRouting $rootfsDir
        initApache $rootfsDir
    fi
}

configUserApplications () {
    local rootfsDir=$1

    [ -d $rootfsDir ] || { error "Invalid rootfs directory: $rootfsDir"; }

    # copy fluxbox window manager
    cp -rf $BIN/../fluxbox $rootfsDir/home/totus/.fluxbox

    # copy totus docs
    cp -rf $BIN/../docs $rootfsDir/home/totus/documents

    # TODO:
    #   config preferences for pgadmin3, gqis, firefox and gnome-terminal
    #

    chroot $rootfsDir chown totus:users /home/totus -R
}

setupIsoLinux () {
    local rootfsDir=$1
    local applianceDir=$2

    # setup isolinux - for ISO
    [ -d $applianceDir/isolinux ] || mkdir -p $applianceDir/isolinux
    cp -pf $rootfsDir/usr/share/syslinux/isolinux.bin $applianceDir/isolinux
    cp -pf $rootfsDir/usr/share/syslinux/vesamenu.c32 $applianceDir/isolinux
    cp -p $rootfsDir/boot/$kernel $applianceDir/isolinux/vmlinuz0
    cp -p $rootfsDir/boot/$initFSImage $applianceDir/isolinux/initrd0.img
    cp -p $BIN/../liveboot/splash.jpg $applianceDir/isolinux/
    cp -p $BIN/../liveboot/boot.cat $applianceDir/isolinux/
    cp -p $BIN/../liveboot/memtest $applianceDir/isolinux/
 
    cat <<EOF > $applianceDir/isolinux/isolinux.cfg
default vesamenu.c32
timeout 100

menu background splash.jpg
menu title Welcome to TOTUS Live
menu color border 0 #ffffffff #00000000
menu color sel 7 #ffffffff #ff000000
menu color title 0 #ffffffff #00000000
menu color tabmsg 0 #ffffffff #00000000
menu color unsel 0 #ffffffff #00000000
menu color hotsel 0 #ff000000 #ffffffff
menu color hotkey 7 #ffffffff #ff000000
menu color timeout_msg 0 #ffffffff #00000000
menu color timeout 0 #ffffffff #00000000
menu color cmdline 0 #ffffffff #00000000
menu hidden
menu hiddenrow 5
menu default
label totuslive
  menu label TOTUS Live
  kernel vmlinuz0
  append initrd=initrd0.img root=live:LABEL=TOTUS rootfstype=auto ro liveimg 3 quiet nodiskmount nolvmmount rhgb vga=791 rd.luks=0 rd.md=0 rd.dm=0 rdshell
label memtest
  menu label Memory Test
  kernel memtest
label local
  menu label Do not boot TOTUS
  localboot 0xffff
EOF
}

squashRootFS () {
    local rootImageDir=$1
    local applianceDir=$2

    # check that appliance directory exists
    [ -d $applianceDir/LiveOS ] || mkdir -p $applianceDir/LiveOS

    # remove squashed image if it exist, we do not want to append to it or modify existing
    [ -s $applianceDir/LiveOS/squashfs.img ] && rm -vf $applianceDir/LiveOS/squashfs.img

    # squash rootfs
    mksquashfs $rootImageDir $applianceDir/LiveOS/squashfs.img -b 1M -keep-as-directory
}

prepareRestoreImage () {
    local dataImage=$1
    local restoreImage=$2

    dd if=$dataImage of=$restoreImage || error "Could not create restore image: $restoreImage from data image: $dataImage"
}

prepareLiveISO () {
    local baseDir=$1
    local applianceDir=$2
    local target=$3
    local squashDB=$4

    rm -vf $applianceDir/LiveOS/*.img

    # now prepare live ISO by sqaushing root
    squashRootFS $baseDir/rootfs/LiveOS $applianceDir

    if [ $squashDB -eq 1 -o "$target" = "dvd" ]; then
        # compress the data partition that holds the TOTUS database when we request
        # the smallest possible live system or the target is DVD and it won't fit

        if [ $squashDB -eq 0 -a "$target" = "dvd" ]; then
            # conditional squashing, check if the image will fit onto a DVD
            rootfsSize=$(du -sm $applianceDir/LiveOS/squashfs.img | gawk '{ print $1 }')
            dataSize=$dataImageSize

            if [ $(( rootfsSize + dataSize )) -gt $MAX_DVD_SIZE_MB ]; then
                # squash data image and assume it will fit
                squashDB=1
            fi
        fi

        if [ $squashDB -eq 1 ]; then
            # compress data image
            mksquashfs $baseDir/images/data.img $applianceDir/LiveOS/data.img
        else
            # no need to squash, just copy it
            cp -pf $baseDir/images/data.img $applianceDir/LiveOS
        fi
    else
        # copy data and restore image unsquashed
        cp -pf $baseDir/images/*.img $applianceDir/LiveOS
    fi
}

createISO () {
    local applianceDir=$1
    local isoDir=$2
    local target=$3

    if [ -n "$target" -a "$target" = "dvd" ]; then
        outputISO=$isoDir/${systemName}-dvd.iso
    else
        outputISO=$isoDir/$systemName.iso
    fi

    # make ISO filesystem
    mkisofs -r -V "TOTUS" -cache-inodes -J -l -b isolinux/isolinux.bin -c isolinux/boot.cat -no-emul-boot -boot-load-size 4 -boot-info-table -o $outputISO $applianceDir
}

createUSB () {
    local liveISO=$1
    local usbDevice=$2

    # create live usb using fedora livecd script
    livecd-iso-to-disk $liveISO $usbDevice

    # a hack to support our data/restore images
    [ -d /mnt/usb ] || mkdir -p /mnt/usb
    [ -d /mnt/iso ] || mkdir -p /mnt/iso
    mount -o loop $liveISO /mnt/iso
    mount $usbDevice /mnt/usb
    cp -pf /mnt/iso/LiveOS/data.img /mnt/usb/LiveOS
    [ -s /mnt/iso/LiveOS/restore.img ] && cp -pf /mnt/iso/LiveOS/data.img /mnt/usb/LiveOS
    umount /mnt/iso
    umount /mnt/usb
}

cleanup () {
    echo ""
}

# check sudo
if [ $(id -u) -ne 0 ]; then
    echo "ERROR: Run script as sudo"
    exit -1
fi

# main
# 
# steps:
# create rootfs image
# setup it up, install distro plus postgres, qgis, pgadmin, customize, etc.
# for iso and liveCD
# /isolinux
# /LiveOS
#   /squashfs.img
#   - /squashfs-root/LiveOS/ext3fs.img
#   /data.img
## squash it
# create restore image - postgres tablespace
# copy to data image when init.d
# add swap file?
#

# source the params needed to setup the appliance
. $BIN/params.sh

createTargetOnly=0
squashDB=0
burnOnly=0

# check command line
while getopts "ct:u:sb" opt; do
    case $opt in
        c):
            # skip creation of fs images, just create the target
            createTargetOnly=1
            ;;
        t):
            target=$OPTARG
            ;;
        u):
            usbDevice=$OPTARG
            ;;
        s):
            squashDB=1
            ;;
        b):
            # burn ISO only
            burnOnly=1
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

# verify target
[ "$target" ] || { usage; error "Missing target"; }
[ "$target" != "dvd" -a "$target" != "usb" ] && error "Invalid target: $target provided, only dvd and usb are supported"

# verify usb device
if [ "$target" = "usb" -a -z "$usbDevice" ]; then
    error "Provide a USB device for creating a live USB"
elif [ "$target" = "usb" ]; then
    [ -b $usbDevice ] || error "Invalid USB device: $usbDevice provided. Reason: $usbDevice is not a block device"
fi

# fixed layout to allow using liveimg kernel option and standard fedora livecd tools
rootfsImage=$baseDir/rootfs/LiveOS/ext3fs.img
dataImage=$baseDir/images/data.img
restoreImage=$baseDir/images/restore.img

if [ $burnOnly -eq 0 ]; then
    # not just burning ISO, check if we need to create target only
    if [ $createTargetOnly -eq 0 ]; then
        # rootfs image - defined according to dracut liveimg spec
        createImage $rootfsImage $rootfsImageSize $rootfsMountDir

        # data image
        createImage $dataImage $dataImageSize $dataMountDir

        # data restore image
        createImage $restoreImage $restoreImageSize $restoreMountDir

        # create base system
        createRootFS $rootfsMountDir

        # mount raw data image as /data inside chroot
        mountDataImageAsPartition $rootfsMountDir $dataMountDir $dataImage
        # temporarily use the restore image as /tmp inside chroot
        mountRestoreImageAsTmp $rootfsMountDir $restoreMountDir $restoreImage

        # install and initialise all user applications needed by TOTUS
        setupUserApplications $rootfsMountDir

        # deploy the TOTUS system
        $BIN/deployTotus.sh $rootfsMountDir

        # configure user applications
        configUserApplications $rootfsMountDir

        # unmount /data and mount data image
        unmountDataPartition $rootfsMountDir $dataMountDir $dataImage

        # unmount /tmp and mount restore image
        unmountTmpPartition $rootfsMountDir $restoreMountDir $restoreImage
    else
        # remount images
        mount -o loop -t ext4 $rootfsImage $rootfsMountDir || error "Failed to mount previous root image: $rootfsImage"
        mount -o loop -t ext4 $dataImage $dataMountDir || error "Failed to mount previous data image: $dataImage"
        mount -o loop -t ext4 $restoreImage $restoreMountDir || error "Failed to mount previous restore image: $restoreImage"
    fi

    # copy kernel, etc. from rootfs to isolinux before unmounting
    setupIsoLinux $rootfsMountDir $applianceDir

    # unmount all images
    umount $rootfsMountDir
    umount $dataMountDir
    umount $restoreMountDir

    prepareRestoreImage $dataImage $restoreImage
    prepareLiveISO $baseDir $applianceDir $target $squashDVD

    # finally create the ISO
    createISO $applianceDir $isoDir $target
fi

if [ "$target" = "usb" ]; then
    createUSB $isoDir/$systemName.iso $usbDevice
fi

# rm $rootfsImage $dataImage $restoreImage
