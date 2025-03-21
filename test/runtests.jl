using FileIO, GeometryBasics
using Test
const tf = joinpath(dirname(@__FILE__), "testfiles")
using MeshIO

function test_face_indices(mesh)
    for face in faces(mesh)
        for index in face
            pass = firstindex(coordinates(mesh)) <= index <= lastindex(coordinates(mesh))
            pass || return false
        end
    end
    return true
end

@testset "MeshIO" begin
    dirlen = 1.0f0
    baselen = 0.02f0
    mesh = [
        Rect3f(Vec3f(baselen), Vec3f(dirlen, baselen, baselen)),
        Rect3f(Vec3f(baselen), Vec3f(baselen, dirlen, baselen)),
        Rect3f(Vec3f(baselen), Vec3f(baselen, baselen, dirlen))
    ]
    uvn_mesh = GeometryBasics.expand_faceviews(merge(map(uv_normal_mesh, mesh)))
    mesh     = GeometryBasics.expand_faceviews(merge(map(triangle_mesh, mesh)))
    empty!(uvn_mesh.views)
    empty!(mesh.views)


    mktempdir() do tmpdir
        for ext in ["2dm", "off", "obj"]
            @testset "load save $ext" begin
                save(joinpath(tmpdir, "test.$ext"), mesh)
                mesh_loaded = load(joinpath(tmpdir, "test.$ext"))
                @test mesh_loaded == mesh
            end
        end
        @testset "PLY ascii and binary" begin
            f = File{format"PLY_ASCII"}(joinpath(tmpdir, "test.ply"))
            save(f, mesh)
            mesh_loaded = load(joinpath(tmpdir, "test.ply"))
            @test mesh_loaded == mesh
            save(File{format"PLY_BINARY"}(joinpath(tmpdir, "test.ply")), mesh)
        end
        @testset "STL ascii and binary" begin
            save(File{format"STL_ASCII"}(joinpath(tmpdir, "test.stl")), mesh)
            mesh_loaded = load(joinpath(tmpdir, "test.stl"))
            @test Set(mesh.position) == Set(mesh_loaded.position)
            save(File{format"STL_BINARY"}(joinpath(tmpdir, "test.stl")), mesh)
            mesh_loaded = load(joinpath(tmpdir, "test.stl"))
            @test Set(mesh.position) == Set(mesh_loaded.position)
        end
        @testset "load save OBJ" begin
            save(joinpath(tmpdir, "test.obj"), uvn_mesh)
            mesh_loaded = load(joinpath(tmpdir, "test.obj"))
            @test mesh_loaded == uvn_mesh
        end
    end


    @testset "Real world files" begin

        @testset "STL" begin
            msh = load(joinpath(tf, "ascii.stl"))
            @test length(faces(msh)) == 12
            @test length(coordinates(msh)) == 36
            @test length(normals(msh)) == 36
            @test test_face_indices(msh)

            msh = load(joinpath(tf, "binary.stl"))
            @test msh isa Mesh{D, Float32, GLTriangleFace} where D
            @test all(v -> v isa AbstractVector, values(vertex_attributes(msh)))
            @test length(faces(msh)) == 828
            @test length(coordinates(msh)) == 2484
            @test length(normals(msh)) == 2484
            @test test_face_indices(msh)

            mktempdir() do tmpdir
                save(File{format"STL_BINARY"}(joinpath(tmpdir, "test.stl")), msh)
                msh1 = load(joinpath(tmpdir, "test.stl"))
                @test msh1 isa Mesh{D, Float32, GLTriangleFace} where D
                @test all(v -> v isa AbstractVector, values(vertex_attributes(msh1)))
                @test faces(msh) == faces(msh1)
                @test coordinates(msh) == coordinates(msh1)
                @test normals(msh) == normals(msh1)
            end

            msh = load(joinpath(tf, "binary_stl_from_solidworks.STL"))
            @test msh isa Mesh{D, Float32, GLTriangleFace} where D
            @test all(v -> v isa AbstractVector, values(vertex_attributes(msh)))
            @test length(faces(msh)) == 12
            @test length(coordinates(msh)) == 36
            @test test_face_indices(msh)

            # STL Import
            msh = load(joinpath(tf, "cube_binary.stl"))
            @test length(coordinates(msh)) == 36
            @test length(faces(msh)) == 12
            @test test_face_indices(msh)


            msh = load(joinpath(tf, "cube.stl"))
            @test length(coordinates(msh)) == 36
            @test length(faces(msh)) == 12
            @test test_face_indices(msh)

        end
        @testset "PLY" begin
            msh = load(joinpath(tf, "ascii.ply"))
            @test length(faces(msh)) == 36
            @test test_face_indices(msh)
            @test length(coordinates(msh)) == 72

            msh = load(joinpath(tf, "binary.ply"))
            @test length(faces(msh)) == 36
            @test test_face_indices(msh)
            @test length(coordinates(msh)) == 72

            msh = load(joinpath(tf, "cube.ply")) # quads
            @test length(coordinates(msh)) == 24
            @test length(faces(msh)) == 12
            @test test_face_indices(msh)
        end
        @testset "OFF" begin
            msh = load(joinpath(tf, "test.off"))
            @test length(faces(msh)) == 28
            @test length(coordinates(msh)) == 20
            @test test_face_indices(msh)

            msh = load(joinpath(tf, "test2.off"))
            @test length(faces(msh)) == 810
            @test length(coordinates(msh)) == 405
            @test test_face_indices(msh)

            msh = load(joinpath(tf, "cube.off"))
            @test length(faces(msh)) == 12
            @test length(coordinates(msh)) == 8
            @test test_face_indices(msh)
        end
        @testset "OBJ" begin
            msh = load(joinpath(tf, "test.obj"))
            @test length(faces(msh)) == 3954
            @test length(coordinates(msh)) == 2248
            @test length(normals(msh)) == 2240
            @test length(texturecoordinates(msh)) == 2220
            @test test_face_indices(msh)

            msh = load(joinpath(tf, "cube.obj")) # quads
            @test msh isa MetaMesh
            @test length(faces(msh)) == 12
            @test length(coordinates(msh)) == 8
            @test test_face_indices(msh)

            @testset "OBJ meta and mtl data" begin
                @test msh[:material_names] == ["Material"]
                @test msh[:shading] == BitVector([0])
                @test msh[:object] == ["Cube"]
                @test length(msh[:materials]) == 1
                @test length(msh[:materials]["Material"]) == 7
                @test msh[:materials]["Material"]["refractive index"]   === 1f0
                @test msh[:materials]["Material"]["illumination model"] === 2
                @test msh[:materials]["Material"]["alpha"]              === 1f0
                @test msh[:materials]["Material"]["diffuse"]            === Vec3f(0.64, 0.64, 0.64)
                @test msh[:materials]["Material"]["specular"]           === Vec3f(0.5, 0.5, 0.5)
                @test msh[:materials]["Material"]["shininess"]          === 96.07843f0
                @test msh[:materials]["Material"]["ambient"]            === Vec3f(0.0, 0.0, 0.0)
            end

            msh = Mesh(load(joinpath(tf, "cube_uv.obj")))
            @test typeof(msh.uv) == Vector{Vec{2,Float32}}
            @test length(msh.uv) == 8

            msh = load(joinpath(tf, "cube_uvw.obj"))
            @test typeof(msh.uv) == Vector{Vec{3,Float32}}
            @test length(msh.uv) == 8

            msh = load(joinpath(tf, "polygonal_face.obj"))
            @test length(faces(msh)) == 4
            @test length(coordinates(msh)) == 6
            @test test_face_indices(msh)

            msh = load(joinpath(tf, "test_face_normal.obj"))
            @test length(faces(msh)) == 1
            @test length(coordinates(msh)) == 3
            @test test_face_indices(msh)
        end
        @testset "2DM" begin
            msh = load(joinpath(tf, "test.2dm"))
            @test test_face_indices(msh)
        end
        @testset "GMSH" begin
            msh = load(joinpath(tf, "cube.msh"))
            @test length(faces(msh)) == 24
            @test length(coordinates(msh)) == 14
            @test test_face_indices(msh)
        end
        @testset "GTS" begin
            # TODO: FileIO upstream
            # msh = load(joinpath(tf, "sphere5.gts"))
            # @test typeof(msh) == GLNormalMesh
            # test_face_indices(msh)
        end

        @testset "Partial Sponza (OBJ)" begin
            # reduced version of the Sponza model from https://casual-effects.com/data/
            # Contains one sub-mesh and all materials
            msh = load(joinpath(tf, "mini sponza/sponza.obj"))

            @test msh isa MetaMesh
            @test length(faces(msh)) == 1344
            @test length(coordinates(msh)) == 1236
            @test length(texturecoordinates(msh)) == 1236
            @test msh.views == [0x00000001:0x000000c0, 0x000000c1:0x00000540]
            @test test_face_indices(msh)

            # :groups, :material_names are in sync with views
            @test haskey(msh, :groups)
            @test msh[:groups] == ["arcs_floor", "arcs_03"]
            @test haskey(msh, :material_names)
            @test msh[:material_names] == ["sp_00_luk_mali", "sp_00_luk_mali"]

            # :materials are all of them
            @test haskey(msh, :materials)
            material_names = ["sp_01_stup", "sp_svod_kapitel", "sp_vijenac", "sp_00_pod", "sp_02_reljef", "sp_00_vrata_kock", "sp_zid_vani", "sp_00_vrata_krug", "sp_01_stub_baza", "sp_01_stub", "sp_00_luk_mali", "sp_01_stub_kut", "sp_00_svod", "sp_00_luk_mal1", "sp_00_zid", "sp_00_prozor", "sp_01_luk_a", "sp_00_stup", "sp_01_stub_baza_", "sp_01_stup_baza"]
            @test all(k -> haskey(msh[:materials], k), material_names)

            # Test one explicitly
            material = msh[:materials]["sp_00_luk_mali"]
            @test material["refractive index"]    == 1.5
            @test material["diffuse"]             == Vec3f(0.745098, 0.709804, 0.67451)
            @test material["transmission filter"] == 1.0
            @test material["ambient"]             == Vec3f(0.0, 0.0, 0.0)
            @test material["specular"]            == Vec3f(0.0, 0.0, 0.0)
            @test material["alpha"]               == 1.0
            @test material["illumination model"]  == 2
            @test material["shininess"]           == 50.0
            @test material["emissive"]            == 0.0

            @test material["bump map"] isa Dict{String, Any}
            @test material["bump map"]["filename"]    == replace(joinpath(tf, "mini sponza/sp_luk-bump.JPG"), '\\' => '/')
            @test material["ambient map"] isa Dict{String, Any}
            @test material["ambient map"]["filename"] == replace(joinpath(tf, "mini sponza/SP_LUK.JPG"), '\\' => '/')
            @test material["diffuse map"] isa Dict{String, Any}
            @test material["diffuse map"]["filename"] == replace(joinpath(tf, "mini sponza/SP_LUK.JPG"), '\\' => '/')
        end
    end
end
