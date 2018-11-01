# MeshIO

[![Build Status](https://travis-ci.org/JuliaIO/MeshIO.jl.svg)](https://travis-ci.org/JuliaIO/MeshIO.jl)
[![Build status](https://ci.appveyor.com/api/projects/status/db53fjnhbp1m0bk8/branch/master?svg=true)](https://ci.appveyor.com/project/SimonDanisch/meshio-jl/branch/master)
[![codecov.io](http://codecov.io/github/JuliaIO/MeshIO.jl/coverage.svg?branch=master)](http://codecov.io/github/JuliaIO/MeshIO.jl?branch=master)
[![Coverage Status](https://coveralls.io/repos/JuliaIO/MeshIO.jl/badge.svg?branch=master&service=github)](https://coveralls.io/github/JuliaIO/MeshIO.jl?branch=master)

This package supports loading 3D model file formats: `obj`, `stl`, `ply`, `off` and `2DM`.
More 3D model formats will be supported in the future.

## Installation

Enter package mode in the Julia REPL and run the following command:

```Julia
pkg> add FileIO MeshIO
```

## Usage

Loading works over the [FileIO](https://github.com/JuliaIO/FileIO.jl) interface.
This means loading a mesh is as simple as this:
```Julia
using FileIO
mesh = load("path/to/mesh.obj")
```
Displaying a mesh can be achieved with [GLVisualize](https://github.com/JuliaGL/GLVisualize.jl), [GLPlot](https://github.com/SimonDanisch/GLPlot.jl) and [ThreeJS](https://github.com/rohitvarkey/ThreeJS.jl/).

Functions for mesh manipulation can be found in [Meshes](https://github.com/JuliaGeometry/Meshes.jl) and [JuliaGeometry](https://github.com/JuliaGeometry)

## Additional Information

MeshIO now has the HomogenousMesh type. Name is still not settled, but it's supposed to be a dense mesh with all attributes either having the length of one (constant over the whole mesh) or the same length (per vertex).
This meshtype holds a large variability for all the different attribute mixtures that I've encountered while trying to visualize things over at GLVisualize. This is the best type I've found so far to encode this large variability, without an explosion of functions.

The focus is on conversion between different mesh types and creation of different mesh types.
This has led to some odd seeming design choices.
First, you can get an attribute via `decompose(::Type{AttributeType}, ::Mesh)`.
This will try to get this attribute, and if it has the wrong type try to convert it, or if it is not available try to create it.
So `decompose(Point3{Float32}, mesh)` on a mesh with vertices of type `Point3{Float64}` will return a vector of type `Point3{Float32}`.
Similarly, if you call `decompose(Normal{3, Float32}, mesh)` but the mesh doesn't have normals, it will call the function `normals(mesh.vertices, mesh.faces, Normal{3, Float32}`, which will create the normals for the mesh.
As most attributes are independent, this  enables us to easily create all kinds of conversions.
Also, I can define `decompose` for arbitrary geometric types.
`decompose{T}(Point3{T}, r::Rectangle)` can actually return the needed vertices for a rectangle.
This together with `convert` enables us to create mesh primitives like this:
```Julia
MeshType(Cube(...))
MeshType(Sphere(...))
MeshType(Volume, 0.4f0) #0.4f0 => isovalue
```

Similarly, I can pass a meshtype to an IO function, which then parses only the attributes that I really need.
So passing `Mesh{Point3{Float32}, Face3{UInt32}}` to the obj importer will skip normals, uv coordinates etc, and automatically converts the given attributes to the right number type.

To put this one level further, the `Face` type has the index offset relative to Julia's indexing as a parameter (e.g. `Face3{T, 0}` is 1 indexed). Also, you can index into an array with this face type, and it will convert the indexes correctly while accessing the array. So something like this always works, independent of the underlying index offset:
```Julia
v1, v2, v3 = vertices[face]
```
Also, the importer is sensitive to this, so if you always want to work with 0-indexed faces (like it makes sense for opengl based visualizations), you can parse the mesh already as an 0-indexed mesh, by just defining the mesh format to use `Face3{T, -1}`. (only the OBJ importer yet)

Small example to demonstrate the advantage for IO:
```Julia
#Export takes any mesh
function write{M <: Mesh}(msh::M, fn::File{:ply_binary})
    # even if the native mesh format doesn't have an array of dense points or faces, the correct ones will
    # now be created, or converted:
    vts = decompose(Point3{Float32}, msh) # I know ply_binary needs Point3{Float32}
    fcs = decompose(Face3{Int32, -1}, msh) # And 0 indexed Int32 faces.
    #write code...
end
  ```

## TODO

1. Port all the other importers/exporters to use the new mesh type and the FileIO API
2. Include more meshtypes for more exotic formats
3. Write tests
