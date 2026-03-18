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

    # Parse header — same property tracking as binary loader
    line = readline(io)

    vertex_props = Tuple{Symbol, DataType}[]
    in_vertex_element = false
    in_face_element = false
    while !startswith(line, "end_header")
        if startswith(line, "element vertex")
            n_points = parse(Int, split(line)[3])
            in_vertex_element = true
            in_face_element = false
        elseif startswith(line, "element face")
            n_faces = parse(Int, split(line)[3])
            in_vertex_element = false
            in_face_element = true
        elseif startswith(line, "element")
            in_vertex_element = false
            in_face_element = false
        elseif startswith(line, "property") && in_vertex_element && !startswith(line, "property list")
            parts = split(line)
            push!(vertex_props, (Symbol(parts[3]), _ply_type(parts[2])))
        end
        line = readline(io)
    end

    # Detect grouped attributes
    prop_names = [p[1] for p in vertex_props]
    has_normals = :nx in prop_names && :ny in prop_names && :nz in prop_names
    has_uv = (:u in prop_names && :v in prop_names) ||
             (:s in prop_names && :t in prop_names) ||
             (:texture_u in prop_names && :texture_v in prop_names)
    uv_names = :u in prop_names ? (:u, :v) : :s in prop_names ? (:s, :t) : (:texture_u, :texture_v)

    # Build property-name-to-column-index mapping
    prop_idx = Dict(name => i for (i, (name, _)) in enumerate(vertex_props))

    faceeltype = eltype(facetype)
    points = Array{pointtype}(undef, n_points)
    point_normals = has_normals ? Array{normalstype}(undef, n_points) : nothing
    point_uvs = has_uv ? Array{Vec{2, Float32}}(undef, n_points) : nothing
    faces = facetype[]

    # Read vertex data — parse all columns, extract by index
    for i = 1:n_points
        numbers = parse.(Float32, split(readline(io)))
        points[i] = pointtype(numbers[prop_idx[:x]], numbers[prop_idx[:y]], numbers[prop_idx[:z]])
        if has_normals
            point_normals[i] = normalstype(numbers[prop_idx[:nx]], numbers[prop_idx[:ny]], numbers[prop_idx[:nz]])
        end
        if has_uv
            point_uvs[i] = Vec2f(numbers[prop_idx[uv_names[1]]], numbers[prop_idx[uv_names[2]]])
        end
    end

    for i = 1:n_faces
        line = split(readline(io))
        len = parse(Int, popfirst!(line))
        indices = reinterpret(ZeroIndex{UInt32}, parse.(UInt32, line[1:len]))
        if len == 3
            push!(faces, NgonFace{3, faceeltype}(indices))
        elseif len == 4
            push!(faces, convert_simplex(facetype, QuadFace{faceeltype}(indices))...)
        else
            for j in 2:len-1
                push!(faces, NgonFace{3, faceeltype}((indices[1], indices[j], indices[j+1])))
            end
        end
    end

    kwargs = Pair{Symbol, Any}[]
    has_normals && push!(kwargs, :normal => point_normals)
    has_uv && push!(kwargs, :uv => point_uvs)

    return Mesh(points, faces; kwargs...)
end

function load(fs::Stream{format"PLY_BINARY"}; facetype=GLTriangleFace, pointtype=Point3f, normalstype=Vec3f)
    io = stream(fs)
    n_points = 0
    n_faces = 0

    # Parse header — track ALL vertex properties for correct byte stride and attribute extraction
    line = readline(io)

    vertex_props = Tuple{Symbol, DataType}[]  # (:x, Float32), (:nx, Float64), (:u, Float32), ...
    face_index_type = UInt32
    face_count_type = UInt8
    in_vertex_element = false
    in_face_element = false
    while !startswith(line, "end_header")
        if startswith(line, "element vertex")
            n_points = parse(Int, split(line)[3])
            in_vertex_element = true
            in_face_element = false
        elseif startswith(line, "element face")
            n_faces = parse(Int, split(line)[3])
            in_vertex_element = false
            in_face_element = true
        elseif startswith(line, "element")
            in_vertex_element = false
            in_face_element = false
        elseif startswith(line, "property") && in_vertex_element && !startswith(line, "property list")
            parts = split(line)
            push!(vertex_props, (Symbol(parts[3]), _ply_type(parts[2])))
        elseif startswith(line, "property list") && in_face_element
            parts = split(line)
            face_count_type = _ply_type(parts[3])
            face_index_type = _ply_type(parts[4])
        end
        line = readline(io)
    end

    # Group scalar properties into known multi-component attributes:
    #   x,y,z → position (Point3f)
    #   nx,ny,nz → normal (Vec3f)
    #   u,v (or s,t or texture_u,texture_v) → uv (Vec2f)
    #   red,green,blue[,alpha] → color (Vec3f or Vec4f, normalized if UInt8)
    # Remaining scalars are kept as-is.
    prop_names = [p[1] for p in vertex_props]
    has_normals = :nx in prop_names && :ny in prop_names && :nz in prop_names
    has_uv = (:u in prop_names && :v in prop_names) ||
             (:s in prop_names && :t in prop_names) ||
             (:texture_u in prop_names && :texture_v in prop_names)
    has_rgb = :red in prop_names && :green in prop_names && :blue in prop_names
    has_alpha = has_rgb && :alpha in prop_names
    uv_names = :u in prop_names ? (:u, :v) : :s in prop_names ? (:s, :t) : (:texture_u, :texture_v)

    # Grouped attribute names to skip when collecting ungrouped scalars
    grouped = Set([:x, :y, :z])
    has_normals && union!(grouped, Set([:nx, :ny, :nz]))
    has_uv && union!(grouped, Set([uv_names...]))
    has_rgb && union!(grouped, Set([:red, :green, :blue]))
    has_alpha && push!(grouped, :alpha)

    # Ungrouped scalar properties (e.g. "confidence", "intensity", custom floats)
    ungrouped = [(name, typ) for (name, typ) in vertex_props if name ∉ grouped]

    # Pre-allocate arrays
    points = Array{pointtype}(undef, n_points)
    point_normals = has_normals ? Array{normalstype}(undef, n_points) : nothing
    point_uvs = has_uv ? Array{Vec{2, Float32}}(undef, n_points) : nothing
    point_colors = if has_alpha
        Array{Vec{4, Float32}}(undef, n_points)
    elseif has_rgb
        Array{Vec{3, Float32}}(undef, n_points)
    else
        nothing
    end
    scalar_arrays = Dict{Symbol, Vector{Float32}}(
        name => Vector{Float32}(undef, n_points) for (name, _) in ungrouped
    )

    # Read vertex data — iterate all properties in header order for correct byte alignment
    for i = 1:n_points
        vals = Dict{Symbol, Any}()
        for (pname, ptype) in vertex_props
            vals[pname] = read(io, ptype)
        end
        points[i] = pointtype(Float32(vals[:x]), Float32(vals[:y]), Float32(vals[:z]))
        if has_normals
            point_normals[i] = normalstype(Float32(vals[:nx]), Float32(vals[:ny]), Float32(vals[:nz]))
        end
        if has_uv
            point_uvs[i] = Vec2f(Float32(vals[uv_names[1]]), Float32(vals[uv_names[2]]))
        end
        if has_rgb
            # Normalize UInt8 color channels to [0,1]
            r, g, b = vals[:red], vals[:green], vals[:blue]
            color_type = Dict(vertex_props)[:red]
            if color_type <: Integer
                r, g, b = Float32(r) / 255f0, Float32(g) / 255f0, Float32(b) / 255f0
            else
                r, g, b = Float32(r), Float32(g), Float32(b)
            end
            if has_alpha
                a = vals[:alpha]
                a = color_type <: Integer ? Float32(a) / 255f0 : Float32(a)
                point_colors[i] = Vec4f(r, g, b, a)
            else
                point_colors[i] = Vec3f(r, g, b)
            end
        end
        for (name, _) in ungrouped
            scalar_arrays[name][i] = Float32(vals[name])
        end
    end

    # Read faces
    faceeltype = eltype(facetype)
    faces = facetype[]
    for i = 1:n_faces
        len = Int(read(io, face_count_type))
        indices = reinterpret(ZeroIndex{UInt32}, [UInt32(read(io, face_index_type) % UInt32) for _ in 1:len])
        if len == 3
            push!(faces, NgonFace{3, faceeltype}(indices))
        elseif len == 4
            push!(faces, convert_simplex(facetype, QuadFace{faceeltype}(indices))...)
        else
            for j in 2:len-1
                push!(faces, NgonFace{3, faceeltype}((indices[1], indices[j], indices[j+1])))
            end
        end
    end

    # Verify face indices are in bounds
    for f in faces
        for idx in f
            vidx = raw(idx) + 1  # ZeroIndex → 1-based
            if vidx < 1 || vidx > n_points
                error("Faces address $vidx vertex attributes but only $n_points are present.")
            end
        end
    end

    # Build keyword arguments for Mesh constructor
    kwargs = Pair{Symbol, Any}[]
    has_normals && push!(kwargs, :normal => point_normals)
    has_uv && push!(kwargs, :uv => point_uvs)
    point_colors !== nothing && push!(kwargs, :color => point_colors)
    for (name, arr) in scalar_arrays
        push!(kwargs, name => arr)
    end

    return Mesh(points, faces; kwargs...)
end

# Map PLY type strings to Julia types
function _ply_type(s::AbstractString)
    s == "float" || s == "float32" ? Float32 :
    s == "double" || s == "float64" ? Float64 :
    s == "int" || s == "int32" ? Int32 :
    s == "uint" || s == "uint32" ? UInt32 :
    s == "short" || s == "int16" ? Int16 :
    s == "ushort" || s == "uint16" ? UInt16 :
    s == "char" || s == "int8" ? Int8 :
    s == "uchar" || s == "uint8" ? UInt8 :
    error("Unknown PLY type: $s")
end
