for script in ./tools/preinstall/*.sh; do
  /bin/bash "$script"
done

# get config here into the home config
cp -r ./.config/* ~/.config/

# dotfiles
cp .bash_aliases ~/.bash_aliases

# my aws home
echo 'export AWS_DEFAULT_REGION=us-west-2' >> ~/.bashrc
