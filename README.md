# work repository

simple things I used at work:

# miniBSD v1.0

A script to create minimal, optimized FreeBSD images from an existing FreeBSD installation.

## Overview

**miniBSD** creates a minimal FreeBSD image by extracting and optimizing components from an existing FreeBSD installation. The script must be run on a functioning FreeBSD system, which serves as the source for all binaries, libraries, and kernel modules.

## Features

### 🔧 Optimizations
- **Minimal footprint**: 1GB image with ~750MB free space
- **Selective binary inclusion**: Only essential system binaries
- **Stripped libraries**: All libraries are stripped of debug symbols
- **Curated kernel modules**: VM-optimized module selection (expandable to full set)
- **Clean system**: No pkg manager preinstalled, no development tools

### 🔒 Security
- Random 6-digit root password generated for each build
- Standardized root shell (`/bin/sh`)
- Safety aliases preconfigured (`rm -I`, `cp -ip`, `mv -i`)
- SSH ready with custom configuration

### ⚙️ Built-in Features
- Automatic NTP synchronization with randomized schedule
- Dynamic MOTD showing system information
- Colored terminal output (ls, grep)
- Customized prompt showing `user@host:path`
- Useful aliases preconfigured system-wide

## Compatibility

### Hypervisor Support
- **Proxmox** (KVM/QEMU)
- **VMware** ESXi, Workstation, Fusion
- **VirtualBox**
- **bhyve** (FreeBSD native)
- **Xen**
- **Hyper-V**
- Physical hardware

### System Requirements
- **Source System**: FreeBSD 13.x or newer (developed on 14.x)
- **Privileges**: Root access required
- **Free Space**: ~2GB for image creation
- **Target Size**: 1GB (configurable)

## Quick Start

```bash
# Download the script
fetch https://github.com/ggiovannelli/miniBSD/raw/main/miniBSD.sh

# Make it executable
chmod +x miniBSD.sh

# Run as root
./miniBSD.sh

# Image will be created as miniBSD.img and miniBSD.img.gz
```

## Configuration

Key variables at the top of the script:

```bash
IMG_SIZE_MB=1024              # Image size (increase to 1536 for full kernel modules)
MINIMAL_KERNEL_MODULES="yes"  # "yes" for VM-optimized, "no" for full set
```

## Output

The script creates:
- `miniBSD.img` - Raw disk image
- `miniBSD.img.gz` - Compressed image for distribution

Each build displays:
- Unique root password (save it!)
- NTP sync schedule
- Build summary

## Usage Examples

### Proxmox
```bash
scp miniBSD.img.gz root@proxmox:/tmp/
gunzip /tmp/miniBSD.img.gz
qm importdisk <vmid> /tmp/miniBSD.img <storage>
```

### VMware ESXi
```bash
qemu-img convert -f raw -O vmdk miniBSD.img freebsd.vmdk
# Upload to datastore and create VM
```

### bhyve
```bash
bhyve -c 2 -m 1G -H \
  -s 0,hostbridge \
  -s 1,lpc \
  -s 2,virtio-blk,miniBSD.img \
  -s 3,virtio-net,tap0 \
  -l com1,stdio \
  minibsd
```

## What's Included

- Core FreeBSD base system
- Essential networking tools
- SSH server
- Text editors (vi, ee)
- Compression utilities
- System management tools
- Virtual machine drivers

## What's Excluded

- Package manager (can be installed post-boot)
- Development tools (compilers, headers)
- Documentation and man pages
- Source code
- Debug symbols
- X11/Graphics
- Sound support

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

This project is licensed under the BSD 2-Clause License - same as FreeBSD.

## Acknowledgments

- FreeBSD Project for the amazing OS
- All contributors who helped optimize this script through 97 iterations

---

**miniBSD v1.0** - Less is More! 🚀
