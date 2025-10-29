# Rather than a config file, set values via command line so as not to overwrite any existing settings
# in a codespace. Particularly commiter username

git config --global push.autoSetupRemote true
git config --global init.defaultBranch main
