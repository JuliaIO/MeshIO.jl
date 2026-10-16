# A rigged glTF built in code, so the numbers that matter sit next to the tests:
#
#   node 0: the mesh, bound to skin 0
#   node 1: the root joint
#   node 2: its child at (1, 0, 0), which the clip rotates
#
# `skin.joints` lists the child first: glTF does not promise parents first, the
# loader must sort and remap.

using Base64: base64encode
using LinearAlgebra: I

function rigged_gltf(; unskinned_primitive_first = false)
    buf = UInt8[]
    views = Any[]
    function view!(xs)
        append!(buf, zeros(UInt8, mod(-length(buf), 4)))
        push!(views, Dict("buffer" => 0, "byteOffset" => length(buf), "byteLength" => sizeof(xs)))
        append!(buf, reinterpret(UInt8, xs))
        return length(views) - 1
    end
    # JOINTS_0 indexes `skin.joints`: 1 is the root, 0 the child.
    data = Any[UInt16[0, 1, 2, 1, 3, 2],                                 # indices
            Float32[0, 0, 0, 1, 0, 0, 2, 0, 0, 3, 0, 0],                # positions
            Float32[0, 0, 1, 0, 0, 1, 0, 0, 1, 0, 0, 1],                # normals
            UInt8[1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0],      # joints
            Float32[1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0],    # weights
            Float32[1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, -1, 0, 0, 1,    # inverse binds, child
                    1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1],    # and root
            Float32[0, 1],                                              # key times
            Float32[0, 0, 0, 1, 0, 0, sinpi(0.25), cospi(0.25)]]        # quarter turn about z
    foreach(view!, data)
    accessor(v, ctype, count, type) = Dict("bufferView" => v, "componentType" => ctype, "count" => count, "type" => type)
    accessors = [accessor(0, 5123, 6, "SCALAR"), accessor(1, 5126, 4, "VEC3"), accessor(2, 5126, 4, "VEC3"),
                 accessor(3, 5121, 4, "VEC4"), accessor(4, 5126, 4, "VEC4"), accessor(5, 5126, 2, "MAT4"),
                 accessor(6, 5126, 2, "SCALAR"), accessor(7, 5126, 2, "VEC4")]
    skinned = Dict("attributes" => Dict("POSITION" => 1, "NORMAL" => 2, "JOINTS_0" => 3, "WEIGHTS_0" => 4),
                   "indices" => 0)
    plain = Dict("attributes" => Dict("POSITION" => 1), "indices" => 0)   # no normals, no skin
    gltf = Dict(
        "asset" => Dict("version" => "2.0"),
        "scene" => 0,
        "scenes" => [Dict("nodes" => [0, 1])],
        "nodes" => [Dict("mesh" => 0, "skin" => 0),
                    Dict("name" => "root", "children" => [2]),
                    Dict("name" => "tip", "translation" => [1.0, 0.0, 0.0])],
        "meshes" => [Dict("primitives" => unskinned_primitive_first ? [plain, skinned] : [skinned])],
        "skins" => [Dict("inverseBindMatrices" => 5, "joints" => [2, 1])],
        "animations" => [Dict(
            "name" => "bend",
            "channels" => [Dict("sampler" => 0, "target" => Dict("node" => 2, "path" => "rotation"))],
            "samplers" => [Dict("input" => 6, "interpolation" => "LINEAR", "output" => 7)])],
        "accessors" => accessors,
        "bufferViews" => views,
        "buffers" => [Dict("byteLength" => length(buf),
                           "uri" => "data:application/octet-stream;base64," * base64encode(buf))])
    path = joinpath(mktempdir(), "rigged.gltf")
    write(path, MeshIO.JSON3.write(gltf))
    return path
end

@testset "glTF skinning" begin
    @testset "skin as vertex attributes plus a sorted skeleton" begin
        mm = load(rigged_gltf())
        skel = mm[:skeleton]
        @test skel.names == ["root", "tip"]
        @test skel.parents == Int32[0, 1]
        @test skel.translation[2] ≈ Vec3f(1, 0, 0)
        @test skel.inverse_bind[1] ≈ Mat4f(I)
        attrs = vertex_attributes(Mesh(mm))
        @test eltype(attrs.skinjoints) === Vec{4, Int32}
        @test first.(attrs.skinjoints) == [1, 1, 2, 2]
        @test all(≈(Vec4f(1, 0, 0, 0)), attrs.skinweights)
    end

    @testset "animation by bone and by node" begin
        mm = load(rigged_gltf())
        clip = only(mm[:animations])
        @test clip.name == "bend" && clip.duration ≈ 1
        track = only(clip.tracks)
        @test (track.bone, track.property, track.times) == (2, :rotation, Float32[0, 1])
        @test track.values[end] ≈ Vec4f(0, 0, sinpi(0.25), cospi(0.25))
        nodes = mm[:nodes]
        @test nodes.names == ["node_0", "root", "tip"]
        @test nodes.parents == Int32[0, 0, 2]
        @test only(only(mm[:node_animations]).tracks).node == 3
    end

    @testset "the up rotation rides on the skeleton root" begin
        # The inverse bind matrices would undo it in the vertices.
        zup, yup = load(rigged_gltf()), load(rigged_gltf(); up = Vec3f(0, 1, 0))
        @test yup[:skeleton].root ≈ Mat4f(I)
        @test zup[:skeleton].root ≈ MeshIO.Y_TO_Z_UP_MAT4F
        @test coordinates(Mesh(zup)) == coordinates(Mesh(yup))
    end

    @testset "attributes a leading primitive lacks are padded" begin
        msh = Mesh(load(rigged_gltf(; unskinned_primitive_first = true)))
        attrs = vertex_attributes(msh)
        @test length(attrs.skinjoints) == length(attrs.normal) == length(coordinates(msh)) == 8
        @test all(iszero, attrs.skinweights[1:4])
        @test first.(attrs.skinjoints[5:8]) == [1, 1, 2, 2]
        @test faces(msh)[3] == GLTriangleFace(5, 6, 7)
    end

    @testset "normalized accessors and matrix nodes" begin
        @test MeshIO.gltf_denormalize((0xff, 0x00, UInt16(65535))) === (1f0, 0f0, 1f0)
        @test MeshIO.gltf_denormalize((Int8(-128), Int8(-127), Int16(32767))) === (-1f0, -1f0, 1f0)
        # A mirrored matrix: the flip lands on x's scale and R stays a rotation.
        c, s = cospi(0.25f0), sinpi(0.25f0)
        m = Mat4f(-2c, -2s, 0, 0, -3s, 3c, 0, 0, 0, 0, 4, 0, 1, 2, 3, 1)
        t, q, sc = MeshIO.gltf_decompose_trs(m)
        @test t ≈ Vec3f(1, 2, 3)
        @test sc ≈ Vec3f(-2, 3, 4)
        @test q ≈ Vec4f(0, 0, sinpi(0.125), cospi(0.125))
    end
end
