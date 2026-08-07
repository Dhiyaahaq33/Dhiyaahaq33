#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

OWNER="Dhiyaahaq33"
WORKDIR=$(mktemp -d)
trap 'rm -rf "$WORKDIR"' EXIT

# ---- all repos: own work + forks combined (exclude the profile repo and the padding automation repo) ----
mapfile -t OWN_REPOS < <(gh repo list "$OWNER" --limit 300 --json name,isFork \
  --jq '.[] | select(.name!="'"$OWNER"'" and .name!="daily-activity") | .name')

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
import numpy as np
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
loc_lines = ["![Total Lines of Code](loc-total.png)", "", "| Language | Lines | Share |", "|---|---|---|"]
for ext, n in top_ext:
    pct = (n * 100 / total) if total else 0
    loc_lines.append(f"| {ext} | {n} | {pct:.1f}% |")
loc_block = "\n".join(loc_lines)

# --- 3D-style pie chart (Excel-esque extruded ellipse) of the same top-10 breakdown ---
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.patches import Wedge
from matplotlib.transforms import Affine2D
import matplotlib.colors as mcolors

PALETTE = ["#4C72B0", "#DD8452", "#55A868", "#C44E52", "#8172B2",
           "#937860", "#DA8BC3", "#8C8C8C", "#CCB974", "#64B5CD"]

def draw_3d_pie(labels, sizes, colors, out_path, depth=0.09, squash=0.62):
    fig, ax = plt.subplots(figsize=(9.0, 6.4))
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

    # side "walls" for the front-facing arc, to fake extruded depth
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

    # top ellipse (squashed pie), drawn after the walls so it sits on top
    for (t1, t2, color) in wedges_info:
        w = Wedge((0, 0), 1, t2, t1, facecolor=color, edgecolor="white", linewidth=1.2, zorder=2)
        w.set_transform(Affine2D().scale(1, squash) + ax.transData)
        ax.add_patch(w)

    # labels with percentage, placed just outside the rim
    for (t1, t2, color), s in zip(wedges_info, sizes):
        mid = np.radians((t1 + t2) / 2)
        lx, ly = np.cos(mid) * 1.18, np.sin(mid) * squash * 1.18
        pct = s * 100 / total_sz if total_sz else 0
        if pct >= 1.5:
            ax.text(lx, ly, f"{pct:.1f}%", ha="center", va="center", fontsize=9, color="#e6e6e6")

    legend_handles = [plt.Rectangle((0, 0), 1, 1, color=c) for c in colors]
    ax.legend(legend_handles, labels, loc="center left", bbox_to_anchor=(1.02, 0.5),
               ncol=1, frameon=False, fontsize=11, labelcolor="#e6e6e6", handlelength=1.2, handleheight=1.2)

    fig.patch.set_alpha(0.0)
    plt.savefig(out_path, dpi=150, bbox_inches="tight", transparent=True)
    plt.close(fig)

def draw_total_banner(total_value, out_path):
    fig, ax = plt.subplots(figsize=(9.6, 2.0))
    ax.set_xlim(0, 1)
    ax.set_ylim(0, 1)
    ax.axis("off")
    fig.patch.set_facecolor("#0d1117")
    ax.add_patch(plt.Rectangle((0, 0), 1, 1, transform=ax.transAxes,
                                facecolor="#0d1117", edgecolor="#2ea043", linewidth=3))
    ax.text(0.5, 0.68, f"{total_value:,}", ha="center", va="center",
            fontsize=64, fontweight="bold", color="#3fb950", transform=ax.transAxes)
    ax.text(0.5, 0.20, "TOTAL LINES OF CODE", ha="center", va="center",
            fontsize=20, color="#e6edf3", transform=ax.transAxes,
            fontweight="bold", family="monospace")
    plt.savefig(out_path, dpi=150, bbox_inches="tight", facecolor="#0d1117")
    plt.close(fig)

draw_total_banner(total, "loc-total.png")

chart_labels = [ext for ext, _ in top_ext]
chart_sizes = [n for _, n in top_ext]
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
