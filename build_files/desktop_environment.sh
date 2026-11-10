#!/bin/bash

set -ouex pipefail

### Install packages

# Packages can be installed from any enabled yum repo on the image.
# RPMfusion repos are available by default in ublue main images
# List of rpmfusion packages can be found here:
# https://mirrors.rpmfusion.org/mirrorlist?path=free/fedora/updates/43/x86_64/repoview/index.html&protocol=https&redirect=1

# this installs a package from fedora repos
dnf5 install -y tmux

# apply the system_files overlay into the image (empty dir = no-op)
cp -a /ctx/system_files/. /

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
    # (flatpak support is built into gnome-software itself on F45, no plugin pkg)
    dnf5 remove -y \
      baobab decibels gnome-calculator gnome-calendar gnome-characters \
      gnome-clocks gnome-connections gnome-contacts gnome-font-viewer \
      gnome-logs gnome-maps gnome-text-editor gnome-weather loupe \
      papers papers-libs papers-previewer papers-thumbnailer papers-nautilus \
      showtime snapshot simple-scan
    systemctl enable gdm.service geolinux-flatpak-setup.service
    ;;
  kde)
    dnf5 group install -y kde-desktop
    # KDE apps ship as Flathub flatpaks (installed on boot by
    # geolinux-flatpak-setup.service), not RPMs — drop the comps RPM versions.
    # (spectacle, kdebugsettings, kde-partitionmanager, kdialog have no Flathub
    # builds and stay; konsole/discover/plasma-systemmonitor are integration, stay)
    dnf5 remove -y ark dolphin filelight kcharselect kfind kwrite kwalletmanager5
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
