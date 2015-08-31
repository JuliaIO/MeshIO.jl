import Base.writemime


function FileIO.save(f::Union(File{format"PLY_ASCII"}, File{format"PLY_BINARY"}), msh::AbstractMesh)
    fs = open(f)
    save(fs, msh)
    close(fs)
end

function FileIO.save(f::Stream{format"PLY_ASCII"}, msh::AbstractMesh)
    io      = stream(f)
    vts     = Vector{Point{3, Float32}}(msh)
    fcs     = Vector{Face{3, Float32, -1}}(msh)
    normals = Vector{Normal{3, Float32}}(msh)

    nV = length(vts)
    nF = length(fcs)

    # write the header
    write(io,"solid vcg\n")
    # write the data
    for i = 1:nF
        f = fcs[i]
        n = normals[i] # TODO: properly compute normal(f)
        v1, v2, v3 = vts[f]
        @printf io "  facet normal %e %e %e\n" n[1] n[2] n[3]
        write(io,"    outer loop\n")

        @printf io "      vertex  %e %e %e\n" v1[1] v1[2] v1[3]
        @printf io "      vertex  %e %e %e\n" v2[1] v2[2] v2[3]
        @printf io "      vertex  %e %e %e\n" v3[1] v3[2] v3[3]

        write(io,"    endloop\n")
        write(io,"  endfacet\n")
    end
    write(io,"endsolid vcg\n")
end


writemime(io::IO, ::MIME"model/stl+ascii", msh::AbstractMesh) = save(io, msh)


function FileIO.load(fs::Stream{format"STL_BINARY"}; MeshType=GLNormalMesh)
    #Binary STL
    #https://en.wikipedia.org/wiki/STL_%28file_format%29#Binary_STL
    io = stream(fs)
    readbytes(io, 80) # throw out header

    triangle_count = read(io, Uint32)
    FaceType    = facetype(MeshType)
    VertexType  = vertextype(MeshType)
    NormalType  = normaltype(MeshType)

    faces       = Array(FaceType,   triangle_count)
    vertices    = Array(VertexType, triangle_count*3)
    normals     = Array(NormalType, triangle_count*3)
    i = 0
    while !eof(io)
        faces[i+1]      = Face{3, Int, -1}(i*3, i*3+1, i*3+2)
        normals[i*3+1]  = NormalType(read(io, Float32), read(io, Float32), read(io, Float32))
        normals[i*3+2]  = normals[i*3+2] # hurts, but we need per vertex normals
        normals[i*3+3]  = normals[i*3+2]
        vertices[i*3+1] = VertexType(read(io, Float32), read(io, Float32), read(io, Float32))
        vertices[i*3+2] = VertexType(read(io, Float32), read(io, Float32), read(io, Float32))
        vertices[i*3+3] = VertexType(read(io, Float32), read(io, Float32), read(io, Float32))

        skip(io, 2) # throwout 16bit attribute
        i += 1
    end
    return MeshType(vertices=vertices, faces=faces, normals=normals)
end



function FileIO.load(fs::Stream{format"STL_ASCII"}; MeshType=GLNormalMesh)
    #ASCII STL
    #https://en.wikipedia.org/wiki/STL_%28file_format%29#ASCII_STL
    io = stream(fs)

    FaceType    = facetype(typ)
    VertexType  = vertextype(typ)
    NormalType  = normaltype(typ)

    mesh = MeshType()
    topology = true
    vert_count = 0
    vert_idx = [0,0,0]
    while !eof(file)
        line = split(lowercase(readline(file)))
        if !isempty(line) && line[1] == "facet"
            normal = NormalType(line[3:5])
            readline(file) # Throw away outerloop
            for i = 1:3
                vertex = VertexType(split(readline(file))[2:4])
                if topology
                    idx = findfirst(vts, vertex)
                end
                if topology && idx != 0
                    vert_idx[i] = idx
                else
                    push!(vertices(mesh), vertex)
                    vert_count += 1
                    vert_idx[i] = vert_count
                end
            end
            readline(file) # throwout endloop
            readline(file) # throwout endfacet
            push!(faces(mesh), Face{3, Int, 0}(vert_idx...))
        end
    end

    return typ(vts, fcs, topology)
end
