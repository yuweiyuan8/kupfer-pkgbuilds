#!/bin/bash
verb="$1"
shift

if [[ -n "$KUPFER_CROSS_TARGET" ]]; then
 #--libdir="/chroot/build_$KUPFER_CROSS_TARGET"
    exec /usr/bin/meson "$verb" --cross-file=/usr/lib/meson/cross/cross_"$KUPFER_CROSS_TARGET".txt "$@"
else
    exec meson "$verb" "$@"
fi
