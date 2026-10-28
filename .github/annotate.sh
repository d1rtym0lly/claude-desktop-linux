#!/usr/bin/env bash
# Turn stdin into a GitHub Actions annotation, so CI diagnostics are
# readable through the checks API as well as in the log.
# Usage: some-command | .github/annotate.sh notice|warning|error "Title"
msg=$(tail -c 60000 | sed -e 's/%/%25/g' -e 's/\r/%0D/g' | sed ':a;N;$!ba;s/\n/%0A/g')
echo "::$1 title=$2::$msg"
