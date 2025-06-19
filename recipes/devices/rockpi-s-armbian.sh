#!/usr/bin/env bash
# shellcheck disable=SC2034

## Setup for Radxa Rock Pi S
DEVICE_SUPPORT_TYPE="C" # First letter (Community Porting|Supported Officially|OEM)
DEVICE_STATUS="T"       # First letter (Planned|Test|Maintenance)

# Base system
BASE="Debian"
ARCH="armhf"
BUILD="armv7"
UINITRD_ARCH="arm64"

### Device information
DEVICENAME="RockPi-S" # Pretty name
# This is useful for multiple devices sharing the same/similar kernel
DEVICEFAMILY="armbian"
# tarball from DEVICEFAMILY repo to use
#DEVICEBASE=${DEVICE} # Defaults to ${DEVICE} if unset
DEVICEREPO="https://github.com/volumio/platform-rockpi-s-${DEVICEFAMILY}"

### What features do we want to target
# TODO: Not fully implement
VOLVARIANT=no # Custom Volumio (Motivo/Primo etc)
MYVOLUMIO=no
VOLINITUPDATER=yes
DISABLE_DISPLAY=yes

## Partition info
BOOT_START=20
BOOT_END=148
BOOT_TYPE=msdos          # msdos or gpt
BOOT_USE_UUID=yes        # Add UUID to fstab
INIT_TYPE="initv3"

# Modules that will be added to intramsfs
MODULES=("overlay" "overlayfs" "squashfs" "nls_cp437" "fuse" "nls_iso8859_1")
# Packages that will be installed
PACKAGES=("bluez-firmware" "bluetooth" "bluez" "bluez-tools")

### Device customisation
# Copy the device specific files (Image/DTS/etc..)
write_device_files() {
  log "Running write_device_files" "ext"

  cp -dR "${PLTDIR}/${DEVICE}/boot" "${ROOTFSMNT}"
  cp -pdR "${PLTDIR}/${DEVICE}/lib/modules" "${ROOTFSMNT}/lib"
  cp -pdR "${PLTDIR}/${DEVICE}/lib/firmware" "${ROOTFSMNT}/lib"

  log "copy alsa plugin" "ext"
  cp -r "${PLTDIR}/${DEVICE}/volumio/s2mono/libasound_module_pcm_s2mono.so" "${ROOTFSMNT}/usr/lib/arm-linux-gnueabihf/alsa-lib"

  log "copy s2mono plugin" "ext"
  mkdir -p "${ROOTFSMNT}/data/plugins/audio_interface"
  cp -r "${PLTDIR}/${DEVICE}/volumio/volumio-plugin/s2mono" "${ROOTFSMNT}/data/plugins/audio_interface"

  log "copy yandex-music plugin" "ext"
  mkdir -p "${ROOTFSMNT}/data/plugins/music_service"
  cp -r "${PLTDIR}/${DEVICE}/volumio/volumio-plugin/yandex_music" "${ROOTFSMNT}/data/plugins/music_service"
}

write_device_bootloader() {
  log "Running write_device_bootloader" "ext"

  dd if="${PLTDIR}/${DEVICE}/u-boot/u-boot-rockchip.bin" of="${LOOP_DEV}" seek=64 conv=notrunc status=none
}

# Will be called by the image builder for any customisation
device_image_tweaks() {
  :
}

### Chroot tweaks
# Will be run in chroot (before other things)
device_chroot_tweaks() {
  :
}

# Will be run in chroot - Pre initramfs
device_chroot_tweaks_pre() {
  log "Performing device_chroot_tweaks_pre" "ext"
  log "Fixing armv8 deprecated instruction emulation with armv7 rootfs"
  cat <<-EOF >>/etc/sysctl.conf
abi.cp15_barrier=2
EOF

  echo "Install device tree compiler with overlays support"
  wget -P /tmp http://ftp.debian.org/debian/pool/main/d/device-tree-compiler/device-tree-compiler_1.4.7-4_armhf.deb
  dpkg -i /tmp/device-tree-compiler_1.4.7-4_armhf.deb
  rm /tmp/device-tree-compiler_1.4.7-4_armhf.deb

  log "Creating boot parameters from template"
  sed -i "s/rootdev=UUID=/rootdev=UUID=${UUID_BOOT}/g" /boot/armbianEnv.txt
  sed -i "s/imgpart=UUID=/imgpart=UUID=${UUID_IMG}/g" /boot/armbianEnv.txt
  sed -i "s/bootpart=UUID=/bootpart=UUID=${UUID_BOOT}/g" /boot/armbianEnv.txt
  sed -i "s/datapart=UUID=/datapart=UUID=${UUID_DATA}/g" /boot/armbianEnv.txt

  log "Adding gpio group and udev rules"
  groupadd -f --system gpio
  usermod -aG gpio volumio
  # Works with newer kernels as well
  cat <<-EOF >/etc/udev/rules.d/99-gpio.rules
	SUBSYSTEM=="gpio*", PROGRAM="/bin/sh -c 'find -L /sys/class/gpio/ -maxdepth 2 -exec chown root:gpio {} \; -exec chmod 770 {} \; || true'"
	EOF
  log "Fix for Volumio Remote updater"
  sed -i '10i\RestartSec=5' /lib/systemd/system/volumio-remote-updater.service
}

# Will be run in chroot - Post initramfs
device_chroot_tweaks_post() {
  # log "Running device_chroot_tweaks_post" "ext"
  :
}

# Will be called by the image builder post the chroot, before finalisation
device_image_tweaks_post() {
  log "Running device_image_tweaks_post" "ext"
  log "Creating uInitrd from 'volumio.initrd'" "info"
  if [[ -f "${ROOTFSMNT}"/boot/volumio.initrd ]]; then
    mkimage -v -A "${UINITRD_ARCH}" -O linux -T ramdisk -C none -a 0 -e 0 -n uInitrd -d "${ROOTFSMNT}"/boot/volumio.initrd "${ROOTFSMNT}"/boot/uInitrd
    rm "${ROOTFSMNT}"/boot/volumio.initrd
  fi
  if [[ -f "${ROOTFSMNT}"/boot/boot.cmd ]]; then
    log "Creating boot.scr"
    mkimage -A arm -T script -C none -d "${ROOTFSMNT}"/boot/boot.cmd "${ROOTFSMNT}"/boot/boot.scr
  fi
}
