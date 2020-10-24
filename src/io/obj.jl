##############################
#
# obj-Files
#
##############################

function load(io::Stream{format"OBJ"}; facetype=GLTriangleFace,
        pointtype=Point3f0, normaltype=Vec3f0, uvtype=Vec2f0)

    points, v_normals, uv, faces = pointtype[], normaltype[], uvtype[], facetype[]
    f_uv_n_faces = (faces, GLTriangleFace[], GLTriangleFace[])
    last_command = ""
    attrib_type  = nothing
    for full_line in eachline(stream(io))
        # read a line, remove newline and leading/trailing whitespaces
        line = strip(chomp(full_line))
        !isascii(line) && error("non valid ascii in obj")

        if !startswith(line, "#") && !isempty(line) && !all(iscntrl, line) #ignore comments
            lines = split(line)
            command = popfirst!(lines) #first is the command, rest the data

            if "v" == command # mesh always has vertices
                push!(points, Point{3, Float32}(parse.(Float32, lines))) # should automatically convert to the right type in vertices(mesh)
            elseif "vn" == command
                push!(v_normals, Vec3f0(parse.(Float32, lines)))
            elseif "vt" == command
                if length(lines) == 2
                    push!(uv, Vec2f0(parse.(Float32, lines)))
                elseif length(lines) == 3
                    push!(uv, Vec3f0(parse.(Float32, lines)))
                else
                    error("Unknown UVW coordinate: $lines")
                end
            elseif "f" == command # mesh always has faces
                if any(x-> occursin("//", x), lines)
                    fs = process_face_normal(lines)
                elseif any(x-> occursin("/", x), lines)
                    fs = process_face_uv_or_normal(lines)
                else
                    append!(faces, triangulated_faces(facetype, lines))
                    continue
                end
                for i = 1:length(first(fs))
                    append!(f_uv_n_faces[i], triangulated_faces(facetype, getindex.(fs, i)))
                end
            else
                #TODO
            end
        end
    end
    point_attributes = Dict{Symbol, Any}()

    N = length(points)
    non_empty_faces = filter(f -> !isempty(f), f_uv_n_faces)
    void = tuple((one(eltype(facetype)) for _ in 1:length(non_empty_faces))...)
    vertices = fill(void, N)

    if !isempty(v_normals)
        point_attributes[:normals] = Vector{normaltype}(undef, N)
    end
    if !isempty(uv)
        point_attributes[:uv] = Vector{uvtype}(undef, N)
    end

    for (k, fs) in enumerate(zip(non_empty_faces...))
        f = collect(first(fs)) # position indices
        for i in 1:3
            l = 2
            vertex = getindex.(fs, i) # one of each indices (pos/uv/normal)

            if vertices[vertex[1]] == void
                # Replace void
                vertices[vertex[1]] = vertex
                f[i] = vertex[1]
                if !isempty(uv)
                    point_attributes[:uv][vertex[1]] = uv[vertex[l]]
                    l += 1
                end
                if !isempty(v_normals)
                    point_attributes[:normals][vertex[1]] = v_normals[vertex[l]]
                end
            elseif vertices[vertex[1]] == vertex
                # vertex is correct, nothing to replace
                f[i] = vertex[1]
            else
                @views j = findfirst(==(vertex), vertices[N+1:end])
                if j === nothing
                    # vertex is unique, add it as a new one and adjust
                    # points, uv, normals
                    push!(vertices, vertex)
                    f[i] = length(vertices)
                    push!(points, points[vertex[1]])
                    if !isempty(uv)
                        push!(point_attributes[:uv], uv[vertex[l]])
                        l += 1
                    end
                    if !isempty(v_normals)
                        push!(point_attributes[:normals], v_normals[vertex[l]])
                    end
                else
                    # vertex has already been added, adjust face
                    # (points, uv, normals correct because they've been pushed)
                    f[i] = j + N
                end
            end
        end
        # remap indices
        faces[k] = facetype(f)
    end

    return Mesh(meta(points; point_attributes...), faces)
end

# of form "faces v1 v2 v3 ....""
process_face(lines::Vector) = (lines,) # just put it in the same format as the others
# of form "faces v1//vn1 v2//vn2 v3//vn3 ..."
process_face_normal(lines::Vector) = split.(lines, "//")
# of form "faces v1/vt1 v2/vt2 v3/vt3 ..." or of form "faces v1/vt1/vn1 v2/vt2/vn2 v3/vt3/vn3 ...."
process_face_uv_or_normal(lines::Vector) = split.(lines, ('/',))

function triangulated_faces(::Type{Tf}, vertex_indices::Vector) where {Tf}
    poly_face = NgonFace{length(vertex_indices), UInt32}(parse.(UInt32, vertex_indices))
    return convert_simplex(Tf, poly_face)
end