# iff aws config file doesn't exist, create it and populate with aws creds from codespaces env vars. this
# comes from a secret var in GitHub
if ! test -f ~/.aws/config; then
  mkdir ~/.aws
  touch ~/.aws/config

  # these var(s) must exist in GitHub Codespaces secrets
  echo "$AWS_E_DEV" > ~/.aws/config
fi
