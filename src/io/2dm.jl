# | Read a .2dm (SMS Aquaveo) mesh-file and construct a @Mesh@
function load(st::Stream{format"2DM"}; facetype=GLTriangleFace, pointtype=Point3f0)
    faces = facetype[]
    vertices = pointtype[]
    io = stream(st)
    for line = readlines(io)
        if !isempty(line) && !all(iscntrl, line)
            line = chomp(line)
            w = split(line)
            if w[1] == "ND"
                push!(vertices, Point3f0(parse.(Float32, w[3:end])))
            elseif w[1] == "E3T"
                push!(faces, GLTriangleFace(parse.(Cuint, w[3:5])))
            elseif w[1] == "E4Q"
                push!(faces, convert_simplex(facetype, QuadFace{Cuint}(parse.(Cuint, w[3:6])))...)
            else
                continue
            end
        end
    end
    return Mesh(vertices, faces)
end

function print_face(io::IO, i::Int, f::TriangleFace)
    println(io, "E3T $i ", join(Int.(f), " "))
end

function print_face(io::IO, i::Int, f::QuadFace)
    println(io, "E4Q $i ", join(Int.(f), " "))
end

# | Write @Mesh@ to an IOStream
function save(st::Stream{format"2DM"}, m::AbstractMesh)
    io = stream(st)
    println(io, "MESH2D")
    for (i, f) in enumerate(faces(m))
        print_face(io, i, f)
    end
    for (i, v) in enumerate(coordinates(m))
        println(io, "ND $i ", join(v, " "))
    end
    return
end

show(io::IO, ::MIME"model/2dm", mesh::AbstractMesh) = save(io, mesh)
