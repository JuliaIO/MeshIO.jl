abstract Mesh

# all vectors must have the same length, besides the face vector or empty vector
# Type can be void or a value, this way we can create many combinations from this one mesh type.
# This is not perfect, but helps to reduce a type explosion (imagine defining every attribute combination as a new type).
# It's still experimental, but this design has been working well for me so far.
# This type is also heavily linked to GLVisualize, which means if you can transform another meshtype to this type
# chances are high that GLVisualize can display them.
immutable HomogenousMesh{VertT, FaceT, NormalT, TexCoordT, ColorT, AttribT, AttribIDT} <: Mesh
  vertices            ::Vector{VertT}
  faces               ::Vector{FaceT}
  normals             ::Vector{NormalT}
  texturecoordinates  ::Vector{TexCoordT}
  color               ::ColorT
  attributes          ::AttribT
  attribute_id        ::Vector{AttribIDT}
end
# This function should really be defined in FileIO, but can't as it's ambigous with every damn constructor...
# Its nice, as you can simply do something like GLNormalMesh(file"mesh.obj")
call{T <: Mesh}(::Type{T}, f::File) = read(f, T)

typealias HMesh HomogenousMesh
vertextype            {_VertT,    _1, _2, _3, _4, _5, _6}(::Type{HomogenousMesh{_VertT,    _1, _2, _3, _4, _5, _6}}) = _VertT
facetype              {_1, FaceT,     _2, _3, _4, _5, _6}(::Type{HomogenousMesh{_1, FaceT,     _2, _3, _4, _5, _6}}) = FaceT
normaltype            {_1, _2, NormalT,   _3, _4, _5, _6}(::Type{HomogenousMesh{_1, _2, NormalT,   _3, _4, _5, _6}}) = NormalT
texturecoordinatetype {_1, _2, _3, TexCoordT, _4, _5, _6}(::Type{HomogenousMesh{_1, _2, _3, TexCoordT, _4, _5, _6}}) = TexCoordT
colortype             {_1, _2, _3, _4, ColorT,    _5, _6}(::Type{HomogenousMesh{_1, _2, _3, _4, ColorT,    _5, _6}}) = ColorT

# Bad, bad name! But it's a little tricky to filter out faces and verts from the attributes, after get_attribute
attributes_noVF(m::Mesh) = filter((key,val) -> (val != nothing && val != Void[]), Dict{Symbol, Any}(map(field->(field => m.(field)), fieldnames(typeof(m))[3:end])))
#Gets all non Void attributes from a mesh
attributes(m::Mesh) = filter((key,val) -> (val != nothing && val != Void[]), all_attributes(m))
#Gets all non Void attributes types from a mesh type
attributes{M <: HMesh}(m::Type{M}) = filter((key,val) -> (val != Void && val != Vector{Void}), all_attributes(M))

all_attributes{M <: HMesh}(m::Type{M}) = Dict{Symbol, Any}(map(field -> (field => fieldtype(M, field)), fieldnames(M)))
all_attributes{M <: HMesh}(m::M)       = Dict{Symbol, Any}(map(field -> (field => getfield(m, field)),  fieldnames(M)))

#Some Aliases
typealias HMesh HomogenousMesh

typealias PlainMesh{VT, FT}  HMesh{Point3{VT}, FT, Void, Void,  Void, Void, Void}
typealias GLPlainMesh PlainMesh{Float32, GLTriangle} 

typealias Mesh2D{VT, FT}  HMesh{Point2{VT}, FT, Void, Void,  Void, Void, Void}
typealias GLMesh2D Mesh2D{Float32, GLTriangle} 

typealias UVMesh{VT, FT, UVT}  HMesh{Point3{VT}, FT, Void, UV{UVT},  Void, Void, Void}
typealias GLUVMesh UVMesh{Float32, GLTriangle, Float32} 

typealias UVWMesh{VT, FT, UVT} HMesh{Point3{VT}, FT, Void, UVW{UVT}, Void, Void, Void}
typealias GLUVWMesh UVWMesh{Float32, GLTriangle, Float32} 

typealias NormalMesh{VT, FT, NT}  HMesh{Point3{VT}, FT, Normal3{NT}, Void,  Void, Void, Void}
typealias GLNormalMesh NormalMesh{Float32, GLTriangle, Float32} 

typealias UVMesh2D{VT, FT, UVT}  HMesh{Point2{VT}, FT, Void, UV{UVT},  Void, Void, Void}
typealias GLUVMesh2D UVMesh2D{Float32, GLTriangle, Float32} 

typealias NormalColorMesh{VT, FT, NT, CT}  HMesh{Point3{VT}, FT, Normal3{NT}, Void,  CT, Void, Void}
typealias GLNormalColorMesh NormalColorMesh{Float32, GLTriangle, Float32, RGBA{Float32}} 


typealias NormalAttributeMesh{VT, FT, NT, AT, A_ID_T} HMesh{Point3{VT}, FT, Normal3{NT}, Void,  Void, AT, A_ID_T}
typealias GLNormalAttributeMesh NormalAttributeMesh{Float32, GLTriangle, Float32, Vector{RGBAU8}, Float32} 

typealias NormalUVWMesh{VT, FT, NT, UVT}  HMesh{Point3{VT}, FT, Normal3{NT}, UVW{UVT},  Void, Void, Void}
typealias GLNormalUVWMesh NormalUVWMesh{Float32, GLTriangle, Float32, Float32} 

# Needed to not get into an stack overflow
convert{HM1 <: HMesh}(::Type{HM1}, mesh::HM1) = mesh

# Uses getindex to get all the converted attributes from the meshtype and 
# creates a new mesh with the desired attributes from the converted attributs
# Getindex can be defined for any arbitrary geometric type or exotic mesh type.
# This way, we can make sure, that you can convert most of the meshes from one type to the other
# with minimal code.
function convert{HM1 <: HMesh}(::Type{HM1}, any)
  result = Dict{Symbol, Any}()
  for (field, target_type) in zip(fieldnames(HM1), HM1.parameters)
    if target_type != Void
      result[field] = any[target_type]
    end
  end
  HM1(result)
end

# triangulate a quad. Could be written more generic
function triangulate{FT1, FT2}(::Type{Face3{FT1}}, f::Face4{FT2})
  (Face3{FT1}(f[1], f[2], f[3]), Face3{FT1}(f[3], f[4], f[1]))
end

function convert{FT1, FT2}(::Type{Vector{Face3{FT1}}}, f::Vector{Face4{FT2}})
  fsn = fill(Face3{FT}, length(fs)*2)
  for i=1:2:length(fs)
    a, b = triangulate(Face3{FT}, fs[div(i,2)])
    fsn[i] = a
    fsn[i+1] = b
  end
  return fsn
end


function call{M <: HMesh, VT, FT <: Face}(::Type{M}, vertices::Vector{Point3{VT}}, faces::Vector{FT})
    msh = PlainMesh{VT, FT}(vertices=vertices, faces=faces)
    convert(M, msh)
end

# Creates a mesh from keyword arguments, which have to match the field types
call{M <: HMesh}(::Type{M}; kw_args...) = M(Dict{Symbol, Any}(kw_args))

# Creates a new mesh from a dict of fieldname => value
function call{M <: HMesh}(::Type{M}, attribs::Dict{Symbol, Any})
    newfields = map(zip(fieldnames(HomogenousMesh), M.parameters)) do field_target_type
        field, target_type = field_target_type
        default = fieldtype(HomogenousMesh, field) <: Vector ? Array(target_type, 0) : target_type
        default = default == Void ? nothing : default
        get(attribs, field, default)
    end
    HomogenousMesh(newfields...)
end

#Creates a new mesh from an old one, with changed attributes given by the keyword arguments
function call{M <: HMesh}(::Type{M}, mesh::Mesh, attributes::Dict{Symbol, Any})
    newfields = map(fieldnames(HomogenousMesh)) do field
        get(attributes, field, mesh.(field))
    end
    HomogenousMesh(newfields...)
end

#Creates a new mesh from an old one, with changed attributes given by the keyword arguments
function call{HM <: HMesh, ConstAttrib}(::Type{HM}, mesh::Mesh, constattrib::ConstAttrib)
    result = Dict{Symbol, Any}()
    for (field, target_type) in zip(fieldnames(HM), HM.parameters)
        if target_type <: ConstAttrib
            result[field] = constattrib
        elseif target_type != Void
            result[field] = mesh[target_type]
        end
    end
    HM(result)
end



#=
function show{M <: HMesh}(io::IO, ::Type{M})
  print(io, "HomogenousMesh{")
  for (key,val) in attributes(M)
    print(io, key, ": ", eltype(val), ", ")
  end
  println(io, "}")
end
function show{M <: HMesh}(io::IO, m::M)
  println(io, "HomogenousMesh(")
  for (key,val) in attributes(m)
    print(io, "    ", key, ": ", length(val), "x", eltype(val), ", ")
  end
  println(io, ")")
end
=#

# Getindex methods, for converted indexing into the mesh
# Define getindex for your own meshtype, to easily convert it to Homogenous attributes

#Gets the normal attribute to a mesh
getindex{VT}(mesh::HMesh, ::Type{Point3{VT}}) =  mesh.vertices

# gets the wanted face type
function getindex{FT, Offset}(mesh::HMesh, T::Type{Face3{FT, Offset}})
  fs = mesh.faces
  eltype(fs) == T       && return fs
  eltype(fs) <: Face3   && return map(T, fs)
  if isa(fs, Face4)
    convert(Vector{Face3{FT, Offset}}, fs)
  end
  error("can't get the wanted attribute $(T) from mesh:")
end

#Gets the normal attribute to a mesh
function getindex{NT}(mesh::HMesh, ::Type{Normal3{NT}})
  n = mesh.normals
  eltype(n) == Normal3{NT}   && return n
  eltype(n) <: Normal3       && return map(Normal3{NT1}, n)
  n == Nothing[]             && return normals(mesh.vertices, mesh.faces, Normal3{NT})
end

#Gets the uv attribute to a mesh, or creates it, or converts it
function getindex{UVT}(mesh::HMesh, ::Type{UV{UVT}})
  uv = mesh.texturecoordinates
  eltype(uv) == UV{UVT}           && return uv
  (eltype(uv) <: UV || eltype(uv) <: UVW) && return map(UV{UVT}, uv)
  eltype(uv) == Nothing           && return zeros(UV{UVT}, length(mesh.vertices))
end


#Gets the uv attribute to a mesh
function getindex{UVWT}(mesh::HMesh, ::Type{UVW{UVWT}})
  uvw = mesh.texturecoordinates
  typeof(uvw) == UVW{UVT}     && return uvw
  (isa(uvw, UV) || isa(uv, UVW))  && return map(UVW{UVWT}, uvw)
  uvw == nothing          && return zeros(UVW{UVWT}, length(mesh.vertices))
end
const DefaultColor = RGBA(0.2, 0.2, 0.2, 1.0)

#Gets the color attribute from a mesh
function getindex{T <: Color}(mesh::HMesh, ::Type{Vector{T}})
  colors = mesh.attributes
  typeof(colors) == Vector{T}     && return colors
  colors == nothing           && return fill(DefaultColor, length(mesh.attribute_id))
  map(T, colors)
end

#Gets the color attribute from a mesh
function getindex{T <: Color}(mesh::HMesh, ::Type{T})
  c = mesh.color
  typeof(c) == T    && return c
  c == nothing      && return DefaultColor
  convert(T, c)
end

# Kinda random to have this here, but it's needed for the minimal set of transformations
function normals{VT, FT <: Face}(vertices::Vector{Point3{VT}}, faces::Vector{FT}, NT = Normal3{VT})
    normals_result = zeros(Point3{VT}, length(vertices)) # initilize with same type as verts but with 0
    for face in faces
        v1, v2, v3 = vertices[face]
        a = v2 - v1
        b = v3 - v1
        n = cross(a,b)
        normals_result[face] = normals_result[face] .+ n
    end
    map!(normalize, normals_result)
    normals_result = convert(NT, normals_result)
    normals_result
end
