param(
  [Parameter(Mandatory=$true)][string]$OcctSource,
  [Parameter(Mandatory=$true)][string]$ArchiveName
)
$ErrorActionPreference = "Stop"

function Get-Imports([string]$Path, [string]$Dumpbin) {
  $text = (& $Dumpbin /dependents $Path 2>&1 | Out-String)
  if($LASTEXITCODE -ne 0) { throw "dumpbin /dependents failed for $Path" }
  return @([regex]::Matches($text, '(?im)^\s*([A-Za-z0-9_.+-]+\.dll)\s*$') |
    ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
}

$vswhere = Join-Path ([Environment]::GetFolderPath("ProgramFilesX86")) "Microsoft Visual Studio\Installer\vswhere.exe"
$vs = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
if($LASTEXITCODE -ne 0 -or -not $vs) { throw "Visual Studio 2022 x64 tools were not found." }
$devCmd = Join-Path $vs "Common7\Tools\VsDevCmd.bat"
$devEnvironment = & cmd.exe /s /c ('call "' + $devCmd + '" -arch=amd64 -host_arch=amd64 >nul && set')
if($LASTEXITCODE -ne 0) { throw "VsDevCmd.bat failed." }
foreach($line in $devEnvironment) {
  $separator = $line.IndexOf("=")
  if($separator -lt 1) { continue }
  Set-Item -Path ("Env:" + $line.Substring(0,$separator)) -Value $line.Substring($separator+1)
}
$dumpbin = (Get-Command dumpbin.exe -ErrorAction Stop).Source
$cl = (Get-Command cl.exe -ErrorAction Stop).Source

$source = $env:GITHUB_WORKSPACE
$work = Join-Path $env:RUNNER_TEMP "netgen-windows-static"
$occtBuild = Join-Path $work "occt-build"
$occtInstall = Join-Path $work "occt-install"
$zlibSrcParent = Join-Path $work "zlib-src"
$zlibBuild = Join-Path $work "zlib-build"
$zlibStage = Join-Path $work "zlib-stage"
$netgenBuild = Join-Path $work "netgen-build"
$netgenInstall = Join-Path $work "netgen-install"
$sdk = Join-Path $work "sdk"
$out = Join-Path $env:RUNNER_TEMP "qualified-static-assets"
foreach($p in @($work,$out)) {
  if(Test-Path -LiteralPath $p) { Remove-Item -LiteralPath $p -Recurse -Force }
  New-Item -ItemType Directory -Force -Path $p | Out-Null
}

$actualOcct = (git -C $OcctSource rev-parse HEAD).Trim().ToLowerInvariant()
if($actualOcct -ne $env:OCCT_SOURCE_SHA.ToLowerInvariant()) { throw "OCCT source mismatch: $actualOcct" }

$toolkits = "TKDESTEP;TKDEIGES;TKDESTL;TKOffset;TKMesh"
$occtConfigure = @(
  "-S",$OcctSource,"-B",$occtBuild,"-G","Visual Studio 17 2022","-A","x64",
  "-DBUILD_LIBRARY_TYPE=Static",
  "-DCMAKE_MSVC_RUNTIME_LIBRARY=MultiThreadedDLL",
  "-DBUILD_OPT_PROFILE=Default","-DBUILD_USE_PCH=OFF",
  "-DBUILD_MODULE_Draw=OFF","-DBUILD_MODULE_FoundationClasses=OFF","-DBUILD_MODULE_ModelingData=OFF",
  "-DBUILD_MODULE_ModelingAlgorithms=OFF","-DBUILD_MODULE_ApplicationFramework=OFF",
  "-DBUILD_MODULE_DataExchange=OFF","-DBUILD_MODULE_Visualization=OFF",
  "-DBUILD_ADDITIONAL_TOOLKITS=$toolkits",
  "-DUSE_FREETYPE=OFF","-DUSE_FREEIMAGE=OFF","-DUSE_FFMPEG=OFF","-DUSE_OPENVR=OFF",
  "-DUSE_RAPIDJSON=OFF","-DUSE_DRACO=OFF","-DUSE_TBB=OFF","-DUSE_EIGEN=OFF",
  "-DUSE_TCL=OFF","-DUSE_TK=OFF","-DUSE_VTK=OFF","-DUSE_OPENGL=OFF","-DUSE_GLES2=OFF","-DUSE_D3D=OFF",
  "-DUSE_MMGR_TYPE=NATIVE","-D3RDPARTY_DIR=","-DINSTALL_DIR=$occtInstall"
)
& cmake @occtConfigure
if($LASTEXITCODE -ne 0){throw "OCCT static configure failed."}
cmake --build $occtBuild --target install --config Release --parallel 2
if($LASTEXITCODE -ne 0){throw "OCCT static build/install failed."}
if(-not (Test-Path -LiteralPath "$occtInstall\cmake\OpenCASCADEConfig.cmake")){throw "OCCT config missing."}
if(-not (Test-Path -LiteralPath "$occtInstall\inc\Standard.hxx")){throw "OCCT headers missing."}
$occtDlls=@(Get-ChildItem -LiteralPath $occtInstall -Recurse -File -Filter "*.dll")
$occtLibs=@(Get-ChildItem -LiteralPath $occtInstall -Recurse -File -Filter "*.lib")
if($occtDlls.Count -ne 0){throw "Static OCCT install contains DLLs."}
if($occtLibs.Count -ne 28){throw "Expected 28 static OCCT libraries, got $($occtLibs.Count)."}
$mdEvidence=0
foreach($lib in $occtLibs){
  $d=(& $dumpbin /directives $lib.FullName 2>&1 | Out-String)
  if($LASTEXITCODE -ne 0){throw "dumpbin failed for $($lib.Name)"}
  if($d -match '(?i)DEFAULTLIB:"?LIBCMT'){throw "$($lib.Name) uses /MT."}
  if($d -match '(?i)DEFAULTLIB:"?MSVCRT'){$mdEvidence++}
}
if($mdEvidence -eq 0){throw "No /MD evidence found in OCCT static libraries."}

$downloads = Join-Path $work "downloads"
New-Item -ItemType Directory -Force -Path $downloads,$zlibSrcParent,$zlibStage | Out-Null
$zlibArchive = Join-Path $downloads "zlib-1.3.1.tar.gz"
Invoke-WebRequest -Uri $env:ZLIB_URL -OutFile $zlibArchive
$zHash=(Get-FileHash -LiteralPath $zlibArchive -Algorithm SHA256).Hash.ToLowerInvariant()
if($zHash -ne $env:ZLIB_SHA256){throw "zlib SHA-256 mismatch: $zHash"}
Push-Location $zlibSrcParent
try {
  cmake -E tar xzf $zlibArchive
  if($LASTEXITCODE -ne 0){throw "zlib extract failed."}
}
finally { Pop-Location }
$zsrc=Join-Path $zlibSrcParent "zlib-1.3.1"
& cmake -S $zsrc -B $zlibBuild -G "Visual Studio 17 2022" -A x64 "-DCMAKE_MSVC_RUNTIME_LIBRARY=MultiThreadedDLL" "-DZLIB_BUILD_EXAMPLES=OFF"
if($LASTEXITCODE -ne 0){throw "zlib configure failed."}
cmake --build $zlibBuild --config Release --target zlibstatic
if($LASTEXITCODE -ne 0){throw "zlibstatic build failed."}
$zlib=Get-ChildItem -LiteralPath $zlibBuild -Recurse -File -Filter "zlibstatic.lib" | Where-Object {$_.FullName -match '\\Release\\zlibstatic\.lib$'} | Select-Object -First 1
if(-not $zlib){throw "zlibstatic.lib missing."}
$zd=(& $dumpbin /directives $zlib.FullName 2>&1 | Out-String)
if($LASTEXITCODE -ne 0){throw "dumpbin failed for zlibstatic.lib."}
if($zd -match '(?i)DEFAULTLIB:"?LIBCMT'){throw "zlibstatic uses /MT."}
if($zd -notmatch '(?i)DEFAULTLIB:"?MSVCRT'){throw "zlibstatic lacks /MD evidence."}
New-Item -ItemType Directory -Force -Path "$zlibStage\include","$zlibStage\lib" | Out-Null
Copy-Item -LiteralPath "$zsrc\zlib.h" -Destination "$zlibStage\include\zlib.h"
Copy-Item -LiteralPath "$zlibBuild\zconf.h" -Destination "$zlibStage\include\zconf.h"
Copy-Item -LiteralPath $zlib.FullName -Destination "$zlibStage\lib\zlibstatic.lib"

$zlibPath="$zlibStage\lib\zlibstatic.lib"
$netgenConfigure=@(
  "-S",$source,"-B",$netgenBuild,"-G","Visual Studio 17 2022","-A","x64",
  "-DCMAKE_BUILD_TYPE=Release","-DCMAKE_INSTALL_PREFIX=$netgenInstall",
  "-DCMAKE_MSVC_RUNTIME_LIBRARY=MultiThreadedDLL",
  "-DCMAKE_FIND_USE_PACKAGE_REGISTRY=FALSE","-DCMAKE_FIND_USE_SYSTEM_PACKAGE_REGISTRY=FALSE",
  "-DUSE_SUPERBUILD=OFF","-DUSE_GUI=OFF","-DUSE_PYTHON=OFF","-DUSE_MPI=OFF","-DUSE_CGNS=OFF",
  "-DUSE_JPEG=OFF","-DUSE_MPEG=OFF","-DUSE_STLGEOM=ON","-DUSE_INTERFACE=ON","-DUSE_CSG=ON","-DUSE_GEOM2D=ON",
  "-DUSE_NATIVE_ARCH=OFF","-DUSE_OCC=ON","-DNGLIB_LIBRARY_TYPE=STATIC","-DNGCORE_LIBRARY_TYPE=STATIC",
  "-DNETGEN_NATIVE_SDK=ON","-DENABLE_UNIT_TESTS=ON",
  "-DOpenCascade_DIR=$occtInstall\cmake","-DZLIB_INCLUDE_DIRS=$zlibStage\include",
  "-DZLIB_LIBRARIES=$zlibPath","-DZLIB_LIBRARY_RELEASE=$zlibPath"
)
& cmake @netgenConfigure
if($LASTEXITCODE -ne 0){throw "Netgen static configure failed."}
cmake --build $netgenBuild --config Release --target unit_tests
if($LASTEXITCODE -ne 0){throw "Netgen static unit-test build failed."}
ctest --test-dir $netgenBuild -C Release -R "^unit_" --output-on-failure
if($LASTEXITCODE -ne 0){throw "Netgen static native unit tests failed."}
cmake --install $netgenBuild --config Release
if($LASTEXITCODE -ne 0){throw "Netgen static install failed."}

New-Item -ItemType Directory -Force -Path "$sdk\include","$sdk\lib","$sdk\cmake","$sdk\occt" | Out-Null
Copy-Item -Path "$netgenInstall\include\*" -Destination "$sdk\include" -Recurse
Copy-Item -LiteralPath "$netgenInstall\lib\ngcore.lib" -Destination "$sdk\lib\ngcore.lib"
Copy-Item -LiteralPath "$netgenInstall\lib\nglib.lib" -Destination "$sdk\lib\nglib.lib"
Copy-Item -LiteralPath $zlibPath -Destination "$sdk\lib\zlibstatic.lib"
foreach($f in @("NetgenConfig.cmake","netgen-targets.cmake","netgen-targets-release.cmake")){
  Copy-Item -LiteralPath "$netgenInstall\cmake\$f" -Destination "$sdk\cmake\$f"
}
Copy-Item -Path "$occtInstall\*" -Destination "$sdk\occt" -Recurse

$dlls=@(Get-ChildItem -LiteralPath $sdk -Recurse -File -Filter "*.dll")
if($dlls.Count -ne 0){throw "Static SDK unexpectedly contains DLLs: $($dlls.FullName -join ', ')"}
foreach($f in @("$sdk\lib\ngcore.lib","$sdk\lib\nglib.lib","$sdk\lib\zlibstatic.lib")){
  $m=(& $dumpbin /linkermember:1 $f 2>&1 | Out-String)
  if($LASTEXITCODE -ne 0 -or -not $m.Trim()){throw "Unreadable static library: $f"}
  $d=(& $dumpbin /directives $f 2>&1 | Out-String)
  if($LASTEXITCODE -ne 0){throw "dumpbin directives failed for $f"}
  if($d -match '(?i)DEFAULTLIB:"?LIBCMT'){throw "$f uses /MT."}
}
foreach($f in Get-ChildItem -LiteralPath "$sdk\cmake" -File -Filter "*.cmake"){
  $t=Get-Content -LiteralPath $f.FullName -Raw
  foreach($p in @($source,$work,$OcctSource,$occtInstall,$zlibStage,$netgenBuild,$netgenInstall)){
    foreach($form in @($p,($p -replace '\\','/'))){
      if($form -and $t -match [regex]::Escape($form)){throw "$($f.Name) contains producer path $form"}
    }
  }
}

$clOutput=(& $cl /Bv 2>&1 | Out-String)
$global:LASTEXITCODE=0
$compilerLine=(($clOutput -split '\r?\n') | Where-Object {$_ -match 'Compiler Version'} | Select-Object -First 1).Trim()
$toolchain=[ordered]@{
  runner_os=$env:RUNNER_OS; runner_arch=$env:RUNNER_ARCH; image_os=$env:ImageOS; image_version=$env:ImageVersion;
  cmake=((& cmake --version | Select-Object -First 1).Trim());
  compiler=$compilerLine; generator="Visual Studio 17 2022"; architecture="x64"; configuration="Release"; runtime="/MD (MultiThreadedDLL)"
}
$hashes=[ordered]@{}
foreach($p in @("lib/ngcore.lib","lib/nglib.lib","lib/zlibstatic.lib","cmake/NetgenConfig.cmake","cmake/netgen-targets.cmake","cmake/netgen-targets-release.cmake")){
  $hashes[$p]=(Get-FileHash -LiteralPath (Join-Path $sdk ($p -replace '/','\')) -Algorithm SHA256).Hash.ToLowerInvariant()
}
$info=[ordered]@{
  schema_version=1
  upstream=[ordered]@{tag=$env:BASELINE_TAG;commit=$env:BASELINE_SHA}
  source=[ordered]@{repository=$env:GITHUB_REPOSITORY;ref=$env:GITHUB_REF;commit=$env:GITHUB_SHA;qualification_run_id=$env:QUALIFICATION_RUN_ID}
  toolchain=$toolchain
  netgen=[ordered]@{configuration="Release";cxx_standard=17;linkage="static";msvc_runtime="MultiThreadedDLL";native_arch=$false}
  occt=[ordered]@{version="8.0.1";commit=$env:OCCT_SOURCE_SHA;linkage="static";bundled=$true;profile="lean";toolkit_count=28}
  zlib=[ordered]@{version="1.3.1";sha256=$env:ZLIB_SHA256;linkage="static";msvc_runtime="MultiThreadedDLL"}
  artifact_hashes=$hashes
}
$info | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath "$sdk\producer-info.json"

function Test-Consumer([string]$Root,[string]$BuildDir){
  if(Test-Path -LiteralPath $BuildDir){Remove-Item -LiteralPath $BuildDir -Recurse -Force}
  & cmake -S "$source\tests\windows-native-sdk" -B $BuildDir -G "Visual Studio 17 2022" -A x64 "-DNETGEN_SDK_DIR=$Root" "-DOCCT_INCLUDE_DIR=$Root\occt\inc"
  if($LASTEXITCODE -ne 0){throw "Static SDK consumer configure failed."}
  cmake --build $BuildDir --config Release
  if($LASTEXITCODE -ne 0){throw "Static SDK consumer build failed."}
  $exe="$BuildDir\Release\netgen_native_sdk_smoke.exe"
  $savedPath=$env:PATH
  try {
    $env:PATH="$env:SystemRoot\System32;$env:SystemRoot"
    & $exe "$source\tests\windows-native-sdk\vertex.brep"
    if($LASTEXITCODE -ne 0){throw "Static SDK OCC smoke failed."}
  }
  finally { $env:PATH=$savedPath }
  $imports=Get-Imports $exe $dumpbin
  if($imports | Where-Object {$_ -match '^(?i)(ngcore|nglib|TK.*|zlib1)\.dll$'}){
    throw "Static consumer imports SDK DLLs: $($imports -join ', ')"
  }
}
Test-Consumer $sdk (Join-Path $work "consumer-staged")

$archive=Join-Path $out $ArchiveName
Compress-Archive -Path "$sdk\*" -DestinationPath $archive -CompressionLevel Optimal
$hash=(Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash.ToLowerInvariant()
"$hash  $ArchiveName" | Set-Content -LiteralPath (Join-Path $out "$ArchiveName.sha256") -NoNewline
Remove-Item -LiteralPath $sdk -Recurse -Force
Remove-Item -LiteralPath $netgenInstall -Recurse -Force
$relocated=Join-Path $work "relocated"
Expand-Archive -LiteralPath $archive -DestinationPath $relocated
$top=@(Get-ChildItem -LiteralPath $relocated | Select-Object -ExpandProperty Name | Sort-Object)
$expected=@("cmake","include","lib","occt","producer-info.json") | Sort-Object
if(Compare-Object $top $expected){throw "Unexpected relocated static SDK layout: $($top -join ', ')"}
if(@(Get-ChildItem -LiteralPath $relocated -Recurse -File -Filter "*.dll").Count -ne 0){throw "Relocated static SDK contains DLLs."}
Test-Consumer $relocated (Join-Path $work "consumer-relocated")
$side=((Get-Content -LiteralPath (Join-Path $out "$ArchiveName.sha256") -Raw) -split '\s+')[0].ToLowerInvariant()
$actual=(Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash.ToLowerInvariant()
if($side -ne $actual){throw "Static archive checksum mismatch."}
