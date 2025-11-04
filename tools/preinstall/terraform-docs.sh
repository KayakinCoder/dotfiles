# terraform-docs
cd /tmp
curl -sSLo ./terraform-docs.tar.gz https://terraform-docs.io/dl/v0.20.0/terraform-docs-v0.20.0-$(uname)-amd64.tar.gz
tar -xzf terraform-docs.tar.gz
chmod +x terraform-docs
sudo mv terraform-docs /usr/local/bin/terraform-docs
cd /workspaces/devcontainer-fd
