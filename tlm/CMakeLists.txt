cmake_minimum_required(VERSION 3.16)
project(sc_hub_tlm_python NONE)

find_package(Python3 COMPONENTS Interpreter REQUIRED)

add_custom_target(
    run_all
    COMMAND ${CMAKE_CURRENT_SOURCE_DIR}/scripts/run_all.sh
    WORKING_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}
    COMMENT "Run the Python slow-control hub TLM harness"
)
