# Khronos' glTF test assets against the loader: glTF-Asset-Generator varies one
# feature at a time (skin component types, `normalized` weights, negative
# scale), glTF-Sample-Assets are real rigs. Not vendored: `fetch_khronos.jl`
# downloads them, and without them this file skips.

const KHRONOS = joinpath(@__DIR__, "khronos")

"The JSON of a `.gltf` or `.glb`, to count what the file contains."
function gltf_document(path)
    endswith(path, ".gltf") && return MeshIO.JSON3.read(read(path, String))
    open(path) do io
        skip(io, 12)                         # magic, version, length
        len = read(io, UInt32)
        skip(io, 4)                          # chunk type
        MeshIO.JSON3.read(String(read(io, len)))
    end
end

khronos_models() = isdir(KHRONOS) ? sort!([joinpath(d, f) for (d, _, fs) in walkdir(KHRONOS)
                                           for f in fs if endswith(f, ".gltf") || endswith(f, ".glb")]) : String[]

if isempty(khronos_models())
    @info "Khronos assets absent; run test/fetch_khronos.jl to enable these tests"
else
    @testset "Khronos glTF conformance" begin
        models = khronos_models()
        @test length(models) > 20
        loaded = Dict(f => load(f) for f in models)
        @test all(m -> m isa GeometryBasics.AbstractMesh, values(loaded))

        @testset "skin data in range, weights normalized: $(basename(f))" for (f, m) in loaded
            m isa MetaMesh && haskey(m, :skeleton) || continue
            attrs = vertex_attributes(Mesh(m))
            n = length(m[:skeleton].parents)
            @test all(j -> all(k -> 1 <= k <= n, j), attrs.skinjoints)
            # Zero for a vertex no bone claims: Animation_Skin_04 and _09 ship those.
            @test all(w -> abs(sum(w) - 1) < 2f-3 || sum(w) < 1f-6, attrs.skinweights)
            @test length(attrs.skinjoints) == length(coordinates(Mesh(m)))
        end

        @testset "every node animation channel arrives: $(basename(f))" for (f, m) in loaded
            doc = gltf_document(f)
            want = sum((count(c -> haskey(c.target, :node) && c.target.path in ("translation", "rotation", "scale"),
                              a.channels) for a in get(doc, :animations, ())); init = 0)
            got = m isa MetaMesh && haskey(m, :node_animations) ?
                  sum(c -> length(c.tracks), m[:node_animations]) : 0
            @test got == want
            m isa MetaMesh && haskey(m, :node_animations) || continue
            @test all(t -> all(isfinite, t.times) && all(v -> all(isfinite, v), t.values),
                      (t for c in m[:node_animations] for t in c.tracks))
        end
    end
end
