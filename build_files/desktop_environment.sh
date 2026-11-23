#!/bin/bash

set -ouex pipefail

### Install packages

# Packages can be installed from any enabled yum repo on the image.
# RPMfusion repos are available by default in ublue main images
# List of rpmfusion packages can be found here:
# https://mirrors.rpmfusion.org/mirrorlist?path=free/fedora/updates/43/x86_64/repoview/index.html&protocol=https&redirect=1

# this installs a package from fedora repos
# just runs the opt-in GIS recipes on the installed system (60-gis.just);
# git and slirp4netns are runtime prerequisites for brew and cpak
dnf5 install -y just git slirp4netns tmux fastfetch

# apply the system_files overlay into the image (empty dir = no-op)
cp -a /ctx/system_files/. /

# ship the opt-in GIS recipes so `geolinux-gis` works on the installed system
install -d /usr/share/geolinux/build_files
install -m644 /ctx/60-gis.just /ctx/gis-helpers.sh /usr/share/geolinux/build_files/

# Use a COPR Example:
#
# dnf5 -y copr enable ublue-os/staging
# dnf5 -y install package
# Disable COPRs so they don't end up enabled on the final image:
# dnf5 -y copr disable ublue-os/staging

#### Example for enabling a System Unit File

systemctl enable podman.socket

### Desktop environment, selected by the IMAGE_VARIANT build-arg

# the comps groups install mandatory+default packages: the minimal desktop without
# the full environment extras (base-x X11 drivers, libreoffice, kde-apps, kde-media)
case "${IMAGE_VARIANT:-gnome}" in
  gnome)
    dnf5 group install -y gnome-desktop
    # GNOME core apps ship as Flathub flatpaks (installed on boot by
    # geolinux-flatpak-setup.service), not RPMs — drop the comps RPM versions.
    # gnome-boxes (drags in the whole qemu/libvirt/spice stack), rygel (DLNA
    # server) and gnome-user-share are non-minimal extras and aren't shipped.
    # (flatpak support is built into gnome-software itself on F45, no plugin pkg)
    dnf5 remove -y \
      baobab decibels gnome-boxes gnome-calculator gnome-calendar \
      gnome-characters gnome-clocks gnome-connections gnome-contacts \
      gnome-font-viewer gnome-logs gnome-maps gnome-text-editor gnome-weather \
      gnome-user-share loupe \
      papers papers-libs papers-previewer papers-thumbnailer papers-nautilus \
      rygel showtime snapshot simple-scan
    systemctl enable gdm.service geolinux-flatpak-setup.service
    ;;
  kde)
    # akonadi-server + akonadi-server-mysql = PIM storage daemon + a full
    # MariaDB server; only kdepim apps need it, no place in a base image.
    # Exclude at install time: nothing kept needs them, and it avoids pulling
    # MariaDB/pyside6/Qt3D only to delete them again.
    dnf5 --exclude=akonadi-server --exclude=akonadi-server-mysql \
      group install -y kde-desktop
    # KDE apps ship as Flathub flatpaks (installed on boot by
    # geolinux-flatpak-setup.service), not RPMs — drop the comps RPM versions.
    # (spectacle, kdebugsettings, kde-partitionmanager, kdialog have no Flathub
    # builds and stay; konsole/discover/plasma-systemmonitor are integration, stay)
    dnf5 remove -y \
      ark dolphin filelight kcharselect kfind kwrite kwalletmanager5
    systemctl enable plasmalogin.service geolinux-flatpak-setup.service
    ;;
  *)
    echo "unknown IMAGE_VARIANT: ${IMAGE_VARIANT} (expected gnome or kde)" >&2
    exit 1
    ;;
esac

systemctl set-default graphical.target

# drop packages orphaned by the skip-list removals and clear dnf's cache;
# must stay in this same RUN — a later layer can only tombstone, not shrink
dnf5 autoremove -y
dnf5 clean all

# Fedora 45 moved its repo files to /usr/share/dnf5/repos.d and leaves
# /etc/yum.repos.d empty. bootc-image-builder depsolves the installer ISO from
# /etc/yum.repos.d only, so expose the repo files there too.
for repo in /usr/share/dnf5/repos.d/*.repo; do
  [ -e "$repo" ] || continue
  name=$(basename "$repo")
  [ -e "/etc/yum.repos.d/$name" ] || ln -s "../../usr/share/dnf5/repos.d/$name" "/etc/yum.repos.d/$name"
done
