#!/usr/bin/env bash

release=$(lsb_release -c -s)

# Check if the script is running under Ubuntu 18.04 Bionic Beaver
if [ "$release" != "bionic" ] && [ "$release" != "disco" ]; then
    >&2 echo "This script is made for Ubuntu 18.04/19.04!"
    exit 1
fi

# Check if the script is running as root
if [ "$EUID" -ne 0 ]; then
    >&2 echo "Please run xps-tweaks as root!"
    exit 2
fi

# Enable universe and proposed
add-apt-repository -y universe
apt -y update
apt -y full-upgrade

# Install all the power management tools
add-apt-repository -y ppa:linrunner/tlp
apt -y update
apt -y install thermald tlp tlp-rdw powertop

# Fix Sleep/Wake Bluetooth Bug
sed -i '/RESTORE_DEVICE_STATE_ON_STARTUP/s/=.*/=1/' /etc/default/tlp
systemctl restart tlp

# Other packages
apt -y install intel-microcode

# Install wifi drivers
rm -rf /lib/firmware/ath10k/QCA6174/hw3.0/*
wget -O /lib/firmware/ath10k/QCA6174/hw3.0/board.bin https://github.com/kvalo/ath10k-firmware/blob/master/QCA6174/hw3.0/board.bin?raw=true
wget -O /lib/firmware/ath10k/QCA6174/hw3.0/board-2.bin https://github.com/kvalo/ath10k-firmware/blob/master/QCA6174/hw3.0/board-2.bin?raw=true
wget -O /lib/firmware/ath10k/QCA6174/hw3.0/firmware-4.bin https://github.com/kvalo/ath10k-firmware/blob/master/QCA6174/hw3.0/firmware-4.bin_WLAN.RM.2.0-00180-QCARMSWPZ-1?raw=true

# Enable power saving tweaks for Intel chip
if [[ $(uname -r) == *"4.15"* ]]; then
    echo "options i915 enable_fbc=1 enable_guc_loading=1 enable_guc_submission=1 disable_power_well=0 fastboot=1" > /etc/modprobe.d/i915.conf
else
    echo "options i915 enable_fbc=1 enable_guc=3 disable_power_well=0 fastboot=1" > /etc/modprobe.d/i915.conf
fi

# Let users check fan speed with lm-sensors
echo "options dell-smm-hwmon restricted=0 force=1" > /etc/modprobe.d/dell-smm-hwmon.conf
if cat /etc/modules | grep "dell-smm-hwmon" &>/dev/null
then
    echo "dell-smm-hwmon is already in /etc/modules!"
else
    echo "dell-smm-hwmon" >> /etc/modules
fi
update-initramfs -u

# Switch to Intel card
prime-select intel 2>/dev/null

# Tweak grub defaults
GRUB_OPTIONS_VAR_NAME="GRUB_CMDLINE_LINUX_DEFAULT"
GRUB_OPTIONS="quiet splash acpi_rev_override=1 acpi_osi=Linux nouveau.modeset=0 pcie_aspm=force drm.vblankoffdelay=1 scsi_mod.use_blk_mq=1 nouveau.runpm=0 mem_sleep_default=deep "
echo "Do you wish to disable SPECTRE/Meltdown patches for performance?"
select yn in "Yes" "No"; do
    case $yn in
        Yes ) GRUB_OPTIONS+="pti=off spectre_v2=off l1tf=off nospec_store_bypass_disable no_stf_barrier"; break;;
        No ) break;;
    esac
done
GRUB_OPTIONS_VAR="$GRUB_OPTIONS_VAR_NAME=\"$GRUB_OPTIONS\""

if cat /etc/default/grub | grep "$GRUB_OPTIONS_VAR" &>/dev/null
then
    echo "Grub is already tweaked!"
else
    sed -i "s/^$GRUB_OPTIONS_VAR_NAME/# $GRUB_OPTIONS_VAR_NAME/g" /etc/default/grub
    awk '/# '"$GRUB_OPTIONS_VAR_NAME"'/{print;print "'"$GRUB_OPTIONS_VAR_NAME"'=\"'"$GRUB_OPTIONS"'\"";next}1' /etc/default/grub | \
        tee /etc/default/grub &>/dev/null
    update-grub
fi

# Ask for disabling tracker
echo "Do you wish to disable GNOME tracker (it uses a lot of power)?"
select yn in "Yes" "No"; do
    case $yn in
        Yes ) systemctl mask tracker-extract.desktop tracker-miner-apps.desktop tracker-miner-fs.desktop tracker-store.desktop; break;;
        No ) break;;
    esac
done

# Ask for disabling fingerprint reader
echo "Do you wish to disable the fingerprint reader to save power (no linux driver is available for this device)?"
select yn in "Yes" "No"; do
    case $yn in
        Yes ) echo "# Disable fingerprint reader
SUBSYSTEM==\"usb\", ATTRS{idVendor}==\"27c6\", ATTRS{idProduct}==\"5395\", ATTR{authorized}=\"0\"" > /etc/udev/rules.d/fingerprint.rules; break;;
        No ) break;;
    esac
done

echo "FINISHED! Please reboot the machine!"
