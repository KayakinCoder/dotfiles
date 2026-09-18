# Rather than the main ~/.gitconfig file, set values via command line so as not to overwrite any existing settings
# in a codespace. Particularly commiter username
#
# Values are written to ~/.config/git/config (git's XDG global config) instead of ~/.gitconfig. Git reads both as
# "global" config, but the VS Code Dev Containers extension only copies your *host* ~/.gitconfig (user.name,
# user.email, credential settings) into the container if ~/.gitconfig does not already exist there. Dotfiles run
# before that copy, so creating ~/.gitconfig here would silently block it in a local devcontainer.

mkdir -p "$HOME/.config/git"
gitcfg() { git config --file "$HOME/.config/git/config" "$@"; }

gitcfg push.autoSetupRemote true
gitcfg init.defaultBranch main

# Set VS Code as the difftool
gitcfg diff.tool vscode
# don't prompt me to view/not view each file
gitcfg difftool.prompt false


# For Azure DevOps auth via Microsoft's git credential manager (GCM)
#
# include the repo path in credential requests so GCM (whether running in the container or forwarded to the host by
# VS Code) can work out the Azure DevOps organization. Without this GCM fails with
# "Cannot determine the organization name for this 'dev.azure.com' remote URL"
gitcfg credential.https://dev.azure.com.useHttpPath true
# no OS keychain in a headless container, so use git's own in-memory cache
gitcfg credential.credentialStore cache
# keep cached credentials for 8 hours instead of git's 15-minute default
gitcfg credential.cacheOptions "--timeout 28800"
# use short-lived Entra ID OAuth tokens for Azure Repos instead of minting a long-lived PAT
gitcfg credential.azreposCredentialType oauth
