# configure TOTUS live parameters
systemName=totus-live
baseDir=/extra/totus-live
rootfsImageSize=2560
rootfsMountDir=$baseDir/mnt/totus/rootfs
dataImageSize=6144
dataMountDir=$baseDir/mnt/totus/data
restoreImageSize=$dataImageSize
restoreMountDir=$baseDir/mnt/totus/restore
centosReleaseRPM=centos-release-6-4.el6.centos.10.x86_64.rpm
centosReleaseURL=http://mirror.centos.org/centos/6/os/x86_64/Packages
epelReleaseRPM=epel-release-6-8.noarch.rpm
epelReleaseURL=http://dl.fedoraproject.org/pub/epel/6/x86_64
groupInstall="$(echo \"X Window System\") Fonts"
packageInstall="fluxbox gtk2 gtk2-engines xmessage gnome-terminal vim-enhanced vim-X11 sudo man syslinux syslinux-extlinux kernel funionfs WindowMaker xorg-x11-drv-\*"
kernel=vmlinuz-2.6.32-358.6.2.el6.x86_64
initFSImage=initramfs-2.6.32-358.6.2.el6.x86_64.img
applianceDir=/usr/tmp2/totus-live
isoDir=/home/ideyzel/public

# configure TOTUS applications
pgdgReleaseRPM=pgdg-centos92-9.2-6.noarch.rpm
pgdgReleaseURL=http://yum.postgresql.org/9.2/redhat/rhel-6-x86_64
elgisReleaseRPM=elgis-release-6-6_0.noarch.rpm
elgisReleaseURL=http://elgis.argeo.org/repos/6
applicationInstall="postgresql92-server postgresql92-devel postgresql92-contrib pgadmin3_92 postgis2_92 qgis httpd boost-devel cmake gcc gcc-c++ make firefox install python-psycopg2 python-simplejson python-lxml python-pip mod_python"
pythonEggs="https://pypi.python.org/packages/2.6/s/shortuuid/shortuuid-0.1-py2.6.egg"
extraInstallScripts="$BIN/installPythonModules.sh $rootfsMountDir $pythonEggs"
pgRoutingURL=http://svn.niwa.co.nz/repos/sdt/totus/trunk/database/thirdparty/pgrouting

# packages that assisted in setting up, but not required for operational use
removePackages="yum python-pip cmake postgresql92-devel gcc gcc-c++ make"

# TOTUS clone
totusHost=arctic.niwa.co.nz
totusDatabase=test_totus
dbaUser=sdt_dba
dbaPassword=monkey5moon
liveDatabase=totus
totusServiceSourceURL=http://svn.niwa.co.nz/repos/sdt/totus/trunk/service
totusServiceDeploymentDir=/var/www/vhosts/totus_server
totusWebSourceURL=http://svn.niwa.co.nz/repos/sdt/totus/trunk/web
totusWebDeploymentDir=/var/www/vhosts/totus
