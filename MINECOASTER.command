#!/bin/zsh
# Double-click to play. Launches the hardware ray-traced renderer (default);
# if that binary is missing or the GPU has no hardware RT, falls back to the
# software (OpenGL) renderer.
cd "$(dirname "$0")"

RT="./minecoaster-rt"   # hardware ray tracing (default)
SW="./minecoaster"      # software OpenGL renderer (fallback / backup)

if [[ -x "$RT" ]]; then
  "$RT"
  code=$?
  # exit 3 == GPU lacks hardware raytracing -> fall back to the software build
  if [[ $code -eq 3 ]]; then
    echo "hardware RT unavailable; falling back to software renderer"
    exec "$SW"
  fi
  exit $code
fi

echo "minecoaster-rt not built; launching software renderer"
exec "$SW"
