#!/bin/env python3

import hashlib
import os


class Kernel():
    name = ""
    arch = ""
    url = ""
    defconfigs = []
    dtb_vendor = ""
    dtbs = []
    patches = {}
    commit = ""
    pkgver = ""
    pkgrel = 0

    def __init__(self, name: str, arch: str, url: str, defconfigs: list[str], dtb_vendor: str, dtbs: list[str], patches: dict[str, str], commit: str, pkgver: str, pkgrel: int) -> None:
        self.name = name
        self.arch = arch
        self.url = url
        self.defconfigs = defconfigs
        self.dtb_vendor = dtb_vendor
        self.dtbs = dtbs
        self.patches = patches
        self.commit = commit
        self.pkgrel = pkgrel
        self.pkgver = pkgver

    def karch(self):
        if self.arch == 'aarch64':
            return 'arm64'
        raise Exception(f'Unknown KARCH for {self.arch}')


kernels = [
    Kernel(
        'msm8916',
        'aarch64',
        'https://github.com/msm8916-mainline/linux',
        [
            'msm8916_defconfig',
            'pmos.config',
        ],
        'qcom',
        ['msm8916-longcheer-l8910-modem.dtb'],
        {},
        '586b7e693136acaf31e38f1a9beacf22a07cfde3',
        '5.14.0',
        3,
    ),
    Kernel(
        'sdm845',
        'aarch64',
        'https://gitlab.com/sdm845-mainline/sdm845-linux',
        ['sdm845.config'],
        'qcom',
        [
            'sdm845-xiaomi-beryllium-tianma.dtb',
            'sdm845-xiaomi-beryllium-ebbg.dtb',
            'sdm845-oneplus-enchilada.dtb',
            'sdm845-oneplus-fajita.dtb',
        ],
        {},
        'a620c228c986589ced2cd9369fbce10d219eb0df',
        '5.14.0',
        10,
    )
]

common_files = [
    'extra_config',
    'linux.preset',
    '60-linux.hook',
    '90-linux.hook',
]
common_file_hashes = []
for file in common_files:
    with open(os.path.join('common', 'linux', file), 'rb') as file:
        common_file_hashes.append(hashlib.sha256(file.read()).hexdigest())
symlink_files = common_files.copy()+['linux.install']

newline = "\n"

for kernel in kernels:
    for file in symlink_files:
        result_file = os.path.join('linux', kernel.name, file)
        if not os.path.exists(result_file):
            os.symlink(
                os.path.join('..', '..', 'common', 'linux', file),
                os.path.join('linux', kernel.name, file),
            )
    with open(os.path.join('linux', kernel.name, 'PKGBUILD'), 'w') as file:
        file.write(f"""# THIS IS GENERATED AUTOMATICALLY. DO NOT MODIFY. EDIT common/linux/generate.py INSTEAD
_mode=cross
_kernelname={kernel.name}
pkgbase="linux-$_kernelname"
_desc="The $_kernelname kernel"
_srcname=linux
pkgver={kernel.pkgver}
pkgrel={kernel.pkgrel}
_arches=specific
arch=({kernel.arch})
license=(GPL2)
url={kernel.url}
makedepends=(
    xmlto
    docbook-xsl
    kmod
    inetutils
    bc
    dtc
    cpio
)
options=(!strip)
_commit={kernel.commit}
source=(
    "$_srcname::git+$url#commit=$_commit"{f'{newline}    {f"{newline}    ".join(kernel.patches.keys())}' if len(kernel.patches) > 0 else ''}
    {f"{newline}    ".join(common_files)}
)
sha256sums=(
    SKIP{f'{newline}    {f"{newline}    ".join(kernel.patches.values())}' if len(kernel.patches) > 0 else ''}
    {f"{newline}    ".join(common_file_hashes)}
)

pkgver() {{
    cd $_srcname
    make kernelversion | cut -d "-" -f 1
}}

prepare() {{
    cd $_srcname{f'{newline*2}    {f"{newline}    ".join(f"git apply ../{patch}" for patch in kernel.patches.keys())}' if len(kernel.patches) >0 else ''}

    make defconfig {' '.join(kernel.defconfigs)}
    cat ../extra_config >>.config
    echo "CONFIG_LOCALVERSION=\\"-kupfer-{kernel.name}\\"" >>.config
    make olddefconfig

    # don't run depmod on "make install". We'll do this ourselves in packaging
    sed -i "2iexit 0" scripts/depmod.sh
}}

build() {{
    cd $_srcname
    unset LDFLAGS
    # shellcheck disable=SC2086
    make ${{MAKEFLAGS}} Image.gz modules
    # shellcheck disable=SC2086
    make ${{MAKEFLAGS}} DTC_FLAGS="-@" dtbs
}}

_package() {{
    pkgdesc="The Linux Kernel and modules - $_desc"
    depends=(coreutils kmod mkinitcpio)
    optdepends=("crda: to set the correct wireless channels of your country")
    backup=(etc/mkinitcpio.d/linux.preset)
    install=linux.install

    cd $_srcname

    KARCH={kernel.karch()}

    # get kernel version
    _kernver="$(make kernelrelease)"
    _basekernel=${{_kernver%%-*}}
    _basekernel=${{_basekernel%.*}}

    mkdir -p "$pkgdir"/{{boot,usr/lib/modules}}
    make INSTALL_MOD_PATH="$pkgdir/usr" modules_install
    mkdir -p "$pkgdir/boot/dtbs/{kernel.dtb_vendor}"
    cp arch/$KARCH/boot/dts/{kernel.dtb_vendor}/{kernel.dtbs[0] if len(kernel.dtbs) == 1 else f'{{{",".join(kernel.dtbs)}}}'} "$pkgdir/boot/dtbs/{kernel.dtb_vendor}"
    cp arch/$KARCH/boot/Image.gz "$pkgdir/boot"

    # make room for external modules
    local _extramodules="extramodules-$_basekernel$_kernelname"
    ln -s "../$_extramodules" "$pkgdir/usr/lib/modules/$_kernver/extramodules"

    # add real version for building modules and running depmod from hook
    echo "$_kernver" |
        install -Dm644 /dev/stdin "$pkgdir/usr/lib/modules/$_extramodules/version"

    # remove build and source links
    rm "$pkgdir/usr/lib/modules/$_kernver/"{{source,build}}

    # now we call depmod...
    depmod -b "$pkgdir/usr" -F System.map "$_kernver"

    # sed expression for following substitutions
    local _subst="
    s|%PKGBASE%|$pkgbase|g
    s|%KERNVER%|$_kernver|g
    s|%EXTRAMODULES%|$_extramodules|g
  "

    # install mkinitcpio preset file
    sed "$_subst" ../linux.preset |
        install -Dm644 /dev/stdin "$pkgdir/etc/mkinitcpio.d/linux.preset"

    # install pacman hooks
    sed "$_subst" ../60-linux.hook |
        install -Dm644 /dev/stdin "$pkgdir/usr/share/libalpm/hooks/60-$pkgbase.hook"
    sed "$_subst" ../90-linux.hook |
        install -Dm644 /dev/stdin "$pkgdir/usr/share/libalpm/hooks/90-$pkgbase.hook"
}}

_package-headers() {{
    pkgdesc="Header files and scripts for building modules for linux kernel - $_desc"
    provides=("linux-headers=$pkgver")
    conflicts=(linux-headers linux-aarch64-headers)

    cd $_srcname
    local _builddir="$pkgdir/usr/lib/modules/$_kernver/build"

    install -Dt "$_builddir" -m644 Makefile .config Module.symvers
    install -Dt "$_builddir/kernel" -m644 kernel/Makefile

    mkdir "$_builddir/.tmp_versions"

    cp -t "$_builddir" -a include scripts

    install -Dt "$_builddir/arch/$KARCH" -m644 arch/$KARCH/Makefile
    install -Dt "$_builddir/arch/$KARCH/kernel" -m644 arch/$KARCH/kernel/asm-offsets.s #arch/$KARCH/kernel/module.lds

    cp -t "$_builddir/arch/$KARCH" -a arch/$KARCH/include
    mkdir -p "$_builddir/arch/arm"
    cp -t "$_builddir/arch/arm" -a arch/arm/include

    install -Dt "$_builddir/drivers/md" -m644 drivers/md/*.h

    # copy in Kconfig files
    find . -name Kconfig\* -exec install -Dm644 {{}} "$_builddir/{{}}" \;

    # remove unneeded architectures
    local _arch
    for _arch in "$_builddir"/arch/*/; do
        [[ $_arch == */$KARCH/ || $_arch == */arm/ ]] && continue
        rm -r "$_arch"
    done

    # remove files already in linux-docs package
    rm -r "$_builddir/Documentation"

    # remove now broken symlinks
    find -L "$_builddir" -type l -printf "Removing %P\\n" -delete

    # Fix permissions
    chmod -R u=rwX,go=rX "$_builddir"

    # strip scripts directory
    local _binary _strip
    while read -rd "" _binary; do
        case "$(file -bi "$_binary")" in
        *application/x-sharedlib*) _strip="$STRIP_SHARED" ;;    # Libraries (.so)
        *application/x-archive*) _strip="$STRIP_STATIC" ;;      # Libraries (.a)
        *application/x-executable*) _strip="$STRIP_BINARIES" ;; # Binaries
        *) continue ;;
        esac
        /usr/bin/strip "$_strip" "$_binary"
    done < <(find "$_builddir/scripts" -type f -perm -u+w -print0 2>/dev/null)
}}

pkgname=("$pkgbase" "$pkgbase-headers")
for _p in "${{pkgname[@]}}"; do
    eval "package_$_p() {{
    _package${{_p#${{pkgbase}}}}
  }}"
done
""")
