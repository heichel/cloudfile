cmake_minimum_required(VERSION 3.15)
project(CloudFileCli LANGUAGES OBJC)

set(CMAKE_C_STANDARD 99)
set(CMAKE_OBJC_STANDARD 11)

# Define the executable
add_executable(cloudfile src/main.m src/cloudfile.m)

# Link required frameworks
find_library(FOUNDATION_FRAMEWORK Foundation REQUIRED)
find_library(FILEPROVIDER_FRAMEWORK FileProvider REQUIRED)

target_link_libraries(cloudfile ${FOUNDATION_FRAMEWORK} ${FILEPROVIDER_FRAMEWORK})

