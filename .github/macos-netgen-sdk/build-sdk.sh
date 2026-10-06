#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "usage: $0 <arm64|x86_64> <runner-label>" >&2
  exit 2
fi
architecture="$1"
runner_label="$2"
case "$architecture" in arm64|x86_64) ;; *) exit 2 ;; esac

: "${SOURCE_SHA:?SOURCE_SHA is required}"
: "${SOURCE_DATE_EPOCH:?SOURCE_DATE_EPOCH is required}"
: "${QUALIFICATION_RUN_ID:?QUALIFICATION_RUN_ID is required}"
: "${OCCT_SHA256:?OCCT_SHA256 is required}"
: "${ZLIB_SHA256:?ZLIB_SHA256 is required}"
: "${DEVELOPER_DIR:?DEVELOPER_DIR is required}"
: "${NETGEN_CLANG:?NETGEN_CLANG is required}"
: "${NETGEN_CLANGXX:?NETGEN_CLANGXX is required}"
: "${NETGEN_MACOS_SDK:?NETGEN_MACOS_SDK is required}"
: "${RUNNER_TEMP:?RUNNER_TEMP is required}"
: "${GITHUB_WORKSPACE:?GITHUB_WORKSPACE is required}"

deployment_target=13.0
short_sha="${SOURCE_SHA:0:12}"
sdk_name="netgen-featool-v6.2.2604-${short_sha}-occt7.9.3-macos13-${architecture}-clang"
source_dir="$GITHUB_WORKSPACE"
work_root="$RUNNER_TEMP/netgen-macos-sdk/$architecture"
inputs_dir="$RUNNER_TEMP/netgen-sdk-inputs"
occt_archive="$inputs_dir/occt.tar.gz"
zlib_archive="$inputs_dir/zlib.tar.gz"
build_dir="$work_root/netgen-build"
install_dir="$work_root/netgen-install"
sdk_dir="$work_root/$sdk_name"
out_dir="$RUNNER_TEMP/netgen-macos-sdk-out/$architecture"
consumer_dir="$work_root/consumer"
relocated_dir="$work_root/relocated"

for tool in cmake make gtar gzip shasum file lipo otool xcrun; do
  command -v "$tool" >/dev/null || { echo "missing producer tool: $tool" >&2; exit 1; }
done
[[ "$(uname -m)" == "$architecture" ]]
export COPYFILE_DISABLE=1 SOURCE_DATE_EPOCH

rm -rf "$work_root" "$out_dir"
mkdir -p "$work_root/occt" "$work_root/zlib-src" "$work_root/zlib-stage" "$out_dir"
tar -xzf "$occt_archive" -C "$work_root/occt"
occt_roots=("$work_root/occt"/*)
[[ ${#occt_roots[@]} -eq 1 && -d "${occt_roots[0]}" ]]
occt_root="${occt_roots[0]}"
occt_manifest="$occt_root/build-manifest.json"
[[ -f "$occt_manifest" ]]
python3 - "$occt_manifest" "$architecture" "$deployment_target" "$runner_label" <<'PY'
import json, pathlib, sys
data = json.loads(pathlib.Path(sys.argv[1]).read_text())
assert data["schema_version"] == 1
assert data["occt"]["version"] == "7.9.3"
assert data["occt"]["commit"] == "a016080bf6738d6aeae020badee4e888ad1540a5"
assert data["linkage"] == "shared"
assert data["artifact"]["architecture"] == sys.argv[2]
assert data["artifact"]["deployment_target"] == sys.argv[3]
assert data["producer"]["runner_label"] == sys.argv[4]
PY
[[ -f "$occt_root/lib/cmake/opencascade/OpenCASCADEConfig.cmake" ]]
[[ -f "$occt_root/include/opencascade/Standard.hxx" ]]

tar -xzf "$zlib_archive" -C "$work_root/zlib-src"
zlib_source="$work_root/zlib-src/zlib-1.3.1"
cmake -S "$zlib_source" -B "$work_root/zlib-build" \
  -G "Unix Makefiles" \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX="$work_root/zlib-stage" \
  -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
  -DCMAKE_OSX_ARCHITECTURES="$architecture" \
  -DCMAKE_OSX_DEPLOYMENT_TARGET="$deployment_target" \
  -DCMAKE_OSX_SYSROOT="$NETGEN_MACOS_SDK" \
  -DCMAKE_C_COMPILER="$NETGEN_CLANG" \
  -DCMAKE_CXX_COMPILER="$NETGEN_CLANGXX" \
  -DZLIB_BUILD_EXAMPLES=OFF
cmake --build "$work_root/zlib-build" --parallel "$(sysctl -n hw.logicalcpu)"
cmake --install "$work_root/zlib-build"
zlib_libraries=("$work_root"/zlib-stage/lib*/libz.a)
[[ ${#zlib_libraries[@]} -eq 1 && -f "${zlib_libraries[0]}" ]]
zlib_library="${zlib_libraries[0]}"

configure_options=(
  -G "Unix Makefiles"
  -DCMAKE_BUILD_TYPE=Release
  -DCMAKE_INSTALL_PREFIX="$install_dir"
  -DCMAKE_OSX_ARCHITECTURES="$architecture"
  -DCMAKE_OSX_DEPLOYMENT_TARGET="$deployment_target"
  -DCMAKE_OSX_SYSROOT="$NETGEN_MACOS_SDK"
  -DCMAKE_C_COMPILER="$NETGEN_CLANG"
  -DCMAKE_CXX_COMPILER="$NETGEN_CLANGXX"
  -DCMAKE_FIND_USE_PACKAGE_REGISTRY=FALSE
  -DCMAKE_FIND_USE_SYSTEM_PACKAGE_REGISTRY=FALSE
  -DNG_INSTALL_DIR_BIN=bin
  -DNG_INSTALL_DIR_LIB=lib
  -DNG_INSTALL_DIR_INCLUDE=include
  -DNG_INSTALL_DIR_CMAKE=cmake
  -DNG_INSTALL_DIR_RES=share
  -DUSE_SUPERBUILD=OFF
  -DUSE_GUI=OFF
  -DUSE_PYTHON=OFF
  -DUSE_MPI=OFF
  -DUSE_CGNS=OFF
  -DUSE_JPEG=OFF
  -DUSE_MPEG=OFF
  -DUSE_STLGEOM=ON
  -DUSE_INTERFACE=ON
  -DUSE_CSG=ON
  -DUSE_GEOM2D=ON
  -DUSE_NATIVE_ARCH=OFF
  -DUSE_OCC=ON
  -DNGLIB_LIBRARY_TYPE=SHARED
  -DNGCORE_LIBRARY_TYPE=SHARED
  -DNETGEN_NATIVE_SDK=ON
  -DENABLE_UNIT_TESTS=ON
  -DOpenCascade_DIR="$occt_root/lib/cmake/opencascade"
  -DZLIB_INCLUDE_DIRS="$work_root/zlib-stage/include"
  -DZLIB_LIBRARIES="$zlib_library"
  -DZLIB_LIBRARY_RELEASE="$zlib_library"
)
printf '%s\n' "${configure_options[@]}" > "$work_root/configure-options.txt"
cmake -S "$source_dir" -B "$build_dir" "${configure_options[@]}"
cmake --build "$build_dir" --parallel "$(sysctl -n hw.logicalcpu)" --target unit_tests

DYLD_LIBRARY_PATH="$build_dir/libsrc/core:$build_dir/nglib:$occt_root/lib" \
  ctest --test-dir "$build_dir" -R '^unit_' --output-on-failure
cmake --install "$build_dir"

mkdir -p "$sdk_dir/include" "$sdk_dir/lib" "$sdk_dir/cmake"
cp -a "$install_dir/include/." "$sdk_dir/include/"
cp -a "$install_dir/lib/libngcore.dylib" "$sdk_dir/lib/"
cp -a "$install_dir/lib/libnglib.dylib" "$sdk_dir/lib/"
cp -a "$install_dir/cmake/NetgenConfig.cmake" "$sdk_dir/cmake/"
cp -a "$install_dir/cmake/netgen-targets.cmake" "$sdk_dir/cmake/"
cp -a "$install_dir/cmake/netgen-targets-release.cmake" "$sdk_dir/cmake/"

for library in "$sdk_dir/lib/libngcore.dylib" "$sdk_dir/lib/libnglib.dylib"; do
  [[ "$(lipo -archs "$library")" == "$architecture" ]]
  install_name="$(otool -D "$library" | sed -n '2p' | xargs)"
  expected_install_name="@rpath/$(basename "$library")"
  [[ "$install_name" == "$expected_install_name" ]] || {
    echo "unexpected install name in $(basename "$library"): $install_name" >&2
    exit 1
  }
  load_commands="$(otool -l "$library")"
  dependencies="$(otool -L "$library")"
  grep -Eq 'minos[[:space:]]+13\.0([[:space:]]|$)' <<<"$load_commands"
  for forbidden in "$source_dir" "$build_dir" "$install_dir" "$occt_root" "$work_root/zlib-stage"; do
    if grep -Fq "$forbidden" <<<"$load_commands$dependencies"; then
      echo "producer path leaked into $(basename "$library"): $forbidden" >&2
      exit 1
    fi
  done
  if grep -Eqi '(libz\.|python|tcl|tk[0-9]|mpi|cgns|jpeg|avcodec|avformat)' <<<"$dependencies"; then
    echo "disabled runtime dependency found in $(basename "$library")" >&2
    exit 1
  fi
  while IFS= read -r dependency; do
    [[ -z "$dependency" ]] && continue
    case "$dependency" in
      @rpath/*|@loader_path/*|/usr/lib/*|/System/Library/*) ;;
      *) echo "non-relocatable dependency in $(basename "$library"): $dependency" >&2; exit 1 ;;
    esac
  done < <(awk 'NR > 1 {print $1}' <<<"$dependencies")
  if [[ "$(basename "$library")" == libnglib.dylib ]]; then
    grep -Eq '^[[:space:]]+@rpath/libngcore\.dylib[[:space:]]' <<<"$dependencies"
    grep -Eq '^[[:space:]]+@rpath/libTK[^[:space:]]*\.dylib[[:space:]]' <<<"$dependencies"
  fi
  runtime_paths="$(awk '/cmd LC_RPATH/{getline; getline; print $2}' <<<"$load_commands")"
  [[ -n "$runtime_paths" ]] || { echo "missing LC_RPATH in $(basename "$library")" >&2; exit 1; }
  while IFS= read -r runtime_path; do
    [[ -z "$runtime_path" ]] && continue
    case "$runtime_path" in
      @loader_path|@loader_path/*) ;;
      *) echo "non-relocatable LC_RPATH in $(basename "$library"): $runtime_path" >&2; exit 1 ;;
    esac
  done <<<"$runtime_paths"
done

for cmake_file in "$sdk_dir"/cmake/*.cmake; do
  for forbidden in "$source_dir" "$build_dir" "$install_dir" "$occt_root" "$work_root/zlib-stage"; do
    if grep -Fq "$forbidden" "$cmake_file"; then
      echo "producer path leaked into $(basename "$cmake_file"): $forbidden" >&2
      exit 1
    fi
  done
  if grep -Eqi '(netgen_cgns|netgen_python|netgen_gui|pyngcore|ngpy|nggui|-march=native|-mavx)' "$cmake_file"; then
    echo "disabled target or native CPU option leaked into $(basename "$cmake_file")" >&2
    exit 1
  fi
done

python3 - "$sdk_dir" "$runner_label" "$architecture" "$deployment_target" "$OCCT_SHA256" "$ZLIB_SHA256" "$QUALIFICATION_RUN_ID" <<'PY'
import hashlib, json, os, pathlib, subprocess, sys
sdk = pathlib.Path(sys.argv[1])
def run(*args):
    return subprocess.check_output(args, text=True).strip()
def sha(path):
    h = hashlib.sha256(); h.update(path.read_bytes()); return h.hexdigest()
info = {
    "schema_version": 1,
    "upstream": {"tag": "v6.2.2604", "commit": "3ee489c7d58fdbc2a6708cca3cbaefaae506dc17"},
    "source": {"commit": os.environ["SOURCE_SHA"], "qualification_run_id": sys.argv[7]},
    "producer": {
        "runner_label": sys.argv[2], "architecture": sys.argv[3], "deployment_target": sys.argv[4],
        "image_os": os.environ.get("ImageOS", ""), "image_version": os.environ.get("ImageVersion", ""),
        "xcode": run("xcodebuild", "-version"), "clang": run(os.environ["NETGEN_CLANG"], "--version").splitlines()[0],
        "cmake": run("cmake", "--version").splitlines()[0], "sdk_version": run("xcrun", "--sdk", "macosx", "--show-sdk-version")
    },
    "netgen": {"configuration": "Release", "cxx_standard": 17, "linkage": "shared", "native_arch": False},
    "occt": {"release": "occt-sdk-7.9.3", "commit": "a016080bf6738d6aeae020badee4e888ad1540a5", "asset_sha256": sys.argv[5], "linkage": "shared"},
    "zlib": {"version": "1.3.1", "sha256": sys.argv[6], "linkage": "static", "pic": True},
    "artifact_hashes": {p.relative_to(sdk).as_posix(): sha(p) for p in sorted([sdk / "lib/libngcore.dylib", sdk / "lib/libnglib.dylib", *sorted((sdk / "cmake").glob("*.cmake"))])}
}
(sdk / "producer-info.json").write_text(json.dumps(info, indent=2, sort_keys=True) + "\n")
PY

configure_consumer() {
  local root="$1"
  local build="$2"
  rm -rf "$build"
  cmake -G "Unix Makefiles" \
    -S "$source_dir/tests/unix-native-sdk" \
    -B "$build" \
    -DCMAKE_OSX_ARCHITECTURES="$architecture" \
    -DCMAKE_OSX_DEPLOYMENT_TARGET="$deployment_target" \
    -DCMAKE_OSX_SYSROOT="$NETGEN_MACOS_SDK" \
    -DCMAKE_C_COMPILER="$NETGEN_CLANG" \
    -DCMAKE_CXX_COMPILER="$NETGEN_CLANGXX" \
    -DCMAKE_BUILD_RPATH="$root/lib;$occt_root/lib" \
    -DNETGEN_SDK_DIR="$root" \
    -DOCCT_INCLUDE_DIR="$occt_root/include/opencascade"
  cmake --build "$build" --parallel "$(sysctl -n hw.logicalcpu)"
  "$build/netgen_native_sdk_smoke" "$source_dir/tests/unix-native-sdk/vertex.brep"
}

configure_consumer "$sdk_dir" "$consumer_dir"

archive="$out_dir/$sdk_name.tar.gz"
gtar -C "$work_root" --sort=name --mtime="@$SOURCE_DATE_EPOCH" --owner=0 --group=0 --numeric-owner -cf - "$sdk_name" | gzip -n > "$archive"
(cd "$out_dir" && shasum -a 256 "$(basename "$archive")" > "$(basename "$archive").sha256" && shasum -a 256 -c "$(basename "$archive").sha256")

rm -rf "$sdk_dir" "$install_dir" "$consumer_dir"
mkdir -p "$relocated_dir"
tar -xzf "$archive" -C "$relocated_dir"
relocated_sdk="$relocated_dir/$sdk_name"
[[ -f "$relocated_sdk/producer-info.json" ]]
configure_consumer "$relocated_sdk" "$work_root/consumer-relocated"

echo "SDK_ARCHIVE=$archive"
