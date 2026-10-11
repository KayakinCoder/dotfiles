# Note that plugins are installed, but disabled. I work on disparate, wide-ranging projects; each project's
# devcontainer startup code should enable the plugins that are relevant.

# install claude code
curl -fsSL https://claude.ai/install.sh | bash

# anthropic's curated list of high-quality plugins (https://github.com/anthropics/claude-plugins-official and https://claude.com/plugins). may not be needed if claude is already installed, but it doesn't hurt to run it again
claude plugin marketplace add anthropics/claude-plugins-official

# aws agent plugin (https://github.com/awslabs/agent-plugins)
claude plugin install aws-core@claude-plugins-official --scope user
claude plugin disable aws-core@claude-plugins-official --scope user

# azure plugin (https://github.com/microsoft/azure-skills)
claude plugin install azure@claude-plugins-official --scope user
claude plugin disable azure@claude-plugins-official --scope user

# buildkite plugins (https://github.com/buildkite/skills)
claude plugin marketplace add buildkite/skills
claude plugin install buildkite@buildkite-skills --scope user
claude plugin disable buildkite@buildkite-skills --scope user

# pulumi plugins (https://github.com/pulumi/agent-skills)
claude plugin marketplace add pulumi/agent-skills
claude plugin install pulumi-authoring --scope user
claude plugin disable pulumi-authoring --scope user

# databricks
claude plugin marketplace add databricks/databricks-agent-skills
claude plugin install databricks@databricks-agent-skills --scope user
claude plugin disable databricks@databricks-agent-skills --scope user
