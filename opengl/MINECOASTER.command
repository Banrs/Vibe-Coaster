#!/bin/zsh
# MINECOASTER launcher: always grab the latest from GitHub, rebuild, then play.
cd "$(dirname "$0")"

# The branch that carries the live coaster work. `git pull` alone pulls whatever
# branch the checkout happens to be on (often `main`, which is behind), so the game
# silently ran an old build. Pin the launcher to this branch and hard-sync to it.
MC_BRANCH="claude/vulkan-port-alpha-pkif4h"

# Step 1: update from GitHub, then re-exec the freshly-pulled launcher (the guard
# stops it looping, and re-execing means we build/run the *updated* script, not the
# one that may have just been rewritten under us by the pull).
if [[ -z "$MC_LAUNCHER_UPDATED" ]]; then
    echo "==> Updating to the latest version from GitHub ($MC_BRANCH)..."
    if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        # Fetch just that branch and force the working tree to exactly match it.
        # -f discards any local build junk / stray edits so the sync can't be blocked;
        # -B (re)points the local branch at the freshly fetched remote tip.
        if git fetch origin "$MC_BRANCH" 2>&1; then
            git checkout -f -B "$MC_BRANCH" "origin/$MC_BRANCH" 2>&1 \
                || echo "    (could not switch to $MC_BRANCH — playing the local version instead)"
        else
            echo "    (could not reach GitHub — playing the local version instead)"
        fi
    else
        echo "    (not a git checkout — playing the local version)"
    fi
    export MC_LAUNCHER_UPDATED=1
    exec "$0"
fi

# Step 2: build the latest source and launch.
echo "==> Building..."
./build.sh || { echo "Build failed."; exit 1; }

echo "==> Launching MINECOASTER"
exec ./minecoaster
