# Geolinux

<p align="center">
  <img src="logo/logo.png" alt="Geolinux Logo" width="200"/>
</p>

A Fedora bootc distro for the people who use GIS and Remote Sensing to make the world a better place. Built on [ublue-os/image-template](https://github.com/ublue-os/image-template) and [Fedora bootc](https://github.com/bootc-dev/bootc).

The base image stays minimal: QGIS, GRASS and Zen Browser are Flatpak apps and SAGA runs in a container, so the OS layer is small and updates stay fast. Everything heavier (GDAL/PROJ, PostGIS, Jupyter, ML stacks) is opt-in and lives in user space.

Available in two editions:

| Edition | Desktop | Base Image | Image |
|---------|---------|-----------|-------|
| **Geolinux GNOME** | GNOME | Fedora bootc 45 | `ghcr.io/a2rk313/geolinux-gnome` |
| **Geolinux KDE** | KDE Plasma | Fedora bootc 45 | `ghcr.io/a2rk313/geolinux-kde` |

Both editions ship only the desktop's comps *mandatory+default* packages. The rest of the app set, including QGIS and Zen Browser, is installed from Flathub by `geolinux-flatpak-setup.service` on boot.

## Included Software

- **QGIS** — Flathub Flatpak (`org.qgis.qgis`), installed on first boot. It bundles GRASS 8.4, GDAL and PROJ.
- **GRASS GIS** — ships inside the QGIS Flatpak. The `grass` wrapper runs it and `GRASSBIN=/usr/bin/grass` points host Python tooling (`grass.script`) at it.
- **Zen Browser** — Flathub Flatpak (`app.zen_browser.zen`), installed on first boot.
- **SAGA GIS 9.9.3** — cpak package from `ghcr.io/a2rk313/geolinux-saga`, opt-in (it pulls a ~700 MB image on first run).
- **Desktop apps** — most of each desktop's app set (GNOME apps, or Dolphin, Ark, Filelight, …) comes from Flathub as well, not RPMs.

No geospatial libraries, databases or Python stacks are baked into the image. They are one recipe away:

| Command | Installs |
|---------|----------|
| `geolinux-gis install-geolibs` | GDAL, PROJ, GEOS, PDAL, LibGEOTIFF (brew) |
| `geolinux-gis install-postgis` | Rootless PostgreSQL + PostGIS, database `gis` ready for QGIS |
| `geolinux-gis install-jupyter` | JupyterLab with a GIS kernel |
| `geolinux-gis install-bundle-rs` | Remote sensing: geolibs + OTB + PROJ grids + JupyterLab |
| `geolinux-gis install-bundle-lidar` | LiDAR: geolibs + PROJ grids + WhiteboxTools + CloudCompare |
| `geolinux-gis install-bundle-carto` | Cartographer: JupyterLab with the GIS kernel |
| `geolinux-gis install-bundle-geoai` | GeoAI: GPU ML stack + JupyterLab |
| `geolinux-gis install-bundle-webgis` | Web GIS: PostGIS + GeoServer + MapProxy |
| `geolinux-gis install-bundle-field` | Field: GPS tools + Mergin CLI + QField |

`geolinux-gis --list` shows every recipe, `geolinux-gis status` shows what is already installed, and `geolinux-gis update-all` updates brew formulae, cpak apps, Flatpaks, venvs and field tools.

## Quick Start

### Switch to Geolinux from an Existing bootc System

```bash
# GNOME edition
sudo bootc switch ghcr.io/a2rk313/geolinux-gnome:latest

# KDE Plasma edition
sudo bootc switch ghcr.io/a2rk313/geolinux-kde:latest
```

Reboot after the command completes. Images are also tagged `latest-YYYYMMDD` and with the build SHA.

### Install from a Disk Image

CI produces the install media; dispatching the workflow yourself is the normal path:

```bash
# QCOW2 VM image (default)
gh workflow run build-disk.yml -f platform=amd64 -f variant=gnome -f disk-type=qcow2

# Anaconda installer ISO
gh workflow run build-disk.yml -f platform=amd64 -f variant=gnome -f disk-type=anaconda-iso
```

When the run finishes, download the image from the run's **Artifacts** section. Images are zstd-compressed:

```bash
zstd -d disk.qcow2.zst
```

Boot the qcow2 in your VM manager of choice, or run it locally with `just run-vm-qcow2` after building it yourself. The ISO boots the Anaconda installer and deploys the latest Geolinux image; it does not install from the ISO's own packages.

## Using the GIS Stack

- **QGIS** — launch `qgis` or pick it from the app menu. Plugins install from inside QGIS (*Plugins → Manage and Install Plugins*).
- **GRASS** — `grass` on the command line, or the GRASS provider inside QGIS.
- **SAGA** — install the cpak package (its image is publicly pullable):

  ```bash
  geolinux-gis install-saga
  ```

  This installs the cpak package, the GUI app entry and a `saga_cmd` wrapper in `~/.local/bin` that runs SAGA inside its container.

## Building Locally

You need [Podman](https://podman.io/) and [just](https://just.systems/). The desktop edition is chosen at build time with `IMAGE_VARIANT` (default `gnome`):

```bash
# GNOME edition
just build geolinux-gnome

# KDE Plasma edition
IMAGE_VARIANT=kde just build geolinux-kde
```

### Build Disk Images (QCOW2 / ISO / RAW)

Disk image builds use [bootc-image-builder](https://osbuild.org/docs/bootc/) through `sudo podman`, so they need root:

```bash
# QCOW2 virtual machine image
just build-qcow2 geolinux-gnome

# RAW image
just build-raw geolinux-gnome
```

Installer ISOs are built by CI, which picks the per-edition Anaconda config (`disk_config/iso-gnome.toml` or `iso-kde.toml`).

### Run in a VM

```bash
# Run the QCOW2 image in a VM (qemux, opens the browser)
just run-vm-qcow2 geolinux-gnome

# Run the newest QCOW2 output with systemd-vmspawn
just spawn-vm
```

## Branding

`build_files/branding.sh` sets the OS identity (`ID=geolinux`, pretty name, variant), writes the MOTD, and installs the plymouth watermark, Fedora pixmap logo and GDM logo. It runs after the desktop packages so their theme and applet files exist.

## Repository Structure

| Path | Description |
|------|-------------|
| `Containerfile` | Image build definition; takes `IMAGE_VARIANT=gnome\|kde` |
| `build_files/desktop_environment.sh` | Minimal desktop install, package skip-list, Flatpak service |
| `build_files/branding.sh` | os-release, MOTD, boot splash and logos |
| `build_files/60-gis.just` | Opt-in GIS recipes used by `geolinux-gis` |
| `build_files/gis-helpers.sh` | Shared brew/cpak helpers for the GIS recipes |
| `system_files/` | Files overlaid into the image (`qgis`/`grass` wrappers, profile.d, systemd units) |
| `disk_config/` | Bootc image builder configuration (`iso-gnome.toml`, `iso-kde.toml`) |
| `cpak.json` | SAGA package manifest, pinned to the built image digest |
| `saga/Containerfile` | Ubuntu-based image that packages SAGA 9.9.3 for cpak |
| `Justfile` | Build, VM, and utility commands |
| `.github/workflows/build.yml` | CI: builds and publishes both editions to GHCR |
| `.github/workflows/build-disk.yml` | CI: builds QCOW2/ISO disk images (manual, per platform and edition) |
| `.github/workflows/saga-image.yml` | CI: builds the SAGA cpak image and pins its digest in `cpak.json` |
| `cosign.pub` | Public key for container image signature verification |

## License

[Apache 2.0](LICENSE)
