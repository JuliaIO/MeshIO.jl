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
    uv_faces = f_uv_n_faces[2]
    normal_faces = f_uv_n_faces[3]
    if !isempty(v_normals)
        if !isempty(normal_faces)
            normals_remapped = similar(points, eltype(v_normals))
            for (vf, nf) in zip(faces, normal_faces)
                for (vidx, nidx) in zip(vf, nf)
                    normals_remapped[vidx] = v_normals[nidx]
                end
            end
            v_normals = normals_remapped
        else
            # these are not per vertex normals, which we
            # can't deal with at the moment, so we just generate our own!
            if length(points) != length(v_normals)
                v_normals = normals(points, faces, normaltype)
            end
        end
        point_attributes[:normals] = v_normals
    end
    if !isempty(uv)
        if !isempty(uv_faces)
            uv_remapped = similar(points, eltype(uv))
            for (vf, uvf) in zip(faces, uv_faces)
                for (vidx, uvidx) in zip(vf, uvf)
                    uv_remapped[vidx] = uv[uvidx]
                end
            end
            uv = uv_remapped
        end
        point_attributes[:uv] = uv
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
