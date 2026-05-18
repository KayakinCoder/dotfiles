# starship
../../helpers/install-font.sh https://github.com/ryanoasis/nerd-fonts/releases/download/v3.4.0/FiraCode.zip
curl -sS https://starship.rs/install.sh | sh -s -- -y

# needed for starship fonts to work correctly
echo 'export LC_ALL="en_US.UTF-8"' >> ~/.bashrc

# use starship on startup
echo 'eval "$(starship init bash)"' >> ~/.bashrc
