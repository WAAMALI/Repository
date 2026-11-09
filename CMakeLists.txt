cmake_minimum_required(VERSION 3.21)
project(MotionTextEngine VERSION 0.3.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>DLL")

find_package(OpenCV REQUIRED COMPONENTS core imgproc video videoio photo calib3d)
find_path(TESSERACT_INCLUDE_DIR tesseract/baseapi.h REQUIRED)
find_library(TESSERACT_LIBRARY NAMES tesseract54 tesseract53 tesseract52 tesseract51 tesseract REQUIRED)
find_library(LEPTONICA_LIBRARY NAMES leptonica-6 leptonica-5 leptonica REQUIRED)

add_library(MotionTextEngine SHARED src/MotionTextEngine.cpp)
target_include_directories(MotionTextEngine PUBLIC ${CMAKE_CURRENT_SOURCE_DIR}/include PRIVATE ${TESSERACT_INCLUDE_DIR})
target_link_libraries(MotionTextEngine PRIVATE ${TESSERACT_LIBRARY} ${LEPTONICA_LIBRARY})
target_link_libraries(MotionTextEngine PRIVATE ${OpenCV_LIBS})
target_compile_definitions(MotionTextEngine PRIVATE MTE_BUILD_DLL)
set_target_properties(MotionTextEngine PROPERTIES OUTPUT_NAME "MotionTextEngine")

add_executable(MotionText src/main.cpp)
target_include_directories(MotionText PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/include)
target_link_libraries(MotionText PRIVATE MotionTextEngine)
set_target_properties(MotionText PROPERTIES OUTPUT_NAME "MotionText")
