# create a temp dir in our workspace, download and unzip the aws cli package, then install it
cd /workspaces && mkdir tempinstall && cd tempinstall
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install
cd /workspaces/devcontainer
