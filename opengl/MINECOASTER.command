#!/bin/zsh
# MINECOASTER launcher: always grab the latest from GitHub, rebuild, then play.
cd "$(dirname "$0")"

# Step 1: hard-sync this checkout to the latest on GitHub, then re-exec the freshly
# pulled launcher (the guard stops it looping, and re-execing runs the *updated*
# script rather than the one that may have just been rewritten under us).
if [[ -z "$MC_LAUNCHER_UPDATED" ]]; then
    echo "==> Updating to the latest version from GitHub..."
    if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        BR=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
        if [[ -z "$BR" || "$BR" == "HEAD" ]]; then BR="main"; fi   # detached -> default to main
        if git fetch origin "$BR" 2>&1; then
            # Force the working tree to EXACTLY match the remote tip. A plain
            # `git pull --ff-only` silently no-ops when the local branch has drifted
            # (stray edit, diverged history, wrong branch) and leaves you on an old
            # build -- the reset guarantees we always run the real latest source.
            git reset --hard "origin/$BR" 2>&1 || echo "    (could not sync — playing the local version)"
        else
            echo "    (could not reach GitHub — playing the local version)"
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
