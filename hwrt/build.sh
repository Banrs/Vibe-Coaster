#!/bin/zsh
# Build BOTH hardware ray-traced executables into mythostest/:
#   minecoaster-rt            -> NEW: infinite streaming generator (default; MINECOASTER.command)
#   minecoaster-rt-benchmark  -> the pre-generated demo map (hwrt/track.txt); --bench fps mode
# (Benign stb sprintf deprecation warning is expected — ignore it.)
set -e
cd "$(dirname "$0")"

FRAMEWORKS=(-framework Metal -framework QuartzCore -framework Cocoa \
  -framework Foundation -framework AVFoundation -framework CoreAudio)

echo "building minecoaster-rt (infinite streaming generator)..."
clang++ -std=c++17 -O2 -DRT_STREAM -x objective-c++ main.mm -o ../minecoaster-rt \
  "${FRAMEWORKS[@]}" -fobjc-arc

echo "building minecoaster-rt-benchmark (pre-generated demo map)..."
clang++ -std=c++17 -O2 -x objective-c++ main.mm -o ../minecoaster-rt-benchmark \
  "${FRAMEWORKS[@]}" -fobjc-arc

echo "built minecoaster-rt + minecoaster-rt-benchmark"
