#!/bin/zsh
# Build the hardware ray-traced renderer -> mythostest/minecoaster-rt
set -e
cd "$(dirname "$0")"
clang++ -std=c++17 -O2 -x objective-c++ main.mm -o ../minecoaster-rt \
  -framework Metal -framework QuartzCore -framework Cocoa -framework Foundation -fobjc-arc
echo "built minecoaster-rt"
