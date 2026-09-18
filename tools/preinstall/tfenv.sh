git clone --depth=1 https://github.com/tfutils/tfenv.git ~/.tfenv

# symlink into /usr/local/bin rather than appending to ~/.bashrc: devcontainer postAttach/postCreate scripts
# run in a non-interactive shell that never reads ~/.bashrc, but /usr/local/bin is on PATH for every shell.
# this is tfenv's documented install method and its shims resolve symlinks correctly.
sudo ln -sf ~/.tfenv/bin/* /usr/local/bin/
