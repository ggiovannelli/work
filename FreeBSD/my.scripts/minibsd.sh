#!/bin/sh
# Script to create a clean FreeBSD image (no pkg installed)

# Variables
IMG_FILE="freebsd-clean.img"
IMG_SIZE_MB=1536  # Size in MB (1536 = 1.5GB)
MNT_POINT="/mnt/imgbuild"

# Check root
if [ "$(id -u)" != "0" ]; then
   echo "This script must be run as root"
   exit 1
fi

# Cleanup previous if exists
if mount | grep -q $MNT_POINT; then
    echo "Unmounting previous mount..."
    umount -f $MNT_POINT 2>/dev/null
fi
if [ -n "$(mdconfig -l | grep md1)" ]; then
    echo "Removing previous md1..."
    mdconfig -d -u 1
fi

# Create mount point directory if it doesn't exist
if [ ! -d "$MNT_POINT" ]; then
    echo "Creating mount point directory: $MNT_POINT"
    mkdir -p $MNT_POINT
fi

echo "=== Creating Clean FreeBSD Image (no pkg, no installed software) ==="
echo "    Size: ${IMG_SIZE_MB}MB ($((IMG_SIZE_MB/1024))GB)"

# Create image
echo -e "\n1. Creating image file (${IMG_SIZE_MB}MB)..."
rm -f $IMG_FILE
# Use dd with size variable
dd if=/dev/zero of=$IMG_FILE bs=1M count=$IMG_SIZE_MB status=progress

# Memory disk
MD_DEV=$(mdconfig -a -t vnode -f $IMG_FILE)
echo "   Memory disk: $MD_DEV"

# GPT partitioning
echo -e "\n2. Creating GPT partitions..."
gpart create -s gpt $MD_DEV
gpart add -t freebsd-boot -s 512k -l bootcode $MD_DEV
gpart add -t freebsd-ufs -l rootfs $MD_DEV

# Filesystem
echo -e "\n3. Creating filesystem..."
newfs -U -L rootfs /dev/${MD_DEV}p2

# Mount
echo -e "\n4. Mounting..."
mkdir -p $MNT_POINT
mount /dev/${MD_DEV}p2 $MNT_POINT

# Copy clean base system
echo -e "\n5. Copying clean base system..."
echo "   Excluding: all /usr/local, /home, development tools, headers, docs..."

tar -cf - 2>/dev/null \
    --exclude=/dev \
    --exclude=/proc \
    --exclude=/tmp \
    --exclude=/mnt \
    --exclude=/media \
    --exclude=/sys \
    --exclude=/var/run \
    --exclude=/var/tmp \
    --exclude=/home \
    --exclude=/usr/home \
    --exclude=/usr/src \
    --exclude=/usr/obj \
    --exclude=/usr/ports \
    --exclude=/usr/doc \
    --exclude=/usr/include \
    --exclude=/usr/share/doc \
    --exclude=/usr/share/examples \
    --exclude=/usr/share/man \
    --exclude=/usr/share/info \
    --exclude=/usr/share/i18n \
    --exclude=/usr/share/locale \
    --exclude=/usr/share/nls \
    --exclude=/usr/share/games \
    --exclude=/usr/share/sendmail \
    --exclude=/usr/share/groff \
    --exclude=/usr/share/dict \
    --exclude=/usr/share/zoneinfo-leaps \
    --exclude=/usr/local \
    --exclude=/usr/lib/clang \
    --exclude=/usr/lib/debug \
    --exclude=/usr/libdata/gcc \
    --exclude=/usr/libdata/ldscripts \
    --exclude=/usr/libdata/lint \
    --exclude=/usr/bin/cc \
    --exclude=/usr/bin/gcc \
    --exclude=/usr/bin/g++ \
    --exclude=/usr/bin/cpp \
    --exclude=/usr/bin/c++ \
    --exclude=/usr/bin/clang* \
    --exclude=/usr/bin/llvm* \
    --exclude=/usr/bin/ld \
    --exclude=/usr/bin/as \
    --exclude=/usr/bin/ar \
    --exclude=/usr/bin/nm \
    --exclude=/usr/bin/strip \
    --exclude=/usr/bin/objdump \
    --exclude=/usr/bin/make \
    --exclude=/usr/bin/bmake \
    --exclude=/usr/bin/ctags \
    --exclude=/usr/bin/indent \
    --exclude=/usr/bin/gdb \
    --exclude=/usr/bin/git* \
    --exclude=/var/db/freebsd-update \
    --exclude=/var/db/portsnap \
    --exclude=/var/cache \
    --exclude='/var/log/*' \
    --exclude=/boot/kernel.old \
    --exclude=/boot/kernel/*.symbols \
    --exclude=/boot/firmware \
    --exclude=/rescue \
    --exclude='*.core' \
    --exclude=/var/crash \
    --exclude=/var/db/pkg \
    --exclude='*/.cache' \
    --exclude='*/.ccache' \
    --exclude=/usr/tests \
    --exclude=/usr/games \
    --exclude=/var/mail \
    --exclude=/var/spool \
    --exclude=/var/db/etcupdate \
    --exclude=/entropy \
    --exclude=/var/db/entropy \
    --exclude=$IMG_FILE \
    --exclude=$MNT_POINT \
    --exclude=/usr/share/openssl/man \
    --exclude=/usr/lib32 \
    --exclude=/usr/lib/dtrace \
    --exclude=/usr/libexec/cc1* \
    --exclude=/usr/libexec/lint* \
    / | (cd $MNT_POINT && tar -xpf -)

# Copy essential terminal database files
echo "   Copying terminal database..."
mkdir -p $MNT_POINT/usr/share/misc
cp -p /usr/share/misc/termcap* $MNT_POINT/usr/share/misc/ 2>/dev/null || true
# If using terminfo instead
if [ -d /usr/share/terminfo ]; then
    mkdir -p $MNT_POINT/usr/share/terminfo
    cp -rp /usr/share/terminfo $MNT_POINT/usr/share/
fi

# Copy essential locale files (C and POSIX minimum)
echo "   Copying essential locale files..."
mkdir -p $MNT_POINT/usr/share/locale
# Copy only C and POSIX locales (minimal)
for loc in C POSIX C.UTF-8 en_US.UTF-8; do
    if [ -d /usr/share/locale/$loc ]; then
        cp -rp /usr/share/locale/$loc $MNT_POINT/usr/share/locale/
    fi
done
# Copy locale.alias if exists
cp -p /usr/share/locale/locale.alias $MNT_POINT/usr/share/locale/ 2>/dev/null || true

# Create necessary directories (including empty /usr/local)
echo -e "\n6. Creating system directories..."
for dir in dev proc tmp mnt media sys var/run var/log var/cache var/db/pkg usr/local home usr/home; do
    mkdir -p $MNT_POINT/$dir
done
chmod 1777 $MNT_POINT/tmp

# Create /var/tmp as symlink to /tmp
echo "   Creating /var/tmp symlink to /tmp..."
ln -s /tmp $MNT_POINT/var/tmp

# Minimal log files
touch $MNT_POINT/var/log/messages
touch $MNT_POINT/var/log/auth.log

# Bootloader
echo -e "\n7. Installing bootloader..."
gpart bootcode -b /boot/pmbr -p /boot/gptboot -i 1 $MD_DEV

# Configuration
echo -e "\n8. Configuring system..."

# fstab
cat > $MNT_POINT/etc/fstab << EOF
# Device                Mountpoint      FStype  Options Dump    Pass
/dev/gpt/rootfs        /               ufs     rw      1       1
tmpfs                  /tmp            tmpfs   rw,mode=1777,size=256m 0  0
EOF

# Minimal rc.conf
cat > $MNT_POINT/etc/rc.conf << EOF
# Clean base system
hostname="freebsd-clean"

# Network
ifconfig_DEFAULT="DHCP"

# Base services
sshd_enable="YES"
sendmail_enable="NO"
sendmail_submit_enable="NO"
sendmail_outbound_enable="NO"
sendmail_msp_queue_enable="NO"

# Security
clear_tmp_enable="YES"
syslogd_flags="-ss"

# No dump
dumpdev="NO"

# Locale settings
LANG="C"
LC_ALL="C"
EOF

# Minimal loader.conf
cat > $MNT_POINT/boot/loader.conf << EOF
# Serial console
console="comconsole"
comconsole_speed="115200"

# Fast boot
autoboot_delay="2"
beastie_disable="YES"
loader_color="NO"
boot_verbose="NO"

# GPT
kern.geom.label.gpt.enable="1"

# Disable unnecessary hardware
hint.agp.0.disabled=1
hint.pcm.0.disabled=1
hint.hdac.0.disabled=1
EOF

# boot.config
echo '-P' > $MNT_POINT/boot.config

# ttys for serial console
sed -i '' 's/^ttyu0.*/ttyu0   "\/usr\/libexec\/getty 3wire"   vt100   onifconsole secure/' $MNT_POINT/etc/ttys

# First boot script to install pkg (optional)
cat > $MNT_POINT/etc/rc.local << 'EOF'
#!/bin/sh
# First boot script - install pkg if needed

FIRSTBOOT_MARKER="/var/db/.firstboot_done"

if [ ! -f "$FIRSTBOOT_MARKER" ]; then
    echo "=== First boot - Initial configuration ==="
    
    # Generate SSH host keys if they don't exist
    if [ ! -f /etc/ssh/ssh_host_rsa_key ]; then
        echo "Generating SSH keys..."
        /usr/bin/ssh-keygen -A
    fi
    
    # Optional: install pkg automatically
    # echo "Installing pkg manager..."
    # ASSUME_ALWAYS_YES=yes /usr/sbin/pkg bootstrap
    
    # Mark as complete
    touch "$FIRSTBOOT_MARKER"
    echo "=== Initial configuration complete ==="
fi
EOF
chmod +x $MNT_POINT/etc/rc.local

# periodic.conf - disable unnecessary tasks
cat > $MNT_POINT/etc/periodic.conf << EOF
daily_status_security_enable="NO"
daily_clean_disks_enable="NO"
daily_clean_tmps_enable="NO"
daily_status_disks_enable="NO"
daily_status_network_enable="NO"
daily_status_rwho_enable="NO"
daily_status_mailq_enable="NO"
weekly_locate_enable="NO"
weekly_whatis_enable="NO"
weekly_catman_enable="NO"
monthly_accounting_enable="NO"
EOF

# Final cleanup
echo -e "\n9. Final cleanup..."
# Remove non-essential kernel modules
find $MNT_POINT/boot/kernel -name "*.ko" -type f | \
    grep -v -E "(kernel|if_|virtio|ahci|cam|umass|ata)" | xargs rm -f 2>/dev/null

# SSH keys - will be generated on first boot
rm -f $MNT_POINT/etc/ssh/ssh_host_*

# History and temporary files
rm -f $MNT_POINT/root/.history
rm -f $MNT_POINT/root/.viminfo

# Show disk usage
echo -e "\n10. Disk usage:"
df -h $MNT_POINT
echo ""
echo "Main content:"
du -sh $MNT_POINT/* 2>/dev/null | sort -h | tail -10

# Unmount
echo -e "\n11. Unmounting..."
umount $MNT_POINT
# Don't remove directory if not empty - might be existing mount point
if [ -z "$(ls -A $MNT_POINT 2>/dev/null)" ]; then
    rmdir $MNT_POINT 2>/dev/null || true
fi

# Disconnect memory disk
mdconfig -d -u ${MD_DEV#md}

# Compress (optional)
echo -e "\n12. Creating compressed version..."
gzip -c $IMG_FILE > ${IMG_FILE}.gz

# Final info
echo -e "\n=== COMPLETED! ==="
echo "Files created:"
ls -lh $IMG_FILE ${IMG_FILE}.gz 2>/dev/null
echo ""
echo "CLEAN FreeBSD base system:"
echo "  ✓ NO pkg preinstalled"
echo "  ✓ NO third-party software"
echo "  ✓ NO development tools"
echo "  ✓ Minimal base system only"
echo ""
echo "To install pkg after boot:"
echo "  # ASSUME_ALWAYS_YES=yes pkg bootstrap"
echo ""
echo "To enable automatic pkg installation:"
echo "  Uncomment lines in /etc/rc.local"
echo ""
echo "=== Usage Instructions ==="
echo ""
echo "For Proxmox:"
echo "  1. scp ${IMG_FILE}.gz root@proxmox:/tmp/"
echo "  2. gunzip /tmp/${IMG_FILE}.gz"
echo "  3. qm importdisk <vmid> /tmp/$IMG_FILE <storage>"
echo "  4. Configure VM with SeaBIOS (not UEFI)"
echo ""
echo "For VMware ESXi:"
echo "  1. Convert to VMDK: qemu-img convert -f raw -O vmdk $IMG_FILE freebsd.vmdk"
echo "  2. Upload to datastore"
echo "  3. Create VM with 'FreeBSD 12 or later' guest OS"
echo "  4. Use existing disk and select the VMDK"
echo ""
echo "For VMware Workstation/Fusion:"
echo "  1. Convert: qemu-img convert -f raw -O vmdk -o adapter_type=lsilogic $IMG_FILE freebsd.vmdk"
echo "  2. Create new VM, use existing virtual disk"
echo ""
echo "For USB/Physical disk:"
echo "  1. Insert USB drive (check device with: geom disk list)"
echo "  2. dd if=$IMG_FILE of=/dev/daX bs=1M conv=sync"
echo "     (replace daX with your USB device)"
echo "  3. Boot from USB"
echo ""
echo "For VirtualBox:"
echo "  1. Convert: VBoxManage convertfromraw $IMG_FILE freebsd.vdi"
echo "  2. Create VM and attach VDI disk"
echo ""
