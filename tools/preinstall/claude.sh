# install claude code
curl -fsSL https://claude.ai/install.sh | bash

# anthropic's curated list of high-quality plugins (https://github.com/anthropics/claude-plugins-official and https://claude.com/plugins). may not be needed if claude is already installed, but it doesn't hurt to run it again
claude plugin marketplace add anthropics/claude-plugins-official

# aws agent plugin (https://github.com/awslabs/agent-plugins)
claude plugin install aws-core@claude-plugins-official --scope user

# azure plugin (https://github.com/microsoft/azure-skills)
claude plugin install azure@claude-plugins-official --scope user

# buildkite plugin
claude plugin marketplace add buildkite/skills
claude plugin install buildkite@buildkite-skills
