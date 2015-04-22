module MeshIO

import FileIO: File, @file_str
using GeometryTypes, ImageIO
include("types.jl")

export Mesh


export HomogenousAttributes
export UVAttribute
export UVWAttribute
export UVNormalAttribute

export NormalAttribute

export vertices
export faces
export attributes


typealias UVWMesh{TV, TF} Mesh{Point3{TV}, Triangle{TF}, UVWAttribute{TV}}
typealias GLUVWMesh UVWMesh{Float32, Uint32}
export UVWMesh
export GLUVWMesh

typealias UVMesh{TV, TF} Mesh{Point3{TV}, Triangle{TF}, UVAttribute{TV}}
typealias GLUVMesh UVMesh{Float32, Uint32}

export UVMesh
export GLUVMesh

typealias NormalMesh{TV, TF} Mesh{Point3{TV}, Triangle{TF}, NormalAttribute{TV}}
typealias GLNormalMesh NormalMesh{Float32, Uint32}

export NormalMesh
export GLNormalMesh

typealias Mesh2D{TV, TF} Mesh{Point2{TV}, Triangle{TF}, PlainMesh}
typealias GLMesh2D Mesh2D{Float32, Uint32}

export Mesh2D
export GLMesh2D

end # module
