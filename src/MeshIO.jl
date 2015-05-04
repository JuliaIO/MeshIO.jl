module MeshIO

importall FileIO

using GeometryTypes
using ColorTypes
using ImageIO
using FixedPointNumbers
using Compat

import Base.merge
import Base.convert
import Base.getindex
import Base.show
import Base.call

include("types.jl")
include("io/ply.jl")
include("io/vtkxml.jl")

export Mesh
export HomogenousMesh
export HMesh
export NormalMesh
export UVWMesh
export UVMesh2D
export UVMesh
export PlainMesh
export Mesh2D
export NormalAttributeMesh
export NormalColorMesh
export NormalUVWMesh

export GLMesh2D
export GLNormalMesh
export GLUVWMesh
export GLUVMesh2D
export GLUVMesh
export GLPlainMesh
export GLNormalAttributeMesh
export GLNormalColorMesh
export GLNormalUVWMesh

export vertextype
export facetype
export normaltype
export texturecoordinatetype
export colortype


export attributes
export attributes_noVF

export normals

end # module
