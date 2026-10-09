#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: $0 <shared|static>" >&2
  exit 2
fi
linkage="$1"
case "$linkage" in shared|static) ;; *) exit 2 ;; esac
library_type="${linkage^^}"

: "${SOURCE_SHA:?SOURCE_SHA is required}"
: "${SOURCE_DATE_EPOCH:?SOURCE_DATE_EPOCH is required}"
: "${QUALIFICATION_RUN_ID:?QUALIFICATION_RUN_ID is required}"
: "${PRODUCER_IMAGE:?PRODUCER_IMAGE is required}"
: "${PRODUCER_IMAGE_TAG:?PRODUCER_IMAGE_TAG is required}"
: "${PRODUCER_IMAGE_DIGEST:?PRODUCER_IMAGE_DIGEST is required}"
: "${OCCT_SHA256:?OCCT_SHA256 is required}"
: "${ZLIB_SHA256:?ZLIB_SHA256 is required}"

source_mount=/source
source_dir=/work/src
work_root=/work
inputs_dir=/inputs
occt_archive="$inputs_dir/occt.tar.gz"
zlib_archive="$inputs_dir/zlib.tar.gz"
short_sha="${SOURCE_SHA:0:12}"
sdk_name="netgen-featool-v6.2.2608-${short_sha}-occt8.0.1-linux-x86_64-glibc2.17-gcc10"
if [[ "$linkage" == "static" ]]; then
  sdk_name="${sdk_name}-static"
fi
build_dir="$work_root/netgen-build"
install_dir="$work_root/netgen-install"
sdk_dir="$work_root/$sdk_name"
out_dir="$work_root/out"
consumer_dir="$work_root/consumer"
relocated_dir="$work_root/relocated"

find_python() {
  local candidate
  for candidate in /opt/python/cp311-cp311/bin/python /opt/python/cp310-cp310/bin/python /opt/python/cp39-cp39/bin/python /usr/bin/python3; do
    if [[ -x "$candidate" ]]; then
      echo "$candidate"
      return 0
    fi
  done
  return 1
}

python_bin="$(find_python)"
cmake_version=3.31.6
tools_dir="$work_root/tools/cmake-$cmake_version"
cmake_bin=""
if command -v cmake >/dev/null 2>&1; then
  cmake_bin="$(command -v cmake)"
  current_cmake="$($cmake_bin --version | sed -n '1s/.* //p')"
  if [[ "$(printf '%s\n%s\n' 3.16 "$current_cmake" | sort -V | head -n1)" != 3.16 ]]; then
    cmake_bin=""
  fi
fi
if [[ -z "$cmake_bin" ]]; then
  rm -rf "$tools_dir"
  mkdir -p "$tools_dir"
  "$python_bin" -m pip install --disable-pip-version-check --no-deps --only-binary=:all: --target "$tools_dir" "cmake==$cmake_version"
  cmake_bin="$tools_dir/cmake/data/bin/cmake"
fi
export PATH="$(dirname "$cmake_bin"):$PATH"

for tool in gcc g++ make cmake ld readelf objdump file sha256sum tar gzip; do
  command -v "$tool" >/dev/null || { echo "missing producer tool: $tool" >&2; exit 1; }
done
[[ "$(uname -m)" == x86_64 ]]

rm -rf "$source_dir" "$build_dir" "$install_dir" "$sdk_dir" "$out_dir" "$consumer_dir" "$relocated_dir" "$work_root/occt" "$work_root/zlib-src" "$work_root/zlib-build" "$work_root/zlib-stage"
mkdir -p "$source_dir" "$out_dir" "$work_root/occt" "$work_root/zlib-src" "$work_root/zlib-stage"
cp -a "$source_mount/." "$source_dir/"
git config --global --add safe.directory "$source_dir"

tar -xzf "$occt_archive" -C "$work_root/occt"
mapfile -t occt_roots < <(find "$work_root/occt" -mindepth 1 -maxdepth 1 -type d -print)
[[ ${#occt_roots[@]} -eq 1 ]]
occt_root="${occt_roots[0]}"
occt_manifest="$occt_root/build-manifest.json"
[[ -f "$occt_manifest" ]]
"$python_bin" - "$occt_manifest" "$PRODUCER_IMAGE_DIGEST" "$linkage" <<'PY'
import json, pathlib, sys
data = json.loads(pathlib.Path(sys.argv[1]).read_text())
assert data["schema_version"] == 1
assert data["occt"]["version"] == "8.0.1"
assert data["occt"]["commit"] == "b8f597c677811d1f9f4d8a97f5ae2825c0353a42"
assert data["linkage"] == sys.argv[3]
assert data["producer"]["architecture"] == "x86_64"
assert data["producer"]["glibc_baseline"] == "2.17"
assert data["producer"]["image_digest"] == sys.argv[2]
PY
[[ -f "$occt_root/lib/cmake/opencascade/OpenCASCADEConfig.cmake" ]]
[[ -f "$occt_root/include/opencascade/Standard.hxx" ]]

tar -xzf "$zlib_archive" -C "$work_root/zlib-src"
zlib_source="$work_root/zlib-src/zlib-1.3.1"
[[ -d "$zlib_source" ]]
cmake -S "$zlib_source" -B "$work_root/zlib-build" \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
  -DCMAKE_INSTALL_PREFIX="$work_root/zlib-stage" \
  -DZLIB_BUILD_EXAMPLES=OFF
cmake --build "$work_root/zlib-build" --parallel 4
cmake --install "$work_root/zlib-build"
mapfile -t zlib_libraries < <(find "$work_root/zlib-stage" -type f -name libz.a -print)
[[ ${#zlib_libraries[@]} -eq 1 ]]
zlib_library="${zlib_libraries[0]}"

configure_options=(
  -DCMAKE_BUILD_TYPE=Release
  -DCMAKE_POSITION_INDEPENDENT_CODE=ON
  -DCMAKE_INSTALL_PREFIX="$install_dir"
  -DCMAKE_FIND_USE_PACKAGE_REGISTRY=FALSE
  -DCMAKE_FIND_USE_SYSTEM_PACKAGE_REGISTRY=FALSE
  -DNG_INSTALL_DIR_BIN=bin
  -DNG_INSTALL_DIR_LIB=lib
  -DNG_INSTALL_DIR_INCLUDE=include
  -DNG_INSTALL_DIR_CMAKE=cmake
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
  -DNGLIB_LIBRARY_TYPE="$library_type"
  -DNGCORE_LIBRARY_TYPE="$library_type"
  -DNETGEN_NATIVE_SDK=ON
  -DENABLE_UNIT_TESTS=ON
  -DOpenCascade_DIR="$occt_root/lib/cmake/opencascade"
  -DZLIB_INCLUDE_DIRS="$work_root/zlib-stage/include"
  -DZLIB_LIBRARIES="$zlib_library"
  -DZLIB_LIBRARY_RELEASE="$zlib_library"
)
printf '%s\n' "${configure_options[@]}" > "$work_root/configure-options.txt"
cmake -S "$source_dir" -B "$build_dir" "${configure_options[@]}"
cmake --build "$build_dir" --parallel 4 --target unit_tests

if [[ "$linkage" == "shared" ]]; then
  LD_LIBRARY_PATH="$build_dir/libsrc/core:$build_dir/nglib:$occt_root/lib" \
    ctest --test-dir "$build_dir" -R '^unit_' --output-on-failure
else
  ctest --test-dir "$build_dir" -R '^unit_' --output-on-failure
fi
cmake --install "$build_dir"

mkdir -p "$sdk_dir/include" "$sdk_dir/lib" "$sdk_dir/cmake"
cp -a "$install_dir/include/." "$sdk_dir/include/"
if [[ "$linkage" == "shared" ]]; then
  cp -a "$install_dir/lib/libngcore.so" "$sdk_dir/lib/"
  cp -a "$install_dir/lib/libnglib.so" "$sdk_dir/lib/"
else
  cp -a "$install_dir/lib/libngcore.a" "$sdk_dir/lib/"
  cp -a "$install_dir/lib/libnglib.a" "$sdk_dir/lib/"
  cp -a "$zlib_library" "$sdk_dir/lib/libz.a"
fi
cp -a "$install_dir/cmake/NetgenConfig.cmake" "$sdk_dir/cmake/"
cp -a "$install_dir/cmake/netgen-targets.cmake" "$sdk_dir/cmake/"
cp -a "$install_dir/cmake/netgen-targets-release.cmake" "$sdk_dir/cmake/"

if [[ "$linkage" == "shared" ]]; then
  for library in "$sdk_dir/lib/libngcore.so" "$sdk_dir/lib/libnglib.so"; do
    file "$library" | grep -Eq 'ELF 64-bit.*x86-64|ELF 64-bit.*x86_64'
    dynamic="$(readelf -d "$library")"
    if grep -Fq "$source_dir" <<<"$dynamic" || grep -Fq "$work_root" <<<"$dynamic"; then
      echo "producer path leaked into $(basename "$library")" >&2
      exit 1
    fi
    if grep -Eqi 'NEEDED.*(libz\.so|python|tcl|tk[0-9]|mpi|cgns|jpeg|avcodec|avformat)' <<<"$dynamic"; then
      echo "disabled runtime dependency found in $(basename "$library")" >&2
      exit 1
    fi
    rpath="$(sed -nE 's/.*Library (rpath|runpath): \[([^]]*)\].*/\2/p' <<<"$dynamic")"
    [[ -n "$rpath" ]] || { echo "missing RPATH/RUNPATH in $(basename "$library")" >&2; exit 1; }
    IFS=: read -r -a rpath_entries <<<"$rpath"
    for entry in "${rpath_entries[@]}"; do
      case "$entry" in
        '$ORIGIN'|'$ORIGIN/'*) ;;
        *) echo "non-relocatable runtime path in $(basename "$library"): $entry" >&2; exit 1 ;;
      esac
    done
  done
else
  for library in "$sdk_dir/lib/libngcore.a" "$sdk_dir/lib/libnglib.a" "$sdk_dir/lib/libz.a"; do
    file "$library" | grep -Fq 'current ar archive'
    formats="$(objdump -f "$library" | sed -n 's/.*file format //p' | sort -u)"
    [[ "$formats" == "elf64-x86-64" ]] || {
      echo "unexpected object format in $(basename "$library"): $formats" >&2
      exit 1
    }
  done
fi

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

"$python_bin" - "$sdk_dir" "$PRODUCER_IMAGE" "$PRODUCER_IMAGE_TAG" "$PRODUCER_IMAGE_DIGEST" "$OCCT_SHA256" "$ZLIB_SHA256" "$QUALIFICATION_RUN_ID" "$linkage" <<'PY'
import hashlib, json, os, pathlib, subprocess, sys
sdk = pathlib.Path(sys.argv[1])
linkage = sys.argv[8]
def run(*args):
    return subprocess.check_output(args, text=True).strip()
def sha(path):
    h = hashlib.sha256(); h.update(path.read_bytes()); return h.hexdigest()
def symbol_max(prefix):
    maxima = {}
    for lib in (sdk / "lib").glob("libng*.so"):
        text = run("objdump", "-T", str(lib))
        for token in text.replace("(", " ").replace(")", " ").split():
            if token.startswith(prefix + "_"):
                version = token.split("_", 1)[1]
                key = tuple(int(x) for x in version.split("."))
                if prefix not in maxima or key > maxima[prefix][0]:
                    maxima[prefix] = (key, version)
    return maxima.get(prefix, (None, None))[1]
glibc = symbol_max("GLIBC") if linkage == "shared" else None
if glibc and tuple(map(int, glibc.split("."))) > (2, 17):
    raise SystemExit(f"Netgen shared libraries require GLIBC_{glibc}")
suffix = ".so" if linkage == "shared" else ".a"
artifacts = [sdk / f"lib/libngcore{suffix}", sdk / f"lib/libnglib{suffix}"]
if linkage == "static":
    artifacts.append(sdk / "lib/libz.a")
info = {
    "schema_version": 1,
    "upstream": {"tag": "v6.2.2608", "commit": "96e5682f6ea43ba77ba3bb2ae4bb4bd1791f506e"},
    "source": {"commit": os.environ["SOURCE_SHA"], "qualification_run_id": sys.argv[7]},
    "producer": {
        "image": sys.argv[2], "image_tag": sys.argv[3], "image_digest": sys.argv[4],
        "architecture": run("uname", "-m"), "gcc": run("gcc", "--version").splitlines()[0],
        "gxx": run("g++", "--version").splitlines()[0], "cmake": run("cmake", "--version").splitlines()[0],
        "glibc_baseline": "2.17"
    },
    "netgen": {"configuration": "Release", "cxx_standard": 17, "linkage": linkage, "native_arch": False, "position_independent_code": True},
    "occt": {"release": "occt-sdk-8.0.1", "commit": "b8f597c677811d1f9f4d8a97f5ae2825c0353a42", "asset_sha256": sys.argv[5], "linkage": linkage},
    "zlib": {"version": "1.3.1", "sha256": sys.argv[6], "linkage": "static", "pic": True},
    "symbol_versions": {"GLIBC": glibc, "GLIBCXX": symbol_max("GLIBCXX") if linkage == "shared" else None, "CXXABI": symbol_max("CXXABI") if linkage == "shared" else None},
    "artifact_hashes": {p.relative_to(sdk).as_posix(): sha(p) for p in sorted([*artifacts, *sorted((sdk / "cmake").glob("*.cmake"))])}
}
(sdk / "producer-info.json").write_text(json.dumps(info, indent=2, sort_keys=True) + "\n")
PY

configure_consumer() {
  local root="$1"
  local build="$2"
  rm -rf "$build"
  LDFLAGS="-Wl,-rpath-link,$occt_root/lib" cmake \
    -S "$source_dir/tests/unix-native-sdk" \
    -B "$build" \
    -DCMAKE_BUILD_RPATH="$root/lib" \
    -DNETGEN_SDK_DIR="$root" \
    -DOpenCASCADE_DIR="$occt_root/lib/cmake/opencascade" \
    -DOCCT_INCLUDE_DIR="$occt_root/include/opencascade"
  cmake --build "$build" --parallel 4
  if [[ "$linkage" == "shared" ]]; then
    LD_LIBRARY_PATH="$occt_root/lib" \
      "$build/netgen_native_sdk_smoke" "$source_dir/tests/unix-native-sdk/vertex.brep"
  else
    "$build/netgen_native_sdk_smoke" "$source_dir/tests/unix-native-sdk/vertex.brep"
    if readelf -d "$build/netgen_native_sdk_smoke" | grep -Eq 'NEEDED.*(libng|libTK)[^]]*\.so'; then
      echo "static consumer unexpectedly depends on shared Netgen/OCCT libraries" >&2
      readelf -d "$build/netgen_native_sdk_smoke" >&2
      exit 1
    fi
  fi
}

configure_consumer "$sdk_dir" "$consumer_dir"

archive="$out_dir/$sdk_name.tar.gz"
"$python_bin" - "$sdk_dir" "$archive" "$SOURCE_DATE_EPOCH" <<'PY'
import gzip, pathlib, sys, tarfile

root = pathlib.Path(sys.argv[1])
archive = pathlib.Path(sys.argv[2])
epoch = int(sys.argv[3])

def normalize(info):
    info.mtime = epoch
    info.uid = info.gid = 0
    info.uname = info.gname = ""
    return info

with archive.open("wb") as raw:
    with gzip.GzipFile(fileobj=raw, mode="wb", mtime=0) as compressed:
        with tarfile.open(fileobj=compressed, mode="w", format=tarfile.PAX_FORMAT) as tar:
            paths = [root, *sorted(root.rglob("*"), key=lambda path: path.relative_to(root).as_posix())]
            for path in paths:
                arcname = root.name if path == root else f"{root.name}/{path.relative_to(root).as_posix()}"
                info = normalize(tar.gettarinfo(str(path), arcname=arcname))
                if info.isfile():
                    with path.open("rb") as stream:
                        tar.addfile(info, stream)
                else:
                    tar.addfile(info)
PY
(cd "$out_dir" && sha256sum "$(basename "$archive")" > "$(basename "$archive").sha256" && sha256sum -c "$(basename "$archive").sha256")

rm -rf "$sdk_dir" "$install_dir" "$consumer_dir"
mkdir -p "$relocated_dir"
tar -xzf "$archive" -C "$relocated_dir"
relocated_sdk="$relocated_dir/$sdk_name"
[[ -f "$relocated_sdk/producer-info.json" ]]
if [[ "$linkage" == "shared" ]]; then
  [[ -f "$relocated_sdk/lib/libngcore.so" ]]
  [[ -f "$relocated_sdk/lib/libnglib.so" ]]
else
  [[ -f "$relocated_sdk/lib/libngcore.a" ]]
  [[ -f "$relocated_sdk/lib/libnglib.a" ]]
  [[ -f "$relocated_sdk/lib/libz.a" ]]
fi
configure_consumer "$relocated_sdk" "$work_root/consumer-relocated"

echo "SDK_ARCHIVE=$archive"
