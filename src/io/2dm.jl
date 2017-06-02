# | Read a .2dm (SMS Aquaveo) mesh-file and construct a @Mesh@
function load(st::Stream{format"2DM"}, MeshType=GLNormalMesh)
    FT       = facetype(MeshType)
    VT       = vertextype(MeshType)
    faces    = FT[]
    vertices = VT[]
    io = stream(st)
    for line = readlines(io)
        if !isempty(line) && !all(iscntrl, line)
            line = chomp(line)
            w = split(line)
            if w[1] == "ND"
                push!(vertices, Point{3, Float32}(parse.(Float32, w[3:end])))
            elseif w[1] == "E3T"
                push!(faces, Face{3, Cuint}(parse.(Cuint, w[3:5])))
            elseif w[1] == "E4Q"
                push!(faces, decompose(FT, Face{4, Cuint}(parse.(Cuint, w[3:6])))...)
            else
                continue
            end
        end
    end
    MeshType(vertices, faces)
end

function render(i::Int, f::Face{3})
    string("E3T $i ", join(Int.(f), " "))
end

function render(i::Int, f::Face{4})
    string("E4Q $i ", join(Int.(f), " "))
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

show(io::IO, ::MIME"model/2dm", mesh::AbstractMesh) = save(io, mesh)
