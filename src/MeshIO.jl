module MeshIO

import FileIO: File, @file_str
using GeometryTypes, ImageIO
include("types.jl")

export Mesh


export HomogenousAttributes
export UVAttribute
export UVNormalAttribute
export NormalAttribute

export vertices
export faces
export attributes


typealias UVMesh{TV, TF} Mesh{Point3{TV}, Triangle{TF}, UVAttribute{TV}}
typealias GLUVMesh UVMesh{Float32, Uint32}
export UVMesh
export GLUVMesh

end # module
