#!/data/data/com.termux/files/usr/bin/bash

# Optimized Kali Linux installation script for Termux
# This script installs Kali Linux rootfs and configures XFCE4 desktop environment with VNC

set -e  # Exit on error

# Configuration variables
FOLDER="kali-fs"
SOURCE="https://raw.githubusercontent.com/st4rk-7/kali-termux/main"
TARBALL="kali-rootfs.tar.xz"
BINDS_DIR="kali-binds"
STARTUP_SCRIPT="start-kali.sh"

# Color codes
RED='\e[31m'
GREEN='\e[32m'
YELLOW='\e[33m'
RESET='\e[0m'

# Helper functions
show_status() {
    echo -e "${GREEN}[*] $1${RESET}"
}

show_warning() {
    echo -e "${YELLOW}[!] $1${RESET}"
}

show_error() {
    echo -e "${RED}[✗] $1${RESET}"
}

# Check if folder exists (skips downloading if it does)
if [ -d "$FOLDER" ]; then
    show_status "Kali rootfs directory already exists, skipping download"
    SKIP_DOWNLOAD=true
fi

# Get device architecture
get_architecture() {
    ARCH=$(uname -m)
    case "$ARCH" in
        aarch64)  echo "arm64" ;;
        armv7l)   echo "armhf" ;;
        x86_64)   echo "amd64" ;;
        i*86)     echo "i386" ;;
        *)        show_error "Unsupported architecture: $ARCH"; exit 1 ;;
    esac
}

# Download rootfs
download_rootfs() {
    ARCH=$(get_architecture)
    show_status "Detected architecture: $ARCH"

    if [ ! -f "$TARBALL" ]; then
        show_status "Downloading Kali rootfs ($ARCH). This may take a while depending on your internet speed."

        wget --progress=dot:giga "${SOURCE}/rootfs/${ARCH}/kali-rootfs-${ARCH}.tar.xz" -O "$TARBALL" || {
            show_error "Failed to download rootfs"; exit 1;
        }
    else
        show_status "Rootfs tarball already exists, skipping download"
    fi
}

# Extract rootfs
extract_rootfs() {
    show_status "Creating rootfs directory"
    mkdir -p "$FOLDER"

    show_status "Extracting rootfs, please be patient"
    cd "$FOLDER" || exit
    proot --link2symlink tar -xJf "../${TARBALL}" || {
        show_error "Failed to extract rootfs";
        cd ..;
        exit 1;
    }
    cd ..
}

# Create startup script
create_startup_script() {
    show_status "Creating startup script"
    cat > "$STARTUP_SCRIPT" <<- 'EOF'
#!/bin/bash
cd $(dirname $0)
# Unset LD_PRELOAD in case termux-exec is installed
unset LD_PRELOAD
command="proot"
command+=" --link2symlink"
command+=" -0"
command+=" -r kali-fs"

# Add bind mounts
if [ -n "$(ls -A kali-binds 2>/dev/null)" ]; then
    for f in kali-binds/* ; do
        [ -f "$f" ] && . "$f"
    done
fi

command+=" -b /dev"
command+=" -b /proc"
command+=" -b kali-fs/root:/dev/shm"
## Uncomment the following line to have access to the home directory of termux
#command+=" -b /data/data/com.termux/files/home:/root"
## Uncomment the following line to mount /sdcard directly to /
#command+=" -b /sdcard"

command+=" -w /root"
command+=" /usr/bin/env -i"
command+=" HOME=/root"
command+=" PATH=/usr/local/sbin:/usr/local/bin:/bin:/usr/bin:/sbin:/usr/sbin:/usr/games:/usr/local/games"
command+=" TERM=$TERM"
command+=" LANG=C.UTF-8"
command+=" /bin/bash --login"

com="$@"
if [ -z "$1" ]; then
    exec $command
else
    $command -c "$com"
fi
EOF

    # Create bash logout script
    cat > "$FOLDER/root/.bash_logout" <<- 'EOF'
#!/bin/bash
vncserver-stop
pkill dbus* 2>/dev/null
pkill ssh* 2>/dev/null
EOF
}

# Configure system
configure_system() {
    show_status "Configuring apt sources"
    show_warning "Patching mirrorlist temporarily. Don't worry about GPG errors"
    echo "deb [trusted=yes] https://http.kali.org/kali kali-rolling main contrib non-free" > "$FOLDER/etc/apt/sources.list"

    show_status "Optimizing APT settings"
    mkdir -p "$FOLDER/etc/apt/apt.conf.d"
    echo 'APT::Acquire::Retries "3";' > "$FOLDER/etc/apt/apt.conf.d/80-retries"

    show_status "Setting up desktop environment installation"
    # Create .bash_profile for first run
    cat > "$FOLDER/root/.bash_profile" <<- EOF
#!/bin/bash
apt update -y && apt install wget sudo dbus-x11 -y || {
    echo "Failed to install base packages"
    exit 1
}

# Install XFCE Desktop Environment
if [ ! -f /root/xfce4_de.sh ]; then
    wget --tries=20 $SOURCE/startup/xfce4_de.sh -O /root/xfce4_de.sh || {
        echo "Failed to download XFCE setup script"
        exit 1
    }
    bash ~/xfce4_de.sh
else
    bash ~/xfce4_de.sh
fi

# Install VNC server scripts
if [ ! -f /usr/local/bin/vncserver-start ]; then
    wget --tries=20 $SOURCE/startup/vncserver-start -O /usr/local/bin/vncserver-start
    wget --tries=20 $SOURCE/startup/vncserver-stop -O /usr/local/bin/vncserver-stop
    chmod +x /usr/local/bin/vncserver-stop
    chmod +x /usr/local/bin/vncserver-start
fi

# Install VNC server if not already installed
if [ ! -f /usr/bin/vncserver ]; then
    apt install tigervnc-standalone-server -y
fi

# Install browser
echo 'Installing browser'
apt install firefox-esr -y

echo -e "\n\033[1;32mWelcome to termux-Kali (St4rk-7)\033[0m"
echo -e "VNC server is ready. Use vncserver-start to start, vncserver-stop to stop\n"

# Remove first run script
rm -rf ~/.bash_profile
EOF
}

# Download desktop environment setup script
download_de_script() {
    show_status "Downloading XFCE desktop environment setup script"
    mkdir -p "$FOLDER/root"
    wget --tries=20 "$SOURCE/startup/xfce4_de.sh" -O "$FOLDER/root/xfce4_de.sh" || {
        show_warning "Failed to download DE script, will try again at first run"
    }
}

# Finalize installation
finalize() {
    show_status "Fixing script permissions"
    termux-fix-shebang "$STARTUP_SCRIPT"
    chmod +x "$STARTUP_SCRIPT"

    mkdir -p "$BINDS_DIR"

    show_status "Cleaning up"
    if [ -f "$TARBALL" ]; then
        show_status "Removing tarball to free up space"
        rm "$TARBALL"
    fi

    show_status "Installation complete!"
    show_status "To start Kali Linux, run ./$STARTUP_SCRIPT"
    show_status "After first run, start VNC server with 'vncserver-start'"
}

# Main installation process
main() {
    show_status "Starting Kali Linux installation for Termux"

    if [ "$SKIP_DOWNLOAD" != true ]; then
        download_rootfs
        extract_rootfs
    fi

    create_startup_script
    configure_system
    download_de_script
    finalize

    show_status "Starting Kali Linux to complete setup..."
    bash "$STARTUP_SCRIPT"
}

# Run the installation
main