cmake_minimum_required(VERSION 3.20)
project(MotionTextEngine VERSION 0.3.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_WINDOWS_EXPORT_ALL_SYMBOLS OFF)

find_package(OpenCV REQUIRED COMPONENTS core imgproc video videoio photo calib3d)

add_library(MotionTextEngine SHARED src/MotionTextEngine.cpp)

target_include_directories(MotionTextEngine
    PUBLIC ${CMAKE_CURRENT_SOURCE_DIR}/include
    PRIVATE ${OpenCV_INCLUDE_DIRS}
)
target_link_libraries(MotionTextEngine PRIVATE ${OpenCV_LIBS})
target_compile_definitions(MotionTextEngine PRIVATE MTE_BUILD_DLL)
target_compile_options(MotionTextEngine PRIVATE
    $<$<CXX_COMPILER_ID:MSVC>:/W4>
    $<$<CXX_COMPILER_ID:MSVC>:/permissive->
    $<$<NOT:$<CXX_COMPILER_ID:MSVC>>:-Wall>
    $<$<NOT:$<CXX_COMPILER_ID:MSVC>>:-Wextra>
    $<$<NOT:$<CXX_COMPILER_ID:MSVC>>:-Wpedantic>
)
set_target_properties(MotionTextEngine PROPERTIES
    OUTPUT_NAME "MotionTextEngine"
    WINDOWS_EXPORT_ALL_SYMBOLS OFF
)
