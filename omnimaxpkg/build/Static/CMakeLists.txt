cmake_minimum_required(VERSION 3.0)

#Pre-target
include(${CMAKE_CURRENT_SOURCE_DIR}/../../max-api/script/max-pretarget.cmake)

#Include all Max's headers
include_directories( 
	"${C74_INCLUDES}"
)

#Actual shared library to compile
add_library( 
	${PROJECT_NAME} 
	MODULE
	${PROJECT_NAME}.cpp
)

#Post-target
include(${CMAKE_CURRENT_SOURCE_DIR}/../../max-api/script/max-posttarget.cmake)

#Fix c++14 bug with windows' MinGW not finding the /wd4814 folder... this flag was set in max-posttarget.cmake
set_target_properties(${PROJECT_NAME} PROPERTIES COMPILE_FLAGS "")

#omni.h
include_directories(${CMAKE_CURRENT_SOURCE_DIR})

#Set release build type as default
if(NOT CMAKE_BUILD_TYPE)
  set(CMAKE_BUILD_TYPE Release)
endif()

#MSVC
if(MSVC)
	#linker - not working if the omni file has been compiled with nim's MinGW, it need also to be compiled with MSVC (using the --cc:vcc flag)!
	target_link_libraries(${PROJECT_NAME} PUBLIC "${CMAKE_CURRENT_SOURCE_DIR}/libOmniSaw.a")
#Clang (MacOS) / MinGW (Windows)
else()

	#Build architecture
	#message(STATUS "BUILD ARCHITECTURE : ${BUILD_MARCH}")
	#add_definitions(-march=${BUILD_MARCH})
	message(STATUS "BUILD ARCHITECTURE : native")
	add_definitions(-march=native)

	#Set optimizer flags
	set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -O3")
	set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -O3")

	#Add linker flags
	target_link_libraries(${PROJECT_NAME} PUBLIC "-L'${CMAKE_CURRENT_SOURCE_DIR}' -lOmniSaw")
endif()