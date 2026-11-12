#!/usr/bin/bash
# Shared helpers for the opt-in GIS recipes in 60-gis.just.
# Nothing here touches the bootc image: brew, cpak and venvs all live in $HOME.

gis_state_dir="${HOME}/.config/geolinux"

gis_mark() {
  mkdir -p "${gis_state_dir}"
  date -I > "${gis_state_dir}/$1.installed"
}

# Put Homebrew on PATH, installing it to /home/linuxbrew on first use.
gis_brew() {
  if [ -x /home/linuxbrew/.linuxbrew/bin/brew ]; then
    eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
  elif command -v brew >/dev/null 2>&1; then
    eval "$(brew shellenv)"
  else
    echo "=== Homebrew not installed; installing to /home/linuxbrew (sudo needed once) ==="
    sudo -v
    NONINTERACTIVE=1 /bin/bash -c \
      "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
  fi
  if ! grep -qF 'linuxbrew/.linuxbrew/bin/brew shellenv' "${HOME}/.bashrc" 2>/dev/null; then
    # shellcheck disable=SC2016  # literal $(...) intended: evaluated in future shells
    printf '\n# Homebrew (added by geolinux GIS recipes)\neval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"\n' >> "${HOME}/.bashrc"
  fi
}

# Put cpak on PATH, downloading both binaries on first use.
gis_cpak() {
  export PATH="${HOME}/.local/bin:${PATH}"
  if command -v cpak >/dev/null 2>&1; then
    return 0
  fi
  case "$(uname -m)" in
    x86_64) arch=amd64 ;;
    aarch64) arch=arm64 ;;
    *)
      echo "unsupported architecture: $(uname -m)" >&2
      return 1
      ;;
  esac
  local tmp base
  tmp="$(mktemp -d)"
  base="https://github.com/Containerpak/cpak/releases/latest/download"
  curl -fsSL -o "${tmp}/cpak" "${base}/cpak-linux-${arch}"
  curl -fsSL -o "${tmp}/cpak-storaged" "${base}/cpak-storaged-linux-${arch}"
  curl -fsSL -o "${tmp}/SHA256SUMS" "${base}/SHA256SUMS"
  (
    cd "${tmp}" || exit 1
    grep -E "  (cpak|cpak-storaged)-linux-${arch}$" SHA256SUMS > SHA256SUMS.part
    sha256sum -c SHA256SUMS.part
  )
  install -Dm755 "${tmp}/cpak" "${HOME}/.local/bin/cpak"
  install -Dm755 "${tmp}/cpak-storaged" "${HOME}/.local/bin/cpak-storaged"
  rm -rf "${tmp}"
}

# Ensure the shared rootless Fedora environment used for SAGA/OTB exists.
gis_cpak_fedora_env() {
  gis_cpak
  cpak install --yes github.com/containerpak/fedora
  if ! cpak environment inspect --environment gis >/dev/null 2>&1; then
    cpak environment create --name gis --origin github.com/containerpak/fedora
  fi
}
