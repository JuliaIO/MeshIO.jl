import Base.writemime
# | Read a .2dm (SMS Aquaveo) mesh-file and construct a @Mesh@
function FileIO.load(con::Stream{format"2DM"}, MeshType=GLNormalMesh)
    faces    = facetype(MeshType)[]
    vertices = vertextype(MeshType)[]

    for line = readlines(con)
        line = chomp(line)
        w = split(line)
        if w[1] == "ND"
            push!(vertices, Point{3, Float32}(w[3:end]))
        elseif w[1] == "E3T"
            push!(faces, Triangle{Cuint}(w[3:end]))
        elseif w[1] == "E4Q"
            push!(faces, Face{4, Cuint, 0}(w[3:end]))
        else
            continue
        end
    end
    MeshType(vertices, faces)
end

function render{T, O}(i::Int, f::Face{3, T, O})
    string("E3T $i ", join(Face{3, Cuint, 0}(f), " "))
end

function render{T, O}(i::Int, f::Face{4, T, O})
    string("E4Q $i ", join(Face{4, Cuint, 0}(f), " "))
end
# | Write @Mesh@ to an IOStream
function FileIO.save(con::Stream{format"2DM"}, m::AbstractMesh)
    println(con, "MESH2D")
    for (i, f) in enumerate(m.faces)
        println(con, render(i, f))
        
    end
    for (i, v) in enumerate(m.vertices)
        println(con, "ND $i ", join(v, " "))
    end
    nothing
end

Base.writemime(io::IO, ::MIME"model/2dm", mesh::AbstractMesh) = FileIO.save(io, mesh)
