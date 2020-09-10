function save(f::Stream{format"STL_ASCII"}, mesh::AbstractMesh)
    io = stream(f)
    points = decompose(Point3f0, mesh)
    faces = decompose(GLTriangleFace, mesh)
    normals = decompose_normals(mesh)

    n_points = length(points)
    n_faces = length(faces)

    # write the header
    write(io,"solid vcg\n")
    # write the data
    for i = 1:n_faces
        f = faces[i]
        n = normals[f][1] # TODO: properly compute normal(f)
        v1, v2, v3 = points[f]
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
    io = stream(f)
    points = decompose(Point3f0, mesh)
    faces = decompose(GLTriangleFace, mesh)
    normals = decompose_normals(mesh)
    n_faces = length(faces)
    # Implementation made according to https://en.wikipedia.org/wiki/STL_%28file_format%29#Binary_STL
    for i in 1:80 # write empty header
        write(io, 0x00)
    end

    write(io, UInt32(n_faces)) # write triangle count
    for i = 1:n_faces
        f = faces[i]
        n = normals[f][1] # TODO: properly compute normal(f)
        triangle = points[f]
        foreach(j-> write(io, n[j]), 1:3)
        for point in triangle
            foreach(p-> write(io, p), point)
        end
        write(io, 0x0000) # write 16bit empty bit
    end
end


function load(fs::Stream{format"STL_BINARY"}; facetype=GLTriangleFace,
              pointtype=Point3f0, normaltype=Vec3f0)
    #Binary STL
    #https://en.wikipedia.org/wiki/STL_%28file_format%29#Binary_STL
    io = stream(fs)
    read(io, 80) # throw out header
    triangle_count = read(io, UInt32)

    faces = Array{facetype}(undef, triangle_count)
    vertices = Array{pointtype}(undef, triangle_count * 3)
    normals = Array{normaltype}(undef, triangle_count * 3)

    i = 0
    while !eof(io)
        faces[i+1] = GLTriangleFace(i * 3 + 1, i * 3 + 2, i * 3 + 3)
        normal = (read(io, Float32), read(io, Float32), read(io, Float32))

        normals[i*3+1] = normaltype(normal...)
        normals[i*3+2] = normals[i*3+1] # hurts, but we need per vertex normals
        normals[i*3+3] = normals[i*3+1]

        vertices[i*3+1] = pointtype(read(io, Float32), read(io, Float32), read(io, Float32))
        vertices[i*3+2] = pointtype(read(io, Float32), read(io, Float32), read(io, Float32))
        vertices[i*3+3] = pointtype(read(io, Float32), read(io, Float32), read(io, Float32))

        skip(io, 2) # throwout 16bit attribute
        i += 1
    end

    return Mesh(meta(vertices; normals=normals), faces)
end



function load(fs::Stream{format"STL_ASCII"}; facetype=GLTriangleFace,
              pointtype=Point3f0, normaltype=Vec3f0, topology=false)
    #ASCII STL
    #https://en.wikipedia.org/wiki/STL_%28file_format%29#ASCII_STL
    io = stream(fs)

    points = pointtype[]
    faces = facetype[]
    normals = normaltype[]

    vert_count = 0
    vert_idx = [0, 0, 0]

    while !eof(io)
        line = split(lowercase(readline(io)))
        if !isempty(line) && line[1] == "facet"
            normal = normaltype(parse.(eltype(normaltype), line[3:5]))
            readline(io) # Throw away outerloop
            for i in 1:3
                vertex = pointtype(parse.(eltype(pointtype),
                                   split(readline(io))[2:4]))
                if topology
                    idx = findfirst(vertices(mesh), vertex)
                end
                if topology && idx != 0
                    vert_idx[i] = idx
                else
                    push!(points, vertex)
                    push!(normals, normal)
                    vert_count += 1
                    vert_idx[i] = vert_count
                end
            end
            readline(io) # throwout endloop
            readline(io) # throwout endfacet
            push!(faces, TriangleFace{Int}(vert_idx...))
        end
    end
    return Mesh(meta(points; normals=normals), faces)
end
