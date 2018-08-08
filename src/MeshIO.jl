module MeshIO

using GeometryTypes
using GeometryTypes: raw
using ColorTypes
using Printf
import FileIO

import FileIO: DataFormat, @format_str, Stream, File, filename, stream, skipmagic
import Base.show



include("io/off.jl")
include("io/ply.jl")
include("io/stl.jl")
include("io/obj.jl")
include("io/2dm.jl")

load(fn::File{format}, MeshType=GLNormalMesh) where {format} = open(fn) do s
    skipmagic(s)
    load(s, MeshType)
end
save(fn::File{format}, msh::AbstractMesh) where {format} = open(fn, "w") do s
    save(s, msh)
end

end # module
