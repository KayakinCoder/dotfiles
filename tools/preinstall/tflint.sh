#!/usr/bin/env bash
#
# Installs a pinned, verified release of tflint.
#
# Verifies the downloaded archive against tflint's published checksums.txt
# before installing.
#
set -uo pipefail

TFLINT_VERSION="v0.64.0"

main() {
  set -e

  local version="${TFLINT_VERSION}"

  local workdir
  workdir="$(mktemp -d -t tflint-install.XXXXXXXXXX)"
  trap 'rm -rf "${workdir}"' RETURN

  local zip_name="tflint_linux_amd64.zip"
  local base_url="https://github.com/terraform-linters/tflint/releases/download/${version}"

  echo "==> Downloading tflint ${version}"
  curl -fsSL -o "${workdir}/${zip_name}" "${base_url}/${zip_name}"
  curl -fsSL -o "${workdir}/checksums.txt" "${base_url}/checksums.txt"

  echo "==> Verifying checksum of downloaded archive"
  if ! (cd "${workdir}" && sha256sum --ignore-missing -c checksums.txt); then
    echo "error: checksum verification failed — aborting install, not touching binary" >&2
    return 1
  fi

  echo "==> Unpacking and installing"
  (cd "${workdir}" && unzip -q "${zip_name}")
  sudo install -c -v "${workdir}/tflint" /usr/local/bin/

  echo "==> Installed:"
  tflint --version
}

if ! main "$@"; then
  echo "warning: tflint installation failed — continuing without tflint" >&2
  exit 0
fi
