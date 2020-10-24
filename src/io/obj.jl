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

    non_empty_faces = filter(f -> !isempty(f), f_uv_n_faces)
    vertices = Vector{NTuple{length(non_empty_faces), eltype(facetype)}}()
    for (k, fs) in enumerate(zip(non_empty_faces...))
        f = collect(first(fs)) # position indices
        for i in 1:3
            vertex = getindex.(fs, i) # one of each indices (pos/uv/normal)
            j = findfirst(==(vertex), vertices)
            if j === nothing
                push!(vertices, vertex)
                f[i] = length(vertices)
            else
                f[i] = j
            end
        end
        # remap indices
        faces[k] = facetype(f)
    end
    
    # remap positions, uvs, normals
    positions = Vector{pointtype}(undef, length(vertices))
    if !isempty(v_normals)
        point_attributes[:normals] = Vector{normaltype}(undef, length(vertices))
    end
    if !isempty(uv)
        point_attributes[:uv] = Vector{uvtype}(undef, length(vertices))
    end

    for (i, vertex) in enumerate(vertices)
        positions[i] = points[first(vertex)]
        j = 2
        if !isempty(uv)
            point_attributes[:uv][i] = uv[vertex[j]]
            j += 1
        end
        if !isempty(v_normals)
            point_attributes[:normals][i] = v_normals[vertex[j]]
        end
    end

    return Mesh(meta(positions; point_attributes...), faces)
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
