#!/usr/bin/env bash
# Smoke test of a running site container: content types, headers, 404 and a non-zero release count.
# Usage: scripts/test-container.sh [base-url]   (default http://127.0.0.1:8080)
set -euo pipefail

base="${1:-http://127.0.0.1:8080}"
fail=0

check_type() { # path expected-content-type-prefix
  local type
  type=$(curl -fsS -o /dev/null -w '%{content_type}' "$base$1")
  if [[ "$type" == *"$2"* ]]; then echo "ok   $1 -> $type"; else echo "FAIL $1 -> '$type', expected '$2'"; fail=1; fi
}

check_type / text/html
check_type /healthz text/plain
check_type /data/releases.json application/json
check_type /calendar.ics text/calendar
check_type /calendar-reminders.ics text/calendar
check_type /feed.json application/feed+json
check_type /feed.xml application/rss+xml
check_type /site.webmanifest application/manifest+json
check_type /sw.js javascript

code=$(curl -sS -o /dev/null -w '%{http_code}' "$base/does-not-exist")
if [[ "$code" == "404" ]]; then echo "ok   /does-not-exist -> 404"; else echo "FAIL /does-not-exist -> $code"; fail=1; fi

headers=$(curl -fsSI "$base/")
for header in x-content-type-options content-security-policy; do
  if grep -qi "^$header:" <<<"$headers"; then echo "ok   header $header"; else echo "FAIL missing header $header"; fail=1; fi
done

if curl -fsS -H 'Accept-Encoding: gzip' -o /dev/null -D - "$base/data/releases.json" | grep -qi '^content-encoding: gzip'; then echo "ok   gzip"; else echo "FAIL gzip"; fail=1; fi

count=$(curl -fsS "$base/data/releases.json" | python3 -c 'import json,sys; print(len(json.load(sys.stdin)["releases"]))')
if [[ "$count" -gt 0 ]]; then echo "ok   $count releases"; else echo "FAIL no releases in data"; fail=1; fi

exit $fail
