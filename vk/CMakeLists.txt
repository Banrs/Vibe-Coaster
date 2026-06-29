cmake_minimum_required(VERSION 3.16)
project(minecoaster_vk CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
if(NOT CMAKE_BUILD_TYPE)
  set(CMAKE_BUILD_TYPE Release)
endif()

find_package(Vulkan REQUIRED)

# --- compile GLSL -> SPIR-V (glslangValidator ships with the Vulkan SDK / distro) ---
find_program(GLSLANG glslangValidator)
if(NOT GLSLANG)
  message(FATAL_ERROR "glslangValidator not found (install glslang-tools)")
endif()

set(SHADER_OUT ${CMAKE_BINARY_DIR}/shaders)
file(MAKE_DIRECTORY ${SHADER_OUT})
set(SPV_FILES)
foreach(stage mesh.vert mesh.frag)
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
target_link_libraries(minecoaster_vk PRIVATE Vulkan::Vulkan)
target_include_directories(minecoaster_vk PRIVATE src)

# put the exe where it can find shaders/ at runtime
set_target_properties(minecoaster_vk PROPERTIES RUNTIME_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR})
