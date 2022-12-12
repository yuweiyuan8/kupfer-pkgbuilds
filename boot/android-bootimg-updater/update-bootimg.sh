#!/bin/bash

set -e

if [ "$(id -u)" -ne "0" ]; then
  echo "This script requires root."
  exit 1
fi

unset initramfs_file
if [ -f "/boot/initramfs-initsquared.img" ]; then
  initramfs_file="initramfs-initsquared.img"
elif [ -f "/boot/initramfs-linux.img" ]; then
  initramfs_file="initramfs-linux.img"
elif [ -z "$1" ]; then
  echo "/boot/initramfs-initsquared.img or /boot/initramfs-linux.img not found. initramfs file name (located in /boot) must be specified via argument."
  exit 1
else
  initramfs_file="$1"
fi

dir=$(mktemp -d)

echo "Generating new boot.img with initramfs $initramfs_file"

boot-deploy -i "$initramfs_file" -k Image.gz -d /boot -o /boot -c /etc/kupfer/deviceinfo

qhypstub_offset="508KiB"
qhypstub_size="4KiB"
lk2nd_bootimg_offset="512KiB"

flash_file="/boot/boot.img"
if [[ "$deviceinfo_lk2nd" == "true" ]]; then
  echo "Generating new boot.bin for lk2nd device"
  flash_file="/boot/boot.bin"
  dd if=/dev/zero of="$flash_file" bs="$lk2nd_bootimg_offset" count=1
  dd of="$flash_file" bs="$qhypstub_offset" count=1 conv=notrunc if=/boot/lk2nd.img
  dd of="$flash_file" bs="$qhypstub_size" count=1 conv=notrunc seek="$qhypstub_offset" oflag=seek_bytes if=/boot/qhypstub.bin
  dd of="$flash_file" conv=notrunc oflag=append if=/boot/boot.img
fi

AB_SLOT_SUFFIX=$(grep -o 'androidboot\.slot_suffix=..' /proc/cmdline | cut -d "=" -f2)
ABOOT_PART="/dev/disk/by-partlabel/boot${AB_SLOT_SUFFIX}"

if [ -e "$ABOOT_PART" ]; then
  echo "Running on the device"

  ABOOT_PART="$(readlink -f "$ABOOT_PART")"

  dd if="$ABOOT_PART" of=/tmp/boot.bin
  if [[ "$deviceinfo_lk2nd" == "true" ]]; then
    dd if=/tmp/boot.bin of=/tmp/boot.img skip="$lk2nd_bootimg_offset" iflag=skip_bytes
  else
    cp /tmp/boot.bin /tmp/boot.img
  fi

  permanent=false
  if [[ "$(file /tmp/boot.img)" != "/tmp/boot.img: data" ]]; then
    cmdline=$(unpack_bootimg --boot_img /tmp/boot.img --out "$dir" | grep -E "^command line args")
    if [[ "$cmdline" == *"kupfer"* ]]; then
      permanent=true
    fi
  fi

  if [[ "$permanent" == "true" ]]; then
    echo "Running with permanent boot.img"
    echo "Flashing new boot.img"
    dd if="$flash_file" of="$ABOOT_PART"
  elif [[ "$1" == "-f" ]]; then
    echo "Flashing new boot.img"
    dd if="$flash_file" of="$ABOOT_PART"
  else
    echo "Running with temporary boot.img"
    echo "Skip flashing new boot.img"
  fi
else
  echo "Not running on the device"
  echo "Skip flashing new boot.img"
fi

rm -rf "$dir" /tmp/boot.bin /tmp/boot.img

