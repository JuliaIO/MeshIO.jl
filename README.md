# MeshIO

[![codecov.io](http://codecov.io/github/JuliaIO/MeshIO.jl/coverage.svg?branch=master)](http://codecov.io/github/JuliaIO/MeshIO.jl?branch=master)
[![Coverage Status](https://coveralls.io/repos/JuliaIO/MeshIO.jl/badge.svg?branch=master&service=github)](https://coveralls.io/github/JuliaIO/MeshIO.jl?branch=master)

This package supports loading 3D model file formats: `obj`, `stl`, `ply`, `off`, `msh` and `2DM`.
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
The result will usually be a [GeometryBasics](https://github.com/JuliaGeometry/GeometryBasics.jl) `Mesh`.
The exception are `obj` files with non-vertex data such as material data or "group" tags, which return a `MetaMesh`.

Displaying a mesh can be achieved with [Makie](https://github.com/JuliaPlots/Makie.jl).

Functions for mesh manipulation can be found in [JuliaGeometry](https://github.com/JuliaGeometry)

## Additional Information

### Usage

The GeometryBasics `Mesh` supports vertex attributes with different lengths which get addressed by different faces (as of 0.5).
As such MeshIO makes no effort to convert vertex attributes to a common length, indexed by one set of faces.
If you need a single set of faces, e.g. for rendering, you can use `new_mesh = GeometryBasics.expand_faceviews(mesh)` to generate a fitting mesh.

The GeometryBasics `Mesh` allows for different element types for coordinates, normals, faces, etc.
These can set when loading a mesh using keyword arguments:
```julia
load(filename; pointtype = Point3f, uvtype = Vec2f, facetype = GLTriangleFace, normaltype = Vec3f)
```
Note that not every file format supports normals and uvs (texture coordinates) and thus some loaders don't accept `uvtype` and/or `normaltype`.

The facetypes from GeometryBasics support 0 and 1-based indexing using `OffsetInteger`s.
For example `GLTriangleFace` is an alias for `NgonFace{3, OffsetInteger{-1, UInt32}}`, i.e. a face containing 3 indices offset from 1-based indexing by `-1`.
The raw data in a `GLTriangleFace` is 0-based so that it can be uploaded directly in a Graphics API.
In Julia code it gets converted back to a 1-based Int, so that it can be used as is.

### Extending MeshIO

To implement a new file format you need to add the appropriate `load()` and `save()` methods.
You also need to register the file format with [FileIO](https://juliaio.github.io/FileIO.jl/stable/registering/)
For saving it may be useful to know that you can convert vertex data to specific types using the [decompose interface](https://juliageometry.github.io/GeometryBasics.jl/stable/decomposition/).
