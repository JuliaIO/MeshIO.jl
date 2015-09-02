VERSION >= v"0.4.0-dev+6521" && __precompile__(true)
module MeshIO

using GeometryTypes
using ColorTypes
using Compat
using FileIO

import FileIO: load, save
import Base: writemime, call

for format in [format"OBJ", format"PLY_ASCII", format"PLY_BINARY", format"STL_ASCII", format"STL_BINARY", format"OFF", format"2DM"]
	eval(quote
		load(fn::File{$format}, MeshType=GLNormalMesh) = open(fn) do s
			skipmagic(s)
	    	load(s, MeshType)
		end
		save(fn::File{$format}, msh::AbstractMesh) = open(fn, "w") do s
	    	save(s, msh)
		end
	end)
end
call{M <: AbstractMesh}(m::Type{M}, f::AbstractString) = load(f, m)

include("io/off.jl")
include("io/ply.jl")
include("io/stl.jl")
include("io/obj.jl")
include("io/2dm.jl")


end # module
