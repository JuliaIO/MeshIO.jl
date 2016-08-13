VERSION >= v"0.4.0-dev+6521" && __precompile__(true)
module MeshIO

using GeometryTypes
using ColorTypes
using Compat
import FileIO

import FileIO: DataFormat, @format_str, Stream, File, filename, stream, skipmagic
@compat import Base.show



include("io/off.jl")
include("io/ply.jl")
include("io/stl.jl")
include("io/obj.jl")
include("io/2dm.jl")

load{format}(fn::File{format}, MeshType=GLNormalMesh) = open(fn) do s
	skipmagic(s)
	load(s, MeshType)
end
save{format}(fn::File{format}, msh::AbstractMesh) = open(fn, "w") do s
	save(s, msh)
end

end # module
