export exportBinaryPly,
       exportAsciiPly,
       importAsciiPly

function write(msh::Mesh, fn::File{:plyb})
    vts = vertices(msh)
    fcs = faces(msh)

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
    for v in vts
        write(io, convert(Float32, v[1]))
        write(io, convert(Float32, v[2]))
        write(io, convert(Float32, v[3]))
    end

    for f in fcs
        write(io, convert(Uint8, 3))
        write(io, convert(Int32, f[1]-1))
        write(io, convert(Int32, f[2]-1))
        write(io, convert(Int32, f[3]-1))
    end
    close(io)
end


function exportAsciiPly(msh::Mesh, fn::File{:ply})

    vts = vertices(msh)
    fcs = faces(msh)

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
        print(io, "$(v[1]) $(v[2]) $(v[3])\n")
    end

    for f in fcs
        print(io, "3 $(f[1]-1) $(f[2]-1) $(f[3]-1)\n")
    end

    close(io)
end


function read(fn::File{:ply}; topology=false)
    io = open(fn, "r")
    mesh = importAsciiPly(io, topology=topology)
    close(io)
    return mesh
end


function importAsciiPly(io::IO; MT=GLNormalMesh, topology=false)
    mesh = MT()
    
    nV = 0
    nF = 0

    properties = String[]

    # read the header
    line = readline(io)

    while !startswith(line, "end_header")
        if startswith(line, "element vertex")
            nV = int(split(line)[3])
        elseif startswith(line, "element face")
            nF = int(split(line)[3])
        elseif startswith(line, "property")
            push!(properties, line)
        end
        line = readline(io)
    end
    # read the data
    for i = 1:nV
        push!(vts, eltype(vts)(split(readline(io)))) # line looks like: "-0.018 0.038 0.086"
    end

    for i = 1:nF
        push!(fcs, Face4(split(readline(io)))) # line looks like: "3 0 1 2"
    end


    return Mesh{Vertex, Face{Int}}(vts, fcs, topology)
end