#!/bin/bash

build() {
  add_binary buffyboard

  add_runscript
}

help() {
  cat <<HELPEOF
This hook installs and runs the Buffyboard OSK
HELPEOF
}

