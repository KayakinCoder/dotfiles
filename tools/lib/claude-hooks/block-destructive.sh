#!/usr/bin/env bash
# block-destructive.sh — Claude Code PreToolUse hook for the Bash tool.
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

input=$(cat)
cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null) || exit 0
[ -z "$cmd" ] && exit 0

# --- Normalise -----------------------------------------------------------------
# One regex pass should cover multi-line, line-continued and compound commands:
# newlines/tabs -> spaces, backslash-continuations dropped, whitespace collapsed.
norm=$(printf '%s' "$cmd" | tr '\n\t\r' '   ' | sed -E 's/\\ +/ /g; s/[[:space:]]+/ /g')

# Known false positives: rewrite so the generic patterns below skip them.
norm=$(printf '%s' "$norm" | sed -E \
  -e 's/git( -[^ ]+)* rm /git-rm /g' \
  -e 's/aws configure /aws-configure /g' \
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
deny "${WB}${AWS} [a-z0-9-]+ (delete|terminate|purge|batch-delete|batch-terminate|schedule-key-deletion|close-account)[a-z-]*( |$)" \
                                                 "aws <service> delete-*/terminate-*/purge-*"
deny "${WB}${AWS} s3 (rb|rm)( |$)"               "aws s3 rb / rm"
deny "${WB}${AWS} s3 sync${SEG} --delete( |$)"   "aws s3 sync --delete"

# --- Azure --------------------------------------------------------------------
deny "${WB}${AZ} (delete|purge)[a-z-]*( |$)"     "az ... delete / purge"
deny "${WB}az${OPTS} deployment${SEG} --mode[= ]?[Cc]omplete( |$)" \
                                                 "az deployment --mode Complete (deletes resources not in the template)"
deny "${WB}az${OPTS} storage blob sync( |$)"     "az storage blob sync (deletes destination blobs)"
deny "${WB}azcopy${OPTS} (rm|remove)( |$)"       "azcopy remove"

# --- GCP ----------------------------------------------------------------------
deny "${WB}${GCLOUD} delete( |$)"                "gcloud ... delete"
deny "${WB}gcloud${OPTS} storage rm( |$)"        "gcloud storage rm"
deny "${WB}gsutil${OPTS} (rm|rb)( |$)"           "gsutil rm / rb"
deny "${WB}gsutil${OPTS} rsync${SEG} -d( |$)"    "gsutil rsync -d (deletes destination objects)"

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

# --- Cloud CLIs: anything that mutates ---------------------------------------
ask "${WB}${AWS} [a-z0-9-]+ (create|run|start|stop|reboot|update|modify|put|set|reset|rotate|enable|disable|attach|detach|associate|disassociate|register|deregister|authorize|revoke|remove|release|cancel|reject|deprecate|restore|invoke|execute|send|publish|tag|untag|import)[a-z-]*( |$)" \
                                                 "aws command that changes cloud state"
ask "${WB}${AWS} s3 mv( |$)"                     "aws s3 mv (removes the source)"
ask "${WB}${AZ} (create|start|stop|restart|deallocate|update|set|add|remove|reset|rotate|regenerate-keys|scale|move|import|invoke|run|attach|detach|enable|disable|revoke|assign|upload)( |$)" \
                                                 "az command that changes cloud state"
ask "${WB}${GCLOUD} (create|update|start|stop|reset|remove|add|set|deploy|run|import|move|resize|suspend|restore|enable|disable|revoke)( |$)" \
                                                 "gcloud command that changes cloud state"

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
