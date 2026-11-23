#!/usr/bin/bash
# Image branding: os-release identity, MOTD, boot splash, menu icons and the
# GDM logo.
set -ouex pipefail

IMAGE_PRETTY_NAME="Geolinux"
IMAGE_EDITION="${IMAGE_VARIANT:-gnome}"
case "${IMAGE_EDITION}" in
  kde) IMAGE_VARIANT_NAME="KDE Plasma" ;;
  *) IMAGE_VARIANT_NAME="GNOME" ;;
esac

# --- OS-RELEASE ---
OS_RELEASE="/usr/lib/os-release"

inject_os_release() {
  local key=$1
  local value=$2
  if grep -q "^${key}=" "$OS_RELEASE"; then
    sed -i "s|^${key}=.*|${key}=${value}|" "$OS_RELEASE"
  else
    echo "${key}=${value}" >> "$OS_RELEASE"
  fi
}

inject_os_release "NAME" "\"${IMAGE_PRETTY_NAME}\""
inject_os_release "PRETTY_NAME" "\"${IMAGE_PRETTY_NAME}\""
inject_os_release "ID" "geolinux"
inject_os_release "ID_LIKE" "\"fedora image-based immutable gis rs workstation\""
inject_os_release "VARIANT" "\"${IMAGE_VARIANT_NAME}\""
inject_os_release "VARIANT_ID" "geolinux"
inject_os_release "HOME_URL" "\"https://github.com/a2rk313/geolinux\""
inject_os_release "SUPPORT_URL" "\"https://github.com/a2rk313/geolinux/issues\""
inject_os_release "DEFAULT_HOSTNAME" "\"geolinux\""

sed -i "/^REDHAT_BUGZILLA_PRODUCT=/d; /^REDHAT_BUGZILLA_PRODUCT_VERSION=/d; /^REDHAT_SUPPORT_PRODUCT=/d; /^REDHAT_SUPPORT_PRODUCT_VERSION=/d" "$OS_RELEASE"

# --- MOTD ---
cat >/etc/motd <<'EOF'
🌍 Welcome to Geolinux
**GIS and Remote Sensing out of the box.**

| Command | Description |
|---------|-------------|
| `geolinux-gis --list` | Show all available commands |
| `geolinux-gis status` | Show installed GIS recipes |
| `geolinux-gis install-saga` | Install SAGA GIS (container) |
| `geolinux-gis install-bundle-rs` | Install Remote Sensing stack |
| `geolinux-gis install-bundle-lidar` | Install LiDAR stack |
| `qgis` | Launch QGIS Desktop |

- [Geolinux Repository](https://github.com/a2rk313/geolinux)
- [Report an Issue](https://github.com/a2rk313/geolinux/issues)
EOF

# --- PLYMOUTH ---
# The base image's initramfs predates the desktop packages, so the branded theme
# only shows at boot after the initramfs is rebuilt here.
PLYMOUTH_ASSETS="/usr/share/plymouth/themes/spinner"
PLYMOUTH_TEMPLATE=""
if [[ -f /usr/share/plymouth/themes/bgrt/bgrt.plymouth ]]; then
  PLYMOUTH_TEMPLATE="/usr/share/plymouth/themes/bgrt/bgrt.plymouth"
elif [[ -f "$PLYMOUTH_ASSETS/spinner.plymouth" ]]; then
  PLYMOUTH_TEMPLATE="$PLYMOUTH_ASSETS/spinner.plymouth"
fi
PLYMOUTH_THEME="/usr/share/plymouth/themes/geolinux"
if [[ -d "$PLYMOUTH_ASSETS" && -n "$PLYMOUTH_TEMPLATE" ]]; then
  rm -rf "$PLYMOUTH_THEME"
  cp -a "$PLYMOUTH_ASSETS" "$PLYMOUTH_THEME"
  cp "$PLYMOUTH_TEMPLATE" "$PLYMOUTH_THEME/geolinux.plymouth"
  sed -i \
    -e 's|^Name=.*|Name=Geolinux|' \
    -e 's|^Description=.*|Description=Geolinux boot splash|' \
    -e "s|^ImageDir=.*|ImageDir=$PLYMOUTH_THEME|" \
    -e 's|^WatermarkVerticalAlignment=.*|WatermarkVerticalAlignment=.42|' \
    -e 's|^DialogVerticalAlignment=.*|DialogVerticalAlignment=.85|' \
    -e 's|^TitleVerticalAlignment=.*|TitleVerticalAlignment=.85|' \
    -e 's|^UseFirmwareBackground=.*|UseFirmwareBackground=false|' \
    "$PLYMOUTH_THEME/geolinux.plymouth"
  cp /ctx/logo/logo_small_256.png "${PLYMOUTH_THEME}/watermark.png"
  printf '[Daemon]\nTheme=geolinux\n' > /etc/plymouth/plymouthd.conf

  KERNEL_VERSION="$(rpm -q kernel --qf '%{VERSION}-%{RELEASE}.%{ARCH}\n' 2>/dev/null | sort -V | tail -1 || true)"
  if [[ -n "$KERNEL_VERSION" && -f "/usr/lib/modules/${KERNEL_VERSION}/initramfs.img" ]]; then
    DRACUT_ARGS=(--no-hostonly --kver "$KERNEL_VERSION" --reproducible
      -f "/usr/lib/modules/${KERNEL_VERSION}/initramfs.img")
    if [[ -d /usr/lib/dracut/modules.d/50ostree ]]; then
      DRACUT_ARGS+=(--add ostree)
    fi
    export DRACUT_NO_XATTR=1
    dracut "${DRACUT_ARGS[@]}"
    chmod 0600 "/usr/lib/modules/${KERNEL_VERSION}/initramfs.img"
    echo "Plymouth theme applied, initramfs rebuilt for $KERNEL_VERSION"
  else
    echo "WARNING: no initramfs for '$KERNEL_VERSION', splash will not show" >&2
  fi
else
  echo "WARNING: Plymouth theme assets not found, skipping"
fi

# --- GNOME Logo menu extension override (only when the extension is present) ---
if compgen -G "/usr/share/gnome-shell/extensions/*logo*menu*" >/dev/null 2>&1; then
  cat >/usr/share/glib-2.0/schemas/99-geolinux-branding.gschema.override <<'EOF'
[org.gnome.shell.extensions.logo-menu]
use-custom-icon=true
menu-button-icon-image=2
custom-icon-path='/usr/share/icons/hicolor/256x256/apps/geolinux-logo.png'
menu-button-terminal='ptyxis'
menu-button-software-center='gnome-software'
EOF
  if ! glib-compile-schemas /usr/share/glib-2.0/schemas/; then
    echo "ERROR: glib schema compilation failed" >&2
    exit 1
  fi
  echo "GNOME branding applied"
else
  echo "Logomenu extension not present — skipping GNOME logo-menu override"
fi

# --- GDM / FEDORA LOGO REPLACEMENTS ---
PIXMAPS="/usr/share/pixmaps"
LOGO_128="/ctx/logo/logo_small_128.png"
LOGO_256="/ctx/logo/logo_small_256.png"

# Path must match the gschema override above and the KDE kickoff icon lookup
mkdir -p /usr/share/icons/hicolor/256x256/apps
cp "$LOGO_256" /usr/share/icons/hicolor/256x256/apps/geolinux-logo.png

mkdir -p "$PIXMAPS"
cp "$LOGO_128" "${PIXMAPS}/fedora-gdm-logo.png"
cp "$LOGO_128" "${PIXMAPS}/fedora-logo.png"
cp "$LOGO_128" "${PIXMAPS}/fedora-logo-icon.png"
cp "$LOGO_128" "${PIXMAPS}/fedora-logo-small.png"
cp "$LOGO_256" "${PIXMAPS}/fedora-logo-sprite.png"
cp "$LOGO_128" "${PIXMAPS}/fedora_logo_med.png"
cp "$LOGO_128" "${PIXMAPS}/fedora_whitelogo_med.png"
