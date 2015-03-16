abstract MeshPrimitive

#WORK IN PROGRESS
#Started accumulating all the different mesh types and attributes. 




abstract AbstractFixedVector{C} # will ultimately come from FixedSizeArrays

abstract MeshAttribute
abstract MeshPrimitive

abstract FSMeshAttribute{T, NDim, SIZE} <: FixedSizeArray{T, NDim, SIZE}
abstract FSMeshPrimitive{T, NDim, SIZE} <: FixedSizeArray{T, NDim, SIZE}

abstract MeshAttribute <: MeshAttribute
abstract MeshPrimitive <: MeshPrimitive
abstract FSMeshAttribute <: 


immutable Vector3{T} <: AbstractFixedVector{3}
  x::T
  y::T
  z::T
end

immutable AABB{T}
    min::Vector3{T}
    max::Vector3{T}
end


immutable Face{T} <: AbstractFixedVector{3}
    i1::T
    i2::T
    i3::T
end
immutable Triangle{T} <: AbstractFixedVector{3}
    i1::T
    i2::T
    i3::T
end

immutable UV{T} <: AbstractFixedVector{2}
    u::T
    v::T
end
immutable UVW{T} <: AbstractFixedVector{3}
    u::T
    v::T
    w::T
end
immutable Vertex{T} <: AbstractFixedVector{3}
    x::T
    y::T
    z::T
end
immutable Normal{T} <: AbstractFixedVector{3}
    x::T
    y::T
    z::T
end

immutable Vector2{T} <: AbstractFixedVector{3}
  x::T
  y::T
end
# No fixedsizeArrays yet:
Base.getindex(a::AbstractFixedVector, i::Integer) = getfield(a,i)


immutable GLMesh{NDim, Primitive, Attributes}
    data::Dict{Symbol, Any}
end

Base.getindex{T <: MeshAttribute}(m::GLMesh, key::Type{T})      = m.data[key]
Base.setindex!{T <: MeshAttribute(m::GLMesh, arr, key::Type{T}) = m.data[key] = arr

function Base.show(io::IO, m::GLMesh)
    println(io, "Mesh:")
    maxnamelength = 0
    maxtypelength = 0
    names = map(m.data) do x
        n = string(x[1])
        t = string(eltype(x[2]).parameters...)
        namelength = length(n)
        typelength = length(t)
        maxnamelength = maxnamelength < namelength ? namelength : maxnamelength
        maxtypelength = maxtypelength < typelength ? typelength : maxtypelength

        return (n, t, length(x[2]))
    end

    for elem in names
        kname, tname, alength = elem
        namespaces = maxnamelength - length(kname)
        typespaces = maxtypelength - length(tname)
        println(io, "   ", kname, " "^namespaces, " : ", tname, " "^typespaces, ", length: ", alength)
    end
end