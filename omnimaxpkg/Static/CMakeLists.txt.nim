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
		set(CMAKE_C_FLAGS_RELEASE   "-O3 -DNDEBUG -march=${BUILD_MARCH} -mtune=${BUILD_MARCH}")
		set(CMAKE_CXX_FLAGS_RELEASE "-O3 -DNDEBUG -march=${BUILD_MARCH} -mtune=${BUILD_MARCH}")
	else()
		set(CMAKE_C_FLAGS_RELEASE   "${CMAKE_C_FLAGS_RELEASE}   -O3 -DNDEBUG -march=${BUILD_MARCH} -mtune=${BUILD_MARCH}")
		set(CMAKE_CXX_FLAGS_RELEASE "${CMAKE_CXX_FLAGS_RELEASE} -O3 -DNDEBUG -march=${BUILD_MARCH} -mtune=${BUILD_MARCH}")
	endif()

	message(STATUS "RELEASE FLAGS: ${CMAKE_CXX_FLAGS_RELEASE}")

	#Build architecture.. I should get rid of this next bit, or remove it from the flags
	message(STATUS "BUILD ARCHITECTURE : ${BUILD_MARCH}")
	add_definitions(-march=${BUILD_MARCH} -mtune=${BUILD_MARCH})
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