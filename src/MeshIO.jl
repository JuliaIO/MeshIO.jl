module MeshIO

using GeometryBasics
using ColorTypes
using Printf

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
include("io/nas.jl")

# Register NAS format with FileIO for automatic detection by extension
# Since NAS has no magic header, we use empty magic bytes
FileIO.add_format(:NAS, UInt8[], ".nas")


# Add a convenience function for loading NAS files with the same interface as other formats

"""
    load(fn::File{MeshFormat}; pointtype=Point3f, uvtype=Vec2f,
         facetype=GLTriangleFace, normaltype=Vec3f)

"""
function load(fn::File{format}; element_types...) where {format}
    open(fn) do s
        # NAS format has no magic header, so skip skipmagic for it
        if format != format"NAS"
            skipmagic(s)
        end
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

end # module
