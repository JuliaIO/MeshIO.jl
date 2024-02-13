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
    uvn_mesh = merge(map(uv_normal_mesh, mesh))
    mesh = merge(map(triangle_mesh, mesh))


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
            @test msh isa GLNormalMesh
            @test length(faces(msh)) == 828
            @test length(coordinates(msh)) == 2484
            @test length(msh.normals) == 2484
            @test test_face_indices(msh)

            mktempdir() do tmpdir
                save(File{format"STL_BINARY"}(joinpath(tmpdir, "test.stl")), msh)
                msh1 = load(joinpath(tmpdir, "test.stl"))
                @test msh1 isa GLNormalMesh
                @test faces(msh) == faces(msh1)
                @test coordinates(msh) == coordinates(msh1)
                @test msh.normals == msh1.normals
            end

            msh = load(joinpath(tf, "binary_stl_from_solidworks.STL"))
            @test msh isa GLNormalMesh
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
            @test length(coordinates(msh)) == 2520
            @test length(normals(msh)) == 2520
            @test test_face_indices(msh)

            msh = load(joinpath(tf, "cube.obj")) # quads
            @test length(faces(msh)) == 12
            @test length(coordinates(msh)) == 8
            @test test_face_indices(msh)

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
            #msh = load(joinpath(tf, "sphere5.gts"))
            #@test typeof(msh) == GLNormalMesh
            #test_face_indices(msh)
        end
    end
end
