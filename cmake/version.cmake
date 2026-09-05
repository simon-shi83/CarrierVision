cmake_minimum_required(VERSION 3.21)

set(VERSION_MAJOR 5  CACHE STRING "主版本号")
set(VERSION_MINOR 0  CACHE STRING "子版本号")
set(VERSION_PATCH 0  CACHE STRING "修正号")
set(VERSION_SUFFIX "unknown" CACHE STRING "Git suffix")

#获取.git所在的文件夹
get_filename_component(GIT_ROOT_DIR "${CMAKE_CURRENT_LIST_DIR}/.." ABSOLUTE)

find_package(Git QUIET)
if(GIT_FOUND AND EXISTS "${GIT_ROOT_DIR}/.git")
    # 1. 获取从最初到现在的 commit 总数（作为“build序号”）
    execute_process(
        COMMAND ${GIT_EXECUTABLE} rev-list --count HEAD
        WORKING_DIRECTORY ${GIT_ROOT_DIR}
        OUTPUT_VARIABLE GIT_COMMIT_COUNT
        OUTPUT_STRIP_TRAILING_WHITESPACE
        RESULT_VARIABLE COUNT_RESULT
    )
    # 2. 获取当前 commit 的短 hash（默认 7 位）
    execute_process(
        COMMAND ${GIT_EXECUTABLE} rev-parse --short=7 HEAD
        WORKING_DIRECTORY ${GIT_ROOT_DIR}
        OUTPUT_VARIABLE GIT_SHORT_HASH
        OUTPUT_STRIP_TRAILING_WHITESPACE
        RESULT_VARIABLE HASH_RESULT
    )
    # 3. 检查是否有未提交改动（dirty）
    execute_process(
        COMMAND ${GIT_EXECUTABLE} diff --quiet
        WORKING_DIRECTORY ${GIT_ROOT_DIR}
        RESULT_VARIABLE DIRTY_RESULT
    )
    set(DIRTY_SUFFIX "")
    if(NOT DIRTY_RESULT EQUAL 0)
        set(DIRTY_SUFFIX "-dirty")
    endif()

    if(COUNT_RESULT EQUAL 0 AND HASH_RESULT EQUAL 0)
        set(VERSION_SUFFIX "${GIT_COMMIT_COUNT}.${GIT_SHORT_HASH}${DIRTY_SUFFIX}")
    endif()

else()
    message(WARNING "Git not found or not a git repo → version suffix = unknown")
endif()

# 最终完整版本字符串（你指定的 0.00.00.0000 风格，但第四段带点）
set(VERSION_FULL
    "${VERSION_MAJOR}.${VERSION_MINOR}.${VERSION_PATCH}.${VERSION_SUFFIX}"
    CACHE STRING "完整版本号" FORCE
)

# project() 用的标准三段版本
set(PROJECT_VERSION
    "${VERSION_MAJOR}.${VERSION_MINOR}.${VERSION_PATCH}"
    CACHE STRING "SemVer 兼容版本" FORCE
)

# 生成 version.h（供 C/C++ 代码中使用）
if(EXISTS "${CMAKE_CURRENT_LIST_DIR}/../src/version.h.in")
    configure_file(
        ${CMAKE_CURRENT_LIST_DIR}/../src/version.h.in
        ${CMAKE_CURRENT_LIST_DIR}/../src/version.h
        @ONLY
    )
endif()

