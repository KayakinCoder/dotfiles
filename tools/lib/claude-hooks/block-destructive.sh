#!/usr/bin/env bash
# block-destructive.sh — Claude Code PreToolUse hook for the Bash tool and MCP tools.
#
# A deterministic guardrail that inspects the shell command Claude is about to run:
#
#   DENY  — destroys infrastructure, data or files. Claude can never run these;
#           if they are needed, the user runs them by hand.
#           (terraform destroy/apply, pulumi up, rm -rf, aws ... delete-*,
#            az ... delete, git push --force, mkfs, DROP TABLE, ...)
#
#   ASK   — risky but sometimes legitimate. Forces a permission prompt even in
#           auto / acceptEdits mode so the user explicitly approves.
#           (git reset --hard, kubectl delete, aws ... update-*, make deploy, ...)
#
# Anything not matched falls through to the normal permission flow.
# Hooks run in every permission mode, including auto and bypassPermissions.
#
# Input : hook JSON on stdin ({"tool_name":"Bash","tool_input":{"command":"..."}})
#         For MCP tools (tool_name mcp__<server>__<tool>) the tool name plus the
#         command/intent/operation/action fields of tool_input are inspected instead,
#         e.g. the Azure MCP server's {"command":"storage account delete", ...}.
# Output: JSON permission decision on stdout, or nothing for "no opinion".
#
# Try one : echo '{"tool_input":{"command":"terraform destroy"}}' | bash block-destructive.sh
# Test all: bash test-block-destructive.sh   (lives next to this file in the dotfiles repo)
#
# Regexes are POSIX ERE (bash [[ =~ ]]): no \b, \s, \d or lookarounds, so the
# whole thing stays portable between GNU (devcontainer) and BSD (macOS) libc.

set -u

if ! command -v jq >/dev/null 2>&1; then
  # Fail closed: a safety hook that silently no-ops is worse than a loud one.
  echo "block-destructive hook: jq is not installed, refusing to run Bash commands until it is." >&2
  exit 2
fi

emit() { # $1 = deny|ask, $2 = reason
  local verdict="$1" reason="$2" msg
  if [ "$verdict" = deny ]; then
    msg="BLOCKED by the destructive-command guardrail: ${reason}. Do not try to work around this (no rewriting, no wrapper scripts, no other tools). If it genuinely needs to happen, tell the user and let them run it themselves."
    jq -n --arg d "$verdict" --arg r "$msg" --arg s "Destructive-command guardrail blocked: ${reason}" \
      '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:$d,permissionDecisionReason:$r},systemMessage:$s}'
  else
    msg="Destructive-command guardrail: ${reason} — requires explicit user approval."
    jq -n --arg d "$verdict" --arg r "$msg" \
      '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:$d,permissionDecisionReason:$r}}'
  fi
  exit 0
}

input=$(cat)
tool=$(printf '%s' "$input" | jq -r '.tool_name // empty' 2>/dev/null)
export TOOL_NAME="$tool"

case "$tool" in
  mcp__*)
    # MCP tool: inspect the tool name and the fields that name the operation. Free-text
    # fields (queries, file contents) are deliberately left out to avoid false positives.
    # If the input has none of the known operation fields, short identifier-like string
    # values (e.g. {"action":"delete"}) are inspected instead, but never prose.
    text=$(printf '%s' "$input" | jq -r '
      .tool_input as $in
      | [$in.command?, $in.intent?, $in.operation?, $in.action?, $in.method?, $in.subcommand?, $in.tool?, $in.name?]
      | map(select(type == "string" and . != ""))
      | if length > 0 then . else [$in | .. | strings | select((test("[[:space:]]") | not) and length <= 64)] end
      | [$ENV.TOOL_NAME] + . | join(" ")' 2>/dev/null)
    lc=$(printf '%s' "$text" | tr '[:upper:]\n\t' '[:lower:]  ' | sed -E 's/[[:space:]]+/ /g')
    MB='(^|[^a-z0-9])'                  # word boundary for tool names (mcp__azure__storage_account_delete)
    ME='([^a-z0-9]|$)'
    if [[ $lc =~ ${MB}(delete|purge|destroy|remove|terminate|drop|truncate|flush|wipe|erase|deallocate|deprovision|decommission|unassign|revoke)${ME} ]] \
       || [[ $lc =~ mode[^a-z0-9]?complete ]]; then
      emit deny "MCP tool call that deletes or destroys (${BASH_REMATCH[0]})"
    fi
    if [[ $lc =~ ${MB}(create|update|set|put|patch|post|write|deploy|start|stop|restart|redeploy|reimage|scale|resize|assign|upload|apply|run|invoke|execute|exec|import|move|regenerate|rotate|reset|enable|disable|failover|promote|restore|cancel|approve|submit|trigger|send|publish|migrate|modify|attach|detach|add|register|deregister|grant|createorupdate|setup)${ME} ]]; then
      emit ask "MCP tool call that changes cloud state (${BASH_REMATCH[0]})"
    fi
    exit 0
    ;;
esac

cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null) || exit 0
[ -z "$cmd" ] && exit 0

# --- Normalise -----------------------------------------------------------------
# One regex pass should cover multi-line, line-continued and compound commands:
# newlines/tabs -> spaces, backslash-continuations dropped, whitespace collapsed.
norm=$(printf '%s' "$cmd" | tr '\n\t\r' '   ' | sed -E 's/\\ +/ /g; s/[[:space:]]+/ /g')

# Known false positives: rewrite so the generic patterns below skip them.
norm=$(printf '%s' "$norm" | sed -E \
  -e 's/git( -[^ ]+)* rm /git-rm /g' \
  -e 's/aws configure (set|get|list|list-profiles|sso|import) /aws-configure \1 /g' \
  -e 's/aws eks update-kubeconfig/aws eks kubeconfig/g' \
  -e 's/az (account|config) set /az-\1-set /g' \
  -e 's/gcloud config set /gcloud-config-set /g')

# Lower-cased copy for case-insensitive (SQL) checks.
lc=$(printf '%s' "$norm" | tr '[:upper:]' '[:lower:]')

# --- Regex building blocks ----------------------------------------------------
WB='(^|[^[:alnum:]_.-])'                       # word start: line start, space, ; & | ( $ ` / \
SEG='[^;&|]*'                                  # rest of the current command segment
OPTS='( -[^ ]+)*'                              # -flags / --flags between binary and subcommand
TF='(terraform|tofu|terragrunt)( -[^ ]+| run-all| run)*'
AWS='aws( --?[a-z-]+(=[^ ]+| [^- ][^ ]*)?)*'   # aws [--profile x] [--region=y] <service> <verb>
AZ='az( -[^ ]+)*( [a-z][a-z0-9-]*)+'           # az [--flags] <group> [<subgroup>...]
GCLOUD='gcloud( -[^ ]+)*( [a-z][a-z0-9-]*)+'
GIT='git( --?[a-zA-Z-]+(=[^ ]+| [^- ][^ ]*)?)*'      # git [-C dir] [-c k=v] <subcommand>

DENY_PAT=();    DENY_MSG=()
DENY_CI_PAT=(); DENY_CI_MSG=()
ASK_PAT=();     ASK_MSG=()
ASK_CI_PAT=();  ASK_CI_MSG=()
deny()    { DENY_PAT+=("$1");    DENY_MSG+=("$2"); }
deny_ci() { DENY_CI_PAT+=("$1"); DENY_CI_MSG+=("$2"); }
ask()     { ASK_PAT+=("$1");     ASK_MSG+=("$2"); }
ask_ci()  { ASK_CI_PAT+=("$1");  ASK_CI_MSG+=("$2"); }

# =============================================================================
# DENY — never run by Claude
# =============================================================================

# --- Infrastructure as code ---------------------------------------------------
deny "${WB}${TF} destroy"                        "terraform/tofu/terragrunt destroy"
deny "${WB}${TF} apply${SEG} -destroy"           "terraform apply -destroy"
deny "${WB}${TF} state (rm|push)( |$)"           "terraform state rm/push (rewrites remote state)"
deny "${WB}${TF} workspace delete( |$)"          "terraform workspace delete"
deny "${WB}pulumi${OPTS} (destroy|stack rm|state delete)( |$)" "pulumi destroy / stack rm / state delete"
deny "${WB}(cdk|cdktf)${OPTS} destroy( |$)"      "cdk destroy"
deny "${WB}sam${OPTS} delete( |$)"               "sam delete"
deny "${WB}(serverless|sls)${OPTS} remove( |$)"  "serverless remove"
deny "${WB}${TF} (apply|import|taint|untaint|force-unlock|state (mv|replace-provider))( |$)" \
                                                 "terraform/tofu/terragrunt apply (or another command that changes real infrastructure or state) — the user applies changes themselves"
deny "${WB}pulumi${OPTS} (up|refresh|import|cancel|state (rename|move))( |$)" \
                                                 "pulumi up (or another command that changes real infrastructure or state) — the user applies changes themselves"
deny "${WB}(cdk|cdktf)${OPTS} (deploy|bootstrap)( |$)" "cdk deploy — the user applies changes themselves"
deny "${WB}sam${OPTS} deploy( |$)"               "sam deploy — the user applies changes themselves"
deny "${WB}(serverless|sls)${OPTS} deploy( |$)"  "serverless deploy — the user applies changes themselves"
deny "${WB}(make|just|task|rake|npm run|yarn( run)?|pnpm( run)?|bun run)${OPTS} [A-Za-z0-9_:./-]*(destroy|apply)" \
                                                 "task-runner target containing 'destroy' or 'apply'"

# --- AWS ----------------------------------------------------------------------
deny "${WB}${AWS} [a-z0-9-]+ (admin-)?(delete|terminate|purge|batch-delete|batch-terminate|schedule-key-deletion|close-account)[a-z-]*( |$)" \
                                                 "aws <service> delete-*/terminate-*/purge-*"
deny "${WB}${AWS} cloudformation (deploy|execute-change-set|create-stack|update-stack|create-stack-set|update-stack-set|create-stack-instances|update-stack-instances)( |$)" \
                                                 "aws cloudformation deploy/create/update (IaC apply) — the user applies changes themselves"
deny "${WB}${AWS} s3 (rb|rm)( |$)"               "aws s3 rb / rm"
deny "${WB}${AWS} s3 sync${SEG} --delete( |$)"   "aws s3 sync --delete"

# --- Azure --------------------------------------------------------------------
deny "${WB}${AZ} (delete|purge)[a-z-]*( |$)"     "az ... delete / purge"
deny "${WB}az${OPTS} deployment${SEG} --mode[= ]?[Cc]omplete( |$)" \
                                                 "az deployment --mode Complete (deletes resources not in the template)"
deny "${WB}az${OPTS} (deployment|stack)( [a-z-]+)* create( |$)" \
                                                 "az deployment/stack create (IaC apply) — the user applies changes themselves"
deny "${WB}az${OPTS} storage blob sync( |$)"     "az storage blob sync (deletes destination blobs)"
deny "${WB}azcopy${OPTS} (rm|remove)( |$)"       "azcopy remove"

# --- GCP ----------------------------------------------------------------------
deny "${WB}${GCLOUD} delete( |$)"                "gcloud ... delete"
deny "${WB}gcloud${OPTS} storage rm( |$)"        "gcloud storage rm"
deny "${WB}gsutil${OPTS} (rm|rb)( |$)"           "gsutil rm / rb"
deny "${WB}gsutil${OPTS} rsync${SEG} -d( |$)"    "gsutil rsync -d (deletes destination objects)"
deny "${WB}gcloud${OPTS} (deployment-manager deployments (create|update)|infra-manager deployments apply)( |$)" \
                                                 "gcloud deployment (IaC apply) — the user applies changes themselves"

# --- Databases (case-insensitive) --------------------------------------------
deny_ci "${WB}drop (database|schema|table|index|user|role|view|collection|keyspace)( |$)" "SQL DROP"
deny_ci "${WB}truncate (table )?[a-z_.]"         "SQL TRUNCATE"
deny_ci "${WB}redis-cli${SEG} (flushall|flushdb)( |$)" "redis FLUSHALL/FLUSHDB"
deny_ci "\.(dropdatabase|drop)[(][)]"            "mongo drop()/dropDatabase()"

# --- Filesystem / host ---------------------------------------------------------
deny "${WB}rm( ${SEG})? -(-recursive|[a-zA-Z]*[rR][a-zA-Z]*)" "recursive rm (rm -r / rm -rf)"
deny "${WB}(mkfs(\.[a-z0-9]+)?|wipefs|shred|blkdiscard)( |$)" "disk format / secure wipe"
deny "${WB}dd( ${SEG})? of=/dev/"                "dd writing to a device"
deny ">[ ]?/dev/(sd|hd|nvme|vd|xvd|mmcblk|disk|md|dm-)" "redirect into a block device"
deny "${WB}(chmod|chown|chgrp)( ${SEG})? -[a-zA-Z]*R[a-zA-Z]*( ${SEG})? (/|/[*]|~|~/|\\\$HOME|\\\$HOME/)( |$)" \
                                                 "recursive chmod/chown on / or home"
deny "${WB}mv( ${SEG})? /dev/null( |$)"          "mv into /dev/null"
deny "${WB}rsync( ${SEG})? --del[a-z-]*( |$)"    "rsync --delete (removes files from the destination)"
deny ":[(][)] ?[{] ?:[|]:& ?[}] ?;:"             "fork bomb"
deny "${WB}crontab${OPTS} -r( |$)"               "crontab -r"
deny "${WB}(shutdown|reboot|halt|poweroff)( |$)" "host power command"

# --- Git ----------------------------------------------------------------------
deny "${WB}${GIT} push( ${SEG})? (-f|--force)( |$)" "git push --force (run it yourself; --force-with-lease will prompt)"
deny "${WB}${GIT} push( ${SEG})? [+][^ ]+"   "git push with a +refspec (force)"

# --- Containers ---------------------------------------------------------------
deny "${WB}kubectl${OPTS} delete( ${SEG})? (--all|-A|--all-namespaces|ns|namespaces?|pv|persistentvolumes?|pvc|persistentvolumeclaims?|nodes?)( |$)" \
                                                 "kubectl delete of namespaces / volumes / nodes / --all"
deny "${WB}docker${OPTS} (system prune|volume (prune|rm))( |$)" "docker system prune / volume rm"
deny "${WB}(docker${OPTS} compose|docker-compose)( ${SEG})? down( ${SEG})? (-v|--volumes)( |$)" \
                                                 "docker compose down -v (deletes volumes)"

# =============================================================================
# ASK — always prompt, even in auto mode
# =============================================================================

# --- Infrastructure as code ---------------------------------------------------
ask "${WB}(make|just|task|rake|npm run|yarn( run)?|pnpm( run)?|bun run)${OPTS} [A-Za-z0-9_:./-]*(deploy|release|publish)" \
                                                 "task-runner target that looks like a deploy"

# --- Secrets: anything that prints credentials into the transcript ----------
CREDPATH='(~|[$]HOME|/home/[^ /]+|/root)/\.(aws|ssh|azure|kube|docker|gnupg|config/gcloud|netrc|npmrc|pypirc|git-credentials|claude/\.credentials)'
ask "${WB}(cat|less|more|head|tail|bat|strings|base64|xxd|od|hexdump|cp|scp|rsync|tar|zip|gzip|curl|wget|nc|grep|awk|sed|cut|tee|source|python3?|node)( ${SEG})? [^ ]*${CREDPATH}" \
                                                 "reads a credential file (~/.aws, ~/.ssh, ~/.azure, ...)"
ask "${WB}(cat|less|more|head|tail|bat|strings|base64|grep|awk|sed|cut|tee|source|\.)( ${SEG})? [^ ]*\.env(\.[A-Za-z0-9_-]+)?( |$)" \
                                                 "reads a .env file"
ask "${WB}(printenv|env)( ?[|>;&]|$)"            "dumps the whole environment (may contain secrets)"
ask "${WB}(printenv|env)( ${SEG})? [A-Za-z0-9_]*(SECRET|TOKEN|PASSWORD|PASSWD|API_KEY|PRIVATE_KEY|CREDENTIAL)" \
                                                 "prints a secret environment variable"
ask "${WB}(echo|printf)( ${SEG})? [^ ]*[$][{]?[A-Za-z0-9_]*(SECRET|TOKEN|PASSWORD|PASSWD|API_KEY|PRIVATE_KEY|CREDENTIAL)" \
                                                 "prints a secret environment variable"
ask "${WB}${AWS} (configure export-credentials|sts (assume-role|get-session-token|get-federation-token|assume-role-with-[a-z-]+)|secretsmanager get-secret-value|ssm get-parameters?( ${SEG})? --with-decryption|ecr get-(login-password|authorization-token)|iam create-access-key|kms decrypt)( |$)" \
                                                 "mints or reveals AWS credentials/secrets"
ask "${WB}az${OPTS} (account get-access-token|keyvault (secret|key|certificate) (show|download|backup|list-versions)|storage account (keys list|show-connection-string)|acr (credential show|login)|ad (sp|app) credential reset|webapp deployment list-publishing-(profiles|credentials))( |$)" \
                                                 "mints or reveals Azure credentials/secrets"
ask "${WB}gcloud${OPTS} (auth (print-access-token|print-identity-token|application-default print-access-token)|secrets versions access|iam service-accounts keys create)( |$)" \
                                                 "mints or reveals GCP credentials/secrets"
ask "${WB}(gh auth token|kubectl${OPTS} get secrets?( ${SEG})? (-o|--output)[ =](yaml|json|jsonpath[^ ]*)|vault (read|kv get)|op (read|item get)|docker login)( |$)" \
                                                 "reveals credentials/secrets"

# --- Cloud CLIs: anything that mutates ---------------------------------------
ask "${WB}${AWS} [a-z0-9-]+ (create|run|start|stop|reboot|update|modify|put|set|reset|rotate|enable|disable|attach|detach|associate|disassociate|register|deregister|authorize|revoke|remove|release|cancel|reject|deprecate|restore|invoke|execute|send|publish|tag|untag|import|change|add|allocate|assign|copy|promote|failover|switchover|activate|deactivate|batch-write|batch-put|batch-update|admin|accept|approve|initiate|resize|upgrade|apply|move|migrate|replace|transfer|submit|suspend|resume)[a-z-]*( |$)" \
                                                 "aws command that changes cloud state"
ask "${WB}${AWS} s3 mv( |$)"                     "aws s3 mv (removes the source)"
ask "${WB}${AWS} s3 (cp|sync)( -[^ ]+)* [^ ]+ s3://" "aws s3 cp/sync into a bucket (overwrites objects)"
ask "${WB}${AZ} (create|start|stop|restart|deallocate|update|set|add|remove|reset|rotate|regenerate-keys|renew|scale|move|import|invoke|run|attach|detach|enable|disable|revoke|assign|upload|up|deploy|redeploy|reimage|resize|copy|failover|promote|cancel|approve|reject|pause|resume|suspend|apply|publish|submit|trigger|send|migrate)(-[a-z-]+)?( |$)" \
                                                 "az command that changes cloud state"
ask "${WB}${GCLOUD} (create|update|start|stop|reset|remove|add|set|deploy|run|import|move|resize|suspend|restore|enable|disable|revoke|apply|attach|detach|promote|failover|upgrade|scale|patch|replace|submit|trigger|copy|write)( |$)" \
                                                 "gcloud command that changes cloud state"
ask "${WB}(gsutil${OPTS} (cp|rsync|mv)|gcloud${OPTS} storage (cp|rsync|mv))( -[^ ]+)* [^ ]+ gs://" \
                                                 "gsutil cp/rsync into a bucket (overwrites objects)"

# --- Self-protection: Claude changing its own guardrails ----------------------
ask "(~|[$]HOME|/home/[^ /]+|/root)/\.claude/(settings(\.local)?\.json|hooks/)" \
                                                 "touches Claude Code settings or hooks (the guardrail itself)"

# --- Databases (case-insensitive) --------------------------------------------
ask_ci "${WB}delete from( |$)"                   "SQL DELETE"
ask_ci "${WB}alter (table|database|schema)( |$)" "SQL ALTER"

# --- Git ----------------------------------------------------------------------
ask "${WB}${GIT} push( ${SEG})? (-d|--delete|--force-with-lease|--force-if-includes|:[^ ])" "git push that deletes or force-updates a remote branch"
ask "${WB}${GIT} reset( ${SEG})? --hard( |$)" "git reset --hard"
ask "${WB}${GIT} clean( ${SEG})? -[a-zA-Z]*[fdx]" "git clean -f/-d/-x"
ask "${WB}${GIT} (checkout|restore)( ${SEG})? (-- )?\.( |$)" "discarding all working-tree changes"
ask "${WB}${GIT} branch( ${SEG})? -[a-zA-Z]*D" "git branch -D"
ask "${WB}${GIT} stash (drop|clear)( |$)"    "git stash drop/clear"
ask "${WB}${GIT} (filter-branch|filter-repo|reflog expire|update-ref -d)( |$)" "git history rewrite"

# --- Containers ---------------------------------------------------------------
ask "${WB}kubectl${OPTS} (delete|drain|cordon|taint|replace|patch|scale|edit|rollout undo)( |$)" "kubectl command that changes cluster state"
ask "${WB}helm${OPTS} (uninstall|delete|del|un|rollback)( |$)" "helm uninstall/rollback"
ask "${WB}docker${OPTS} (rm|rmi|container (rm|prune)|image (rm|prune)|network (rm|prune))( |$)" "docker removal"

# --- Filesystem / misc --------------------------------------------------------
ask "${WB}find( ${SEG})? (-delete|-exec rm)( |$)" "find -delete / -exec rm"
ask "${WB}(curl|wget)( ${SEG})? [|] ?(sudo )?(ba|z|da|k)?sh( |$)" "piping a download into a shell"

# =============================================================================
# Evaluate
# =============================================================================

i=0
while [ "$i" -lt "${#DENY_PAT[@]}" ]; do
  [[ $norm =~ ${DENY_PAT[$i]} ]] && emit deny "${DENY_MSG[$i]}"
  i=$((i + 1))
done
i=0
while [ "$i" -lt "${#DENY_CI_PAT[@]}" ]; do
  [[ $lc =~ ${DENY_CI_PAT[$i]} ]] && emit deny "${DENY_CI_MSG[$i]}"
  i=$((i + 1))
done
i=0
while [ "$i" -lt "${#ASK_PAT[@]}" ]; do
  [[ $norm =~ ${ASK_PAT[$i]} ]] && emit ask "${ASK_MSG[$i]}"
  i=$((i + 1))
done
i=0
while [ "$i" -lt "${#ASK_CI_PAT[@]}" ]; do
  [[ $lc =~ ${ASK_CI_PAT[$i]} ]] && emit ask "${ASK_CI_MSG[$i]}"
  i=$((i + 1))
done

# No opinion: fall through to normal permission handling.
exit 0
