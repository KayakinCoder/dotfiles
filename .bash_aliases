alias tf='terraform'
alias pl='pulumi'

# aws. these profiles need to exist in ~/.aws/config for SSO login to work
alias aws-e='export AWS_PROFILE=e-dev && aws sso login --profile e-dev'
alias aws-k='export AWS_PROFILE=k-dev && aws sso login --profile k-dev'

# github (note: most gh aliases are in /.config/gh/config.yml)
alias gh-a='unset GITHUB_TOKEN && gh auth login'

# my favorite git commands
alias gitl='git log --graph --oneline --decorate'
