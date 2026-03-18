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

            msh = load(joinpath(tf, "cube.ply")) # quads with normals
            @test length(coordinates(msh)) == 24
            @test length(faces(msh)) == 12
            @test test_face_indices(msh)
            @test length(normals(msh)) == 24
            @test normals(msh)[1] ≈ Vec3f(0, 0, -1)

            @testset "ASCII normals + UVs" begin
                msh = load(joinpath(tf, "ascii_normals_uvs.ply"))
                @test length(coordinates(msh)) == 4
                @test length(faces(msh)) == 2
                @test test_face_indices(msh)
                @test length(normals(msh)) == 4
                @test all(n -> n ≈ Vec3f(0, 0, 1), normals(msh))
                @test haskey(vertex_attributes(msh), :uv)
                uvs = msh.uv
                @test length(uvs) == 4
                @test uvs[1] ≈ Vec2f(0, 0)
                @test uvs[2] ≈ Vec2f(1, 0)
                @test uvs[3] ≈ Vec2f(1, 1)
                @test uvs[4] ≈ Vec2f(0, 1)
            end

            @testset "ASCII s/t UVs" begin
                msh = load(joinpath(tf, "ascii_st_uvs.ply"))
                @test length(coordinates(msh)) == 3
                @test length(faces(msh)) == 1
                @test haskey(vertex_attributes(msh), :uv)
                uvs = msh.uv
                @test uvs[1] ≈ Vec2f(0.25, 0.75)
                @test uvs[2] ≈ Vec2f(0.5, 0.5)
                @test uvs[3] ≈ Vec2f(0.0, 1.0)
            end

            @testset "ASCII n-gon triangulation" begin
                msh = load(joinpath(tf, "ascii_pentagon.ply"))
                @test length(coordinates(msh)) == 5
                # Pentagon should be triangulated into 3 triangles
                @test length(faces(msh)) == 3
                @test test_face_indices(msh)
            end

            @testset "ASCII extra elements ignored" begin
                msh = load(joinpath(tf, "ascii_extra_elements.ply"))
                @test length(coordinates(msh)) == 4
                @test length(faces(msh)) == 2
                @test test_face_indices(msh)
            end

            @testset "Binary normals + UVs" begin
                msh = load(joinpath(tf, "binary_normals_uvs.ply"))
                @test length(coordinates(msh)) == 4
                @test length(faces(msh)) == 2
                @test test_face_indices(msh)
                @test length(normals(msh)) == 4
                @test all(n -> n ≈ Vec3f(0, 0, 1), normals(msh))
                @test haskey(vertex_attributes(msh), :uv)
                uvs = msh.uv
                @test uvs[1] ≈ Vec2f(0, 0)
                @test uvs[3] ≈ Vec2f(1, 1)
            end

            @testset "Binary RGBA colors (UInt8)" begin
                msh = load(joinpath(tf, "binary_colors_uint8.ply"))
                @test length(coordinates(msh)) == 3
                @test length(faces(msh)) == 1
                @test haskey(vertex_attributes(msh), :color)
                colors = msh.color
                @test length(colors) == 3
                # UInt8 colors should be normalized to [0,1]
                @test colors[1] ≈ Vec4f(1.0, 0.0, 0.0, 128/255)
                @test colors[2] ≈ Vec4f(0.0, 1.0, 0.0, 1.0)
                @test colors[3] ≈ Vec4f(0.0, 0.0, 1.0, 64/255)
            end

            @testset "Binary RGB colors (UInt8, no alpha)" begin
                msh = load(joinpath(tf, "binary_colors_rgb.ply"))
                @test length(coordinates(msh)) == 3
                @test haskey(vertex_attributes(msh), :color)
                colors = msh.color
                @test colors[1] ≈ Vec3f(1.0, 0.0, 0.0)
                @test colors[2] ≈ Vec3f(0.0, 1.0, 0.0)
                @test colors[3] ≈ Vec3f(0.0, 0.0, 1.0)
            end

            @testset "Binary double positions + float normals" begin
                msh = load(joinpath(tf, "binary_double_positions.ply"))
                @test length(coordinates(msh)) == 3
                @test length(faces(msh)) == 1
                @test test_face_indices(msh)
                # Positions should be converted to Float32
                @test coordinates(msh)[1] ≈ Point3f(0, 0, 0)
                @test coordinates(msh)[2] ≈ Point3f(1, 0, 0)
                @test coordinates(msh)[3] ≈ Point3f(0.5, 1, 0)
                @test length(normals(msh)) == 3
                @test all(n -> n ≈ Vec3f(0, 1, 0), normals(msh))
            end

            @testset "Binary custom scalar properties" begin
                msh = load(joinpath(tf, "binary_custom_scalars.ply"))
                @test length(coordinates(msh)) == 3
                @test haskey(vertex_attributes(msh), :intensity)
                @test haskey(vertex_attributes(msh), :confidence)
                @test msh.intensity[1] ≈ 0.5f0
                @test msh.intensity[2] ≈ 0.8f0
                @test msh.confidence[3] ≈ 0.95f0
            end

            @testset "Binary uint face indices with ushort count" begin
                msh = load(joinpath(tf, "binary_uint_faces.ply"))
                @test length(coordinates(msh)) == 4
                @test length(faces(msh)) == 2
                @test test_face_indices(msh)
            end

            @testset "PLY round-trip with normals" begin
                mktempdir() do tmpdir
                    msh = load(joinpath(tf, "cube.ply"))
                    # Save as ASCII and reload
                    save(File{format"PLY_ASCII"}(joinpath(tmpdir, "cube_rt.ply")), msh)
                    msh2 = load(joinpath(tmpdir, "cube_rt.ply"))
                    @test length(coordinates(msh2)) == length(coordinates(msh))
                    @test length(faces(msh2)) == length(faces(msh))
                    @test length(normals(msh2)) == length(normals(msh))
                    @test normals(msh2) ≈ normals(msh)

                    # Save as binary and reload
                    save(File{format"PLY_BINARY"}(joinpath(tmpdir, "cube_rt.ply")), msh)
                    msh3 = load(joinpath(tmpdir, "cube_rt.ply"))
                    @test length(coordinates(msh3)) == length(coordinates(msh))
                    @test length(faces(msh3)) == length(faces(msh))
                    @test length(normals(msh3)) == length(normals(msh))
                    @test normals(msh3) ≈ normals(msh)
                end
            end
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

            msh = load(joinpath(tf, "cube_uv.obj"))
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
            @test length(normals(msh)) == 3
            @test test_face_indices(msh)
            @test normals(msh) isa FaceView

            # test correctness of reordered vertices
            msh2 = expand_faceviews(Mesh(msh))
            @test !(normals(msh2) isa FaceView)
            @test length(faces(msh2)) == 1
            @test all(coordinates(coordinates(msh2)[faces(msh2)[1]]) .==[Point3f(0), Point3f(0.062805, 0.591207, 0.902102), Point3f(0.058382, 0.577691, 0.904429)])
            @test all(normals(msh2)[faces(msh2)[1]] .== [Vec3f(0.9134, 0.104, 0.3934), Vec3f(0.8079, 0.4428, 0.3887), Vec3f(0.8943, 0.4474, 0.0)])
            # test that save works with FaceViews
            mktempdir() do tmpdir
                save(joinpath(tmpdir, "test.obj"), msh)
                msh1 = load(joinpath(tmpdir, "test.obj"))
                msh3 = expand_faceviews(Mesh(msh1)) # should be unnecessary atm
                @test length(faces(msh2)) == length(faces(msh3))
                for (f1, f2) in zip(faces(msh2), faces(msh3))
                    @test coordinates(msh2)[f1] == coordinates(msh3)[f2]
                    @test normals(msh2)[f1] == normals(msh3)[f2]
                end
            end
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
        @testset "GLB" begin
            msh = load(joinpath(tf, "cube.glb"))
            @test msh isa MetaMesh
            @test length(faces(msh)) == 12
            @test length(coordinates(msh)) == 24
            @test test_face_indices(msh)
        end
        @testset "GLTF" begin
            msh = load(joinpath(tf, "triangle.gltf"))
            @test msh isa MetaMesh
            @test length(faces(msh)) == 1
            @test length(coordinates(msh)) == 3
            @test test_face_indices(msh)
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

        @testset "INP" begin
            msh = load(joinpath(tf, "cube.inp"))
            @test length(faces(msh)) == 24
            @test length(coordinates(msh)) == 14
            @test msh.views == []
            @test test_face_indices(msh)
        end
    end
end
