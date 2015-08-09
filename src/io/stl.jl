export exportStl,
       importBinarySTL,
       importAsciiSTL

import Base.writemime

function detect_stlbinary(io)
    seekstart(io)
    header = readbytes(io, 80)
    header[1:6] == b"solid " && return false
    number_of_triangle_blocks = read(io, Uint32)
    size_triangleblock = (4*3*sizeof(Float32)) + sizeof(Uint16) #1 normal, 3 vertices in Float32 + attrib count, usually 0
    skip(io, number_of_triangle_blocks*size_triangleblock-sizeof(Uint16))
    eof(io) && return false # should not end here
    attrib_byte_count = read(io, Uint16) # read last attrib_byte
    
    attrib_byte_count != zero(Uint16) && return false # should be zero as not used
    eof(io) && return true
    false
end

add_format(format"STL_ASCII", "solid ", ".stl")
add_format(format"STL_BINARY", detect_stlbinary, ".stl")


function save(f::Union(File{format"PLY_ASCII"}, File{format"PLY_BINARY"}), msh::Mesh)
    fs = open(f)
    save(fs, msh)
    close(fs)
end

function save(f::Stream{format"PLY_ASCII"}, msh::Mesh)
    io      = stream(f)
    vts     = Vector{Point{3, Float32}(msh)
    fcs     = Vector{Face{3, Float32, -1}(msh)
    normals = Vector{Normal{3, Float32}(msh)

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


writemime(io::IO, ::MIME"model/stl+ascii", msh::Mesh) = save(io, msh)


function load(fs::Stream{format"PLY_BINARY"}; typ=GLNormalMesh)
    #Binary STL
    #https://en.wikipedia.org/wiki/STL_%28file_format%29#Binary_STL

    binarySTLvertex(file) = Vertex(float64(read(file, Float32)),
                                   float64(read(file, Float32)),
                                   float64(read(file, Float32)))

    io = stream(fs)
    seekstart(io)
    readbytes(file, 80) # throw out header

    triangle_count = read(file, Uint32)
    FaceType    = facetype(typ)
    VertexType  = vertextype(typ)
    NormalType  = normaltype(typ)

    faces       = Array(FaceType,   triangle_count)
    vertices    = Array(VertexType, triangle_count*3)
    normals     = Array(NormalType, triangle_count)
    i = 1
    while !eof(file)
        faces[i+1]      = Face{3, Int, -1}(i*3, i*3+1, i*3+2)
        normals[i+1]    = read(io, Normal{3, Float32})
        vertices[i*3+1] = read(io, Point{3,  Float32})
        vertices[i*3+2] = read(io, Point{3,  Float32})
        vertices[i*3+3] = read(io, Point{3,  Float32})

        skip(file, 2) # throwout 16bit attribute
        i += 1
    end

    return typ(vts, fcs, topology)
end

function load(file::String; topology=false)
    fn = open(file,"r")
    mesh = importAsciiSTL(fn, topology=topology)
    close(fn)
    return mesh
end

function importAsciiSTL(fs::Stream{format"PLY_BINARY"}; typ=GLNormalMesh)
    #ASCII STL
    #https://en.wikipedia.org/wiki/STL_%28file_format%29#ASCII_STL
    io = stream(fs)
    skipmagic(io)

    vts = Vertex[]
    fcs = Face{Int}[]

    vert_count = 0
    vert_idx = [0,0,0]
    while !eof(file)
        line = split(lowercase(readline(file)))
        if !isempty(line) && line[1] == "facet"
            normal = Vertex(float64(line[3:5])...)
            readline(file) # Throw away outerloop
            for i = 1:3
                vertex = Vertex(float64(split(readline(file))[2:4])...)
                if topology
                    idx = findfirst(vts, vertex)
                end
                if topology && idx != 0
                    vert_idx[i] = idx
                else
                    push!(vts, vertex)
                    vert_count += 1
                    vert_idx[i] = vert_count
                end
            end
            readline(file) # throwout endloop
            readline(file) # throwout endfacet
            push!(fcs, Face{Int}(vert_idx...))
        end
    end

    return typ(vts, fcs, topology)
end
