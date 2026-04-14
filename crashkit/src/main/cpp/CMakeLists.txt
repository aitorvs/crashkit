# For more information about using CMake with Android Studio, read the
# documentation: https://d.android.com/studio/projects/add-native-code.html

# Sets the minimum version of CMake required to build the native library.

cmake_minimum_required(VERSION 3.18.1)

# Creates and names a library, sets it as either STATIC
# or SHARED, and provides the relative paths to its source code.
# You can define multiple libraries, and CMake builds them for you.
# Gradle automatically packages shared libraries with your APK.
# --- Crashpad locations (relative to this CMakeLists in src/main/cpp) ---
# CMAKE_CURRENT_LIST_DIR == crashkit/src/main/cpp
set(CRASHPAD_ROOT ${CMAKE_CURRENT_LIST_DIR}/crashpad)
set(CRASHPAD_LIB_DIR  ${CRASHPAD_ROOT}/lib/${ANDROID_ABI})
set(CRASHPAD_INC_DIR  ${CRASHPAD_ROOT}/include)
set(MINI_INC_DIR      ${CRASHPAD_ROOT}/include/third_party/mini_chromium/mini_chromium)

add_library( # Sets the name of the library.
             crashkit

             # Sets the library as a shared library.
             SHARED

             # Provides a relative path to your source file(s).
             process.cpp
             native-bridge.cpp )

# Crashpad Libraries
add_library(crashpad_client_common STATIC IMPORTED)
set_property(TARGET crashpad_client_common PROPERTY IMPORTED_LOCATION ${CRASHPAD_LIB_DIR}/client/libcommon.a)

add_library(crashpad_client STATIC IMPORTED)
set_property(TARGET crashpad_client PROPERTY IMPORTED_LOCATION ${CRASHPAD_LIB_DIR}/client/libclient.a)

add_library(crashpad_util STATIC IMPORTED)
set_property(TARGET crashpad_util PROPERTY IMPORTED_LOCATION ${CRASHPAD_LIB_DIR}/util/libutil.a)

add_library(base STATIC IMPORTED)
set_property(TARGET base PROPERTY IMPORTED_LOCATION ${CRASHPAD_LIB_DIR}/base/libbase.a)

# Crashpad Headers
include_directories(${CRASHPAD_INC_DIR} ${MINI_INC_DIR})

# Searches for a specified prebuilt library and stores the path as a
# variable. Because CMake includes system libraries in the search path by
# default, you only need to specify the name of the public NDK library
# you want to add. CMake verifies that the library exists before
# completing its build.

find_library( # Sets the name of the path variable.
              log-lib

              # Specifies the name of the NDK library that
              # you want CMake to locate.
              log
            )

find_library(cpp_shared c++_shared)


# Specifies libraries CMake should link to your target library. You
# can link multiple libraries, such as libraries you define in this
# build script, prebuilt third-party libraries, or system libraries.

target_link_libraries(# Specifies the target library.
                       crashkit
#                       c++_shared
                        dl
                        z
                       # Links the target library to the log library
                       # included in the NDK.
                       ${log-lib}
#                       ${cpp_shared}
                        crashpad_client_common
                        crashpad_client
                        crashpad_util
                        base
        )

# Strongly recommended to resolve circular deps among the static libs
target_link_options(crashkit PRIVATE -Wl,--export-dynamic)

target_link_options(
  crashkit
  PRIVATE
  "-Wl,-z,common-page-size=16384"
  "-Wl,-z,max-page-size=16384"
  "-Wl,--no-whole-archive"
)
