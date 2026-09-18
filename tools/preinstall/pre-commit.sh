pipx install pre-commit

# pipx installs to ~/.local/bin, which is only on PATH for interactive shells. expose it to the
# non-interactive devcontainer startup scripts too.
sudo ln -sf ~/.local/bin/pre-commit /usr/local/bin/pre-commit
