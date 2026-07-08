#!/usr/bin/env bash
set -euo pipefail

# install git credential manager (GCM), Microsoft's recommended way to authenticate to azure devops repos
GCM_VERSION=$(curl -fsSL https://api.github.com/repos/git-ecosystem/git-credential-manager/releases/latest | grep -oP '"tag_name": "v\K[^"]+')

curl -fsSL -o /tmp/gcm.deb \
  "https://github.com/git-ecosystem/git-credential-manager/releases/download/v${GCM_VERSION}/gcm-linux-x64-${GCM_VERSION}.deb"
sudo dpkg -i /tmp/gcm.deb
rm /tmp/gcm.deb

# register GCM as git's credential helper
git-credential-manager configure
