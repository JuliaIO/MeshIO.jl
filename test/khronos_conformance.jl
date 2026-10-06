# Khronos' own test assets, run against this loader and GeometryBasics' skinning.
#
# Two suites, and they do different jobs:
#
#   glTF-Asset-Generator  systematically varies ONE feature at a time —
#                         Animation_Skin, Animation_SkinType (joint and weight
#                         component types, including `normalized` integers),
#                         Node_NegativeScale (mirrored transforms). This is the
#                         conformance matrix.
#   glTF-Sample-Assets    real rigs: SimpleSkin, RiggedSimple, RiggedFigure,
#                         Fox, RecursiveSkeletons. This is the reality check.
#
# The assets are not vendored. `fetch_khronos.jl` downloads them; without them
# this file skips, so a checkout with no network still runs green.

const KHRONOS = joinpath(@__DIR__, "khronos")

"The glTF JSON of either a `.gltf` or a `.glb`, for checking what a file contains."
function gltf_document(path)
    endswith(path, ".gltf") && return MeshIO.JSON3.read(read(path, String))
    open(path) do io
        read(io, 12)                                  # magic, version, length
        len = read(io, UInt32); read(io, UInt32)      # chunk length, chunk type
        MeshIO.JSON3.read(String(read(io, len)))
    end
end



khronos_models() = sort!([joinpath(d, f) for (d, _, fs) in walkdir(KHRONOS)
                          for f in fs if endswith(f, ".gltf") || endswith(f, ".glb")])

if !isdir(KHRONOS) || isempty(khronos_models())
    @info "Khronos assets absent; run test/fetch_khronos.jl to enable these tests"
else
    @testset "Khronos glTF conformance" begin
        models = khronos_models()
        @test length(models) > 20

        @testset "every model loads" begin
            for f in models
                @test load(f) isa GeometryBasics.AbstractMesh
            end
        end

        @testset "skin data is in range and normalized" begin
            for f in models
                m = load(f)
                m isa MetaMesh || continue
                me = GeometryBasics.Mesh(m)
                attrs = vertex_attributes(me)
                haskey(attrs, :skinjoints) && haskey(attrs, :skinweights) || continue
                joints, weights = attrs.skinjoints, attrs.skinweights
                n = length(m[:skeleton].parents)
                @test all(v -> all(k -> 1 <= Int(v[k]) <= n, 1:4), joints)
                # Weights sum to one, or to zero for a vertex no bone claims —
                # Animation_Skin_04 and _09 ship such vertices deliberately.
                sums = [sum(Float32.(Tuple(v))) for v in weights]
                @test all(s -> abs(s - 1) < 2.0f-3 || s < 1.0f-6, sums)
            end
        end

        @testset "animation metadata is finite" begin
            for f in models
                m = load(f)
                m isa MetaMesh && haskey(m, :animations) || continue
                for clip in m[:animations], track in clip.tracks
                    @test all(isfinite, track.times)
                    @test all(v -> all(isfinite, v), track.values)
                end
            end
        end

        @testset "every animation channel in the file arrives" begin
            # The gap this closes: glTF animations target NODES, and anything
            # aimed at a node that is not a joint used to be dropped on the
            # floor. BoxAnimated is two channels on a plain node, and it loaded
            # with no animation at all.
            for f in models
                doc = gltf_document(f)
                haskey(doc, :animations) || continue
                want = sum(count(c -> haskey(c.target, :node) &&
                                      Symbol(c.target.path) in (:translation, :rotation, :scale),
                                 a.channels) for a in doc.animations)
                want == 0 && continue
                m = load(f)
                got = haskey(m, :node_animations) ?
                      sum(length(c.tracks) for c in m[:node_animations]; init = 0) : 0
                @test got == want
            end
        end

        @testset "a skinned mesh may omit NORMAL" begin
            # glTF leaves NORMAL optional and 19 of the 21 rigged assets here
            # omit it, so this is the common case rather than the edge one.
            bare = filter(models) do f
                m = load(f)
                m isa MetaMesh || return false
                me = GeometryBasics.Mesh(m)
                attrs = vertex_attributes(me)
                haskey(attrs, :skinjoints) && haskey(attrs, :skinweights) &&
                    isnothing(GeometryBasics.normals(me))
            end
            @test !isempty(bare)
            for f in bare
                m = load(f); me = GeometryBasics.Mesh(m)
                attrs = vertex_attributes(me)
                @test length(attrs.skinjoints) == length(coordinates(me))
                @test length(attrs.skinweights) == length(coordinates(me))
                @test isnothing(GeometryBasics.normals(me))
            end
        end
    end
end
