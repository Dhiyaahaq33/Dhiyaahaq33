#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

OWNER="Dhiyaahaq33"
WORKDIR=$(mktemp -d)
trap 'rm -rf "$WORKDIR"' EXIT

# ---- own repos (exclude forks, the profile repo, and the padding automation repo) ----
mapfile -t OWN_REPOS < <(gh repo list "$OWNER" --limit 300 --json name,isFork \
  --jq '.[] | select(.isFork==false and .name!="'"$OWNER"'" and .name!="daily-activity") | .name')

for name in "${OWN_REPOS[@]}"; do
  git clone --depth 1 -q "https://x-access-token:${GH_TOKEN}@github.com/$OWNER/$name.git" "$WORKDIR/$name" 2>/dev/null || echo "warn: failed to clone $name" >&2
done

find "$WORKDIR" -type f \
  -not -path "*/.git/*" \
  -not -iname "*.png" -not -iname "*.jpg" -not -iname "*.jpeg" -not -iname "*.gif" -not -iname "*.ico" \
  -not -iname "*.db" -not -iname "*.sqlite*" -not -iname "*.pdf" -not -iname "*.docx" \
  -not -iname "*.ttf" -not -iname "*.woff*" -not -iname "*.mp4" -not -iname "*.zip" \
  -not -iname "*.exe" -not -iname "*.dll" -not -iname "*.pyc" \
  -print0 | xargs -0 wc -l 2>/dev/null | grep -v " total$" > "$WORKDIR/all_lines.txt" || true

TOTAL=$(awk '{s+=$1} END {print s+0}' "$WORKDIR/all_lines.txt")

awk '{
  lines=$1; $1="";
  path=$0; sub(/^ /, "", path);
  n=split(path, parts, "/");
  fname=parts[n];
  extidx=match(fname, /\.[^.]+$/);
  if (extidx>0) { ext=substr(fname, extidx+1) } else { ext="(no ext)" }
  sum[ext]+=lines
}
END { for (e in sum) print sum[e], e }' "$WORKDIR/all_lines.txt" | sort -rn | head -10 > "$WORKDIR/top_ext.txt"

{
  printf '**%s total**\n\n' "$(printf "%'d" "$TOTAL" 2>/dev/null || echo "$TOTAL")"
  echo "| Language | Lines | Share |"
  echo "|---|---|---|"
  while read -r lines ext; do
    pct=$(awk -v l="$lines" -v t="$TOTAL" 'BEGIN { printf "%.1f", (t>0 ? l*100/t : 0) }')
    printf '| %s | %s | %s%% |\n' "$ext" "$lines" "$pct"
  done < "$WORKDIR/top_ext.txt"
} > "$WORKDIR/loc_block.md"

# ---- external contributions (PRs on repos NOT owned by the user, forks excluded by definition) ----
gh api "search/issues?q=author:$OWNER+type:pr&per_page=100" \
  --jq --arg owner "$OWNER" '.items[] | select((.repository_url | split("/")[-2]) != $owner) |
    {repo: (.repository_url | split("/")[-2] + "/" + (.repository_url | split("/")[-1])), url: .html_url, merged: (.pull_request.merged_at != null), title: .title}' \
  > "$WORKDIR/ext_prs.jsonl" || true

MERGED_LINES=$(jq -r 'select(.merged==true) | "[" + .repo + "](" + .url + ") — " + .title' "$WORKDIR/ext_prs.jsonl")
OPEN_REPOS=$(jq -r 'select(.merged==false) | .repo' "$WORKDIR/ext_prs.jsonl" | sort -u)
MERGED_COUNT=$(jq -r 'select(.merged==true)' "$WORKDIR/ext_prs.jsonl" | jq -s 'length')
OPEN_COUNT=$(jq -rs 'map(select(.merged==false)) | length' "$WORKDIR/ext_prs.jsonl")

{
  if [ "$MERGED_COUNT" -gt 0 ]; then
    printf '**✅ Merged (%s):** ' "$MERGED_COUNT"
    jq -r 'select(.merged==true) | "[" + .repo + "](" + .url + ") — " + .title' "$WORKDIR/ext_prs.jsonl" | paste -sd, - | sed 's/,/, /g'
    printf '\n\n'
  else
    echo "**✅ Merged (0):** none yet."
    echo ""
  fi
  if [ "$OPEN_COUNT" -gt 0 ]; then
    printf '**⏳ Open / pending review (%s):** ' "$OPEN_COUNT"
    jq -rs 'map(select(.merged==false)) | group_by(.repo) | map("[" + .[0].repo + "](https://github.com/" + .[0].repo + "/pulls" + (if length>1 then ") (x" + (length|tostring) + ")" else ")" end)) | join(", ")' "$WORKDIR/ext_prs.jsonl"
  fi
} > "$WORKDIR/contrib_block.md"

# ---- splice both blocks into README.md between markers ----
python3 - "$WORKDIR/loc_block.md" "$WORKDIR/contrib_block.md" <<'PY'
import sys, re
loc_path, contrib_path = sys.argv[1], sys.argv[2]
with open("README.md", encoding="utf-8") as f:
    readme = f.read()
loc_block = open(loc_path, encoding="utf-8").read().strip()
contrib_block = open(contrib_path, encoding="utf-8").read().strip()
readme = re.sub(r"(<!-- LOC-START -->\n).*?(\n<!-- LOC-END -->)", lambda m: m.group(1) + loc_block + m.group(2), readme, flags=re.S)
readme = re.sub(r"(<!-- CONTRIB-START -->\n).*?(\n<!-- CONTRIB-END -->)", lambda m: m.group(1) + contrib_block + m.group(2), readme, flags=re.S)
with open("README.md", "w", encoding="utf-8") as f:
    f.write(readme)
PY

echo "Stats refreshed."
