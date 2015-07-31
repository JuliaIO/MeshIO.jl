module MeshIO

importall FileIO

using GeometryTypes
using ColorTypes
using Compat

include("io/ply.jl")

call{T <: Mesh}(::Type{T}, f::FileIO.File) = read(f, T)

end # module
