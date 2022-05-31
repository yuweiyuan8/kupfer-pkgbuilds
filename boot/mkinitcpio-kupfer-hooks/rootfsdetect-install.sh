#!/bin/bash

build() {
  add_binary losetup
  add_file /etc/kupfer/deviceinfo
  add_file /usr/lib/initcpio/hooks/kupfer-functions.sh

  add_runscript
}

help() {
  cat <<HELPEOF
This hook detects the rootfs image
HELPEOF
}
