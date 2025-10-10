alias tf='terraform'
alias pl='pulumi'

# aws
alias aws-e='export AWS_PROFILE=e84-dev && aws sso login --profile e84-dev'
alias aws-k='export AWS_PROFILE=ks-playground && aws sso login --profile ks-playground'

# github (note: most gh aliases are in /.config/gh/config.yml)
alias gh-a='unset GITHUB_TOKEN && gh auth login'
