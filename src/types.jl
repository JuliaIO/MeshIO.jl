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
immutable UVNormalAttribute{TexCoordinate, NORMAL} <: HomogenousAttributes{(TexCoordinate, NORMAL)}
    uv::Vector{TexCoordinate}
    normal::Vector{NORMAL}
end

immutable NormalAttribute{NORMAL} <: HomogenousAttributes{(NORMAL,)}
    normal::Vector{NORMAL}
end
type Mesh{V, F, A <: MeshAttribute}
    vertices    ::Vector{V}
    faces       ::Vector{F}
    attributes  ::A
end

attributes{HMA <: HomogenousAttributes}(m::Type{HMA}) = isleaftype(HMA) ? attributes(super(HMA)) : HMA.parameters[1]
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

