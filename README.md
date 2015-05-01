# MeshIO

[![Build Status](https://travis-ci.org/SimonDanisch/MeshIO.jl.svg?branch=master)](https://travis-ci.org/SimonDanisch/MeshIO.jl)


WORK IN PROGRESS
Starting to take the mesh defintions and IO operations from Meshes.jl and Meshes2.jl.

### Update:

MeshIO now has the HomogenousMesh type. Name is still not settled, but it's supposed to be a dense mesh with all attributes either having the length of one (constant over the whole mesh) or the same length (per vertex).
This meshtype holds a large variability for all the different attribute mixtures that I've encountered while trying to visualize things over at GLVisualize. This is the best type I've found so far to encode this large variability, whithout an explosion of functions.

The focus is on conversion between different mesh types and creation of different mesh types.
This has lead to some odd seeming design choices.
First, you can get an attribute via `getindex(::Mesh, ::Type{AttributeType})`. 
This will try to get this attribute, and if it has the wrong type try to convert it, or if it is not available try to create it.
So `mesh[Point3{Float32}]` on a mesh with vertices of type `Point3{Float64}` will return a vector of type `Point3{Float32}`.
Similarly, if you call `mesh[Normal3{Float32}]` but the mesh doesn't have normals, it will call the function `normals(mesh.vertices, mesh.faces, Normal3{Float32}`, which will create the normals for the mesh.
As most attributes are independant, this  enables us to easily create all kinds of conversions.
Also, I can define getindex for arbitrary geometric types.
`getindex{T}(r::Reactangle, Point3{T})` can actually return the needed vertices for a rectangle.
This together with convert enables us to create mesh primitives like this:
```Julia
MeshType(Cube(...))
MeshType(Sphere(...))
MeshType(Volume, 0.4f0) #0.4f0 => isovalue
```

Similarly, I can pass a meshtype to an IO function, which then parses only the attributes that I really need.
So passing `Mesh{Point3{Float32}, Face3{Uint32}}` to the obj importer will skip normals, uv coordinates etc, and automatically converts the given attributes to the right number type.

To put this one level furter, the Face type has the index offset relative to julia's indexing as a parameter (e.g. Face3{T, 0} is 1 indexed}). Also, you can index into an array with this face type, and it will convert the indexes correctly while accessing the array. So something like this always works, independant of the underlying index offset:
```Julia
v1, v2, v3 = vertices[face]
```
Also, the importer is sensitive to this, so if you always want to work with 0-indexed faces (like it makes sense for opengl based visualizations), you can parse the mesh already as an 0-indexed mesh, by just defining the mesh format to use Face3{T, -1}. (only the OBJ importer yet)

Small example to demonstrate the advantage for IO:
```Julia
#Export takes any mesh
function write{M <: Mesh}(msh::M, fn::File{:ply_binary})
    # even if the native mesh format doesn't have an array of dense points or faces, the correct ones will 
    # now be created, or converted:
    vts = msh[Point3{Float32}] # I know ply_binary needs Point3{Float32}
    fcs = msh[Face3{Int32, -1}] # And 0 indexed Int32 faces.
    #write code...
end
  ```
    

### TODO

1. Port all the other importers/exporters to use the new mesh type and the FileIO API
2. Include more meshtypes for more exotic formats
3. Write tests

