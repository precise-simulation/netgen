#include <catch2/catch.hpp>
#include <meshing.hpp>

#include <cmath>

using namespace netgen;


TEST_CASE("Uniform refinement can convert a triangle to three quads")
{
  NetgenGeometry geo;
  Mesh mesh;

  mesh.AddPoint(Point3d(0.0, 0.0, 0.0));
  mesh.AddPoint(Point3d(1.0, 0.0, 0.0));
  mesh.AddPoint(Point3d(0.0, 1.0, 0.0));
  mesh.AddFaceDescriptor(FaceDescriptor(1, 1, 0, 0));

  Element2d trig(TRIG);
  trig.SetIndex(1);
  trig.PNum(1) = PointIndex(1);
  trig.PNum(2) = PointIndex(2);
  trig.PNum(3) = PointIndex(3);
  mesh.AddSurfaceElement(trig);

  geo.GetRefinement().Refine(mesh, true);

  REQUIRE(mesh.GetNSE() == 3);
  REQUIRE(mesh.GetNP() == 7);
  PointIndex center = PointIndex::INVALID;
  for (int i = 1; i <= mesh.GetNP(); i++)
    {
      PointIndex pi(i);
      const auto & p = mesh.Point(pi);
      if (std::abs(p[0]-1.0/3.0) < 1e-12 &&
          std::abs(p[1]-1.0/3.0) < 1e-12 &&
          std::abs(p[2]) < 1e-12)
        center = pi;
    }

  REQUIRE(center.IsValid());
  REQUIRE_FALSE(mesh.mlbetweennodes[center][0].IsValid());
  REQUIRE_FALSE(mesh.mlbetweennodes[center][1].IsValid());

  for (auto & el : mesh.SurfaceElements())
    {
      REQUIRE(el.GetType() == QUAD);
      REQUIRE(el.GetIndex() == 1);

      int original_vertices = 0;
      int center_vertices = 0;
      double signed_area_twice = 0.0;
      for (int k = 1; k <= 4; k++)
        {
          PointIndex pi = el.PNum(k);
          if (pi <= PointIndex(3))
            original_vertices++;
          if (pi == center)
            center_vertices++;

          const auto & p1 = mesh.Point(pi);
          const auto & p2 = mesh.Point(el.PNum(k == 4 ? 1 : k+1));
          signed_area_twice += p1[0]*p2[1] - p2[0]*p1[1];
        }
      REQUIRE(original_vertices == 1);
      REQUIRE(center_vertices == 1);
      REQUIRE(signed_area_twice > 0.0);
    }
}


TEST_CASE("Uniform refinement still refines a triangle to four triangles")
{
  NetgenGeometry geo;
  Mesh mesh;

  mesh.AddPoint(Point3d(0.0, 0.0, 0.0));
  mesh.AddPoint(Point3d(1.0, 0.0, 0.0));
  mesh.AddPoint(Point3d(0.0, 1.0, 0.0));
  mesh.AddFaceDescriptor(FaceDescriptor(1, 1, 0, 0));

  Element2d trig(TRIG);
  trig.SetIndex(1);
  trig.PNum(1) = PointIndex(1);
  trig.PNum(2) = PointIndex(2);
  trig.PNum(3) = PointIndex(3);
  mesh.AddSurfaceElement(trig);

  geo.GetRefinement().Refine(mesh);

  REQUIRE(mesh.GetNSE() == 4);
  REQUIRE(mesh.GetNP() == 6);
  for (auto & el : mesh.SurfaceElements())
    {
      REQUIRE(el.GetType() == TRIG);
      REQUIRE(el.GetIndex() == 1);
    }
}


TEST_CASE("Triangle to quad refinement reuses shared edge midpoints")
{
  NetgenGeometry geo;
  Mesh mesh;

  mesh.AddPoint(Point3d(0.0, 0.0, 0.0));
  mesh.AddPoint(Point3d(1.0, 0.0, 0.0));
  mesh.AddPoint(Point3d(1.0, 1.0, 0.0));
  mesh.AddPoint(Point3d(0.0, 1.0, 0.0));
  mesh.AddFaceDescriptor(FaceDescriptor(1, 1, 0, 0));

  Element2d trig1(TRIG);
  trig1.SetIndex(1);
  trig1.PNum(1) = PointIndex(1);
  trig1.PNum(2) = PointIndex(2);
  trig1.PNum(3) = PointIndex(3);
  mesh.AddSurfaceElement(trig1);

  Element2d trig2(TRIG);
  trig2.SetIndex(1);
  trig2.PNum(1) = PointIndex(1);
  trig2.PNum(2) = PointIndex(3);
  trig2.PNum(3) = PointIndex(4);
  mesh.AddSurfaceElement(trig2);

  geo.GetRefinement().Refine(mesh, true);

  REQUIRE(mesh.GetNSE() == 6);
  REQUIRE(mesh.GetNP() == 11);
  for (auto & el : mesh.SurfaceElements())
    REQUIRE(el.GetType() == QUAD);

  int shared_midpoints = 0;
  int triangle_centers = 0;
  for (int i = 1; i <= mesh.GetNP(); i++)
    {
      PointIndex pi(i);
      const auto & p = mesh.Point(pi);
      if (std::abs(p[0]-0.5) < 1e-12 &&
          std::abs(p[1]-0.5) < 1e-12 &&
          std::abs(p[2]) < 1e-12)
        {
          shared_midpoints++;
          auto parents = mesh.mlbetweennodes[pi];
          REQUIRE(parents[0] == PointIndex(1));
          REQUIRE(parents[1] == PointIndex(3));
        }
      if ((std::abs(p[0]-2.0/3.0) < 1e-12 && std::abs(p[1]-1.0/3.0) < 1e-12) ||
          (std::abs(p[0]-1.0/3.0) < 1e-12 && std::abs(p[1]-2.0/3.0) < 1e-12))
        {
          triangle_centers++;
          REQUIRE_FALSE(mesh.mlbetweennodes[pi][0].IsValid());
          REQUIRE_FALSE(mesh.mlbetweennodes[pi][1].IsValid());
        }
    }
  REQUIRE(shared_midpoints == 1);
  REQUIRE(triangle_centers == 2);
}


TEST_CASE("Triangle to quad refinement keeps duplicate triangle centers distinct")
{
  NetgenGeometry geo;
  Mesh mesh;

  mesh.AddPoint(Point3d(0.0, 0.0, 0.0));
  mesh.AddPoint(Point3d(1.0, 0.0, 0.0));
  mesh.AddPoint(Point3d(0.0, 1.0, 0.0));
  mesh.AddFaceDescriptor(FaceDescriptor(1, 1, 0, 0));

  for (int i = 0; i < 2; i++)
    {
      Element2d trig(TRIG);
      trig.SetIndex(1);
      trig.PNum(1) = PointIndex(1);
      trig.PNum(2) = PointIndex(2);
      trig.PNum(3) = PointIndex(3);
      mesh.AddSurfaceElement(trig);
    }

  geo.GetRefinement().Refine(mesh, true);

  REQUIRE(mesh.GetNSE() == 6);
  REQUIRE(mesh.GetNP() == 8);

  NgArray<PointIndex> centers;
  for (PointIndex pi : mesh.Points().Range())
    {
      const auto & p = mesh.Point(pi);
      if (std::abs(p[0]-1.0/3.0) < 1e-12 &&
          std::abs(p[1]-1.0/3.0) < 1e-12 &&
          std::abs(p[2]) < 1e-12)
        centers.Append(pi);
    }

  REQUIRE(centers.Size() == 2);
  for (auto center : centers)
    {
      REQUIRE_FALSE(mesh.mlbetweennodes[center][0].IsValid());
      REQUIRE_FALSE(mesh.mlbetweennodes[center][1].IsValid());

      int uses = 0;
      for (const auto & el : mesh.SurfaceElements())
        for (auto pi : el.PNums())
          if (pi == center)
            uses++;
      REQUIRE(uses == 3);
    }
}


TEST_CASE("Triangle to quad refinement preserves identified triangle centers")
{
  NetgenGeometry geo;
  Mesh mesh;

  mesh.AddPoint(Point3d(0.0, 0.0, 0.0));
  mesh.AddPoint(Point3d(1.0, 0.0, 0.0));
  mesh.AddPoint(Point3d(0.0, 1.0, 0.0));
  mesh.AddPoint(Point3d(2.0, 0.0, 0.0));
  mesh.AddPoint(Point3d(3.0, 0.0, 0.0));
  mesh.AddPoint(Point3d(2.0, 1.0, 0.0));
  mesh.AddFaceDescriptor(FaceDescriptor(1, 1, 0, 0));

  Element2d trig1(TRIG);
  trig1.SetIndex(1);
  trig1.PNum(1) = PointIndex(1);
  trig1.PNum(2) = PointIndex(2);
  trig1.PNum(3) = PointIndex(3);
  mesh.AddSurfaceElement(trig1);

  Element2d trig2(TRIG);
  trig2.SetIndex(1);
  trig2.PNum(1) = PointIndex(4);
  trig2.PNum(2) = PointIndex(5);
  trig2.PNum(3) = PointIndex(6);
  mesh.AddSurfaceElement(trig2);

  mesh.GetIdentifications().Add(PointIndex(1), PointIndex(4), 1);
  mesh.GetIdentifications().Add(PointIndex(2), PointIndex(5), 1);
  mesh.GetIdentifications().Add(PointIndex(3), PointIndex(6), 1);

  geo.GetRefinement().Refine(mesh, true);

  PointIndex center1 = PointIndex::INVALID;
  PointIndex center2 = PointIndex::INVALID;
  for (PointIndex pi : mesh.Points().Range())
    {
      const auto & p = mesh.Point(pi);
      if (std::abs(p[0]-1.0/3.0) < 1e-12 && std::abs(p[1]-1.0/3.0) < 1e-12)
        center1 = pi;
      if (std::abs(p[0]-7.0/3.0) < 1e-12 && std::abs(p[1]-1.0/3.0) < 1e-12)
        center2 = pi;
    }

  REQUIRE(center1.IsValid());
  REQUIRE(center2.IsValid());
  REQUIRE(mesh.GetIdentifications().Get(center1, center2) == 1);
}


TEST_CASE("Triangle to quad refinement rejects volume meshes")
{
  NetgenGeometry geo;
  Mesh mesh;

  mesh.AddPoint(Point3d(0.0, 0.0, 0.0));
  mesh.AddPoint(Point3d(1.0, 0.0, 0.0));
  mesh.AddPoint(Point3d(0.0, 1.0, 0.0));
  mesh.AddPoint(Point3d(0.0, 0.0, 1.0));

  Element tet(TET);
  tet.PNum(1) = PointIndex(1);
  tet.PNum(2) = PointIndex(2);
  tet.PNum(3) = PointIndex(3);
  tet.PNum(4) = PointIndex(4);
  mesh.AddVolumeElement(tet);

  REQUIRE_THROWS(geo.GetRefinement().Refine(mesh, true));
  REQUIRE(mesh.GetNE() == 1);
  REQUIRE(mesh.GetNP() == 4);
}


TEST_CASE("Uniform refinement still refines a quad to four quads")
{
  NetgenGeometry geo;
  Mesh mesh;

  mesh.AddPoint(Point3d(0.0, 0.0, 0.0));
  mesh.AddPoint(Point3d(2.0, 0.0, 0.0));
  mesh.AddPoint(Point3d(1.5, 1.0, 0.0));
  mesh.AddPoint(Point3d(0.0, 2.0, 0.0));
  mesh.AddFaceDescriptor(FaceDescriptor(1, 1, 0, 0));

  Element2d quad(QUAD);
  quad.SetIndex(1);
  quad.PNum(1) = PointIndex(1);
  quad.PNum(2) = PointIndex(2);
  quad.PNum(3) = PointIndex(3);
  quad.PNum(4) = PointIndex(4);
  mesh.AddSurfaceElement(quad);

  geo.GetRefinement().Refine(mesh);

  REQUIRE(mesh.GetNSE() == 4);
  REQUIRE(mesh.GetNP() == 9);
  for (auto & el : mesh.SurfaceElements())
    REQUIRE(el.GetType() == QUAD);

  bool found_center = false;
  for (PointIndex pi : mesh.Points().Range())
    {
      const auto & p = mesh.Point(pi);
      if (std::abs(p[0]-0.75) < 1e-12 &&
          std::abs(p[1]-0.5) < 1e-12 &&
          std::abs(p[2]) < 1e-12)
        found_center = true;
    }
  REQUIRE(found_center);
}
