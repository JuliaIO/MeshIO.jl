#WORK IN PROGRESS
#Started accumulating all the different mesh types and attributes. 

abstract MeshAttribute
immutable PlainMesh <: MeshAttribute end
const PLAIN = PlainMesh()


type Textured{N, ImageType <: Image} <: MeshAttribute
    uv::NTuple{N, UV}
    textures::NTuple{N, ImageType}
    meta::Dict{Symbol, Any} # Description of what the texture does?
end



abstract HomogenousAttributes{Attributes} <: MeshAttribute

immutable UVAttribute{T} <: HomogenousAttributes{(UV{T},)}
    uv::Vector{UV{T}}
end
immutable UVWAttribute{T} <: HomogenousAttributes{(UVW{T},)}
    uvw::Vector{UVW{T}}
end
immutable UVNormalAttribute{TexCoordinate, NORMAL} <: HomogenousAttributes{(TexCoordinate, NORMAL)}
    uv::Vector{TexCoordinate}
    normal::Vector{NORMAL}
end

call{TexCoordinate, NORMAL}(::Type{UVNormalAttribute{TexCoordinate, NORMAL}}) = UVNormalAttribute(TexCoordinate[], NORMAL[])

immutable UVWNormalAttribute{TexCoordinate, NORMAL} <: HomogenousAttributes{(TexCoordinate, NORMAL)}
    uvw::Vector{TexCoordinate}
    normal::Vector{NORMAL}
end
immutable NormalAttribute{NORMAL} <: HomogenousAttributes{(NORMAL,)}
    normal::Vector{NORMAL}
end
immutable NormalColorAttribute{T, C <: Color} <: MeshAttribute
    normal::Vector{Normal3{T}}
    color::C
end

immutable NormalGenericAttribute{ID, C, T} <: MeshAttribute
    normal::Vector{Normal3{T}}
    attribute_id::Vector{ID}
    attributes::Vector{C}
end

function call{HT <: HomogenousAttributes}(::Type{HT})
    empty_attributes = map(attrib_type -> attrib_type[], attributelist(HT))
    HT(empty_attributes...)
end
getindex{T <: Normal3}(a::HomogenousAttributes, ::Type{T}) = a.normal
getindex{T <: UVW}(a::HomogenousAttributes, ::Type{T})     = a.uvw
getindex{T <: UV}(a::HomogenousAttributes, ::Type{T})      = a.uv




type Mesh{VT, FT, A <: MeshAttribute}
    vertices    ::Vector{VT}
    faces       ::Vector{FT}
    attributes  ::A
end

call{VT, FT, A <: MeshAttribute}(::Type{Mesh{VT, FT, A}}) = Mesh(VT[], FT[], A())

attributelist{HMA <: HomogenousAttributes}(m::Type{HMA}) = isleaftype(HMA) ? attributelist(super(HMA)) : HMA.parameters[1]
attributelist{VT, FT, A<: HomogenousAttributes}(m::Mesh{VT, FT, A}) = [VT, FT, attributelist(A)...]

attributes(m::Mesh) = m.attributes
attributes{M <: Mesh}(m::Type{M}) = M.parameters[3]



Mesh(v,f, a=PLAIN) = Mesh(v,f, a)

vertices{M <: Mesh}(m::Type{M}) = M.parameters[1]
vertices(m::Mesh)   = m.vertices
faces(m::Mesh)      = m.faces

function Base.show{V, F, A}(io::IO, m::Mesh{V, F, A})
    println(io, "vertices: ", V, " length: ", length(vertices(m)))
    println(io, "faces: ", F, " length: ", length(faces(m)))
    println(io, m.attributes)
end

function Base.show{N, ImageType <: Image}(io::IO, a::Textured{N, ImageType})
    println(io, "Textured, with $N textures of type $ImageType")
end

