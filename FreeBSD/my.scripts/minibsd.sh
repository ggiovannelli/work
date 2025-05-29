#!/bin/sh
# Script to create a clean FreeBSD image (no pkg installed)

# Variables
IMG_FILE="miniBSD.img"
IMG_SIZE_MB=1024  # Size in MB (1024 = 1GB)
                  # Note: increase to 1536 if using MINIMAL_KERNEL_MODULES="no"
MNT_POINT="/mnt/imgbuild"
MINIMAL_KERNEL_MODULES="yes"  # "yes" per moduli minimi VM, "no" per tutti i moduli

# Get the directory where the script is running
WORK_DIR="$(pwd)"
IMG_PATH="$WORK_DIR/$IMG_FILE"

# Generate random 6-digit password
ROOT_PASSWORD=$(jot -r 1 100000 999999)

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
echo "    Size: ${IMG_SIZE_MB}MB (${IMG_SIZE_MB}MB = 1GB)"
echo "    Root password: $ROOT_PASSWORD"
echo "    Kernel modules: $([ "$MINIMAL_KERNEL_MODULES" = "yes" ] && echo "Minimal VM set" || echo "Full set")"

# Create image
echo -e "\n1. Creating image file (${IMG_SIZE_MB}MB)..."
rm -f $IMG_PATH
# Use dd with size variable
dd if=/dev/zero of=$IMG_PATH bs=1M count=$IMG_SIZE_MB status=progress

# Memory disk
MD_DEV=$(mdconfig -a -t vnode -f $IMG_PATH)
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
    --exclude=/usr/bin \
    --exclude=/usr/sbin \
    --exclude=/var/db/freebsd-update \
    --exclude=/var/db/portsnap \
    --exclude=/var/cache \
    --exclude='/var/log/*' \
    --exclude=/boot/kernel.old \
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
    --exclude=$IMG_PATH \
    --exclude=$IMG_FILE \
    --exclude=$MNT_POINT \
    --exclude=/usr/share/openssl/man \
    --exclude=/usr/lib32 \
    --exclude=/usr/lib/dtrace \
    --exclude=/usr/libexec/cc1* \
    --exclude=/usr/libexec/lint* \
    --exclude=/usr/lib/engines \
    --exclude=/usr/lib/private \
    --exclude=/usr/lib/*.a \
    --exclude=/usr/lib/libpthread* \
    --exclude=/usr/lib/libthr* \
    --exclude=/usr/lib/libstdc++* \
    --exclude=/usr/lib/libsupc++* \
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

# Strip remaining binaries in /bin and /sbin
echo "   Stripping remaining system binaries..."
find $MNT_POINT/bin $MNT_POINT/sbin -type f -perm +111 -exec strip --strip-unneeded {} \; 2>/dev/null || true

# Strip delle librerie
echo "   Stripping libraries..."
find $MNT_POINT/usr/lib $MNT_POINT/lib -name "*.so*" -type f -exec strip --strip-unneeded {} \; 2>/dev/null || true
# Copy locale.alias if exists
cp -p /usr/share/locale/locale.alias $MNT_POINT/usr/share/locale/ 2>/dev/null || true

# Create necessary directories (including empty /usr/local)
echo -e "\n6. Creating system directories..."
for dir in dev proc tmp mnt media sys var/run var/log var/cache var/db/pkg usr/local home usr/home; do
    mkdir -p $MNT_POINT/$dir
done
chmod 1777 $MNT_POINT/tmp

# Create directories for dhclient
mkdir -p $MNT_POINT/var/db
mkdir -p $MNT_POINT/var/run
chmod 755 $MNT_POINT/var/db
chmod 755 $MNT_POINT/var/run

# Create empty /root directory (not copied from host)
echo "   Creating clean /root directory..."
mkdir -p $MNT_POINT/root
chmod 700 $MNT_POINT/root
# Create minimal .profile for root
cat > $MNT_POINT/root/.profile << 'EOF'
# $FreeBSD$
PATH=/sbin:/bin:/usr/sbin:/usr/bin:/usr/local/sbin:/usr/local/bin:~/bin
export PATH
HOME=/root
export HOME
TERM=${TERM:-xterm}
export TERM
PAGER=less
export PAGER

# Enable .shrc for sh
ENV=$HOME/.shrc
export ENV
EOF
chmod 644 $MNT_POINT/root/.profile

# Create .shrc for root (without PS1, will use global)
cat > $MNT_POINT/root/.shrc << 'EOF'
# $FreeBSD$
# .shrc - shell rc file for sh(1)

# Some useful aliases
alias ll='ls -la'
alias l='ls -l'
alias ..='cd ..'
EOF
chmod 644 $MNT_POINT/root/.shrc

# Create /etc/profile for all users with everything
cat > $MNT_POINT/etc/profile << 'EOF'
# System-wide .profile for sh(1)

# Enable colors for ls
export CLICOLOR="YES"
export LSCOLORS="cxfxcxdxbxegedabagacad"

# Colors for grep
export GREP_COLOR="32"

# Custom prompt for all users
PS1="\u@\h:\w \\$ "
export PS1

# Safety aliases
alias mkdir='mkdir -pv'
alias md='mkdir'
alias rm='rm -I'
alias del='rm'
alias cp='cp -ip'
alias mv='mv -i'

# Navigation aliases
alias cd..='cd ..'
alias ..='cd ..'
alias ...='cd ../..'

# System aliases
alias shut='shutdown -r now'

# ls aliases
alias ls='ls -k'
alias ll='ls -lah'
alias l='ls -l'
alias la='ls -a'
alias dir='ls -lah'

# grep aliases with color
alias grep='grep --color=auto'
alias egrep='egrep --color=auto'
alias fgrep='fgrep --color=auto'

# Other useful aliases
alias h='history'
alias j='jobs -l'
alias ports='netstat -an | grep LISTEN'

# Enable .shrc for sh (if users want custom aliases)
ENV=$HOME/.shrc
export ENV
EOF
chmod 644 $MNT_POINT/etc/profile

# Remove .shrc files - not needed anymore
rm -f $MNT_POINT/root/.shrc
rm -f $MNT_POINT/usr/share/skel/dot.shrc

# Create /var/tmp as symlink to /tmp
echo "   Creating /var/tmp symlink to /tmp..."
ln -s /tmp $MNT_POINT/var/tmp

# Minimal log files
touch $MNT_POINT/var/log/messages
touch $MNT_POINT/var/log/auth.log

# === OTTIMIZZAZIONE 1: Riduzione /usr/lib ===
echo -e "\n6a. Optimizing /usr/lib..."
# Rimuovi librerie di debug e sviluppo non necessarie
find $MNT_POINT/usr/lib -name "*.a" -delete 2>/dev/null
find $MNT_POINT/usr/lib -name "*_p.a" -delete 2>/dev/null
find $MNT_POINT/usr/lib -name "*_pic.a" -delete 2>/dev/null
find $MNT_POINT/usr/lib -name "*.la" -delete 2>/dev/null

# Rimuovi versioni duplicate delle librerie (mantieni solo i symlink e la versione più recente)
for lib in $MNT_POINT/usr/lib/*.so.*; do
    if [ -L "$lib" ]; then
        continue  # Mantieni i symlink
    fi
    base=$(echo $lib | sed 's/\.so\.[0-9]*$//')
    # Se esiste un symlink .so che punta a questa libreria, mantienila
    if [ -L "${base}.so" ] && [ "$(readlink ${base}.so)" = "$(basename $lib)" ]; then
        continue
    fi
done

# Rimuovi librerie opzionali per sistema minimale
# NOTA: molte di queste sono necessarie per comandi di sistema
for lib in libgpio libpmc libprocstat librtld_db \
           libsdp libugidfw libvgl libvmmapi; do
    rm -f $MNT_POINT/usr/lib/${lib}.* 2>/dev/null
done

# === OTTIMIZZAZIONE 2: Copia solo binari essenziali ===
echo -e "\n6b. Copying only essential binaries..."

# Crea directory per i binari
mkdir -p $MNT_POINT/usr/bin $MNT_POINT/usr/sbin

# Lista di binari essenziali da copiare in /usr/bin
ESSENTIAL_BINS="awk basename cat chflags chmod chown clear cmp comm cp \
    cut date dd df dirname du echo env false find grep egrep head hostname \
    id kill ln ls mkdir mkfifo mknod mount mv printf ps pwd rm rmdir \
    sed sh sleep sort stat su tail tar tee test touch tr true tty \
    umount uname uniq wc which whoami yes \
    ssh ssh-add ssh-agent ssh-keygen ssh-keyscan scp sftp \
    login passwd chpass chsh \
    crontab logger sysctl newsyslog \
    gzip gunzip zcat bzip2 bunzip2 bzcat \
    fetch nc telnet ping ping6 netstat sockstat \
    vi ee less more top \
    su sudo doas \
    limits wall install fsync mktemp \
    what xargs \
    openssl \
    pkg"

# Copia binari essenziali in /usr/bin
echo "   Copying essential binaries to /usr/bin..."
for bin in $ESSENTIAL_BINS; do
    if [ -f "/usr/bin/$bin" ]; then
        install -s -m 755 "/usr/bin/$bin" "$MNT_POINT/usr/bin/" 2>/dev/null || \
        install -m 755 "/usr/bin/$bin" "$MNT_POINT/usr/bin/"
    fi
done

# Lista di binari essenziali da copiare in /usr/sbin
ESSENTIAL_SBINS="adduser rmuser pw useradd userdel usermod groupadd groupdel \
    service sysrc newsyslog cron sshd init reboot halt shutdown \
    mount_nfs mount_nullfs mdconfig newfs tunefs fsck fsck_ffs \
    ifconfig route arp ndp dhclient dhclient-script \
    syslogd \
    pkg freebsd-update \
    utx automount automountd autounmountd \
    devctl kldload kldunload kldstat \
    iostat ip6addrctl vipw"

# Copia binari essenziali in /usr/sbin
echo "   Copying essential binaries to /usr/sbin..."
for sbin in $ESSENTIAL_SBINS; do
    if [ -f "/usr/sbin/$sbin" ]; then
        install -s -m 755 "/usr/sbin/$sbin" "$MNT_POINT/usr/sbin/" 2>/dev/null || \
        install -m 755 "/usr/sbin/$sbin" "$MNT_POINT/usr/sbin/"
    fi
done

# Copia anche le librerie necessarie per i binari
echo "   Checking for required shared libraries..."
for dir in /usr/bin /usr/sbin; do
    for bin in $MNT_POINT${dir}/*; do
        if [ -f "$bin" ]; then
            ldd "$bin" 2>/dev/null | grep "=>" | awk '{print $3}' | while read lib; do
                if [ -f "$lib" ] && [ ! -f "$MNT_POINT$lib" ]; then
                    libdir=$(dirname "$lib")
                    mkdir -p "$MNT_POINT$libdir"
                    cp -p "$lib" "$MNT_POINT$lib"
                fi
            done
        fi
    done
done

# === OTTIMIZZAZIONE 3: Comprimi i moduli del kernel ===
# NOTA: La compressione dei moduli kernel con gzip può causare problemi
# su alcune versioni di FreeBSD. Disabilitata per default.
echo -e "\n6c. Kernel modules optimization..."
echo "   Skipping compression (can cause boot issues)"
# Se vuoi comunque comprimere i moduli, decommenta le righe seguenti:
# find $MNT_POINT/boot/kernel -name "*.ko" -type f | while read module; do
#     gzip -9 "$module"
# done

# Bootloader
echo -e "\n7. Installing bootloader..."
gpart bootcode -b /boot/pmbr -p /boot/gptboot -i 1 $MD_DEV

# Configuration
echo -e "\n8. Configuring system..."

# Create custom SSH config directory
mkdir -p $MNT_POINT/usr/local/etc

# Custom sshd_config
cat > $MNT_POINT/usr/local/etc/sshd_config << 'EOF'
# Custom SSH configuration for FreeBSD minimal image

# Performance optimizations for VM
UseDNS no
TCPKeepAlive yes
ClientAliveInterval 120

# Allow root login (change to 'prohibit-password' for key-only)
PermitRootLogin yes

# PAM is needed for FreeBSD
UsePAM yes

# SFTP subsystem
Subsystem sftp /usr/libexec/sftp-server
EOF

# fstab
cat > $MNT_POINT/etc/fstab << EOF
# Device                Mountpoint      FStype  Options Dump    Pass
/dev/gpt/rootfs        /               ufs     rw      1       1
tmpfs                  /tmp            tmpfs   rw,mode=1777,size=256m 0  0
EOF

# Minimal rc.conf
cat > $MNT_POINT/etc/rc.conf << EOF
# Clean base system
hostname="miniBSD"

# Network
ifconfig_DEFAULT="DHCP"

# SSH with custom config
sshd_enable="YES"
sshd_flags="-f /usr/local/etc/sshd_config"

# Other services
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

# Suppress verbose boot messages
rc_startmsgs="NO"

# Disable devd warnings for missing modules
devd_flags="-q"
EOF

# Minimal loader.conf
cat > $MNT_POINT/boot/loader.conf << EOF
# Serial console
console="comconsole"
comconsole_speed="115200"

# Boot timing
autoboot_delay="5"
beastie_disable="YES"
loader_color="NO"
boot_verbose="NO"

# GPT
kern.geom.label.gpt.enable="1"

# Disable unnecessary hardware
hint.agp.0.disabled=1
hint.pcm.0.disabled=1
hint.hdac.0.disabled=1

# Suppress non-critical kernel messages
kern.consmsgbuf_size="8192"
kern.msgbuf_clear="1"
EOF

# boot.config
echo '-P' > $MNT_POINT/boot.config

# ttys for serial console
sed -i '' 's/^ttyu0.*/ttyu0   "\/usr\/libexec\/getty 3wire"   vt100   onifconsole secure/' $MNT_POINT/etc/ttys

# Use default devd.conf with minimal changes
echo "   Using default devd configuration..."
# devd.conf will use system default which handles everything properly

# === OTTIMIZZAZIONE 4: Imposta password per root ===
echo -e "\n8a. Setting root password..."
# Genera l'hash della password
ROOT_PWD_HASH=$(openssl passwd -6 "$ROOT_PASSWORD")
# Aggiorna master.passwd direttamente
sed -i '' "s|^root:[^:]*:|root:$ROOT_PWD_HASH:|" $MNT_POINT/etc/master.passwd

# Set root shell to /bin/sh (standard for modern FreeBSD)
echo "   Setting root shell to /bin/sh..."
TEMP_PASSWD=$(mktemp)
awk -F: 'BEGIN {OFS=":"} $1=="root" {$10="/bin/sh"} {print}' \
    $MNT_POINT/etc/master.passwd > $TEMP_PASSWD
mv $TEMP_PASSWD $MNT_POINT/etc/master.passwd
chmod 600 $MNT_POINT/etc/master.passwd

# Ricostruisci il database delle password
pwd_mkdb -p -d $MNT_POINT/etc $MNT_POINT/etc/master.passwd

# === 8b. Configure NTP synchronization ===
echo -e "\n8b. Configuring NTP synchronization..."
# Create minimal crontab without periodic tasks
echo "   Creating minimal crontab..."
# Generate random hour (0-23) and minute (0-59) for NTP sync
NTP_HOUR=$(jot -r 1 0 23)
NTP_MINUTE=$(jot -r 1 0 59)
cat > $MNT_POINT/etc/crontab << EOF
# /etc/crontab - root's crontab for FreeBSD
#
# \$FreeBSD\$
#
SHELL=/bin/sh
PATH=/etc:/bin:/sbin:/usr/bin:/usr/sbin
#
#minute	hour	mday	month	wday	who	command
#
# NTP time synchronization
$NTP_MINUTE	$NTP_HOUR	*	*	*	root	/usr/sbin/ntpd -gq -l /var/log/ntp.log 0.europe.pool.ntp.org > /dev/null 2>&1
@reboot		root	/usr/sbin/ntpd -gq -l /var/log/ntp.log 0.europe.pool.ntp.org > /dev/null 2>&1
#
# Periodic jobs disabled - add your own cron jobs below
EOF

echo "   NTP sync scheduled at ${NTP_HOUR}:$(printf '%02d' $NTP_MINUTE) daily"

# Create MOTD update script
echo "   Creating MOTD update script..."
mkdir -p $MNT_POINT/usr/local/bin
cat > $MNT_POINT/usr/local/bin/update-motd << 'EOF'
#!/bin/sh
# Update /etc/motd with system information

# Get system information
UPTIME=$(uptime | sed 's/^ *//g')
HOSTNAME=$(hostname)
NCPU=$(sysctl -n hw.ncpu)
RAM_GB=$(sysctl -n hw.physmem | awk '{printf "%.0f", $1/1073741824}')
DISK_INFO=$(df -h / | tail -1 | awk '{printf "%s/%s %s", $2, $3, $5}')
FREEBSD_VER=$(freebsd-version -kru | xargs | awk '{printf "k:%s r:%s u:%s", $1, $2, $3}')

# Write to motd
cat > /etc/motd << EOT

uptime:         ${UPTIME}
hostname:       ${HOSTNAME}
hardware:       ${NCPU} cpu, ${RAM_GB}GB ram, ${DISK_INFO} disk0
freebsd:        ${FREEBSD_VER}

EOT
EOF
chmod 755 $MNT_POINT/usr/local/bin/update-motd

# Add to crontab to update motd at boot and every 37 minutes
sed -i '' '/# NTP time synchronization/i\
# Update MOTD at boot and every 37 minutes\
@reboot		root	/usr/local/bin/update-motd\
*/37	*	*	*	*	root	/usr/local/bin/update-motd\
' $MNT_POINT/etc/crontab

# Run it once to create initial motd
chroot $MNT_POINT /usr/local/bin/update-motd 2>/dev/null || {
    # If chroot fails, create a basic motd
    cat > $MNT_POINT/etc/motd << 'EOF'

Welcome to miniBSD - FreeBSD minimal installation
Run 'update-motd' to refresh system information

EOF
}
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

# Kernel modules optimization
if [ "$MINIMAL_KERNEL_MODULES" = "yes" ]; then
    echo "   Keeping only essential VM kernel modules..."
    
    # Lista dei moduli essenziali per VM
    # Filesystem
    KEEP_MODULES="kernel geom_label geom_mirror geom_nop nullfs tmpfs"
    
    # Storage - Virtual disk drivers
    KEEP_MODULES="$KEEP_MODULES ahci ata cam scsi_da virtio virtio_pci virtio_blk virtio_scsi"
    KEEP_MODULES="$KEEP_MODULES mpt mps mpr pvscsi"
    
    # Network - Virtual network adapters
    KEEP_MODULES="$KEEP_MODULES if_bridge if_tap if_tun if_vlan"
    KEEP_MODULES="$KEEP_MODULES if_em if_igb if_ix if_ixv"  # Intel
    KEEP_MODULES="$KEEP_MODULES if_vtnet virtio_net"       # VirtIO
    KEEP_MODULES="$KEEP_MODULES if_vmx"                    # VMware vmxnet3
    KEEP_MODULES="$KEEP_MODULES if_hn"                     # Hyper-V
    KEEP_MODULES="$KEEP_MODULES if_xn"                     # Xen
    
    # Intel PM e SMBus (questi esistono!)
    KEEP_MODULES="$KEEP_MODULES intpm smbus ichsmb smb"
    
    # USB support (for USB passthrough in VMs)
    KEEP_MODULES="$KEEP_MODULES usb ohci uhci ehci xhci umass"
    KEEP_MODULES="$KEEP_MODULES uhid usbhid ums ukbd wmt hid hidbus hidraw"
    
    # Console and input 
    KEEP_MODULES="$KEEP_MODULES uart pty snp vkbd"
    
    # Memory and CPU
    KEEP_MODULES="$KEEP_MODULES acpi cpufreq coretemp aesni"
    
    # Crypto
    KEEP_MODULES="$KEEP_MODULES crypto cryptodev"
    
    # Network protocols and firewall
    KEEP_MODULES="$KEEP_MODULES pf pflog pfsync ipfw ipfw_nat"
    
    # NFS
    KEEP_MODULES="$KEEP_MODULES nfscl nfsd nfscommon"
    
    # Temperature and monitoring (useful in VMs)
    KEEP_MODULES="$KEEP_MODULES coretemp amdtemp"
    
    # VirtIO console (richiesto per console seriali in VM)
    KEEP_MODULES="$KEEP_MODULES virtio_console"
    
    # VMware specific modules
    KEEP_MODULES="$KEEP_MODULES vmci vmmemctl vmblock vmxnet"
    
    # Create a temporary directory for modules to keep
    TEMP_MODULES="/tmp/keep_modules_$$"
    mkdir -p $TEMP_MODULES
    
    # Move modules to keep
    cd $MNT_POINT/boot/kernel
    for module in $KEEP_MODULES; do
        if [ -f "${module}.ko" ]; then
            cp -p "${module}.ko" $TEMP_MODULES/
            [ -f "${module}.ko.symbols" ] && cp -p "${module}.ko.symbols" $TEMP_MODULES/
        fi
    done
    
    # Remove all modules
    rm -f *.ko *.ko.symbols
    
    # Move back the kept modules
    cp -p $TEMP_MODULES/* . 2>/dev/null || true
    rm -rf $TEMP_MODULES
    
    # List kept modules
    echo "   Kept kernel modules:"
    ls -1 *.ko 2>/dev/null | sed 's/\.ko$//' | sort | pr -t -3 -w 80
    
    # Verify all critical modules at once
    echo "   Verifying critical modules..."
    CRITICAL_MODULES="if_em if_vtnet if_vmx virtio virtio_pci virtio_blk ahci cam scsi_da pf ipfw intpm smbus"
    MISSING_CRITICAL=""
    
    for mod in $CRITICAL_MODULES; do
        if [ -f "$MNT_POINT/boot/kernel/${mod}.ko" ]; then
            echo "     ✓ ${mod}.ko"
        else
            echo "     ✗ ${mod}.ko MISSING!"
            MISSING_CRITICAL="$MISSING_CRITICAL $mod"
            # Try to copy from source if exists
            if [ -f "/boot/kernel/${mod}.ko" ]; then
                echo "       Copying from source..."
                cp -p "/boot/kernel/${mod}.ko" "$MNT_POINT/boot/kernel/"
            fi
        fi
    done
    
    if [ -n "$MISSING_CRITICAL" ]; then
        echo "   WARNING: Some critical modules are missing:$MISSING_CRITICAL"
        echo "   The system may not boot properly!"
    fi
    
else
    echo "   Keeping all kernel modules (except obviously unnecessary ones)..."
    # Remove only obviously unnecessary modules (sound, graphics, wireless, etc)
    find $MNT_POINT/boot/kernel -name "*.ko" -type f | \
        grep -E "(sound|snd_|hdac|hdaa|pcm|mixer|midi|sequencer|drm|drm2|radeon|i915|nvidia|nouveau|splash|agp|iwm|iwn|ath|bwn|ral|rum|run|ural|urtw|zyd)" | \
        xargs rm -f 2>/dev/null
fi

# SSH keys - will be generated on first boot
rm -f $MNT_POINT/etc/ssh/ssh_host_*

# Clean /root from any copied files (ensure it's empty except .profile)
find $MNT_POINT/root -type f ! -name ".profile" -delete 2>/dev/null
find $MNT_POINT/root -type d ! -path "$MNT_POINT/root" -delete 2>/dev/null

# Clean user accounts - keep only system users
echo "   Cleaning non-system user accounts..."
# Backup original files
cp $MNT_POINT/etc/passwd $MNT_POINT/etc/passwd.bak
cp $MNT_POINT/etc/master.passwd $MNT_POINT/etc/master.passwd.bak
cp $MNT_POINT/etc/group $MNT_POINT/etc/group.bak

# Keep only users with UID < 1000 (system users)
awk -F: '$3 < 1000 || $1 == "nobody" {print}' $MNT_POINT/etc/passwd.bak > $MNT_POINT/etc/passwd
awk -F: '$3 < 1000 || $1 == "nobody" {print}' $MNT_POINT/etc/master.passwd.bak > $MNT_POINT/etc/master.passwd

# Keep only system groups
awk -F: '$3 < 1000 || $1 == "nobody" || $1 == "nogroup" {print}' $MNT_POINT/etc/group.bak > $MNT_POINT/etc/group

# Remove backup files before rebuilding database
rm -f $MNT_POINT/etc/*.bak
rm -f $MNT_POINT/etc/*.orig
rm -f $MNT_POINT/etc/*.db

# Rebuild password database
pwd_mkdb -p -d $MNT_POINT/etc $MNT_POINT/etc/master.passwd

# Rimozione file inutili aggiuntivi
echo "   Removing additional unnecessary files..."
# Rimuovi file di documentazione rimasti
find $MNT_POINT -name "*.md" -o -name "README*" -o -name "CHANGELOG*" \
     -o -name "AUTHORS*" -o -name "COPYING*" -o -name "LICENSE*" | xargs rm -f 2>/dev/null

# Rimuovi file .h (header) rimasti
find $MNT_POINT -name "*.h" -delete 2>/dev/null

# Show disk usage
echo -e "\n10. Disk usage:"
df -h $MNT_POINT
echo ""
echo "Main content:"
du -sh $MNT_POINT/* 2>/dev/null | sort -h | tail -10
echo ""
echo "Detailed /usr/lib usage:"
du -sh $MNT_POINT/usr/lib/* 2>/dev/null | sort -h | tail -10

# Ensure we're not in the mount directory before unmount
cd /

# Unmount
echo -e "\n11. Unmounting..."
# Ensure we're not in the mount directory
cd "$WORK_DIR"
# Force sync before unmount
sync
sync
# Try unmount with retry
umount $MNT_POINT || {
    echo "   First unmount attempt failed, retrying..."
    sleep 2
    # Check what's keeping it busy
    fstat -f $MNT_POINT 2>/dev/null || true
    lsof $MNT_POINT 2>/dev/null || true
    # Force unmount
    umount -f $MNT_POINT || {
        echo "   ERROR: Cannot unmount $MNT_POINT"
        echo "   Please check for processes using the mount point"
        exit 1
    }
}

# Don't remove directory if not empty - might be existing mount point
if [ -z "$(ls -A $MNT_POINT 2>/dev/null)" ]; then
    rmdir $MNT_POINT 2>/dev/null || true
fi

# Disconnect memory disk
mdconfig -d -u ${MD_DEV#md} || {
    echo "   ERROR: Cannot detach memory disk $MD_DEV"
    echo "   The image file may be incomplete"
}

# Verify image exists before compression
if [ ! -f "$IMG_PATH" ]; then
    echo "   ERROR: Image file $IMG_PATH not found!"
    exit 1
fi

# Compress (optional)
echo -e "\n12. Creating compressed version..."
gzip -c $IMG_PATH > ${IMG_PATH}.gz

# Final info
echo -e "\n=== COMPLETED! ==="
echo "Files created:"
ls -lh $IMG_PATH ${IMG_PATH}.gz 2>/dev/null
echo ""
echo "OPTIMIZED FreeBSD base system:"
echo "  ✓ NO pkg preinstalled"
echo "  ✓ NO third-party software"
echo "  ✓ NO development tools"
echo "  ✓ Minimal base system only"
echo "  ✓ Stripped binaries"
echo "  ✓ Optimized /usr/lib"
echo "  ✓ Random root password: $ROOT_PASSWORD"
if [ "$MINIMAL_KERNEL_MODULES" = "yes" ]; then
    echo "  ✓ Minimal kernel modules for VMs"
else
    echo "  ✓ Full kernel modules (except multimedia)"
fi
echo ""
echo "=== IMPORTANT: ROOT PASSWORD ==="
echo "Username: root"
echo "Password: $ROOT_PASSWORD"
echo "*** SAVE THIS PASSWORD - IT IS UNIQUE TO THIS IMAGE ***"
echo ""
echo "To change kernel module selection:"
echo "  Set MINIMAL_KERNEL_MODULES=\"no\" for full module set"
echo "  Set MINIMAL_KERNEL_MODULES=\"yes\" for VM-optimized set (default)"
echo ""
echo "Note: If using MINIMAL_KERNEL_MODULES=\"no\", increase IMG_SIZE_MB to 1536"
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
echo "  1. scp ${IMG_PATH}.gz root@proxmox:/tmp/"
echo "  2. gunzip /tmp/${IMG_FILE}.gz"
echo "  3. qm importdisk <vmid> /tmp/$IMG_FILE <storage>"
echo "  4. Configure VM with SeaBIOS (not UEFI)"
echo ""
echo "For VMware ESXi:"
echo "  1. Convert to VMDK: qemu-img convert -f raw -O vmdk $IMG_PATH freebsd.vmdk"
echo "  2. Upload to datastore"
echo "  3. Create VM with 'FreeBSD 12 or later' guest OS"
echo "  4. Use existing disk and select the VMDK"
echo ""
echo "For VMware Workstation/Fusion:"
echo "  1. Convert: qemu-img convert -f raw -O vmdk -o adapter_type=lsilogic $IMG_PATH freebsd.vmdk"
echo "  2. Create new VM, use existing virtual disk"
echo ""
echo "For USB/Physical disk:"
echo "  1. Insert USB drive (check device with: geom disk list)"
echo "  2. dd if=$IMG_PATH of=/dev/daX bs=1M conv=sync"
echo "     (replace daX with your USB device)"
echo "  3. Boot from USB"
echo ""
echo "For VirtualBox:"
echo "  1. Convert: VBoxManage convertfromraw $IMG_PATH freebsd.vdi"
echo "  2. Create VM and attach VDI disk"
echo ""
echo "For bhyve (FreeBSD native hypervisor):"
echo "  1. Copy image to bhyve host"
echo "  2. Create VM with:"
echo "     # bhyvectl --create --vm=minibsd"
echo "     # bhyve -c 2 -m 1G -H \\"
echo "       -s 0,hostbridge \\"
echo "       -s 1,lpc \\"
echo "       -s 2,virtio-blk,$IMG_PATH \\"
echo "       -s 3,virtio-net,tap0 \\"
echo "       -l com1,stdio \\"
echo "       minibsd"
echo "  3. Or use vm-bhyve for easier management:"
echo "     # vm create -t freebsd-zvol -s 2G minibsd"
echo "     # vm install minibsd $IMG_PATH"
echo "     # vm start minibsd"
echo ""
echo "=== SECURITY NOTE ==="
echo "Root password for this image: $ROOT_PASSWORD"
echo "This is a randomly generated password unique to this build."
echo "Change it after first login with: passwd"
echo ""
