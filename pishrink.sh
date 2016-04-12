#!/bin/bash
#Args
img=$1

#Usage checks
if [[ -z $img ]]; then
  echo "Usage: $0 imagefile.img"
  exit -1
fi
if [[ ! -e $img ]]; then
  echo "ERROR: $img is not a file..."
  exit -2
fi
if (( EUID != 0 )); then
   echo "ERROR: You need to be running as root."
   exit -3
fi

#Gather info
beforesize=`ls -lah $img | cut -d ' ' -f 5`
partinfo=`parted -m $img unit B print`
partnumber=`echo "$partinfo" | grep ext4 | awk -F: ' { print $img } '`
partstart=`echo "$partinfo" | grep ext4 | awk -F: ' { print substr($2,0,length($2)-1) } '`
loopback=`losetup -f --show -o $partstart $img`

#Make pi expand rootfs on next boot
mountdir=`mktemp -d`
mount $loopback $mountdir
mv $mountdir/etc/rc.local $mountdir/etc/rc.expand.tmp
cat <<\EOF > $mountdir/etc/rc.local
#!/bin/sh
/usr/bin/raspi-config --expand-rootfs; mv -f /etc/rc.expand.tmp /etc/rc.local; reboot
exit 0
EOF
chmod +x $mountdir/etc/rc.local
umount $loopback

#Shrink filesystem
e2fsck -f $loopback
minsize=`resize2fs -P $loopback | awk -F': ' ' { print $2 } '`
minsize=`echo $minsize+20000 | bc`
resize2fs -p $loopback $minsize
sleep 1

#Shrink partition
losetup -d $loopback
partnewsize=`echo "$minsize * 4096" | bc`
newpartend=`echo "$partstart + $partnewsize" | bc`
part1=`parted $img rm 2`
part2=`parted $img unit B mkpart primary $partstart $newpartend`

#Truncate the file
endresult=`parted -m $img unit B print free | tail -1 | awk -F: ' { print substr($2,0,length($2)-1) } '`
truncate -s $endresult $img
aftersize=`ls -lah $img | cut -d ' ' -f 5`

echo "Shrunk $img from $beforesize to $aftersize"