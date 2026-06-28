#!/bin/zsh
# Double-click to play. This is an RT-ONLY build: it requires a GPU with hardware
# ray tracing (Apple M3/M4+ today; portable to a DXR/Vulkan RT path-tracing backend
# in future). There is NO software fallback at runtime — if the GPU lacks hardware
# RT the app reports itself incompatible and exits. (The OpenGL software renderer
# remains in the repo only as a feature/shader reference, not a runtime.)
cd "$(dirname "$0")"

if [[ ! -x "./minecoaster-rt" ]]; then
  echo "minecoaster-rt not built. Build it with:  ./hwrt/build.sh"
  exit 1
fi

"./minecoaster-rt"
code=$?
# exit 3 == the GPU has no hardware ray tracing -> incompatible (no fallback).
if [[ $code -eq 3 ]]; then
  echo "INCOMPATIBLE GPU: this build requires hardware ray tracing. There is no software fallback."
fi
exit $code
