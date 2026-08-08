#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

OWNER="Dhiyaahaq33"

# ---- fetch external PRs as raw JSON (no jq filtering here — do it in Python below) ----
WORKDIR=$(mktemp -d)
trap 'rm -rf "$WORKDIR"' EXIT
gh api "search/issues?q=author:${OWNER}+type:pr&per_page=100" > "$WORKDIR/search_result.json" 2>/dev/null || echo '{"items":[]}' > "$WORKDIR/search_result.json"

# ---- everything else: incremental LOC via per-repo cache, filter PRs, splice into README.md ----
OWNER="$OWNER" GH_TOKEN="$GH_TOKEN" python3 - "$WORKDIR/search_result.json" README.md stats-cache.json <<'PY'
import sys, os, re, json, subprocess, tempfile, shutil
from collections import defaultdict

search_path, readme_path, cache_path = sys.argv[1], sys.argv[2], sys.argv[3]
owner = os.environ["OWNER"]
token = os.environ["GH_TOKEN"]

SKIP_EXT = (".png", ".jpg", ".jpeg", ".gif", ".ico", ".db", ".sqlite", ".sqlite3",
            ".pdf", ".docx", ".ttf", ".woff", ".woff2", ".mp4", ".zip", ".exe", ".dll", ".pyc")

def run(cmd):
    return subprocess.run(cmd, capture_output=True, text=True)

# --- repo list: own work + forks combined (exclude the profile repo and the padding automation repo) ---
out = run(["gh", "repo", "list", owner, "--limit", "300", "--json", "name,defaultBranchRef"])
all_repos = json.loads(out.stdout or "[]")
repos = [r for r in all_repos if r["name"] not in (owner, "daily-activity")]

# --- load existing per-repo cache: {repo_name: {"sha": ..., "ext_totals": {...}}} ---
if os.path.exists(cache_path):
    with open(cache_path, encoding="utf-8") as f:
        cache = json.load(f)
else:
    cache = {}

changed, unchanged = [], []
for r in repos:
    name = r["name"]
    branch = (r.get("defaultBranchRef") or {}).get("name") or "main"
    sha_out = run(["gh", "api", f"repos/{owner}/{name}/commits/{branch}", "--jq", ".sha"])
    sha = sha_out.stdout.strip()
    if not sha:
        continue
    entry = cache.get(name)
    if entry is not None and entry.get("sha") == sha:
        unchanged.append(name)
    else:
        changed.append((name, branch, sha))

print(f"{len(changed)} changed, {len(unchanged)} unchanged (cache hit)", file=sys.stderr)

workdir = tempfile.mkdtemp()
for name, branch, sha in changed:
    dest = os.path.join(workdir, name)
    url = f"https://x-access-token:{token}@github.com/{owner}/{name}.git"
    clone = run(["git", "clone", "--depth", "1", "-q", url, dest])
    ext_totals = defaultdict(int)
    if clone.returncode == 0:
        for root, dirs, files in os.walk(dest):
            if ".git" in root.split(os.sep):
                continue
            for fn in files:
                if fn.lower().endswith(SKIP_EXT):
                    continue
                path = os.path.join(root, fn)
                try:
                    with open(path, "rb") as fh:
                        n = sum(1 for _ in fh)
                except OSError:
                    continue
                if "." in fn and not fn.startswith("."):
                    ext = fn.rsplit(".", 1)[-1]
                elif fn.startswith(".") and fn.count(".") == 1:
                    ext = fn[1:]
                else:
                    ext = "(no ext)"
                ext_totals[ext] += n
    else:
        print(f"warn: failed to clone {name}", file=sys.stderr)
    cache[name] = {"sha": sha, "ext_totals": dict(ext_totals)}
shutil.rmtree(workdir, ignore_errors=True)

# drop repos that no longer exist on GitHub
live_names = {r["name"] for r in repos}
for stale in [n for n in cache if n not in live_names]:
    del cache[stale]

with open(cache_path, "w", encoding="utf-8") as f:
    json.dump(cache, f)

# --- aggregate cached per-repo totals into one Lines-of-Code breakdown ---
ext_totals = defaultdict(int)
total = 0
for entry in cache.values():
    for ext, n in entry.get("ext_totals", {}).items():
        ext_totals[ext] += n
        total += n

top_lang = sorted(ext_totals.items(), key=lambda kv: -kv[1])[:10]
total_badge = f"{total:,}".replace(",", "%2C")
badge_url = f"https://img.shields.io/badge/Total_Lines_of_Code-{total_badge}-red?style=flat-square"
loc_lines = [
    f"![Total Lines of Code]({badge_url})",
    "",
    "| Language | Lines | Share |",
    "|---|---|---|",
]
for lang, n in top_lang:
    pct = (n * 100 / total) if total else 0
    loc_lines.append(f"| {lang} | {n:,} | {pct:.1f}% |")
loc_block = "\n".join(loc_lines)

# --- 3D-style pie chart (Excel-esque extruded ellipse) of the same top-10 breakdown ---
import numpy as np
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.patches import Wedge
from matplotlib.transforms import Affine2D
import matplotlib.colors as mcolors

PALETTE = ["#4C72B0", "#DD8452", "#55A868", "#C44E52", "#8172B2",
           "#937860", "#DA8BC3", "#8C8C8C", "#CCB974", "#64B5CD"]

def draw_3d_pie(labels, sizes, colors, out_path, depth=0.09, squash=0.62):
    fig, ax = plt.subplots(figsize=(10.5, 7.2))
    ax.set_xlim(-1.25, 1.25)
    ax.set_ylim(-1.25 - depth, 1.25)
    ax.set_aspect("equal")
    ax.axis("off")

    total_sz = sum(sizes)
    wedges_info = []
    theta1 = 90.0
    for s, c in zip(sizes, colors):
        frac = s / total_sz if total_sz else 0
        theta2 = theta1 - frac * 360
        wedges_info.append((theta1, theta2, c))
        theta1 = theta2

    for (t1, t2, color) in wedges_info:
        n_samples = max(int(abs(t1 - t2)), 2)
        sample_angles = [t2 + (t1 - t2) * i / n_samples for i in range(n_samples + 1)]
        front = [a for a in sample_angles if 180 <= (a % 360) <= 360]
        if len(front) < 2:
            continue
        xs_top = [np.cos(np.radians(a)) for a in front]
        ys_top = [np.sin(np.radians(a)) * squash for a in front]
        xs_bot = xs_top[::-1]
        ys_bot = [y - depth for y in ys_top][::-1]
        dark = tuple(ch * 0.62 for ch in mcolors.to_rgb(color))
        ax.fill(xs_top + xs_bot, ys_top + ys_bot, color=dark, zorder=1, linewidth=0)

    for (t1, t2, color) in wedges_info:
        w = Wedge((0, 0), 1, t2, t1, facecolor=color, edgecolor="white", linewidth=1.2, zorder=2)
        w.set_transform(Affine2D().scale(1, squash) + ax.transData)
        ax.add_patch(w)

    for (t1, t2, color), s in zip(wedges_info, sizes):
        mid = np.radians((t1 + t2) / 2)
        lx, ly = np.cos(mid) * 1.18, np.sin(mid) * squash * 1.18
        pct = s * 100 / total_sz if total_sz else 0
        if pct >= 1.5:
            ax.text(lx, ly, f"{pct:.1f}%", ha="center", va="center", fontsize=10, color="#e6e6e6")

    legend_handles = [plt.Rectangle((0, 0), 1, 1, color=c) for c in colors]
    ax.legend(legend_handles, labels, loc="center left", bbox_to_anchor=(1.02, 0.5),
               ncol=1, frameon=False, fontsize=12, labelcolor="#e6e6e6", handlelength=1.2, handleheight=1.2)

    fig.patch.set_alpha(0.0)
    plt.savefig(out_path, dpi=150, bbox_inches="tight", transparent=True)
    plt.close(fig)

chart_labels = [lang for lang, _ in top_lang]
chart_sizes = [n for _, n in top_lang]
chart_colors = PALETTE[: len(chart_labels)]
draw_3d_pie(chart_labels, chart_sizes, chart_colors, "loc-chart.png")

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
