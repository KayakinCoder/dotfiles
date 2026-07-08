# Rather than a config file, set values via command line so as not to overwrite any existing settings
# in a codespace. Particularly commiter username

git config --global push.autoSetupRemote true
git config --global init.defaultBranch main

# Set VS Code as the difftool
git config --global diff.tool vscode
# don't prompt me to view/not view each file
git config --global difftool.prompt false


# For Azure DevOps auth via Microsoft's git credential manager (GCM)
#
# no OS keychain in a headless container, so use git's own in-memory cache
git config --global credential.credentialStore cache
# keep cached credentials for 8 hours instead of git's 15-minute default
git config --global credential.cacheOptions "--timeout 28800"
# use short-lived Entra ID OAuth tokens for Azure Repos instead of minting a long-lived PAT
git config --global credential.azreposCredentialType oauth
