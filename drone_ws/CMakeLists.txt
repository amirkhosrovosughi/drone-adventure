cmake_minimum_required(VERSION 3.5)
project(drone_adventure_docs NONE)

find_package(Doxygen)

if(DOXYGEN_FOUND)
  set(DOXYFILE_IN ${CMAKE_SOURCE_DIR}/Doxyfile.in)
  set(DOXYFILE_OUT ${CMAKE_BINARY_DIR}/Doxyfile)

  configure_file(${DOXYFILE_IN} ${DOXYFILE_OUT} @ONLY)

  add_custom_target(doc_doxygen
    COMMAND ${DOXYGEN_EXECUTABLE} ${DOXYFILE_OUT}
    WORKING_DIRECTORY ${CMAKE_SOURCE_DIR}
    COMMENT "Generating API documentation with Doxygen"
    VERBATIM
  )
endif()
