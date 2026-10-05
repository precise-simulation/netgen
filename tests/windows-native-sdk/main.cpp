#include <nglib.h>
#include <nglib_occ.h>

#include <iostream>

int main(int argc, char ** argv)
{
  if(argc != 2)
  {
    std::cerr << "usage: netgen_native_sdk_smoke <fixture.brep>\n";
    return 2;
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
