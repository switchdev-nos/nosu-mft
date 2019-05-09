#!/bin/bash

BUILDDIR="./build"
DEBSDIR="./debs"
ROOTDIR="$PWD"

fail() {
  [ -n "$1" ] && echo $1
  exit 1
}

if [ "$1" == "-h" ] || [ "$1" == "--help" ]; then
  echo "Usage: $0 [ENV_FILE]"
  exit 0
fi

if [ -n "$1" ]; then
  if [ -r "$1" ]; then
    set -a
    . "$1"
    set +a
  else
    fail "ENV_FILE not readable or missing"
  fi
fi

[ -n "$KERNEL_VERSION" ] || fail "KERNEL_VERSION is not set"
[ -n "$KERNEL_HEADERS" ] || fail "KERNEL_HEADERS is not set"
[ -n "$MFT_VERSION" ] || fail "MFT_VERSION is not set"
[ -n "$MFT_SNAPSHOT" ] || fail "MFT_SNAPSHOT is not set"

MFTDIR="$BUILDDIR/mft-$MFT_VERSION-x86_64-deb"
MFT_DKMS_PATH="/lib/modules/$KERNEL_VERSION/updates/dkms"
MFT_DEB_DIR="$BUILDDIR/kernel-mft-dkms"
MFT_KMOD_PATH="lib/modules/$KERNEL_VERSION/extra/mft"


if [ "$CLEAN" = true ] && [ -d "$BUILDDIR" ]; then
  echo "== Cleaning old build"
  rm -fr "$BUILDDIR"
fi

if [ -n "$MFT_SNAPSHOT" ] && [ ! -d "$BUILDDIR/$MFTDIR" ]; then
  mkdir -p "$BUILDDIR"
  echo "== Downloading MFT snapshot: $MFT_SNAPSHOT"
  curl "$MFT_SNAPSHOT" | tar -xz -C "$BUILDDIR"
  [[ $? == 0 ]] || fail "MFT snapshot downloading failed"
fi

echo "== Installing kernel headers: $KERNEL_HEADERS"
dpkg -i "$KERNEL_HEADERS"

echo "== Building MFT kernel modules for kernel $KERNEL_VERSION"
dpkg -i "$MFTDIR"/SDEBS/*.deb
dkms autoinstall -k "$KERNEL_VERSION" --force
[[ $? == 0 ]] || fail "MFT DKMS modules build failed"

mkdir -p "$MFT_DEB_DIR"/debian
mv "$MFT_DKMS_PATH"/*.ko "$MFT_DEB_DIR"

echo 10 > "$MFT_DEB_DIR"/debian/compat

cat <<EOF > "$MFT_DEB_DIR"/debian/control
Source: kernel-mft-dkms
Section: kernel
Priority: optional
Build-Depends: debhelper (>= 8.0.0)
Maintainer: $DEBFULLNAME <$DEBEMAIL>
Homepage: http://www.mellanox.com

Package: kernel-mft-dkms
Architecture: amd64
Depends: linux-image-$KERNEL_VERSION (>= $KERNEL_VERSION)
Description: DKMS support for kernel-mft kernel modules
 This package provides integration with the DKMS infrastructure for
  automatically building out of tree kernel modules.
EOF

TAB="$(printf '\t')"
cat <<EOF > "$MFT_DEB_DIR"/debian/rules
#!/usr/bin/make -f

%:
${TAB}dh \$@

EOF
chmod +x "$MFT_DEB_DIR"/debian/rules

cat <<EOF > "$MFT_DEB_DIR"/debian/changelog
kernel-mft-dkms ($MFT_VERSION-k$KERNEL_VERSION) unstable; urgency=medium

  * debian: update kernel abi to $KERNEL_VERSION

 -- $DEBFULLNAME <$DEBEMAIL>  $(date -R)
EOF


cat <<EOF > "$MFT_DEB_DIR"/debian/install
mst_pci.ko $MFT_KMOD_PATH
mst_pciconf.ko $MFT_KMOD_PATH
EOF

cd "$MFT_DEB_DIR"
dpkg-buildpackage -us -uc -B
[[ $? == 0 ]] ||  fail "MFT DEB package build failed"

echo "== NEW kernel-mft-dkms package for kernel $KERNEL_VERSION was successfully built!"

cd "$ROOTDIR"
mkdir -p "$DEBSDIR"
mv "$BUILDDIR"/*.deb "$DEBSDIR"/
mv "$MFTDIR"/DEBS/mft_*.deb "$DEBSDIR"/
echo "== MFT DEB packages moved to $DEBSDIR"
