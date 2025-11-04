# Rather than a config file, set values via command line so as not to overwrite any existing settings
# in a codespace. Particularly commiter username

git config --global push.autoSetupRemote true
git config --global init.defaultBranch main

# Set VS Code as the difftool
git config --global diff.tool vscode
# don't prompt me to view/not view each file
git config --global difftool.prompt false
