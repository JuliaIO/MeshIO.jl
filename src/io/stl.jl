function save(f::Stream{format"STL_ASCII"}, mesh::AbstractMesh)
    io      = stream(f)
    vts     = decompose(Point{3, Float32}, mesh)
    fcs     = decompose(Face{3, ZeroIndex{Cuint}}, mesh)
    normals = decompose(Normal{3, Float32}, mesh)

    nV = length(vts)
    nF = length(fcs)

    # write the header
    write(io,"solid vcg\n")
    # write the data
    for i = 1:nF
        f = fcs[i]
        n = normals[f][1] # TODO: properly compute normal(f)
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


show(io::IO, ::MIME"model/stl+ascii", mesh::AbstractMesh) = save(io, mesh)


function save(f::Stream{format"STL_BINARY"}, mesh::AbstractMesh)
    io      = stream(f)
    vts     = decompose(Point{3, Float32}, mesh)
    fcs     = decompose(Face{3, ZeroIndex{Cuint}}, mesh)
    normals = decompose(Normal{3, Float32}, mesh)
    nF = length(fcs)
    # Implementation made according to https://en.wikipedia.org/wiki/STL_%28file_format%29#Binary_STL
    for i in 1:80 # write empty header
        write(io,0x00)
    end

    write(io, UInt32(nF)) # write triangle count
    for i = 1:nF
        f = fcs[i]
        n = normals[f][1] # TODO: properly compute normal(f)
        v1, v2, v3 = vts[f]
        for j=1:3; write(io, n[j]); end # write normal

        for v in [v1, v2, v3]
            for j = 1:3
                write(io, v[j]) # write vertex coordinates
            end
        end
        write(io,0x0000) # write 16bit empty bit
    end
end


function load(fs::Stream{format"STL_BINARY"}, MeshType=GLNormalMesh)
    #Binary STL
    #https://en.wikipedia.org/wiki/STL_%28file_format%29#Binary_STL
    io = stream(fs)
    read(io, 80) # throw out header

    triangle_count = read(io, UInt32)
    FaceType    = facetype(MeshType)
    VertexType  = vertextype(MeshType)
    NormalType  = normaltype(MeshType)

    faces       = Array{FaceType}(undef, triangle_count)
    vertices    = Array{VertexType}(undef, triangle_count*3)
    normals     = Array{NormalType}(undef, triangle_count*3)
    i = 0
    while !eof(io)
        faces[i+1]      = Face{3, ZeroIndex{Int}}(i*3+1, i*3+2, i*3+3)
        normals[i*3+1]  = NormalType(read(io, Float32), read(io, Float32), read(io, Float32))
        normals[i*3+2]  = normals[i*3+1] # hurts, but we need per vertex normals
        normals[i*3+3]  = normals[i*3+1]
        vertices[i*3+1] = VertexType(read(io, Float32), read(io, Float32), read(io, Float32))
        vertices[i*3+2] = VertexType(read(io, Float32), read(io, Float32), read(io, Float32))
        vertices[i*3+3] = VertexType(read(io, Float32), read(io, Float32), read(io, Float32))

        skip(io, 2) # throwout 16bit attribute
        i += 1
    end
    return MeshType(vertices=vertices, faces=faces, normals=normals)
end



function load(fs::Stream{format"STL_ASCII"}, MeshType=GLNormalMesh)
    #ASCII STL
    #https://en.wikipedia.org/wiki/STL_%28file_format%29#ASCII_STL
    io = stream(fs)

    FaceType   = facetype(MeshType)
    VertexType = vertextype(MeshType)
    vs         = VertexType[]
    fs         = FaceType[]

    topology   = false
    vert_count = 0
    vert_idx   = [0,0,0]

    while !eof(io)
        line = split(lowercase(readline(io)))
        if !isempty(line) && line[1] == "facet"
            #normal = NormalType(line[3:5])
            readline(io) # Throw away outerloop
            for i=1:3
                vertex = VertexType(parse.(eltype(VertexType), split(readline(io))[2:4]))
                if topology
                    idx = findfirst(vertices(mesh), vertex)
                end
                if topology && idx != 0
                    vert_idx[i] = idx
                else
                    push!(vs, vertex)
                    vert_count += 1
                    vert_idx[i] = vert_count
                end
            end
            readline(io) # throwout endloop
            readline(io) # throwout endfacet
            push!(fs, Face{3, Int}(vert_idx...))
        end
    end
    return MeshType(vs, fs)
end
