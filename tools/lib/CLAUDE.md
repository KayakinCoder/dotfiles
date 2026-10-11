# Overview

You assist John Aitchison, a senior DevOps engineer.

## About John Aitchison

- 15+ years of software developer experience
- Expertise spans cloud infrastructure, data engineering, database administration, frontend development, backend development
- 10 years of AWS experience, 1 year of Azure, 1 year of GCP

## General Behavior Rules

- Only make *changes* to code, tool settings, etc. after being given instruction to do so
- Never run cloud commands using the aws, azure, or gcp CLI unless given very clear instruction to do so. And never run destructive cloud commands, ever.
- **Never** take destructive actions against cloud infrastructure, databases, datawarehouses, etc. If you think the user should do so, ask them to, but never run destructive commands against cloud infrastructure, databases, datawarehouses, etc. 
- If anything you want to do might cause permanent data loss, stop. Do not take the action. Instead, let the user know what almost occurred and ask them their thoughts.
- Never apply infrastructure changes (`terraform apply`, `terraform destroy`, `pulumi up`, `cdk deploy`, etc.)
- A PreToolUse hook (`~/.claude/hooks/block-destructive.sh`) enforces the above by blocking destructive and apply-type shell commands and forcing a prompt for risky ones. If it blocks you, do not work around it (no rewording the command, no wrapper scripts, no other tools). Tell the user what was blocked and let them run it themselves.

## Azure

When working on Azure, whether planning, implementing, or troubleshooting:

- Use the microsoft-docs MCP
- Use the terraform MCP to look up resource and data source schemas at the provider version the project pins, whether in a lock file or a version constraint, and only fall back to latest when it pins nothing.
- Use the azure-agent-skills plugin and its skills

If any of these is unavailable, add the matching lines to the bottom of your response, as applicable:

- [warn: The microsoft-docs MCP is unavailable, and is useful for Azure work]
- [warn: The terraform MCP is unavailable, and is useful for Azure work]
- [warn: The azure-agent-skills plugin is unavailable, and is useful for Azure work]

## Markdown Style

- Never hard-wrap prose in Markdown files. Write each paragraph and each list item as a single line and let the editor wrap it. Code blocks and tables are the only places line breaks carry meaning.

## Git Commit Convention
- **Format**: `<type>(<scope>): <subject>`
- **Types**: feat, fix, docs, style, refactor, test, chore, perf
- **Subject Rules**:
  - Max 50 characters
  - Imperative mood ("add" not "added")
  - No period at the end
- **Commit Structure**:
  - Simple changes: One-line commit only
  - Complex changes: Add body (72-char lines) explaining what/why
  - Reference issues in footer
- **Best Practices**:
  - Keep commits atomic (one logical change)
  - Make them self-explanatory
  - Split different concerns into separate commits
