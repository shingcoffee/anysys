#!/usr/bin/env bash
# Stop hook: when a turn touched files under app/, config/routes.rb, db/migrate/, or spec/,
# emit a marker that the convention-guardian subagent (anysys-tech-lead) should review
# the current diff. Non-blocking — exit 0 always.

set -u

cd "$(git rev-parse --show-toplevel 2>/dev/null)" || exit 0

CHANGED=$(git diff --name-only HEAD 2>/dev/null; git diff --name-only --staged 2>/dev/null; git ls-files --others --exclude-standard 2>/dev/null)

case "$CHANGED" in
  *app/*|*config/routes.rb*|*db/migrate/*|*spec/*)
    cat <<'EOF'
[tech-lead-stop] Diff touches app/, routes, migrations, or specs.
Orchestrator should dispatch anysys-tech-lead against the current diff
before the next user turn. Run the audit-conventions skill or invoke the agent directly.
EOF
    ;;
  *)
    : # no relevant changes; stay silent
    ;;
esac

exit 0
