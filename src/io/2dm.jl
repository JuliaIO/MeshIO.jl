# | Read a .2dm (SMS Aquaveo) mesh-file and construct a @Mesh@
function load(st::Stream{format"2DM"}, MeshType=GLNormalMesh)
    FT       = facetype(MeshType)
    VT       = vertextype(MeshType)
    faces    = FT[]
    vertices = VT[]
    io = stream(st)
    for line = readlines(io)
        if !isempty(line) && !iscntrl(line)
            line = chomp(line)
            w = split(line)
            if w[1] == "ND"
                push!(vertices, Point{3, Float32}(w[3:end]))
            elseif w[1] == "E3T"
                push!(faces, Face{3, Cuint, 0}(w[3:5]))
            elseif w[1] == "E4Q"
                push!(faces, decompose(FT, Face{4, Cuint, 0}(w[3:6]))...)
            else
                continue
            end
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
function save(st::Stream{format"2DM"}, m::AbstractMesh)
    io = stream(st)
    println(io, "MESH2D")
    for (i, f) in enumerate(m.faces)
        println(io, render(i, f))
    end
    for (i, v) in enumerate(m.vertices)
        println(io, "ND $i ", join(v, " "))
    end
    nothing
end

@compat show(io::IO, ::MIME"model/2dm", mesh::AbstractMesh) = save(io, mesh)
