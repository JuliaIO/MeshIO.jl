#WORK IN PROGRESS
#Started accumulating all the different mesh types and attributes. 

abstract MeshAttribute
immutable Plain <: MeshAttribute end
const PLAIN = Plain()


type Textured{N, ImageType <: Image} <: MeshAttribute
    uv::NTuple{N, UV}
    textures::NTuple{N, ImageType}
    meta::Dict{Symbol, Any} # Description of what the texture does?
end
type Mesh{V, F, A <: MeshAttribute}
    vertices    ::Vector{V}
    faces       ::Vector{F}
    attributes  ::A
end
Mesh(v,f, a=PLAIN) = Mesh(v,f, a)

vertices(m::Mesh)   = m.vertices
faces(m::Mesh)      = m.faces

function Base.show(io::IO, m::Mesh{V, F, A})
    println(io, "vertices: ", V, " length: ", length(vertices(m)))
    println(io, "faces: ", F, " length: ", length(faces(m)))
    println(io, m.attributes)
end

function Base.show{N, ImageType <: Image}(io::IO, a::Textured{N, ImageType})
    println(io, "Textured, with $N textures of type $ImageType")
end

