# Note that plugins are installed, but disabled. I work on disparate, wide-ranging projects; each project's
# devcontainer startup code should enable the plugins that are relevant.

# install claude code
curl -fsSL https://claude.ai/install.sh | bash

# anthropic's curated list of high-quality plugins (https://github.com/anthropics/claude-plugins-official and https://claude.com/plugins). may not be needed if claude is already installed, but it doesn't hurt to run it again
claude plugin marketplace add anthropics/claude-plugins-official

# aws agent plugin (https://github.com/awslabs/agent-plugins)
claude plugin install aws-core@claude-plugins-official --scope user
claude plugin disable aws-core@claude-plugins-official --scope user

# azure: docs-oriented, login not required
# (https://github.com/MicrosoftDocs/Agent-Skills)
claude plugin marketplace add MicrosoftDocs/agent-skills
claude plugin install azure-agent-skills@microsoft-agent-skills --scope user
claude plugin disable azure-agent-skills@microsoft-agent-skills --scope user

# azure: build-oriented, uses their MCP and requires azure login
# (https://github.com/microsoft/azure-skills)
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

# microsoft docs mcp server. used by MicrosoftDocs/agent-skills
claude mcp get microsoft-docs >/dev/null 2>&1 || \
  claude mcp add --transport http --scope user microsoft-docs https://learn.microsoft.com/api/mcp

# terraform mcp server
# hashicorp does not maintain a remote mcp, so we build one locally and let clause use it
TF_MCP_VERSION=$(curl -fsSL https://releases.hashicorp.com/terraform-mcp-server/index.json \
  | jq -r '.versions | keys_unsorted | map(select(test("^[0-9]+\\.[0-9]+\\.[0-9]+$"))) | sort_by(split(".") | map(tonumber)) | last')
ARCH=$(uname -m | sed 's/x86_64/amd64/; s/aarch64/arm64/')
curl -fsSL "https://releases.hashicorp.com/terraform-mcp-server/${TF_MCP_VERSION}/terraform-mcp-server_${TF_MCP_VERSION}_linux_${ARCH}.zip" -o /tmp/tf-mcp.zip
sudo unzip -o -q /tmp/tf-mcp.zip terraform-mcp-server -d /usr/local/bin
rm /tmp/tf-mcp.zip

# register it with Claude Code, idempotently
claude mcp get terraform >/dev/null 2>&1 || \
  claude mcp add --scope user terraform -- terraform-mcp-server stdio
