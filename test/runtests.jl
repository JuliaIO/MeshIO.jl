using FileIO, GeometryTypes
using Test
const tf = joinpath(dirname(@__FILE__), "testfiles")

@testset "MeshIO" begin
    dirlen = 1f0
    baselen = 0.02f0
    mesh = [
        AABB{Float32}(Vec3f0(baselen), Vec3f0(dirlen, baselen, baselen)),
        AABB{Float32}(Vec3f0(baselen), Vec3f0(baselen, dirlen, baselen)),
        AABB{Float32}(Vec3f0(baselen), Vec3f0(baselen, baselen, dirlen))
    ]
    mesh = merge(map(GLPlainMesh, mesh))
    mktempdir() do tmpdir
        for ext in ["2dm", "off"]
            @testset "load save $ext" begin
                save(joinpath(tmpdir, "test.$ext"), mesh)
                mesh_loaded = load(joinpath(tmpdir, "test.$ext"), GLPlainMesh)
                @test mesh_loaded == mesh
            end
        end
        @testset "PLY ascii and binary" begin
            f = File(format"PLY_ASCII", joinpath(tmpdir, "test.ply"))
            save(f, mesh)
            mesh_loaded = load(joinpath(tmpdir, "test.ply"), GLPlainMesh)
            @test mesh_loaded == mesh
            save(File(format"PLY_BINARY", joinpath(tmpdir, "test.ply")), mesh)
        end
        @testset "STL ascii and binary" begin
            save(File(format"STL_ASCII", joinpath(tmpdir, "test.stl")), mesh)
            mesh_loaded = load(joinpath(tmpdir, "test.stl"), GLPlainMesh)
            #@test mesh_loaded == mesh
            save(File(format"STL_BINARY", joinpath(tmpdir, "test.stl")), mesh)
            mesh_loaded = load(joinpath(tmpdir, "test.stl"), GLNormalMesh)
            #@test mesh_loaded == mesh
        end
    end
    @testset "Real world files" begin

        @testset "STL" begin
            msh = load(joinpath(tf, "ascii.stl"))
            @test typeof(msh) == GLNormalMesh
            @test length(faces(msh)) == 12
            @test length(vertices(msh)) == 36
            @test length(normals(msh)) == 36

            msh = load(joinpath(tf, "binary.stl"))
            @test typeof(msh) == GLNormalMesh
            @test length(faces(msh)) == 828
            @test length(vertices(msh)) == 2484
            @test length(normals(msh)) == 2484

            mktempdir() do tmpdir
                save(File(format"STL_BINARY", joinpath(tmpdir, "test.stl")), msh)
                msh1 = load(joinpath(tmpdir, "test.stl"))
                @test typeof(msh1) == GLNormalMesh
                @test faces(msh) == faces(msh1)
                @test vertices(msh) == vertices(msh1)
                @test normals(msh) == normals(msh1)
            end

            msh = load(joinpath(tf, "binary_stl_from_solidworks.STL"))
            @test typeof(msh) == GLNormalMesh
            @test length(faces(msh)) == 12
            @test length(vertices(msh)) == 36

            # STL Import
            msh = load(joinpath(tf, "cube_binary.stl"))
            @test length(vertices(msh)) == 36
            @test length(faces(msh)) == 12


            msh = load(joinpath(tf, "cube.stl"))
            @test length(vertices(msh)) == 36
            @test length(faces(msh)) == 12

        end
        @testset "PLY" begin
            msh = load(joinpath(tf, "ascii.ply"))
            @test typeof(msh) == GLNormalMesh
            @test length(faces(msh)) == 36
            @test length(vertices(msh)) == 72
            @test length(normals(msh)) == 72
            #msh = load(joinpath(tf, "binary.ply")) # still missing
            #@test typeof(msh) == GLNormalMesh
            #println(msh)
            msh = load(joinpath(tf, "cube.ply")) # quads
            @test length(vertices(msh)) == 24
            @test length(faces(msh)) == 12
        end
        @testset "OFF" begin
            msh = load(joinpath(tf, "test.off"))
            @test typeof(msh) == GLNormalMesh
            @test length(faces(msh)) == 28
            @test length(vertices(msh)) == 20
            @test length(normals(msh)) == 20

            msh = load(joinpath(tf, "test2.off"))
            @test typeof(msh) == GLNormalMesh
            @test length(faces(msh)) == 810
            @test length(vertices(msh)) == 405
            @test length(normals(msh)) == 405

            msh = load(joinpath(tf, "cube.off"))
            @test typeof(msh) == GLNormalMesh
            @test length(faces(msh)) == 12
            @test length(vertices(msh)) == 8

        end
        @testset "OBJ" begin
            msh = load(joinpath(tf, "test.obj"))
            @test typeof(msh) == GLNormalMesh
            @test length(faces(msh)) == 3954
            @test length(vertices(msh)) == 2248
            @test length(normals(msh)) == 2248

            msh = load(joinpath(tf, "cube.obj")) # quads
            @test length(faces(msh)) == 12
            @test length(vertices(msh)) == 8

            msh = load(joinpath(tf, "polygonal_face.obj"))
            @test length(faces(msh)) == 4
            @test length(vertices(msh)) == 6

            msh = load(joinpath(tf, "test_face_normal.obj"))
            @test length(faces(msh)) == 1
            @test length(vertices(msh)) == 3

        end
        @testset "2DM" begin
            msh = load(joinpath(tf, "test.2dm"))
            @test typeof(msh) == GLNormalMesh
            #@test length(faces(msh)) == 3954
            #@test length(vertices(msh)) == 2248
            #@test length(normals(msh)) == 2248
        end
    end
end




if false
    #using GLVisualize, GLAbstraction, FileIO
    w = glscreen()
    meshes = [visualize(load(joinpath(tf, name))) for name in readdir(tf)];
    meshes = convert(Matrix{Context}, reshape(meshes, (7, 2)));
    view(visualize(meshes))
    renderloop(w)
end
#=

amf1 = mesh(data_path*"pyramid.amf")
@test length(amf1[1].vertices) == 5
@test length(amf1[1].faces) == 4
@test length(amf1[2].vertices) == 5
@test length(amf1[2].faces) == 4

amf1 = mesh(data_path*"pyramid_zip.amf")
@test length(amf1[1].vertices) == 5
@test length(amf1[1].faces) == 4
@test length(amf1[2].vertices) == 5
@test length(amf1[2].faces) == 4
=#
