function save(f::Stream{format"PLY_BINARY"}, msh::AbstractMesh)
    io = stream(f)
    vts = decompose(Point{3, Float32}, msh)
    fcs = decompose(Face{3, ZeroIndex{Int32}}, msh)

    nV = length(vts)
    nF = length(fcs)

    # write the header
    write(io, "ply\n")
    write(io, "format binary_little_endian 1.0\n")
    write(io, "element vertex $nV\n")
    write(io, "property float x\nproperty float y\nproperty float z\n")
    write(io, "element face $nF\n")
    write(io, "property list uchar int vertex_index\n")
    write(io, "end_header\n")

    # write the vertices and faces
    write(io, vts)

    for f in fcs
        write(io, convert(UInt8, 3))
        write(io, raw.(f)...)
    end
    close(io)
end

function save(f::Stream{format"PLY_ASCII"}, msh::AbstractMesh)
    io = stream(f)
    vts = vertices(msh)
    fcs = faces(msh)

    nV = length(vts)
    nF = length(fcs)


    # write the header
    write(io, "ply\n")
    write(io, "format ascii 1.0\n")
    write(io, "element vertex $nV\n")
    write(io, "property float x\nproperty float y\nproperty float z\n")
    write(io, "element face $nF\n")
    write(io, "property list uchar int vertex_index\n")
    write(io, "end_header\n")

    # write the vertices and faces
    for v in vts
        println(io, join(Point{3, Float32}(v), " "))
    end
    for f in fcs
        println(io, length(f), " ", join(raw.(ZeroIndex.(f)), " "))
    end
    close(io)
end

function load(fs::Stream{format"PLY_ASCII"}, MeshType=GLNormalMesh)
    io = stream(fs)
    nV = 0
    nF = 0

    properties = String[]

    # read the header
    line = readline(io)

    while !startswith(line, "end_header")
        if startswith(line, "element vertex")
            nV = parse(Int, split(line)[3])
        elseif startswith(line, "element face")
            nF = parse(Int, split(line)[3])
        elseif startswith(line, "property")
            push!(properties, line)
        end
        line = readline(io)
    end
    VertexType  = vertextype(MeshType)
    FaceType    = facetype(MeshType)
    FaceEltype  = eltype(FaceType)

    vts         = Array{VertexType}(nV)
    #fcs         = Array{FaceType}(nF)
    fcs         = FaceType[]

    # read the data
    for i = 1:nV
        vts[i] = VertexType(parse.(eltype(VertexType), split(readline(io)))) # line looks like: "-0.018 0.038 0.086"
    end

    for i = 1:nF
        line    = split(readline(io))
        len     = parse(Int, shift!(line))
        if len == 3
            push!(fcs, Face{3, FaceEltype}(reinterpret(ZeroIndex{Int}, parse.(Int, line)))) # line looks like: "3 0 1 3"
        elseif len == 4
            push!(fcs, decompose(FaceType, Face{4, FaceEltype}(reinterpret(ZeroIndex{Int}, parse.(Int, line))))...) # line looks like: "4 0 1 2 3"
        end
    end

    return MeshType(vts, fcs)
end
