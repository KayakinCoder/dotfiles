# install all scripts located here. note that /tools/extra are other tools I've used in the past but don't currently
# use regularly enough to preinstall
for script in ./tools/preinstall/*.sh; do
  /bin/bash "$script"
done

# note that codespaces does not, as their docs *somewhat* misleadingly allude to, do this for you:
cp -r ./.config/* ~/.config/
cp .bash_aliases ~/.bash_aliases

# my aws home
echo 'export AWS_DEFAULT_REGION=us-west-2' >> ~/.bashrc
