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

# ---- fetch external PRs as raw JSON (no jq filtering here — do it in Python below) ----
gh api "search/issues?q=author:${OWNER}+type:pr&per_page=100" > "$WORKDIR/search_result.json" 2>/dev/null || echo '{"items":[]}' > "$WORKDIR/search_result.json"

# ---- everything else: compute LOC breakdown, filter PRs, splice into README.md ----
OWNER="$OWNER" python3 - "$WORKDIR/all_lines.txt" "$WORKDIR/search_result.json" README.md <<'PY'
import sys, os, re, json
from collections import defaultdict

lines_path, search_path, readme_path = sys.argv[1], sys.argv[2], sys.argv[3]
owner = os.environ["OWNER"]

# --- Lines of Code ---
ext_totals = defaultdict(int)
total = 0
with open(lines_path, encoding="utf-8", errors="replace") as f:
    for line in f:
        line = line.rstrip("\n")
        if not line.strip():
            continue
        parts = line.strip().split(None, 1)
        if len(parts) != 2:
            continue
        try:
            n = int(parts[0])
        except ValueError:
            continue
        path = parts[1]
        fname = path.rsplit("/", 1)[-1]
        if "." in fname and not fname.startswith("."):
            ext = fname.rsplit(".", 1)[-1]
        elif fname.startswith(".") and fname.count(".") == 1:
            ext = fname[1:]
        else:
            ext = "(no ext)"
        ext_totals[ext] += n
        total += n

top_ext = sorted(ext_totals.items(), key=lambda kv: -kv[1])[:10]
loc_lines = [f"**{total:,} total**", "", "| Language | Lines | Share |", "|---|---|---|"]
for ext, n in top_ext:
    pct = (n * 100 / total) if total else 0
    loc_lines.append(f"| {ext} | {n} | {pct:.1f}% |")
loc_block = "\n".join(loc_lines)

# --- External contributions ---
with open(search_path, encoding="utf-8") as f:
    search_data = json.load(f)
items = search_data.get("items", []) if isinstance(search_data, dict) else []

merged, open_repos = [], defaultdict(int)
for it in items:
    if not isinstance(it, dict):
        continue
    repo_url = it.get("repository_url", "")
    parts = repo_url.rstrip("/").split("/")
    if len(parts) < 2:
        continue
    repo_owner, repo_name = parts[-2], parts[-1]
    if repo_owner == owner:
        continue
    full_repo = f"{repo_owner}/{repo_name}"
    pr = it.get("pull_request") or {}
    is_merged = pr.get("merged_at") is not None
    if is_merged:
        merged.append((full_repo, it.get("html_url", ""), it.get("title", "")))
    else:
        open_repos[full_repo] += 1

contrib_lines = []
if merged:
    entries = ", ".join(f"[{repo}]({url}) — {title}" for repo, url, title in merged)
    contrib_lines.append(f"**Merged ({len(merged)}):** {entries}")
else:
    contrib_lines.append("**Merged (0):** none yet.")
contrib_lines.append("")
if open_repos:
    entries = ", ".join(
        f"[{repo}](https://github.com/{repo}/pulls)" + (f" (x{count})" if count > 1 else "")
        for repo, count in sorted(open_repos.items())
    )
    contrib_lines.append(f"**Open / pending review ({sum(open_repos.values())}):** {entries}")
else:
    contrib_lines.append("**Open / pending review (0):** none.")
contrib_block = "\n".join(contrib_lines)

# --- splice into README.md ---
with open(readme_path, encoding="utf-8") as f:
    readme = f.read()
readme = re.sub(r"(<!-- LOC-START -->\n).*?(\n<!-- LOC-END -->)", lambda m: m.group(1) + loc_block + m.group(2), readme, flags=re.S)
readme = re.sub(r"(<!-- CONTRIB-START -->\n).*?(\n<!-- CONTRIB-END -->)", lambda m: m.group(1) + contrib_block + m.group(2), readme, flags=re.S)
with open(readme_path, "w", encoding="utf-8") as f:
    f.write(readme)

print("Stats refreshed.")
PY
