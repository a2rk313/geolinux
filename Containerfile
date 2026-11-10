# Allow build scripts to be referenced without being copied into the final image
FROM scratch AS ctx
COPY build_files /
COPY system_files /system_files

# LAYER ORDER RULE: least-frequently-changing layers first, most-frequent last, so
# routine edits only rebuild the tail of this file. Base image and one-time fixups
# (FROM, /opt) at the top; package/desktop customizations (the ctx script) at the
# bottom. The ctx stage above is exempt: it is build-time context only and must
# always carry the latest script contents, and it never lands in the final image.

# Base Image
FROM quay.io/fedora/fedora-bootc:45
## Other possible base images include:
# FROM ghcr.io/ublue-os/bazzite:testing
# FROM ghcr.io/ublue-os/aurora:stable
# FROM ghcr.io/ublue-os/bluefin-nvidia-open:stable
# 
# ... and so on, here are more base images
# Universal Blue Images: https://github.com/orgs/ublue-os/packages
# Fedora base image: quay.io/fedora/fedora-bootc:44
# CentOS base images: quay.io/centos-bootc/centos-bootc:stream10

### [IM]MUTABLE /opt
## Some bootable images have /opt symlinked to /var/opt to make it mutable/writable for users.
## fedora-bootc ships /opt as a plain directory already, so only unlink it on bases that symlink it.

RUN if [ -L /opt ]; then rm /opt && mkdir /opt; fi

### MODIFICATIONS
## make modifications desired in your image and install packages by modifying the build.sh script
## the following RUN directive does all the things required to run "build.sh" as recommended.

# Desktop variant: "gnome" (default) or "kde". Pass with --build-arg IMAGE_VARIANT=kde
ARG IMAGE_VARIANT=gnome

RUN --mount=type=bind,from=ctx,source=/,target=/ctx \
  --mount=type=cache,dst=/var/cache \
  --mount=type=cache,dst=/var/log \
  --mount=type=tmpfs,dst=/tmp \
  /ctx/desktop_environment.sh

### LINTING
## Verify final image and contents are correct.
RUN bootc container lint
