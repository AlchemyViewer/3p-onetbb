#!/usr/bin/env bash

cd "$(dirname "$0")"

set -eux

TBB_SOURCE_DIR="onetbb"

top="$(pwd)"
stage="$top"/stage

# load autobuild provided shell functions and variables
case "$AUTOBUILD_PLATFORM" in
    windows*)
        autobuild="$(cygpath -u "$AUTOBUILD")"
    ;;
    *)
        autobuild="$AUTOBUILD"
    ;;
esac
source_environment_tempfile="$stage/source_environment.sh"
"$autobuild" source_environment > "$source_environment_tempfile"
. "$source_environment_tempfile"

# remove_cxxstd apply_patch
source "$(dirname "$AUTOBUILD_VARIABLES_FILE")/functions"

pushd "$TBB_SOURCE_DIR"
    case "$AUTOBUILD_PLATFORM" in

        # ------------------------ windows, windows64 ------------------------
        windows*)
            load_vsvars

            mkdir -p "build_debug"
            pushd "build_debug"
                opts="$LL_BUILD_DEBUG"
                opts="$(remove_switch /DUNICODE $opts)"
                opts="$(remove_switch /D_UNICODE $opts)"
                plainopts="$(remove_switch /GR $(remove_cxxstd $opts))"

                cmake -G "$AUTOBUILD_WIN_CMAKE_GEN" -A "$AUTOBUILD_WIN_VSPLATFORM" .. -DTBB_TEST=OFF \
                        -DCMAKE_CONFIGURATION_TYPES="Debug" \
                        -DCMAKE_C_FLAGS_DEBUG="$plainopts" \
                        -DCMAKE_CXX_FLAGS_DEBUG="$opts /EHsc" \
                        -DCMAKE_MSVC_DEBUG_INFORMATION_FORMAT="ProgramDatabase" \
                        -DCMAKE_INSTALL_PREFIX="$(cygpath -m $stage)" \
                        -DCMAKE_INSTALL_LIBDIR="$(cygpath -m "$stage/lib/debug")" \
                        -DCMAKE_INSTALL_BINDIR="$(cygpath -m "$stage/lib/debug")"

                cmake --build . --config Debug --parallel $AUTOBUILD_CPU_COUNT
                cmake --install . --config Debug

                # conditionally run unit tests
                if [ "${DISABLE_UNIT_TESTS:-0}" = "0" ]; then
                    ctest -C Debug --parallel $AUTOBUILD_CPU_COUNT
                fi
            popd

            mkdir -p "build_release"
            pushd "build_release"
                opts="$LL_BUILD_RELEASE"
                opts="$(remove_switch /DUNICODE $opts)"
                opts="$(remove_switch /D_UNICODE $opts)"
                plainopts="$(remove_switch /GR $(remove_cxxstd $opts))"

                cmake -G "$AUTOBUILD_WIN_CMAKE_GEN" -A "$AUTOBUILD_WIN_VSPLATFORM" .. -DTBB_TEST=OFF \
                        -DCMAKE_CONFIGURATION_TYPES="Release" \
                        -DCMAKE_C_FLAGS="$plainopts" \
                        -DCMAKE_CXX_FLAGS="$opts /EHsc" \
                        -DCMAKE_MSVC_DEBUG_INFORMATION_FORMAT="ProgramDatabase" \
                        -DCMAKE_INSTALL_PREFIX="$(cygpath -m $stage)" \
                        -DCMAKE_INSTALL_LIBDIR="$(cygpath -m "$stage/lib/release")" \
                        -DCMAKE_INSTALL_BINDIR="$(cygpath -m "$stage/lib/release")"

                cmake --build . --config Release --parallel $AUTOBUILD_CPU_COUNT
                cmake --install . --config Release

                # conditionally run unit tests
                if [ "${DISABLE_UNIT_TESTS:-0}" = "0" ]; then
                    ctest -C Release --parallel $AUTOBUILD_CPU_COUNT
                fi
            popd
        ;;

        # ------------------------- darwin, darwin64 -------------------------
        darwin*)
            export MACOSX_DEPLOYMENT_TARGET="$LL_BUILD_DARWIN_DEPLOY_TARGET"

            for arch in x86_64 arm64 ; do
                ARCH_ARGS="-arch $arch"
                cc_opts="${TARGET_OPTS:-$ARCH_ARGS $LL_BUILD_RELEASE}"
                cc_opts="$(remove_cxxstd $cc_opts)"
                ld_opts="$ARCH_ARGS"

                mkdir -p "build_$arch"
                pushd "build_$arch"
                    CFLAGS="$cc_opts" \
                    LDFLAGS="$ld_opts" \
                    cmake .. -G "Xcode" -DTBB_TEST=OFF \
                        -DCMAKE_CONFIGURATION_TYPES="Release" \
                        -DCMAKE_C_FLAGS="$cc_opts" \
                        -DCMAKE_CXX_FLAGS="$cc_opts" \
                        -DCMAKE_INSTALL_PREFIX="$stage" \
                        -DCMAKE_INSTALL_LIBDIR="$stage/lib/release/$arch" \
                        -DCMAKE_INSTALL_BINDIR="$stage/lib/release/$arch" \
                        -DCMAKE_OSX_ARCHITECTURES="$arch" \
                        -DCMAKE_OSX_DEPLOYMENT_TARGET=${MACOSX_DEPLOYMENT_TARGET}

                    cmake --build . --config Release --parallel $AUTOBUILD_CPU_COUNT
                    cmake --install . --config Release

                    # conditionally run unit tests
                    if [ "${DISABLE_UNIT_TESTS:-0}" = "0" ]; then
                        ctest -C Release --parallel $AUTOBUILD_CPU_COUNT
                    fi
                popd
            done

            lipo -create -output "$stage/lib/release/libz.a" "$stage/lib/release/x86_64/libz.a" "$stage/lib/release/arm64/libz.a"
        ;;

        # -------------------------- linux, linux64 --------------------------
        linux*)
            # Default target per autobuild build --address-size
            opts="${TARGET_OPTS:--m$AUTOBUILD_ADDRSIZE $LL_BUILD_RELEASE}"

            # Release
            mkdir -p "build"
            pushd "build"
                cmake .. -GNinja -DTBB_TEST=OFF \
                    -DCMAKE_BUILD_TYPE="Release" \
                    -DCMAKE_C_FLAGS="$(remove_cxxstd $opts)" \
                    -DCMAKE_CXX_FLAGS="$opts" \
                    -DCMAKE_INSTALL_PREFIX="$stage" \
                    -DCMAKE_INSTALL_LIBDIR="$stage/lib/release" \
                    -DCMAKE_INSTALL_BINDIR="$stage/lib/release"

                cmake --build . --config Release
                cmake --install . --config Release

                # conditionally run unit tests
                if [ "${DISABLE_UNIT_TESTS:-0}" = "0" ]; then
                    ctest -C Release --parallel $AUTOBUILD_CPU_COUNT
                fi
            popd
        ;;
    esac

    mkdir -p "$stage/LICENSES"
    cp LICENSE.txt "$stage/LICENSES/onetbb.txt"
popd
