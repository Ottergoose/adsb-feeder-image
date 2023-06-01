#!/bin/bash
#shellcheck shell=bash external-sources=false disable=SC1090,SC2164
# DOCKER-INSTALL.SH -- Installation script for the Docker infrastructure on a Raspbian or Ubuntu system
# Usage: source <(curl -s https://raw.githubusercontent.com/sdr-enthusiasts/docker-install/main/docker-install.sh)
#
# Copyright 2021-2023 Ramon F. Kolb (kx1t)- licensed under the terms and conditions
# of the MIT license. The terms and conditions of this license are included with the Github
# distribution of this package.
#
#
# modified to build a base image (so intended for non-interactive use) by Dirk Hohndel <dirk@hohndel.org>


    echo "Installing docker, each step may take a while:"
    echo -n "Updating repositories... "
    sudo apt-get update -qq -y >/dev/null && sudo apt-get upgrade -q -y
    echo -n "Ensuring dependencies are installed... "
    sudo apt-get install -qq -y apt-transport-https ca-certificates curl gnupg2 slirp4netns software-properties-common uidmap w3m jq netcat-openbsd >/dev/null
    echo -n "Getting docker..."
    curl -fsSL https://get.docker.com -o get-docker.sh
    echo "Installing Docker... "
    sudo sh get-docker.sh
    echo "Docker installed -- configuring docker..."
    sudo usermod -aG docker "${USER}"
    sudo mkdir -p /etc/docker
    sudo chmod a+rwx /etc/docker
    cat > /etc/docker/daemon.json <<EOF
{
  "log-driver": "local",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  }
}
EOF
    sudo chmod u=rw,go=r /etc/docker/daemon.json
    echo 'export PATH=/usr/bin:$PATH' >> ~/.bashrc
    export PATH=/usr/bin:$PATH


echo -n "Checking for Docker Compose installation... "
if which docker-compose >/dev/null 2>&1
then
    echo "found! No need to install..."
elif docker compose version >/dev/null 2>&1
then
    echo "Docker Compose plugin found. Creating an alias to it for \"docker-compose \"..."
    echo "alias docker-compose=\"docker compose\"" >> ~/.bash_aliases
    source ~/.bash_aliases
else
    echo "not found!"
    echo "Installing Docker-compose... "
    sudo apt install -y docker-compose-plugin
    echo "alias docker-compose=\"docker compose\"" >> ~/.bash_aliases
    source ~/.bash_aliases

    if docker-compose version
    then
      echo "Docker-compose was installed successfully. You can use either \"docker compose\" or \"docker-compose\", they are aliases of each other"
    else
      echo "Docker-compose was not installed correctly - you may need to do this manually."
    fi
fi

# Now make sure that libseccomp2 >= version 2.4. This is necessary for Bullseye-based containers
# This is often an issue on Buster and Stretch-based host systems with 32-bits Rasp Pi OS installed pre-November 2021.
# The following code checks and corrects this - see also https://github.com/fredclausen/Buster-Docker-Fixes
OS_VERSION="$(sed -n 's/\(^\s*VERSION_CODENAME=\)\(.*\)/\2/p' /etc/os-release)"
[[ "$OS_VERSION" == "" ]] && OS_VERSION="$(sed -n 's/^\s*VERSION=.*(\(.*\)).*/\1/p' /etc/os-release)"
OS_VERSION=${OS_VERSION^^}
LIBVERSION_MAJOR="$(apt-cache policy libseccomp2 | grep -e libseccomp2: -A1 | tail -n1 | sed -n 's/.*:\s*\([0-9]*\).\([0-9]*\).*/\1/p')"
LIBVERSION_MINOR="$(apt-cache policy libseccomp2 | grep -e libseccomp2: -A1 | tail -n1 | sed -n 's/.*:\s*\([0-9]*\).\([0-9]*\).*/\2/p')"

if (( LIBVERSION_MAJOR < 2 )) || (( LIBVERSION_MAJOR == 2 && LIBVERSION_MINOR < 4 )) && [[ "${OS_VERSION}" == "BUSTER" ]]
then
  echo "libseccomp2 needs updating. Please wait while we do this."
  sudo apt-key adv --keyserver keyserver.ubuntu.com --recv-keys 04EE7237B7D453EC 648ACFD622F3D138
  echo "deb http://deb.debian.org/debian buster-backports main" | sudo tee -a /etc/apt/sources.list.d/buster-backports.list
  sudo apt update
  sudo apt install -y -q -t buster-backports libseccomp2
elif (( LIBVERSION_MAJOR < 2 )) || (( LIBVERSION_MAJOR == 2 && LIBVERSION_MINOR < 4 )) && [[ "${OS_VERSION}" == "STRETCH" ]]
then
  INSTALL_CANDIDATE=$(curl -qsL http://ftp.debian.org/debian/pool/main/libs/libseccomp/ |w3m -T text/html -dump | sed -n 's/^.*\(libseccomp2_2.5.*armhf.deb\).*/\1/p' | sort | tail -1)
  curl -qsL -o /tmp/"${INSTALL_CANDIDATE}" http://ftp.debian.org/debian/pool/main/libs/libseccomp/${INSTALL_CANDIDATE}
  sudo dpkg -i /tmp/"${INSTALL_CANDIDATE}" && rm -f /tmp/"${INSTALL_CANDIDATE}"
fi
# Now make sure all went well
LIBVERSION_MAJOR="$(apt-cache policy libseccomp2 | grep -e libseccomp2: -A1 | tail -n1 | sed -n 's/.*:\s*\([0-9]*\).\([0-9]*\).*/\1/p')"
LIBVERSION_MINOR="$(apt-cache policy libseccomp2 | grep -e libseccomp2: -A1 | tail -n1 | sed -n 's/.*:\s*\([0-9]*\).\([0-9]*\).*/\2/p')"
if (( LIBVERSION_MAJOR > 2 )) || (( LIBVERSION_MAJOR == 2 && LIBVERSION_MINOR >= 4 ))
then
   echo "Your system now uses libseccomp2 version $(apt-cache policy libseccomp2|sed -n 's/\s*Installed:\s*\(.*\)/\1/p')."
else
    echo "Something went wrong. Your system is using libseccomp2 v$(apt-cache policy libseccomp2|sed -n 's/\s*Installed:\s*\(.*\)/\1/p'), and it needs to be v2.4 or greater for the ADSB containers to work properly."
    echo "Please follow these instructions to fix this after this install script finishes: https://github.com/fredclausen/Buster-Docker-Fixes"
fi

    tmpdir=$(mktemp -d)
    pushd "$tmpdir" >/dev/null || exit
        echo -n "Getting the latest RTL-SDR packages... "
        sudo apt-get install -qq -y git rtl-sdr >/dev/null
        echo -n "Getting the latest UDEV rules... "
        # First install the UDEV rules for RTL-SDR dongles
        sudo -E "$(which bash)" -c "curl -sL -o /etc/udev/rules.d/rtl-sdr.rules https://raw.githubusercontent.com/wiedehopf/adsb-scripts/master/osmocom-rtl-sdr.rules"
        # Next, exclude the drivers so the dongles stay accessible
        # Please keep the list in this order and add any additional ones to the BOTTOM. 
        BLOCKED_MODULES=()
        BLOCKED_MODULES+=("rtl2832_sdr")
        BLOCKED_MODULES+=("dvb_usb_rtl2832u")
        BLOCKED_MODULES+=("dvb_usb_rtl28xxu")
        BLOCKED_MODULES+=("dvb_usb_v2")
        BLOCKED_MODULES+=("8192cu")
        BLOCKED_MODULES+=("r820t")
        BLOCKED_MODULES+=("rtl2830")
        BLOCKED_MODULES+=("rtl2832")
        BLOCKED_MODULES+=("rtl2838")
        BLOCKED_MODULES+=("rtl8192cu")
        BLOCKED_MODULES+=("rtl8xxxu")
        BLOCKED_MODULES+=("dvb_core")
        echo -n "Excluding and unloading any competing RTL-SDR drivers... "
        for module in "${BLOCKED_MODULES[@]}"
        do
            if ! grep -q $module /etc/modprobe.d/exclusions-rtl2832.conf
            then
              sudo -E "$(which bash)" -c "echo blacklist $module >>/etc/modprobe.d/exclusions-rtl2832.conf"
              sudo -E "$(which bash)" -c "modprobe -r $module 2>/dev/null" || true
            fi
        done
        # Rebuild module dependency database factoring in blacklists
        which depmod >/dev/null 2>&1 && depmod -a || true
        # On systems with initramfs, this needs to be updated to make sure the exclusions take effect:
        which update-initramfs >/dev/null 2>&1 && sudo update-initramfs -u || true 
    popd >/dev/null
    # Check tmpdir is set and not null before attempting to remove it
    if [[ -z "$tmpdir" ]]; then
      rm -rf "$tmpdir" >/dev/null 2>&1
    fi
echo "Making sure commands will persist when the terminal closes..."
sudo loginctl enable-linger "$(whoami)"
#
# The following prevents DHCPCD based systems from trying to assign IP addresses to each of the Docker containers.
# Note that this is not needed or available if the system uses DHCPD instead of DHCPCD.
if [[ -f /etc/dhcpcd.conf ]] && ! grep "denyinterfaces veth\*" /etc/dhcpcd.conf >/dev/null 2>&1
then
  echo -n "Excluding veth interfaces from dhcp. This will prevent problems if you are connected to the internet via WiFi when running many Docker containers... "
  sudo sh -c 'echo "denyinterfaces veth*" >> /etc/dhcpcd.conf'
  sudo systemctl restart dhcpcd.service
  echo "done!"
fi

# Add some aliases to localhost in `/etc/hosts`. This will speed up recreation of images with docker-compose
if ! grep localunixsocket /etc/hosts >/dev/null 2>&1
then
  echo "Speeding up the recreation of containers when using docker-compose..."
  sudo sed -i 's/^\(127.0.0.1\s*localhost\)\(.*\)/\1\2 localunixsocket localunixsocket.local localunixsocket.home/g' /etc/hosts
fi

