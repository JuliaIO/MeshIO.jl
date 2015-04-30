export exportStl,
       importBinarySTL,
       importAsciiSTL

import Base.writemime

function exportStl(msh::Mesh, fn::String)
  exportStl(msh, open(fn, "w"))
end

function exportStl(msh::Mesh, str::IO, closeAfterwards::Bool)
    vts = msh.vertices
    fcs = msh.faces
    nV = size(vts,1)
    nF = size(fcs,1)

    # write the header
    write(str,"solid vcg\n")

    # write the data
    for i = 1:nF
        f = fcs[i]
        n = [0,0,0] # TODO: properly compute normal(f)
        @printf str "  facet normal %e %e %e\n" n[1] n[2] n[3]
        write(str,"    outer loop\n")
        v = vts[f.v1]
        @printf str "      vertex  %e %e %e\n" v[1] v[2] v[3]

        v = vts[f.v2]
        @printf str "      vertex  %e %e %e\n" v[1] v[2] v[3]

        v = vts[f.v3]
        @printf str "      vertex  %e %e %e\n" v[1] v[2] v[3]

        write(str,"    endloop\n")
        write(str,"  endfacet\n")
    end

    write(str,"endsolid vcg\n")
    if closeAfterwards
        close(str)
    end
end

exportStl(msh::Mesh, str::IO) = exportStl(msh, str, true)

function writemime(io::IO, ::MIME"model/stl+ascii", msh::Mesh)
  exportSTL(msh, io)
end


function importBinarySTL(file::String; topology=false)
    fn = open(file,"r")
    mesh = importBinarySTL(fn, topology=topology)
    close(fn)
    return mesh
end

function importBinarySTL(file::IO; topology=false, read_header=false)
    #Binary STL
    #https://en.wikipedia.org/wiki/STL_%28file_format%29#Binary_STL

    binarySTLvertex(file) = Vertex(float64(read(file, Float32)),
                                   float64(read(file, Float32)),
                                   float64(read(file, Float32)))

    vts = Vertex[]
    fcs = Face{Int}[]

    if !read_header
        readbytes(file, 80) # throw out header
    end
    read(file, Uint32) # throwout triangle count

    vert_count = 0
    vert_idx = [0,0,0]
    while !eof(file)
        normal = binarySTLvertex(file)
        for i = 1:3
            vertex = binarySTLvertex(file)
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
        skip(file, 2) # throwout 16bit attribute
        push!(fcs, Face{Int}(vert_idx...))
    end

    return Mesh{Vertex, Face{Int}}(vts, fcs, topology)
end

function importAsciiSTL(file::String; topology=false)
    fn = open(file,"r")
    mesh = importAsciiSTL(fn, topology=topology)
    close(fn)
    return mesh
end

function importAsciiSTL(file::IO; topology=false)
    #ASCII STL
    #https://en.wikipedia.org/wiki/STL_%28file_format%29#ASCII_STL

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

    return Mesh{Vertex, Face{Int}}(vts, fcs, topology)
end
