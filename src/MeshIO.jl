module MeshIO

import FileIO: File, @file_str
using GeometryTypes, ColorTypes, ImageIO, FixedPointNumbers
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
export attributelist
export PlainMesh

typealias UVWNormalMesh{TV, TF} Mesh{Point3{TV}, Triangle{TF}, UVWNormalAttribute{TV}}
typealias GLUVWNormalMesh UVWNormalMesh{Float32, Uint32}
export UVWMesh
export GLUVWMesh


typealias UVWMesh{TV, TF} Mesh{Point3{TV}, Triangle{TF}, UVWAttribute{TV}}
typealias GLUVWMesh UVWMesh{Float32, Uint32}
export UVWMesh
export GLUVWMesh

typealias UVMesh{TV, TF} Mesh{Point3{TV}, Triangle{TF}, UVAttribute{TV}}
typealias GLUVMesh UVMesh{Float32, Uint32}

export UVMesh
export GLUVMesh

typealias NormalMesh{TV, TF} Mesh{Point3{TV}, Triangle{TF}, NormalAttribute{Normal3{TV}}}
typealias GLNormalMesh NormalMesh{Float32, Uint32}

export NormalMesh
export GLNormalMesh

typealias Mesh2D{TV, TF} Mesh{Point2{TV}, Triangle{TF}, PlainMesh}
typealias GLMesh2D Mesh2D{Float32, Uint32}

export Mesh2D
export GLMesh2D

typealias UVMesh2D{TV, TF} Mesh{Point2{TV}, Triangle{TF}, UVAttribute{TV}}
typealias GLUVMesh2D UVMesh2D{Float32, Uint32}

export UVMesh2D
export GLUVMesh2D


export NormalColorAttribute
export NormalGenericAttribute

typealias NormalColorMesh{TV, TF} Mesh{Point3{TV}, Triangle{TF}, NormalColorAttribute{TV, RGBA{TV}}}
typealias GLNormalColorMesh NormalColorMesh{Float32, Uint32}
export NormalColorMesh
export GLNormalColorMesh

typealias NormalAttributeMesh{TV, TF} Mesh{Point3{TV}, Triangle{TF}, NormalGenericAttribute{Float32, RGBA{FixedPointNumbers.UfixedBase{UInt8,8}}, Float32}}
typealias GLNormalAttributeMesh NormalAttributeMesh{Float32, Uint32}
export NormalAttributeMesh
export GLNormalAttributeMesh

end # module
