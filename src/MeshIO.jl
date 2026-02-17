module MeshIO

using GeometryBasics
using ColorTypes
using Printf
using UUIDs: UUID

using GeometryBasics: raw, value, decompose_normals, convert_simplex
using FileIO: FileIO, @format_str, Stream, File, stream, skipmagic

import Base.show

include("io/off.jl")
include("io/ply.jl")
include("io/stl.jl")
include("io/obj.jl")
include("io/2dm.jl")
include("io/msh.jl")
include("io/gts.jl")
include("io/ifs.jl")
include("io/gltf.jl")

"""
    load(fn::File{MeshFormat}; pointtype=Point3f, uvtype=Vec2f,
         facetype=GLTriangleFace, normaltype=Vec3f)

"""
function load(fn::File{format}; element_types...) where {format}
    open(fn) do s
        skipmagic(s)
        load(s; element_types...)
    end
end

function save(fn::File{format}, msh::AbstractMesh) where {format}
    open(fn, "w") do s
        save(s, msh)
    end
end

if Base.VERSION >= v"1.4.2"
    include("precompile.jl")
    _precompile_()
end

# `filter(f, ::Tuple)` is not available on Julia 1.3
# https://github.com/JuliaLang/julia/pull/29259
function filtertuple(f, xs::Tuple)
    return @static if VERSION < v"1.4.0-DEV.551"
        Base.afoldl((ys, x) -> f(x) ? (ys..., x) : ys, (), xs...)
    else
        filter(f, xs)
    end
end

const MeshIO_UUID = UUID("7269a6da-0436-5bbc-96c2-40638cbb6118")

function __init__()
    # Register GLTF/GLB formats with FileIO
    # GLB (binary GLTF) has magic bytes "glTF"
    FileIO.add_format(format"GLB", "glTF", ".glb", [:MeshIO => MeshIO_UUID])
    # GLTF is JSON-based, no reliable magic bytes
    FileIO.add_format(format"GLTF", (), ".gltf", [:MeshIO => MeshIO_UUID])
end

end # module
