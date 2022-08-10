#!/bin/bash

echo2() { echo "meson-cross-wrapper:" "$@" >&2; }

exec_meson() { set -x; exec /usr/bin/meson "$@"; }

verb="$1"
shift

if [[ -z "$CARCH" ]]; then
    echo2 "CARCH not set, not using a cross-config"
    exec_meson "$verb" "$@"
fi


[ -z "$MESON_CROSS_CONFIG" ] || echo2 "using cross config ${MESON_CROSS_CONFIG}"
meson_cross_config="${MESON_CROSS_CONFIG:-/usr/share/meson/cross/cross_$CARCH.txt}"

echo2 "wrapping for architecture $CARCH using $meson_cross_config"
exec_meson "$verb" --cross-file="$meson_cross_config" "$@"
