# ─── GIS Workstation ───────────────────────────────────────────────────────────
# QGIS is preinstalled (Flatpak) and GRASS is bundled with it; SAGA and
# everything else here is opt-in and runs in user space (brew, cpak, venvs,
# ~/.local/bin) so the bootc image stays minimal.
# Based on the geonix recipe set, rewritten away from rpm-ostree layering.

# Show which optional recipes have been installed
[group('GIS Workstation')]
status:
    #!/usr/bin/bash
    source "{{ justfile_directory() }}/build_files/gis-helpers.sh"
    echo "=== geolinux — GIS workstation ==="
    echo "  Default: QGIS + GRASS (Flatpak)"
    echo ""
    echo "  Optional recipes:"
    if [ ! -d "${gis_state_dir}" ] || [ -z "$(ls -A "${gis_state_dir}" 2>/dev/null)" ]; then
        echo "  No optional recipes installed yet."
        echo "  Run 'just --list' to see available recipes."
    else
        for f in "${gis_state_dir}"/*.installed; do
            [ -f "$f" ] || continue
            printf '  [x] %-16s (installed: %s)\n' "$(basename "$f" .installed)" "$(cat "$f")"
        done
    fi

# ─── Desktop GIS & remote sensing ──────────────────────────────────────────────

# QGIS desktop GIS (preinstalled by default; repairs a failed boot install)
[group('GIS Workstation')]
install-qgis:
    #!/usr/bin/bash
    set -euo pipefail
    echo "=== Installing QGIS (Flathub) ==="
    flatpak install -y --system flathub org.qgis.qgis/x86_64/stable
    echo ""
    echo "QGIS installed."
    echo "  Launch from the app menu."
    echo "  GRASS 8.4 is bundled as a QGIS provider; no separate GRASS install."
    echo "  SAGA is opt-in: just install-saga (cpak container)."
    echo "  Plugins: QGIS > Plugins > Manage and Install Plugins (inside the app)."

# CloudCompare point-cloud viewer (opt-in, Flathub)
[group('GIS Workstation')]
install-cloudcompare:
    #!/usr/bin/bash
    set -euo pipefail
    echo "=== Installing CloudCompare (Flathub) ==="
    flatpak install -y --system flathub org.cloudcompare.CloudCompare
    echo "CloudCompare installed. Launch from the app menu."

# GDAL, PROJ, GEOS, PDAL and friends (CLI + shared libraries)
[group('GIS Workstation')]
install-geolibs:
    #!/usr/bin/bash
    set -euo pipefail
    source "{{ justfile_directory() }}/build_files/gis-helpers.sh"
    echo "=== Installing geospatial libraries and CLI tools (brew) ==="
    gis_brew
    brew install gdal proj geos pdal libgeotiff
    gis_mark geolibs
    echo ""
    echo "Installed: ogr2ogr, gdal_translate, projinfo, pdal, ..."
    echo "  They are in /home/linuxbrew/.linuxbrew/bin (added to ~/.bashrc)."

# WhiteboxTools binary to ~/.local/bin — no root, takes effect immediately
[group('GIS Workstation')]
install-whitebox:
    #!/usr/bin/bash
    set -euo pipefail
    source "{{ justfile_directory() }}/build_files/gis-helpers.sh"
    echo "=== Installing WhiteboxTools ==="
    echo "Use case: DEM analysis, hydrology, terrain derivatives"
    INSTALL_DIR="${HOME}/.local/bin"
    WBT_DIR="${HOME}/.local/share/geolinux/whitebox"
    mkdir -p "$INSTALL_DIR" "$WBT_DIR"
    command -v python3 >/dev/null || { echo "python3 is required to unzip the release" >&2; exit 1; }
    # Upstream ships no release assets, so the website zip is the only source and it
    # tracks versions — hence no pinned hash. shortcut: unpinned zip, validated by
    # running --version; pin a hash if upstream starts publishing versioned URLs.
    curl -fsSL -o /tmp/whitebox_tools.zip \
        "https://www.whiteboxgeo.com/WBT_Linux/WhiteboxTools_linux_musl.zip"
    python3 -m zipfile -e /tmp/whitebox_tools.zip "$WBT_DIR"
    rm -f /tmp/whitebox_tools.zip
    # The binary lives inside WBT/ with its settings and plugins; the symlink resolves there.
    chmod +x "${WBT_DIR}/WhiteboxTools_linux_amd64/WBT/whitebox_tools"
    ln -sfn "${WBT_DIR}/WhiteboxTools_linux_amd64/WBT/whitebox_tools" "${INSTALL_DIR}/whitebox_tools"
    WBT_VERSION=$("${INSTALL_DIR}/whitebox_tools" --version | grep -oP '\d+\.\d+\.\d+' | head -1)
    gis_mark whitebox
    echo ""
    echo "WhiteboxTools ${WBT_VERSION} installed to ${INSTALL_DIR}"
    echo "  Test: whitebox_tools --toolbox 'Terrain Analysis'"

# Update WhiteboxTools — reports newer upstream releases; re-run install-whitebox to update
[group('GIS Workstation')]
update-whitebox:
    #!/usr/bin/bash
    CURRENT=$(whitebox_tools --version 2>/dev/null | grep -oP '\d+\.\d+\.\d+' | head -1)
    LATEST=$(curl -fsSL https://api.github.com/repos/jblindsay/whitebox-tools/releases/latest \
        | grep '"tag_name":' | sed -E 's/.*"v?([^"]+)".*/\1/')
    echo "Installed: ${CURRENT:-unknown}   Latest: ${LATEST}"
    if [[ "$CURRENT" == "$LATEST" ]]; then
        echo "Already up to date."
    else
        echo "Newer release available — re-run 'just install-whitebox' to fetch it."
    fi

# SAGA GIS from the repo's cpak package, with a ~/.local/bin/saga_cmd wrapper
[group('GIS Workstation')]
install-saga:
    #!/usr/bin/bash
    set -euo pipefail
    source "{{ justfile_directory() }}/build_files/gis-helpers.sh"
    echo "=== Installing SAGA GIS (cpak package) ==="
    # the shipped justfile has no repo_organization, so the origin is literal
    saga_origin="github.com/a2rk313/geolinux"
    # the package repo is private: cpak reads the gh session for its manifest
    command -v gh >/dev/null || {
        echo "gh (GitHub CLI) is required: the SAGA package repo is private" >&2
        exit 1
    }
    gis_cpak
    cpak auth login "${saga_origin}" --github
    cpak install --yes "${saga_origin}"
    mkdir -p "${HOME}/.local/bin"
    printf '%s\n' \
        '#!/usr/bin/bash' \
        '# SAGA runs in its cpak container, not on the host root' \
        "exec cpak run ${saga_origin} saga_cmd -- \"\$@\"" \
        > "${HOME}/.local/bin/saga_cmd"
    chmod +x "${HOME}/.local/bin/saga_cmd"
    gis_mark saga
    echo ""
    echo "SAGA installed: saga_cmd (~/.local/bin, already on PATH) and the GUI app entry."
    echo "  First run pulls the SAGA image (~700 MB)."

# Orfeo Toolbox CLI apps via the official container (its COPR has no Fedora 44 repo)
[group('GIS Workstation')]
install-otb:
    #!/usr/bin/bash
    set -euo pipefail
    source "{{ justfile_directory() }}/build_files/gis-helpers.sh"
    command -v podman >/dev/null || { echo "podman is required" >&2; exit 1; }
    echo "=== Installing Orfeo Toolbox (container) ==="
    OTB_IMAGE="docker.io/orfeotoolbox/otb:9.1.1"
    mkdir -p "${HOME}/.local/bin"
    # otbcli <App> ... maps to otbcli_<App> inside the image; $PWD is mounted as /work
    printf '%s\n' \
        '#!/usr/bin/bash' \
        '# Usage: otbcli BandMath -il input.tif ...  (runs the official OTB container)' \
        'exec podman run --rm --entrypoint /bin/bash -v "${PWD}:/work:Z" -w /work \' \
        "    ${OTB_IMAGE} -lc 'exec \"otbcli_\$1\" \"\${@:2}\"' otb \"\$@\"" \
        > "${HOME}/.local/bin/otbcli"
    chmod +x "${HOME}/.local/bin/otbcli"
    gis_mark otb
    echo ""
    echo "OTB wrapper installed: ~/.local/bin/otbcli"
    echo "  First run pulls ${OTB_IMAGE} (~2 GB)."
    echo "  Example: otbcli BandMath -il image.tif -exp 'im1b1' -out out.tif"

# ─── Coordinates, databases & servers ─────────────────────────────────────────

# PROJ datum grids — the formula already ships the full set; enable on-demand gaps
[group('GIS Workstation')]
install-proj-grids:
    #!/usr/bin/bash
    set -euo pipefail
    source "{{ justfile_directory() }}/build_files/gis-helpers.sh"
    echo "=== Installing PROJ datum grids ==="
    gis_brew
    brew install proj
    # Do not override PROJ_DATA: the formula installs the proj-data set (~790 MB).
    # Network mode only fetches grids that are missing locally.
    if ! grep -q "PROJ_NETWORK" "${HOME}/.bashrc" 2>/dev/null; then
        echo "export PROJ_NETWORK=ON" >> "${HOME}/.bashrc"
    fi
    gis_mark proj-grids
    echo ""
    echo "PROJ datum grids are installed with proj: $(brew --prefix proj)/share/proj"
    echo "  PROJ_NETWORK=ON added to ~/.bashrc (restart shell to pick it up)"

# Rootless PostgreSQL + PostGIS via brew, database 'gis' ready for QGIS
[group('GIS Workstation')]
install-postgis:
    #!/usr/bin/bash
    set -euo pipefail
    source "{{ justfile_directory() }}/build_files/gis-helpers.sh"
    echo "=== Installing PostgreSQL + PostGIS (brew, user service) ==="
    gis_brew
    # postgis only declares postgresql@17 as a build/test dependency
    brew install postgresql@17 postgis
    brew services start postgresql@17

    PG_BIN="$(brew --prefix postgresql@17)/bin"
    for _ in $(seq 1 30); do
        "${PG_BIN}/pg_isready" -q && break
        sleep 1
    done
    if ! "${PG_BIN}/psql" -d postgres -tAc \
        "SELECT 1 FROM pg_database WHERE datname='gis'" | grep -q 1; then
        "${PG_BIN}/createdb" gis
    fi
    "${PG_BIN}/psql" -d gis -c "CREATE EXTENSION IF NOT EXISTS postgis;"
    "${PG_BIN}/psql" -d gis -c "CREATE EXTENSION IF NOT EXISTS postgis_topology;"

    gis_mark postgis
    echo ""
    echo "PostGIS running as a user service, database 'gis' created."
    echo "  QGIS: host=localhost db=gis user=$(whoami) (no password, local trust)"
    echo "  Shell: $(brew --prefix postgresql@17)/bin/psql -d gis"

# GeoServer as a user systemd Quadlet container — takes effect immediately
[group('GIS Workstation')]
install-geoserver:
    #!/usr/bin/bash
    set -euo pipefail
    source "{{ justfile_directory() }}/build_files/gis-helpers.sh"
    command -v podman >/dev/null || { echo "podman is required" >&2; exit 1; }
    # Release tags look like v3.0.2--2026.10.25--6678d00; the Docker tag is 3.0.2
    GEOSERVER_VERSION=$(curl -fsSL "https://api.github.com/repos/kartoza/docker-geoserver/releases/latest" \
        | grep '"tag_name":' | sed -E 's/.*"v?([0-9]+\.[0-9]+\.[0-9]+).*/\1/')
    echo "=== Installing GeoServer ${GEOSERVER_VERSION} (Quadlet) ==="
    mkdir -p "${HOME}/.config/containers/systemd"
    mkdir -p "${HOME}/geoserver-data"
    printf '%s\n' \
        "[Unit]" \
        "Description=GeoServer OGC Map Server" \
        "After=network-online.target" \
        "" \
        "[Container]" \
        "Image=docker.io/kartoza/geoserver:${GEOSERVER_VERSION}" \
        "PublishPort=8080:8080" \
        "Volume=%h/geoserver-data:/opt/geoserver/data_dir:Z" \
        "Environment=GEOSERVER_DATA_DIR=/opt/geoserver/data_dir" \
        "" \
        "[Service]" \
        "Restart=on-failure" \
        "" \
        "[Install]" \
        "WantedBy=default.target" \
        > "${HOME}/.config/containers/systemd/geoserver.container"
    systemctl --user daemon-reload
    systemctl --user enable --now geoserver
    gis_mark geoserver
    echo ""
    echo "GeoServer running as a user Quadlet."
    echo "  Status: systemctl --user status geoserver"
    echo "  Web UI: http://localhost:8080/geoserver  (admin/geoserver)"
    echo "  Data:   ~/geoserver-data"

# MapProxy tile cache in user space via brew
[group('GIS Workstation')]
install-mapproxy:
    #!/usr/bin/bash
    set -euo pipefail
    source "{{ justfile_directory() }}/build_files/gis-helpers.sh"
    echo "=== Installing MapProxy (brew) ==="
    gis_brew
    brew install mapproxy
    CONF_DIR="${HOME}/.config/mapproxy"
    mkdir -p "$CONF_DIR"
    [ -f "${CONF_DIR}/mapproxy.yaml" ] || \
        mapproxy-util create -t base-config "$CONF_DIR"
    gis_mark mapproxy
    echo ""
    echo "MapProxy installed."
    echo "  Config: ${CONF_DIR}/mapproxy.yaml"
    echo "  Start:  mapproxy-util serve-develop ${CONF_DIR}/mapproxy.yaml"

# ─── Python, notebooks & GeoAI ────────────────────────────────────────────────

# JupyterLab with a GIS kernel in an isolated venv
[group('GIS Workstation')]
install-jupyter:
    #!/usr/bin/bash
    set -euo pipefail
    source "{{ justfile_directory() }}/build_files/gis-helpers.sh"
    echo "=== Installing JupyterLab (GIS kernel) ==="
    gis_brew
    brew install python
    VENV_DIR="${HOME}/.local/share/geolinux/jupyter-env"
    python3 -m venv "$VENV_DIR"
    "$VENV_DIR/bin/pip" install --upgrade pip
    "$VENV_DIR/bin/pip" install \
        jupyterlab ipywidgets ipyleaflet \
        folium mapclassify contextily \
        geopandas rasterio xarray \
        numpy pandas matplotlib scipy
    "$VENV_DIR/bin/python" -m ipykernel install \
        --user --name gis-kernel --display-name "GIS Python"
    mkdir -p "${HOME}/.local/bin"
    printf '%s\n' \
        '#!/bin/bash' \
        "source \"${VENV_DIR}/bin/activate\"" \
        'jupyter lab "$@"' \
        > "${HOME}/.local/bin/gis-lab"
    chmod +x "${HOME}/.local/bin/gis-lab"
    gis_mark jupyter
    echo ""
    echo "JupyterLab installed."
    echo "  Launch: ~/.local/bin/gis-lab  |  Kernel: 'GIS Python'"

# GeoAI stack (PyTorch + torchgeo) in an isolated venv
[group('GIS Workstation')]
install-gpu-ml:
    #!/usr/bin/bash
    set -euo pipefail
    source "{{ justfile_directory() }}/build_files/gis-helpers.sh"
    echo "=== Installing GeoAI stack ==="
    gis_brew
    brew install python
    echo ""
    echo "Select compute backend:"
    echo "  1) NVIDIA GPU (auto-detect CUDA version)"
    echo "  2) Intel GPU (XPU / Arc / integrated Xe)"
    echo "  3) CPU only (no GPU, slower but works anywhere)"
    echo ""
    read -rp "Backend [1-3, default: 1]: " backend_sel
    backend_sel="${backend_sel:-1}"
    echo ""

    VENV_DIR="${HOME}/.local/share/geolinux/geoai-env"
    python3 -m venv "$VENV_DIR"
    "$VENV_DIR/bin/pip" install --upgrade pip

    case "$backend_sel" in
        1)
            if ! command -v nvidia-smi &>/dev/null; then
                echo "nvidia-smi not found. Is the NVIDIA driver installed on the host?"
                read -rp "Continue anyway with cu121 fallback? [y/N] " force
                [[ "$force" =~ ^[Yy]$ ]] || exit 0
                CUDA_TAG="cu121"
            else
                CUDA_FULL=$(nvidia-smi 2>/dev/null | grep "CUDA Version" | awk '{print $NF}')
                CUDA_MAJOR=$(echo "$CUDA_FULL" | cut -d. -f1)
                CUDA_MINOR=$(echo "$CUDA_FULL" | cut -d. -f2)
                CUDA_TAG="cu${CUDA_MAJOR}${CUDA_MINOR}"
                echo "Detected CUDA ${CUDA_FULL} -> using PyTorch wheel: ${CUDA_TAG}"
                case "$CUDA_TAG" in
                    cu118|cu121|cu124|cu126) ;;
                    *)
                        echo "${CUDA_TAG} not a known PyTorch wheel tag (cu118, cu121, cu124, cu126)."
                        read -rp "Override wheel tag (or Enter to use ${CUDA_TAG}): " override
                        [[ -n "$override" ]] && CUDA_TAG="$override"
                        ;;
                esac
            fi
            echo "Installing PyTorch with ${CUDA_TAG}..."
            "$VENV_DIR/bin/pip" install torch torchvision torchaudio \
                --index-url "https://download.pytorch.org/whl/${CUDA_TAG}"
            ;;
        2)
            echo "Installing PyTorch for Intel XPU..."
            "$VENV_DIR/bin/pip" install torch torchvision torchaudio \
                --index-url "https://download.pytorch.org/whl/xpu"
            ;;
        3)
            echo "Installing PyTorch CPU-only..."
            "$VENV_DIR/bin/pip" install torch torchvision torchaudio \
                --index-url "https://download.pytorch.org/whl/cpu"
            ;;
        *)
            echo "Invalid selection. Exiting."
            exit 1
            ;;
    esac

    echo ""
    echo "Select package set:"
    echo "  1) Minimal — torchgeo only"
    echo "  2) Full    — torchgeo + segmentation-models + lightning + wandb"
    echo ""
    read -rp "Package set [1-2, default: 2]: " pkg_sel
    pkg_sel="${pkg_sel:-2}"

    "$VENV_DIR/bin/pip" install torchgeo
    if [[ "$pkg_sel" == "2" ]]; then
        "$VENV_DIR/bin/pip" install segmentation-models-pytorch lightning wandb
    fi

    if ! grep -q "geoai-env" "${HOME}/.bashrc"; then
        echo "alias geoai='source ${VENV_DIR}/bin/activate'" >> "${HOME}/.bashrc"
    fi

    "$VENV_DIR/bin/python" -c "
    import torch
    print(f'PyTorch: {torch.__version__}')
    print(f'CUDA available: {torch.cuda.is_available()}')
    if hasattr(torch, 'xpu'):
        print(f'XPU available: {torch.xpu.is_available()}')
    "
    gis_mark gpu-ml
    echo ""
    echo "GeoAI stack installed."
    echo "  Activate: geoai  (alias in ~/.bashrc)"

# ─── Field tools ──────────────────────────────────────────────────────────────

# Mergin Maps CLI, GPX tools and the QField desktop AppImage
[group('GIS Workstation')]
install-fieldwork:
    #!/usr/bin/bash
    set -euo pipefail
    source "{{ justfile_directory() }}/build_files/gis-helpers.sh"
    echo "=== Installing extended fieldwork tools ==="
    gis_brew
    brew install gpsbabel python
    VENV_DIR="${HOME}/.local/share/geolinux/fieldwork-env"
    python3 -m venv "$VENV_DIR"
    "$VENV_DIR/bin/pip" install --upgrade pip
    "$VENV_DIR/bin/pip" install mergin-client gpxpy gpx-converter

    read -rp "Install QField desktop companion (AppImage)? [Y/n] " qfield
    if [[ ! "$qfield" =~ ^[Nn]$ ]]; then
        INSTALL_DIR="${HOME}/.local/bin"
        APPS_DIR="${HOME}/.local/share/applications"
        mkdir -p "$INSTALL_DIR" "$APPS_DIR"
        LATEST=$(curl -fsSL https://api.github.com/repos/opengisch/QField/releases/latest \
            | grep '"tag_name":' | sed -E 's/.*"v?([^"]+)".*/\1/')
        echo "Downloading QField ${LATEST}..."
        curl -fsSL -o "${INSTALL_DIR}/QField.AppImage" \
            "https://github.com/opengisch/QField/releases/download/v${LATEST}/qfield-v${LATEST}-linux-x64.AppImage"
        # sanity check: an AppImage is an ELF
        if [ "$(head -c 4 "${INSTALL_DIR}/QField.AppImage" | od -An -tx1 | tr -d ' \n')" != "7f454c46" ]; then
            echo "downloaded file is not an ELF binary — aborting" >&2
            rm -f "${INSTALL_DIR}/QField.AppImage"
            exit 1
        fi
        chmod +x "${INSTALL_DIR}/QField.AppImage"
        printf '%s\n' \
            "[Desktop Entry]" \
            "Name=QField" \
            "Comment=Mobile GIS field data collection" \
            "Exec=${INSTALL_DIR}/QField.AppImage" \
            "Icon=qfield" \
            "Type=Application" \
            "Categories=Science;Geography;" \
            > "${APPS_DIR}/qfield.desktop"
        echo "QField ${LATEST} installed."
    fi

    gis_mark fieldwork
    echo ""
    echo "Fieldwork tools installed."
    echo "  Mergin CLI: ${VENV_DIR}/bin/mergin --help"
    echo "  Field sync: https://merginmaps.com"

# Update QField AppImage to the latest release
[group('GIS Workstation')]
update-qfield:
    #!/usr/bin/bash
    INSTALL_DIR="${HOME}/.local/bin"
    LATEST=$(curl -fsSL https://api.github.com/repos/opengisch/QField/releases/latest \
        | grep '"tag_name":' | sed -E 's/.*"v?([^"]+)".*/\1/')
    echo "Downloading QField ${LATEST}..."
    curl -fsSL -o "${INSTALL_DIR}/QField.AppImage" \
        "https://github.com/opengisch/QField/releases/download/v${LATEST}/qfield-v${LATEST}-linux-x64.AppImage"
    chmod +x "${INSTALL_DIR}/QField.AppImage"
    echo "QField updated to ${LATEST}"

# ─── Legacy environment ───────────────────────────────────────────────────────

# Persistent Ubuntu environment for legacy workflows with pinned deps
[group('GIS Workstation')]
install-legacy-env:
    #!/usr/bin/bash
    set -euo pipefail
    source "{{ justfile_directory() }}/build_files/gis-helpers.sh"
    echo "=== Creating legacy GIS environment (cpak Ubuntu) ==="
    gis_cpak
    cpak install --yes github.com/containerpak/ubuntu
    if ! cpak environment inspect --environment gis-legacy >/dev/null 2>&1; then
        cpak environment create --name gis-legacy --origin github.com/containerpak/ubuntu
    fi
    cpak environment shell --environment gis-legacy --command /bin/bash -- -lc '
        set -euo pipefail
        export DEBIAN_FRONTEND=noninteractive
        apt-get update -qq
        apt-get install -y \
            python3-gdal python3-pip \
            libgdal-dev libproj-dev \
            libgeos-dev \
            python3-venv \
            unzip curl
        python3 -m venv /opt/gis-env
        /opt/gis-env/bin/pip install --upgrade pip
        /opt/gis-env/bin/pip install \
            geopandas fiona rasterio pyproj \
            pyshp shapely pandas numpy \
            matplotlib pyogrio whitebox
    '
    gis_mark legacy-env
    echo ""
    echo "Legacy environment ready."
    echo "  Enter:    cpak environment shell --environment gis-legacy --command /bin/bash"
    echo "  Activate: source /opt/gis-env/bin/activate"

# ─── Workflow bundles ─────────────────────────────────────────────────────────

# Cartographer: JupyterLab with the GIS kernel
[group('GIS Workstation')]
install-bundle-carto:
    just --justfile "{{ justfile_directory() }}/Justfile" install-jupyter
    @echo "Cartographer bundle complete."

# Remote sensing: geospatial libs + OTB + PROJ grids + JupyterLab
[group('GIS Workstation')]
install-bundle-rs:
    just --justfile "{{ justfile_directory() }}/Justfile" install-geolibs
    just --justfile "{{ justfile_directory() }}/Justfile" install-otb
    just --justfile "{{ justfile_directory() }}/Justfile" install-proj-grids
    just --justfile "{{ justfile_directory() }}/Justfile" install-jupyter
    @echo "Remote Sensing bundle complete."

# LiDAR: geospatial libs + PROJ grids + WhiteboxTools + CloudCompare
[group('GIS Workstation')]
install-bundle-lidar:
    just --justfile "{{ justfile_directory() }}/Justfile" install-geolibs
    just --justfile "{{ justfile_directory() }}/Justfile" install-proj-grids
    just --justfile "{{ justfile_directory() }}/Justfile" install-whitebox
    just --justfile "{{ justfile_directory() }}/Justfile" install-cloudcompare
    @echo "LiDAR bundle complete."

# GeoAI: GPU ML stack + JupyterLab
[group('GIS Workstation')]
install-bundle-geoai:
    just --justfile "{{ justfile_directory() }}/Justfile" install-gpu-ml
    just --justfile "{{ justfile_directory() }}/Justfile" install-jupyter
    @echo "GeoAI bundle complete."

# Web GIS: PostGIS + GeoServer + MapProxy
[group('GIS Workstation')]
install-bundle-webgis:
    just --justfile "{{ justfile_directory() }}/Justfile" install-postgis
    just --justfile "{{ justfile_directory() }}/Justfile" install-geoserver
    just --justfile "{{ justfile_directory() }}/Justfile" install-mapproxy
    @echo "Web GIS bundle complete."

# Field: GPS tools + Mergin CLI + QField
[group('GIS Workstation')]
install-bundle-field:
    just --justfile "{{ justfile_directory() }}/Justfile" install-fieldwork
    @echo "Field bundle complete."

# ─── Maintenance ──────────────────────────────────────────────────────────────

# Update brew formulae, cpak apps, flatpaks, venvs and field tools
[group('GIS Workstation')]
update-all:
    #!/usr/bin/bash
    source "{{ justfile_directory() }}/build_files/gis-helpers.sh"
    echo "=== Updating geolinux GIS recipes ==="
    if [ -x /home/linuxbrew/.linuxbrew/bin/brew ]; then
        eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
        brew update
        brew upgrade
    fi
    if command -v cpak >/dev/null 2>&1; then
        cpak update --non-interactive || true
    fi
    flatpak update -y 2>/dev/null || true
    [ -f "${gis_state_dir}/whitebox.installed" ] && \
        just --justfile "{{ justfile_directory() }}/Justfile" update-whitebox || true
    [ -f "${gis_state_dir}/fieldwork.installed" ] && \
        just --justfile "{{ justfile_directory() }}/Justfile" update-qfield || true
    for venv in jupyter-env fieldwork-env geoai-env; do
        VENV="${HOME}/.local/share/geolinux/${venv}"
        if [ -d "$VENV" ]; then
            "$VENV/bin/pip" install --upgrade pip -q
            "$VENV/bin/pip" list --outdated 2>/dev/null \
                | awk 'NR>2{print $1}' \
                | xargs -r "$VENV/bin/pip" install --upgrade -q || true
        fi
    done
    echo ""
    echo "Recipe update complete."
