cmake_minimum_required(VERSION 3.0)

include(${CMAKE_CURRENT_SOURCE_DIR}/../../max-api/script/max-pretarget.cmake)

include_directories( 
	"${C74_INCLUDES}"
)

add_library( 
	${PROJECT_NAME} 
	MODULE
	${PROJECT_NAME}.cpp
)

include(${CMAKE_CURRENT_SOURCE_DIR}/../../max-api/script/max-posttarget.cmake)

#Release build
set(CMAKE_BUILD_TYPE Release)

#MacOS (clang) linker

if(MSVC)
	target_link_libraries(${PROJECT_NAME} PUBLIC "${CMAKE_CURRENT_SOURCE_DIR}/libOmniSaw.a")
else()
	#Set optimizer flags
	set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -O3")
	set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -O3")

	#Native
	add_definitions(-march=native)

	target_link_libraries(${PROJECT_NAME} PUBLIC "-L'${CMAKE_CURRENT_SOURCE_DIR}' -lOmniSaw")
endif()

#set(CMAKE_EXE_LINKER_FLAGS "${CMAKE_EXE_LINKER_FLAGS} /I ${CMAKE_CURRENT_SOURCE_DIR}  /ld libOmniSaw.a")
#set(CMAKE_SHARED_LINKER_FLAGS "${CMAKE_SHARED_LINKER_FLAGS} /I ${CMAKE_CURRENT_SOURCE_DIR}  /ld libOmniSaw.a")
#set(CMAKE_MODULE_LINKER_FLAGS "${CMAKE_SHARED_LINKER_FLAGS} /I ${CMAKE_CURRENT_SOURCE_DIR} /ld libOmniSaw.a")