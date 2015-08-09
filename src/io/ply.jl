export exportBinaryPly,
       exportAsciiPly,
       importAsciiPly

add_format(format"PLY_ASCII", b"ply\nformat ascii 1.0\n", ".ply")
add_format(format"PLY_BINARY", b"ply\nformat binary_little_endian 1.0\n", ".ply")

add_loader(format"PLY_ASCII", :GeometryTypes)
add_saver(format"PLY_BINARY", :GeometryTypes)

function save(f::File{format"PLY_BINARY"}, msh::Mesh)

    vts = msh[Point3{Float32}]
    fcs = msh[Face3{Int32, -1}]

    nV = length(vts)
    nF = length(fcs)

    io = open(fn, "w")
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
        write(io, convert(Uint8, 3))
        write(io, f...)
    end
    close(io)
end
const ply_ascii = FileEnding{:ply_binary}(:ply, b"ply\nformat binary_little_endian 1.0\n")


function save(f::File{format"PLY_ASCII"}, msh::Mesh)

    vts = msh[Point3{Float32}]
    fcs = msh[Face3{Int32, -1}]

    nV = length(vts)
    nF = length(fcs)

    io = open(fn, "w")

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
        println(io, join(v, " "))
    end
    for f in fcs
        println(io, length(f), " ", join(f, " "))
    end
    close(io)
end

function load(f::File{format"PLY_ASCII"}; typ=GLNormalMesh)
    io   = open(fn)
    skipmagic(io, f)
    mesh = load(io, typ)
    close(io)
    return mesh
end

function load(fs::Stream{format"PLY_ASCII"}; typ=GLNormalMesh)
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
    VertexType  = vertextype(typ)
    FaceType    = facetype(typ)
    FaceEltype  = eltype(FaceType)

    vts         = Array(VertexType, nV)
    fcs         = Array(FaceType, nF)

    # read the data
    for i = 1:nV
        vts[i] = VertexType(split(readline(io))) # line looks like: "-0.018 0.038 0.086"
    end

    for i = 1:nF
        line    = split(readline(io))
        len     = parse(Int, shift!(line))
        if len == 3 # workaround for not having generic Face type like Face{4, T}
            fcs[i]  = FaceType(Face3{FaceEltype, -1}(line)) # line looks like: "3 0 1 2"
        elseif len == 4
            fcs[i]  = FaceType(Face4{FaceEltype, -1}(line))
        else
            error("face type with length $len is not supported yet")
        end
    end

    return MeshType(vts, fcs)
endexport exportBinaryPly,
       exportAsciiPly,
       importAsciiPly

add_format(format"PLY_ASCII", b"ply\nformat ascii 1.0\n", ".ply")
add_format(format"PLY_BINARY", b"ply\nformat binary_little_endian 1.0\n", ".ply")

add_loader(format"PLY_ASCII", :GeometryTypes)
add_saver(format"PLY_BINARY", :GeometryTypes)

function save(f::File{format"PLY_BINARY"}, msh::Mesh)

    vts = msh[Point3{Float32}]
    fcs = msh[Face3{Int32, -1}]

    nV = length(vts)
    nF = length(fcs)

    io = open(fn, "w")
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
        write(io, convert(Uint8, 3))
        write(io, f...)
    end
    close(io)
end
const ply_ascii = FileEnding{:ply_binary}(:ply, b"ply\nformat binary_little_endian 1.0\n")


function save(f::File{format"PLY_ASCII"}, msh::Mesh)

    vts = msh[Point3{Float32}]
    fcs = msh[Face3{Int32, -1}]

    nV = length(vts)
    nF = length(fcs)

    io = open(fn, "w")

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
        println(io, join(v, " "))
    end
    for f in fcs
        println(io, length(f), " ", join(f, " "))
    end
    close(io)
end

function load(f::File{format"PLY_ASCII"}; typ=GLNormalMesh)
    io   = open(fn)
    skipmagic(io, f)
    mesh = load(io, typ)
    close(io)
    return mesh
end

function load(fs::Stream{format"PLY_ASCII"}; typ=GLNormalMesh)
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
    VertexType  = vertextype(typ)
    FaceType    = facetype(typ)
    FaceEltype  = eltype(FaceType)

    vts         = Array(VertexType, nV)
    fcs         = Array(FaceType, nF)

    # read the data
    for i = 1:nV
        vts[i] = VertexType(split(readline(io))) # line looks like: "-0.018 0.038 0.086"
    end

    for i = 1:nF
        line    = split(readline(io))
        len     = parse(Int, shift!(line))
        if len == 3 # workaround for not having generic Face type like Face{4, T}
            fcs[i]  = FaceType(Face3{FaceEltype, -1}(line)) # line looks like: "3 0 1 2"
        elseif len == 4
            fcs[i]  = FaceType(Face4{FaceEltype, -1}(line))
        else
            error("face type with length $len is not supported yet")
        end
    end

    return MeshType(vts, fcs)
end