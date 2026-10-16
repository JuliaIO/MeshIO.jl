# Download Khronos' glTF test assets into test/khronos for `khronos_conformance.jl`.
using Downloads
using MeshIO: JSON3

const GENERATOR = "https://raw.githubusercontent.com/KhronosGroup/glTF-Asset-Generator/main/Output/Positive"
const SAMPLES = "https://raw.githubusercontent.com/KhronosGroup/glTF-Sample-Assets/main/Models"

"Fetch `url` to `path` unless it is there; a failure is reported and returns false."
function grab(url, path)
    isfile(path) && return true
    mkpath(dirname(path))
    try
        Downloads.download(url, path)
        return true
    catch err
        @warn "could not fetch $url" exception = err
        rm(path; force = true)
        return false
    end
end

"Fetch `file` from `base` into `dir`, with the external buffers a `.gltf` names."
function grabgltf(base, file, dir)
    grab("$base/$file", joinpath(dir, file)) || return false
    endswith(file, ".gltf") || return true
    for buf in get(JSON3.read(read(joinpath(dir, file), String)), :buffers, ())
        uri = get(buf, :uri, "")
        isempty(uri) || startswith(uri, "data:") || grab("$base/$uri", joinpath(dir, uri))
    end
    return true
end

dest = joinpath(@__DIR__, "khronos")
for group in ["Animation_Skin", "Animation_SkinType", "Animation_Node", "Animation_NodeMisc", "Node_NegativeScale"]
    manifest = joinpath(dest, "$(group)_Manifest.json")
    grab("$GENERATOR/$group/Manifest.json", manifest) || continue
    for m in JSON3.read(read(manifest, String)).models
        grabgltf("$GENERATOR/$group", m.fileName, joinpath(dest, group))
    end
end
for name in ["SimpleSkin", "RiggedSimple", "RiggedFigure", "InterpolationTest", "AnimatedMorphCube",
             "BoxAnimated", "RecursiveSkeletons", "Fox"]
    grabgltf("$SAMPLES/$name/glTF-Binary", "$name.glb", joinpath(dest, "Samples")) ||
        grabgltf("$SAMPLES/$name/glTF", "$name.gltf", joinpath(dest, "Samples"))
end
println("fetched into ", dest)
