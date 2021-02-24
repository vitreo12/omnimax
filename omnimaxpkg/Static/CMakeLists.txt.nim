# MIT License
# 
# Copyright (c) 2020-2021 Francesco Cameli
# 
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
# 
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
# 
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

var OMNI_PROTO_CMAKE = """
cmake_minimum_required(VERSION 3.0)

#Set release build type as default
if(NOT CMAKE_BUILD_TYPE)
  set(CMAKE_BUILD_TYPE "Release")
endif()

#If not defined api folder
if (NOT DEFINED C74_MAX_API_DIR)
	set(C74_MAX_API_DIR ${CMAKE_CURRENT_SOURCE_DIR}/../../max-api)
endif ()

#Pre-target
include(${C74_MAX_API_DIR}/script/max-pretarget.cmake)

#Set output directory
set(CMAKE_LIBRARY_OUTPUT_DIRECTORY ${OMNI_BUILD_DIR})
set(CMAKE_LIBRARY_OUTPUT_DIRECTORY_RELEASE ${OMNI_BUILD_DIR})

#Include all Max's headers
include_directories(${C74_INCLUDES})

#omni.h
include_directories(${OMNI_BUILD_DIR})

if(NOT MSVC)
	#Override MSVC release flags (set at the beginning of pretarget)
	if(WIN32)
		set(CMAKE_C_FLAGS_RELEASE   "-O3 -DNDEBUG -march=${BUILD_MARCH}")
		set(CMAKE_CXX_FLAGS_RELEASE "-O3 -DNDEBUG -march=${BUILD_MARCH}")
	else()
		set(CMAKE_C_FLAGS_RELEASE   "${CMAKE_C_FLAGS_RELEASE}   -O3 -DNDEBUG -march=${BUILD_MARCH}")
		set(CMAKE_CXX_FLAGS_RELEASE "${CMAKE_CXX_FLAGS_RELEASE} -O3 -DNDEBUG -march=${BUILD_MARCH}")
	endif()

	#Build architecture.. I should get rid of this next bit, or remove it from the flags
	message(STATUS "BUILD ARCHITECTURE : ${BUILD_MARCH}")
	add_definitions(-march=${BUILD_MARCH})

	#If native, also add mtune=native
	if (BUILD_MARCH STREQUAL "native")
		set(CMAKE_C_FLAGS_RELEASE   "${CMAKE_C_FLAGS_RELEASE} -mtune=native")
		set(CMAKE_CXX_FLAGS_RELEASE "${CMAKE_CXX_FLAGS_RELEASE} -mtune=native")
		add_definitions(-mtune=native)
	endif()
endif()

#Actual shared library to compile
add_library( 
	${PROJECT_NAME} 
	MODULE
	${PROJECT_NAME}.cpp
)

#Post-target
include(${C74_MAX_API_DIR}/script/max-posttarget.cmake)

#MSVC
if(MSVC)
	#linker - not working if the omni file has been compiled with nim's MinGW, it need also to be compiled with MSVC (using the --cc:vcc flag)!
	target_link_libraries(${PROJECT_NAME} PUBLIC "${OMNI_BUILD_DIR}/lib${OMNI_LIB_NAME}.a")

#Clang (MacOS) / MinGW (Windows)
else()
	if(WIN32)
		#Fix c++14 bug with windows' MinGW not finding the /wd4814 folder... this flag was set in max-posttarget.cmake
		set_target_properties(${PROJECT_NAME} PROPERTIES COMPILE_FLAGS "")

		#Fix /INCREMENTAL:NO for MinGW
		set_target_properties(${PROJECT_NAME} PROPERTIES LINK_FLAGS "")
	endif()

	#Add linker flags
	target_link_libraries(${PROJECT_NAME} PUBLIC "-fPIC -L'${OMNI_BUILD_DIR}' -l${OMNI_LIB_NAME}")
endif()
"""