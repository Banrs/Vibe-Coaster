cmake_minimum_required(VERSION 3.16)
project(minecoaster_vk CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
if(NOT CMAKE_BUILD_TYPE)
  set(CMAKE_BUILD_TYPE Release)
endif()

find_package(Vulkan REQUIRED)

# SDL2: prefer a CMake config (vcpkg / SDL2 install — Windows, macOS); fall back to
# pkg-config (Linux distros). Sets SDL2_LINK to whatever the target/lib is.
find_package(SDL2 QUIET)
if(SDL2_FOUND AND TARGET SDL2::SDL2)
  set(SDL2_LINK SDL2::SDL2)
else()
  find_package(PkgConfig REQUIRED)
  pkg_check_modules(SDL2 REQUIRED sdl2)
  set(SDL2_LINK ${SDL2_LIBRARIES})
endif()

# --- compile GLSL -> SPIR-V (glslangValidator ships with the Vulkan SDK / distro) ---
find_program(GLSLANG glslangValidator)
if(NOT GLSLANG)
  message(FATAL_ERROR "glslangValidator not found (install glslang-tools)")
endif()

set(SHADER_OUT ${CMAKE_BINARY_DIR}/shaders)
file(MAKE_DIRECTORY ${SHADER_OUT})
set(SPV_FILES)
foreach(stage mesh.vert mesh.frag fullscreen.vert bloom.frag post.frag)
  add_custom_command(
    OUTPUT ${SHADER_OUT}/${stage}.spv
    COMMAND ${GLSLANG} -V ${CMAKE_CURRENT_SOURCE_DIR}/shaders/${stage} -o ${SHADER_OUT}/${stage}.spv
    MAIN_DEPENDENCY ${CMAKE_CURRENT_SOURCE_DIR}/shaders/${stage}
    COMMENT "glslang ${stage}" VERBATIM)
  list(APPEND SPV_FILES ${SHADER_OUT}/${stage}.spv)
endforeach()
add_custom_target(vk_shaders ALL DEPENDS ${SPV_FILES})

add_executable(minecoaster_vk src/main.cpp)
add_dependencies(minecoaster_vk vk_shaders)
target_link_libraries(minecoaster_vk PRIVATE Vulkan::Vulkan ${SDL2_LINK})
target_include_directories(minecoaster_vk PRIVATE src ${SDL2_INCLUDE_DIRS})

# put the exe where it can find shaders/ at runtime
set_target_properties(minecoaster_vk PROPERTIES RUNTIME_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR})

# copy compiled shaders next to the executable so it finds shaders/ from anywhere
add_custom_command(TARGET minecoaster_vk POST_BUILD
  COMMAND ${CMAKE_COMMAND} -E make_directory "$<TARGET_FILE_DIR:minecoaster_vk>/shaders"
  COMMAND ${CMAKE_COMMAND} -E copy_directory "${SHADER_OUT}" "$<TARGET_FILE_DIR:minecoaster_vk>/shaders"
  VERBATIM)
