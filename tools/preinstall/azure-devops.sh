#!/usr/bin/env bash
set -euo pipefail

# install git credential manager (GCM), Microsoft's recommended way to authenticate to azure devops repos
#
# only needed in codespaces. in a local devcontainer, the VS Code Dev Containers extension forwards git credential
# requests to the credential manager on your host machine, and a container-side GCM would run ahead of that
# forwarder and start its own login flow
if [[ "${CODESPACES:-}" != "true" ]]; then
  echo "local devcontainer: VS Code forwards git credentials to the host's credential manager; skipping GCM install"
  exit 0
fi

# GCM publishes separate debs per architecture (x64 and arm64)
case "$(dpkg --print-architecture)" in
  amd64) gcm_arch=x64 ;;
  arm64) gcm_arch=arm64 ;;
  *) echo "unsupported architecture for GCM: $(dpkg --print-architecture); skipping"; exit 0 ;;
esac

GCM_VERSION=$(curl -fsSL https://api.github.com/repos/git-ecosystem/git-credential-manager/releases/latest | grep -oP '"tag_name": "v\K[^"]+')

curl -fsSL -o /tmp/gcm.deb \
  "https://github.com/git-ecosystem/git-credential-manager/releases/download/v${GCM_VERSION}/gcm-linux-${gcm_arch}-${GCM_VERSION}.deb"
sudo dpkg -i /tmp/gcm.deb
rm /tmp/gcm.deb

# register GCM as git's credential helper
git-credential-manager configure
