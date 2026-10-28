vcpkg_from_github(
    OUT_SOURCE_PATH SOURCE_PATH
    REPO OpenMathLib/OpenBLAS
    REF "v${VERSION}"
    SHA512 b40b5a3b5062ea196b3e48363db584ef91aef21c61becf4f4d6616ba5e413d770c22445c357d06dcf0992dd4666c18cced44cd5d09d8cb884c0d8f62e6940422
    HEAD_REF develop
    PATCHES
        disable-testing.diff
        getarch.diff
        system-check-msvc.diff
        win32-uwp.diff
        android-exclude-sme.diff
        arm64-generic-omatcopy.diff # https://github.com/OpenMathLib/OpenBLAS/pull/5977
)

vcpkg_check_features(OUT_FEATURE_OPTIONS OPTIONS
    FEATURES
        threads        USE_THREAD
        simplethread   USE_SIMPLE_THREADED_LEVEL3
        dynamic-arch   DYNAMIC_ARCH
)

# If not explicitly configured for a cross build, OpenBLAS wants to run
# getarch executables in order to optimize for the target.
# Adapting this to vcpkg triplets:
# - install-getarch.diff introduces and uses GETARCH_BINARY_DIR,
# - architecture and system name are required to match for GETARCH_BINARY_DIR, but
# - uwp (aka WindowsStore) may run windows getarch.
string(REPLACE "WindowsStore_" "_" SYSTEM_KEY "${VCPKG_CMAKE_SYSTEM_NAME}_${VCPKG_TARGET_ARCHITECTURE}")
set(GETARCH_BINARY_DIR "${CURRENT_HOST_INSTALLED_DIR}/manual-tools/${PORT}/${SYSTEM_KEY}")
if(EXISTS "${GETARCH_BINARY_DIR}")
    message(STATUS "OpenBLAS cross build, but may use ${PORT}:${HOST_TRIPLET} getarch")
    list(APPEND OPTIONS "-DGETARCH_BINARY_DIR=${GETARCH_BINARY_DIR}")
elseif(VCPKG_CROSSCOMPILING)
    message(STATUS "OpenBLAS cross build, may not be able to use getarch")
else()
    message(STATUS "OpenBLAS native build")
endif()

if(VCPKG_TARGET_IS_EMSCRIPTEN)
    # Only the riscv64 kernel with riscv64_generic target is supported.
    # Cf. https://github.com/OpenMathLib/OpenBLAS/issues/3640#issuecomment-1144029630 et al.
    list(APPEND OPTIONS
        -DEMSCRIPTEN_SYSTEM_PROCESSOR=riscv64
        -DTARGET=RISCV64_GENERIC
    )
endif()

if("clang-cl" IN_LIST FEATURES)
    # MSVC cannot compile the inline assembly in the optimized kernels, so
    # build with clang-cl, which is ABI-compatible with MSVC, instead.
    vcpkg_find_acquire_program(CLANG)
    cmake_path(GET CLANG PARENT_PATH CLANG_DIR)
    find_program(CLANG_CL NAMES clang-cl PATHS "${CLANG_DIR}" NO_DEFAULT_PATH REQUIRED)
    list(APPEND OPTIONS "-DCMAKE_C_COMPILER=${CLANG_CL}")
    # Recent clang turns incompatible pointer types, which some kernels
    # (e.g. the SKYLAKEX prefetch intrinsics) have, into errors.
    string(APPEND VCPKG_C_FLAGS " -Wno-error=incompatible-pointer-types -w")
    string(APPEND VCPKG_CXX_FLAGS "")
    if(VCPKG_TARGET_ARCHITECTURE STREQUAL "x64")
        list(TRANSFORM OPTIONS REPLACE "^-DDYNAMIC_ARCH=OFF$" "-DDYNAMIC_ARCH=ON")
    elseif(VCPKG_TARGET_ARCHITECTURE STREQUAL "arm64")
        # There is no runtime CPU detection for arm64 on Windows.
        list(APPEND OPTIONS -DTARGET=ARMV8)
    endif()
endif()

vcpkg_cmake_configure(
    SOURCE_PATH "${SOURCE_PATH}"
    OPTIONS
        ${OPTIONS}
        "-DCMAKE_PROJECT_INCLUDE=${CURRENT_PORT_DIR}/cmake-project-include.cmake"
        -DBUILD_TESTING=OFF
        -DBUILD_WITHOUT_LAPACK=ON
        -DNOFORTRAN=ON
    MAYBE_UNUSED_VARIABLES
        GETARCH_BINARY_DIR
)

vcpkg_cmake_install()
vcpkg_copy_pdbs()
vcpkg_cmake_config_fixup(CONFIG_PATH lib/cmake/OpenBLAS)

#fix for libm linking on non-windows platforms
if(NOT VCPKG_TARGET_IS_WINDOWS)
    foreach(PCFILE IN ITEMS
        "${CURRENT_PACKAGES_DIR}/lib/pkgconfig/openblas.pc"
        "${CURRENT_PACKAGES_DIR}/debug/lib/pkgconfig/openblas.pc")
        if(EXISTS "${PCFILE}")
            file(APPEND "${PCFILE}" "Libs.private: -lm\n")
        endif()
    endforeach()
endif()

vcpkg_fixup_pkgconfig()

# Required from native builds, optional from cross builds.
if(NOT VCPKG_CROSSCOMPILING OR EXISTS "${CURRENT_PACKAGES_DIR}/bin/getarch${VCPKG_TARGET_EXECUTABLE_SUFFIX}")
    vcpkg_copy_tools(
        TOOL_NAMES getarch getarch_2nd
        DESTINATION "${CURRENT_PACKAGES_DIR}/manual-tools/${PORT}/${SYSTEM_KEY}"
        AUTO_CLEAN
    )
endif()

file(REMOVE_RECURSE "${CURRENT_PACKAGES_DIR}/debug/include" "${CURRENT_PACKAGES_DIR}/debug/share")

vcpkg_install_copyright(FILE_LIST "${SOURCE_PATH}/LICENSE")
