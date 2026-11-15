#!/usr/bin/bash
# Image branding, borrowed from the geonix project: os-release identity, MOTD,
# boot splash, menu icons and the GDM logo.
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
PLYMOUTH_THEME="/usr/share/plymouth/themes/spinner"
if [[ -d "$PLYMOUTH_THEME" ]]; then
  cp /ctx/logo/logo_small_128.png "${PLYMOUTH_THEME}/watermark.png"
  cp /ctx/logo/logo_small_128.png "${PLYMOUTH_THEME}/bgrt-fallback.png"
  cp /ctx/logo/logo_small_128.png "${PLYMOUTH_THEME}/silverblue-watermark.png"
  cp /ctx/logo/logo_small_128.png "${PLYMOUTH_THEME}/silverblue-logo.png"
  echo "Plymouth branding applied"
else
  echo "WARNING: Plymouth spinner theme not found, skipping"
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

# --- KDE Kickoff icon override (when Plasma's kickoff config is present) ---
# Plasma installs the applet under /usr/share/plasma on some releases and
# /usr/share/plasma6 on others; brand whichever exists.
for KICKOFF_XML in \
  /usr/share/plasma/plasmoids/org.kde.plasma.kickoff/contents/config/main.xml \
  /usr/share/plasma6/plasmoids/org.kde.plasma.kickoff/contents/config/main.xml; do
  [[ -f "$KICKOFF_XML" ]] || continue
  sed -i 's|<default>start-here-kde</default>|<default>geolinux-logo</default>|g' "$KICKOFF_XML"
  echo "KDE Kickoff icon overridden (${KICKOFF_XML})"
done

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
