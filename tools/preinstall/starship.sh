# starship
../../helpers/install-font.sh https://github.com/ryanoasis/nerd-fonts/releases/download/v3.4.0/FiraCode.zip
curl -sS https://starship.rs/install.sh | sh -s -- -y
echo 'eval "$(starship init bash)"' >> ~/.bashrc
cp /workspaces/devcontainer-fd/.build/tools/starship.toml ~/.config/starship.toml
