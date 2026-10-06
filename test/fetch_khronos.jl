# Download Khronos' glTF test assets for `khronos_conformance.jl`.
#
# Not vendored: 1.2 MB of third-party binaries that Khronos already hosts and
# versions. Run this once; the test file skips cleanly when they are absent.
using JSON3
const GENERATOR = "https://raw.githubusercontent.com/KhronosGroup/glTF-Asset-Generator/main/Output/Positive"
const SAMPLES = "https://raw.githubusercontent.com/KhronosGroup/glTF-Sample-Assets/main/Models"
const GROUPS = ["Animation_Skin", "Animation_SkinType", "Animation_Node",
                "Animation_NodeMisc", "Node_NegativeScale"]
const MODELS = ["SimpleSkin", "RiggedSimple", "RiggedFigure", "InterpolationTest",
                "AnimatedMorphCube", "BoxAnimated", "RecursiveSkeletons", "Fox"]
dest = joinpath(@__DIR__, "khronos")

function grab(url, path)
    isfile(path) && return true
    mkpath(dirname(path))
    try
        download(url, path)
        return true
    catch
        rm(path; force = true)
        return false
    end
end

for g in GROUPS
    man = joinpath(dest, "$(g)_Manifest.json")
    grab("$GENERATOR/$g/Manifest.json", man) || continue
    for m in JSON3.read(read(man, String)).models
        file = String(m.fileName)
        grab("$GENERATOR/$g/$file", joinpath(dest, g, file)) || continue
        gltf = JSON3.read(read(joinpath(dest, g, file), String))
        for buf in get(gltf, :buffers, ())
            uri = String(get(buf, :uri, ""))
            (isempty(uri) || startswith(uri, "data:")) && continue
            grab("$GENERATOR/$g/$uri", joinpath(dest, g, uri))
        end
    end
    println("fetched $g")
end

for name in MODELS
    grab("$SAMPLES/$name/glTF-Binary/$name.glb", joinpath(dest, "Samples", "$name.glb")) && continue
    grab("$SAMPLES/$name/glTF/$name.gltf", joinpath(dest, "Samples", "$name.gltf")) || continue
    gltf = JSON3.read(read(joinpath(dest, "Samples", "$name.gltf"), String))
    for buf in get(gltf, :buffers, ())
        uri = String(get(buf, :uri, ""))
        (isempty(uri) || startswith(uri, "data:")) && continue
        grab("$SAMPLES/$name/glTF/$uri", joinpath(dest, "Samples", uri))
    end
end
println("fetched samples into ", dest)
