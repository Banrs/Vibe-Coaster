cmake_minimum_required(VERSION 3.16)
project(minecoaster CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
if(NOT CMAKE_BUILD_TYPE)
  set(CMAKE_BUILD_TYPE Release)
endif()

include(FetchContent)
set(BUILD_EXAMPLES OFF CACHE BOOL "" FORCE)
set(BUILD_GAMES    OFF CACHE BOOL "" FORCE)
FetchContent_Declare(
  raylib
  GIT_REPOSITORY https://github.com/raysan5/raylib.git
  GIT_TAG 5.5
)
FetchContent_MakeAvailable(raylib)

# Track V2 rewrite modules (opengl/COASTER_REWRITE.md). Separate translation
# units on purpose: V2 escapes the V1 unity build and depends only on raymath.
set(V2_TRACK_SOURCES
  src/track/track_math.cpp
  src/track/track_primitives.cpp
  src/track/track_planner.cpp
  src/track/track_terrain.cpp
  src/track/track_validate.cpp
  src/track/track_v2.cpp)

add_executable(minecoaster src/main.cpp ${V2_TRACK_SOURCES})
target_link_libraries(minecoaster raylib)

set_target_properties(minecoaster PROPERTIES
  RUNTIME_OUTPUT_DIRECTORY ${CMAKE_SOURCE_DIR})

# Standalone V2 acceptance harness (no window; exit 0 == pass). Run after
# every track change: build, then ./v2track_tests from opengl/build.
add_executable(v2track_tests src/track/track_tests.cpp ${V2_TRACK_SOURCES})
target_link_libraries(v2track_tests raylib)
