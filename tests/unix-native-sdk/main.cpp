#include <iostream>
#include <core/version.hpp>

namespace nglib
{
#include <nglib.h>
#include <nglib_occ.h>
}

using namespace nglib;

int main(int argc, char ** argv)
{
  if(argc != 3)
  {
    std::cerr << "usage: netgen_native_sdk_smoke <fixture.brep> <expected-version>\n";
    return 2;
  }

  const std::string expected_version = "v" + std::string(argv[2]);
  const std::string runtime_version = ngcore::GetLibraryVersion("netgen").to_string();
  if(runtime_version != expected_version)
  {
    std::cerr << "runtime Netgen version " << runtime_version
              << " does not match " << expected_version << "\n";
    return 5;
  }

  Ng_Init();
  Ng_OCC_Geometry * geometry = Ng_OCC_Load_BREP(argv[1]);
  if(!geometry)
  {
    std::cerr << "Ng_OCC_Load_BREP returned null\n";
    Ng_Exit();
    return 3;
  }

  if(Ng_OCC_DeleteGeometry(geometry) != NG_OK)
  {
    std::cerr << "Ng_OCC_DeleteGeometry failed\n";
    Ng_Exit();
    return 4;
  }

  Ng_Exit();
  return 0;
}
