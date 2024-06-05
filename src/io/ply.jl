function save(f::Stream{format"PLY_BINARY"}, msh::AbstractMesh)
    io = stream(f)
    points = coordinates(msh)
    point_normals = normals(msh)
    meshfaces = faces(msh)
    n_points = length(points)
    n_faces = length(meshfaces)

    # write the header
    write(io, "ply\n")
    write(io, "format binary_little_endian 1.0\n")
    write(io, "element vertex $n_points\n")
    write(io, "property float x\nproperty float y\nproperty float z\n")
    if !isnothing(point_normals)
        write(io, "property float nx\nproperty float ny\nproperty float nz\n")
    end
    write(io, "element face $n_faces\n")
    write(io, "property list uchar int vertex_index\n")
    write(io, "end_header\n")

    # write the vertices and faces

    if isnothing(point_normals)
        write(io, points)
    else
        for (v, n) in zip(points, point_normals)
            write(io, v)
            write(io, n)
        end
    end

    for f in meshfaces
        write(io, convert(UInt8, length(f)))
        write(io, raw.(ZeroIndex.(f))...)
    end
    close(io)
end

function save(f::Stream{format"PLY_ASCII"}, msh::AbstractMesh)
    io = stream(f)
    points = coordinates(msh)
    point_normals = normals(msh)
    meshfaces = faces(msh)
    n_points = length(points)
    n_faces = length(meshfaces)

    # write the header
    write(io, "ply\n")
    write(io, "format ascii 1.0\n")
    write(io, "element vertex $n_points\n")
    write(io, "property float x\nproperty float y\nproperty float z\n")
    if !isnothing(point_normals)
        write(io, "property float nx\nproperty float ny\nproperty float nz\n")
    end
    write(io, "element face $n_faces\n")
    write(io, "property list uchar int vertex_index\n")
    write(io, "end_header\n")

    # write the vertices and faces
    if isnothing(point_normals)
        for v in points
            println(io, join(Point{3, Float32}(v), " "))
        end
    else
        for (v, n) in zip(points, point_normals)
            println(io, join([v n], " "))
        end
    end
    for f in meshfaces
        println(io, length(f), " ", join(raw.(ZeroIndex.(f)), " "))
    end
    close(io)
end

function load(fs::Stream{format"PLY_ASCII"}; facetype=GLTriangleFace, pointtype=Point3f, normalstype=Vec3f)
    io = stream(fs)
    n_points = 0
    n_faces = 0

    properties = String[]

    # read the header
    line = readline(io)

    has_normals = false
    while !startswith(line, "end_header")
        if startswith(line, "element vertex")
            n_points = parse(Int, split(line)[3])
        elseif startswith(line, "property float nx") || startswith(line, "property double nx")
            has_normals = true
        elseif startswith(line, "element face")
            n_faces = parse(Int, split(line)[3])
        elseif startswith(line, "property")
            push!(properties, line)
        end
        line = readline(io)
    end

    faceeltype = eltype(facetype)
    points = Array{pointtype}(undef, n_points)
    point_normals = Array{normalstype}(undef, n_points)
    #faces = Array{FaceType}(undef, n_faces)
    faces = facetype[]

    # read the data
    for i = 1:n_points
        numbers = parse.(eltype(pointtype), split(readline(io)))
        points[i] = pointtype(numbers[1:3])
        if has_normals && length(numbers) >= 6
            point_normals[i] = pointtype(numbers[4:6]) 
        end
    end

    for i = 1:n_faces
        line = split(readline(io))
        len = parse(Int, popfirst!(line))
        if len == 3
            push!(faces, NgonFace{3, faceeltype}(reinterpret(ZeroIndex{UInt32}, parse.(UInt32, line)))) # line looks like: "3 0 1 3"
        elseif len == 4
            push!(faces, convert_simplex(facetype, QuadFace{faceeltype}(reinterpret(ZeroIndex{UInt32}, parse.(UInt32, line))))...) # line looks like: "4 0 1 2 3"
        end
    end
    if has_normals
        return Mesh(meta(points; normals=point_normals), faces)
    else
        return Mesh(points, faces)
    end
end

function load(fs::Stream{format"PLY_BINARY"}; facetype=GLTriangleFace, pointtype=Point3f, normalstype=Vec3f)
    io = stream(fs)
    n_points = 0
    n_faces = 0

    properties = String[]

    # read the header
    line = readline(io)

    has_normals = false
    has_doubles = Float32
    xtype  = Float32; ytype  = Float32;  ztype = Float32
    nxtype = Float32; nytype = Float32; nztype = Float32
    while !startswith(line, "end_header")
        if startswith(line, "element vertex")
            n_points = parse(Int, split(line)[3])
        elseif startswith(line, "property double x")
            xtype = Float64
        elseif startswith(line, "property double y")
            ytype = Float64
        elseif startswith(line, "property double z")
            ztype = Float64
        elseif startswith(line, "property float n")
            has_normals = true
        elseif startswith(line, "property double nx")
            has_normals = true
            nxtype = Float64
        elseif startswith(line, "property double ny")
            has_normals = true
            nytype = Float64
        elseif startswith(line, "property double nz")
            has_normals = true
            nztype = Float64
        elseif startswith(line, "element face")
            n_faces = parse(Int, split(line)[3])
        elseif startswith(line, "property")
            push!(properties, line)
        end
        line = readline(io)
    end

    faceeltype = eltype(facetype)
    points = Array{pointtype}(undef, n_points)
    point_normals = Array{normalstype}(undef, n_points)
    #faces = Array{FaceType}(undef, n_faces)
    faces = facetype[]

    # read the data
    for i = 1:n_points
        points[i] = pointtype(read(io, xtype), read(io, ytype), read(io, ztype))
        if has_normals
            point_normals[i] = normalstype(read(io, nxtype), read(io, nytype), read(io, nztype))
        end
    end

    for i = 1:n_faces
        len = read(io, UInt8)
        indices = reinterpret(ZeroIndex{UInt32}, [ read(io, UInt32) for _ in 1:len ]) 
        if len == 3
            push!(faces, NgonFace{3, faceeltype}(indices)) # line looks like: "3 0 1 3"
        elseif len == 4
            push!(faces, convert_simplex(facetype, QuadFace{faceeltype}(indices))...) # line looks like: "4 0 1 2 3"
        end
    end

    if has_normals
        return Mesh(meta(points; normals=point_normals), faces)
    else
        return Mesh(points, faces)
    end
end
