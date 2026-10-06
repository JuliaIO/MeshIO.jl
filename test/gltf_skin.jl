# A rigged glTF, built here rather than committed as a binary: the numbers that
# matter — which joint a vertex names, which node is a bone's parent, what the
# inverse bind matrices undo — are then readable next to the assertions.
#
#   node 0: the mesh, bound to skin 0
#   node 1: the root joint, at the origin
#   node 2: its child, translated (1, 0, 0), and the one the clip rotates
#
# `skin.joints` lists the CHILD first. glTF does not promise topological order
# and the runtime requires it, so this exercises the sort and joint remap that
# has to come with it.

using Base64
using LinearAlgebra: I

"Pack `xs` into `buf` at a 4-byte boundary and return its (offset, length)."
function packbytes!(buf::Vector{UInt8}, xs)
    while length(buf) % 4 != 0
        push!(buf, 0x00)
    end
    offset = length(buf)
    append!(buf, reinterpret(UInt8, xs))
    return offset, length(buf) - offset
end

function rigged_gltf(; unskinned_primitive_first::Bool = false)
    buf = UInt8[]
    views = Any[]
    function view!(xs)
        offset, len = packbytes!(buf, xs)
        push!(views, Dict("buffer" => 0, "byteOffset" => offset, "byteLength" => len))
        return length(views) - 1
    end

    indices = UInt16[0, 1, 2, 1, 3, 2]
    positions = Float32[0, 0, 0, 1, 0, 0, 2, 0, 0, 3, 0, 0]
    normals = Float32[0, 0, 1, 0, 0, 1, 0, 0, 1, 0, 0, 1]
    # JOINTS_0 indexes `skin.joints`, so 1 is the root (listed second) and 0 the
    # child. The first two vertices belong to the root, the last two to the child.
    joints = UInt8[1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0]
    weights = Float32[1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0]
    # In `skin.joints` order: the child's bind pose undoes its (1, 0, 0) offset,
    # the root's is the identity. Column-major, as glTF writes matrices.
    inverse_binds = Float32[1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, -1, 0, 0, 1,
                            1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]
    keytimes = Float32[0, 1]
    # A quarter turn about z, over one second.
    keyrots = Float32[0, 0, 0, 1, 0, 0, sinpi(0.25), cospi(0.25)]

    vi, vp, vn, vj, vw, vb, vt, vr =
        view!(indices), view!(positions), view!(normals), view!(joints),
        view!(weights), view!(inverse_binds), view!(keytimes), view!(keyrots)

    accessors = [
        Dict("bufferView" => vi, "componentType" => 5123, "count" => 6, "type" => "SCALAR"),
        Dict("bufferView" => vp, "componentType" => 5126, "count" => 4, "type" => "VEC3",
             "min" => [0.0, 0.0, 0.0], "max" => [3.0, 0.0, 0.0]),
        Dict("bufferView" => vn, "componentType" => 5126, "count" => 4, "type" => "VEC3"),
        Dict("bufferView" => vj, "componentType" => 5121, "count" => 4, "type" => "VEC4"),
        Dict("bufferView" => vw, "componentType" => 5126, "count" => 4, "type" => "VEC4"),
        Dict("bufferView" => vb, "componentType" => 5126, "count" => 2, "type" => "MAT4"),
        Dict("bufferView" => vt, "componentType" => 5126, "count" => 2, "type" => "SCALAR"),
        Dict("bufferView" => vr, "componentType" => 5126, "count" => 2, "type" => "VEC4"),
    ]

    skinned_primitive = Dict(
        "attributes" => Dict("POSITION" => 1, "NORMAL" => 2, "JOINTS_0" => 3, "WEIGHTS_0" => 4),
        "indices" => 0,
    )
    # No JOINTS_0: an unskinned primitive sharing the mesh with a skinned one.
    plain_primitive = Dict(
        "attributes" => Dict("POSITION" => 1, "NORMAL" => 2),
        "indices" => 0,
    )
    primitives = unskinned_primitive_first ? [plain_primitive, skinned_primitive] :
                                             [skinned_primitive]

    gltf = Dict(
        "asset" => Dict("version" => "2.0"),
        "scene" => 0,
        "scenes" => [Dict("nodes" => [0, 1])],
        "nodes" => [
            Dict("mesh" => 0, "skin" => 0),
            Dict("name" => "root", "children" => [2]),
            Dict("name" => "tip", "translation" => [1.0, 0.0, 0.0]),
        ],
        "meshes" => [Dict("primitives" => primitives)],
        "skins" => [Dict("inverseBindMatrices" => 5, "joints" => [2, 1])],
        "animations" => [Dict(
            "name" => "bend",
            "channels" => [Dict("sampler" => 0, "target" => Dict("node" => 2, "path" => "rotation"))],
            "samplers" => [Dict("input" => 6, "interpolation" => "LINEAR", "output" => 7)],
        )],
        "accessors" => accessors,
        "bufferViews" => views,
        "buffers" => [Dict(
            "byteLength" => length(buf),
            "uri" => "data:application/octet-stream;base64," * base64encode(buf),
        )],
    )
    return MeshIO.JSON3.write(gltf)
end

function load_rigged(; up = nothing, kwargs...)
    path = joinpath(mktempdir(), "rigged.gltf")
    write(path, rigged_gltf(; kwargs...))
    return isnothing(up) ? load(path) : load(path; up = up)
end

@testset "glTF skinning" begin

    @testset "a skin arrives as vertex attributes plus a skeleton" begin
        mm = load_rigged()
        @test mm isa MetaMesh
        msh = Mesh(mm)
        attrs = vertex_attributes(msh)
        @test haskey(attrs, :skinjoints) && haskey(attrs, :skinweights)
        skel = mm[:skeleton]
        @test skel isa NamedTuple
        @test length(skel.parents) == 2

        # The file lists the child first; the runtime requires parents first, so
        # the sort has to have reordered them and renamed the joints with them.
        @test skel.names == ["root", "tip"]
        @test skel.parents == Int32[0, 1]
        @test skel.translation[2] ≈ Vec3f(1, 0, 0)

        joints, weights = attrs.skinjoints, attrs.skinweights
        @test eltype(joints) === Vec{4, Int32}
        # 1-based and remapped: the first two vertices name the root, which the
        # file called joint 1 and the sort made bone 1; the last two name bone 2.
        @test [Int(j[1]) for j in joints] == [1, 1, 2, 2]
        @test all(w -> w ≈ Vec4f(1, 0, 0, 0), weights)
    end

    @testset "animation arrives as plain constructor data" begin
        mm = load_rigged()
        clip = only(mm[:animations])
        @test clip.name == "bend"
        @test clip.duration ≈ 1.0f0
        track = only(clip.tracks)
        @test track.bone == 2
        @test track.property === :rotation
        @test track.times == Float32[0, 1]
        @test track.values[end] ≈ Vec4f(0, 0, sinpi(0.25), cospi(0.25))
    end

    @testset "the up rotation reaches a skinned mesh through the skeleton" begin
        # A skinned vertex is placed by its bones, so the up rotation cannot be
        # baked into the vertices — the inverse bind matrices would undo it. It
        # rides on the skeleton's root instead, and this is what says so: the
        # same pose read Y-up and Z-up differs by exactly that rotation.
        zup = load_rigged()
        yup = load_rigged(; up = Vec3f(0, 1, 0))
        @test yup[:skeleton].root ≈ Mat4f(I)
        @test zup[:skeleton].root != yup[:skeleton].root
    end

    @testset "an unskinned primitive before a skinned one keeps the skin" begin
        # The skin used to be dropped from the whole mesh here: padding for
        # unskinned primitives only started once a skinned one had been seen, so
        # a leading unskinned primitive left fewer joints than vertices and the
        # length check at the end silently discarded both attributes.
        mm = load_rigged(; unskinned_primitive_first = true)
        msh = Mesh(mm)
        attrs = vertex_attributes(msh)
        @test haskey(attrs, :skinjoints) && haskey(attrs, :skinweights)
        joints, weights = attrs.skinjoints, attrs.skinweights
        @test length(joints) == length(coordinates(msh))
        # The leading primitive is bound to bone 1 at zero weight, which leaves
        # its vertices where they are.
        @test all(w -> w ≈ Vec4f(0, 0, 0, 0), weights[1:4])
        @test [Int(j[1]) for j in joints[5:8]] == [1, 1, 2, 2]
    end
end
