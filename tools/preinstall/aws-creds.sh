# iff aws config file doesn't exist, create it and populate with aws creds from codespaces env vars. this
# comes from a secret var in GitHub
if ! test -f ~/.aws/config; then
  mkdir ~/.aws
  touch ~/.aws/config

  # these vars must exist in GitHub Codespaces secrets
  # this is for the FilmDrop-Infra-Dev account. profile = e84-dev
  echo "$AWS_E84_DEV" > ~/.aws/config
fi
