#! /bin/bash
#
# script to configure the user system of the totus-live image within a chroot jail
# this is done after all packages have been installed
#

error () {
    echo "ERROR: $1"
    exit -1
}

addAndConfigUser () {
    useradd -b /home -c "TOTUS" -g users -m totus
    passwd -d totus > /dev/null

    echo "totus     ALL=(ALL)     NOPASSWD: ALL" >> /etc/sudoers

    cat /etc/sudoers | sed -e "s/Defaults    requiretty/#Defaults    requiretty/" > /tmp/sudoers
    mv /tmp/sudoers /etc/sudoers

    cat  << EOF > /home/totus/.xinitrc
xmodmap -e "pointer=1 2 3 6 7 4 5"
xsetroot -solid Wheat4 &
exec fluxbox
EOF

    cat <<EOF >> /home/totus/.bash_profile

. /etc/profile

if [ -z "\$DISPLAY" -a "\$(tty)" = "/dev/tty1" ]; then
    # when no style have been initialised
    [ -d /home/totus/.fluxbox ] || { 
        mkdir /home/totus/.fluxbox
        fluxbox-generate_menu
    }

    startx
fi

EOF
}

configX () {
    # enable X
    echo "id:5:initdefault:" >> /etc/inittab

    # login and start X as totus
    echo "login totus && startx" >> /etc/rc.local

    # allow X to be started in rc.local
    cat /etc/pam.d/xserver | sed -e "s/auth       required    pam_console.so/auth       optional    pam_console.so/" > /tmp/xserver
    mv /tmp/xserver /etc/pam.d/xserver
}

configGTK () {
    cat <<EOF > /home/totus/.gtkrc-2.0
include "/usr/share/themes/ThinIce/gtk-2.0/gtkrc"
gtk-font-name = "Arial 10"
gtk-can-change-accels = 1
EOF
}

prepareInitScript () {
    # move the init script in place
    mv /tmp/totusInitScript.sh /etc/rc.d/init.d/totus-live

    # add it
    chkconfig --add totus-live
}

configNetwork () {
    cat <<EOF > /etc/sysconfig/network
NETWORKING=NO
HOSTNAME=totus-live
EOF
}

# main

# check that we are running in a chroot jail
[ -x /proc/1/root/. ] && error "$0 should only be run on a live TOTUS image within a chroot jail"

# config system
addAndConfigUser
configX
configGTK
prepareInitScript
configNetwork
