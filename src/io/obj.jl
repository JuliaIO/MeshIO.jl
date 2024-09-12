##############################
#
# obj-Files
#
##############################

function load(io::Stream{format"OBJ"}; facetype=GLTriangleFace,
        pointtype=Point3f, normaltype=Vec3f, uvtype=Any)

    points, v_normals, uv, faces = pointtype[], normaltype[], uvtype[], facetype[]
    f_uv_n_faces = (faces, facetype[], facetype[])

    for full_line in eachline(stream(io))
        # read a line, remove newline and leading/trailing whitespaces
        line = strip(chomp(full_line))
        !isascii(line) && error("non valid ascii in obj")

        if !startswith(line, "#") && !isempty(line) && !all(iscntrl, line) #ignore comments
            lines = split(line)
            command = popfirst!(lines) #first is the command, rest the data

            if "v" == command # mesh always has vertices
                push!(points, pointtype(parse.(eltype(pointtype), lines)))
            elseif "vn" == command
                push!(v_normals, normaltype(parse.(eltype(normaltype), lines)))
            elseif "vt" == command
                if length(lines) == 2
                    if uvtype == Any
                        uvtype = Vec2f
                        uv = uvtype[]
                    end
                    push!(uv, Vec{2,eltype(uvtype)}(parse.(eltype(uvtype), lines)))
                elseif length(lines) == 3
                    if uvtype == Any
                        uvtype = Vec3f
                        uv = uvtype[]
                    end
                    push!(uv, Vec{3,eltype(uvtype)}(parse.(eltype(uvtype), lines)))
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

    if !isempty(f_uv_n_faces[2]) && (f_uv_n_faces[2] != faces)
        uv = FaceView(uv, f_uv_n_faces[2])
    end
    
    if !isempty(f_uv_n_faces[3]) && (f_uv_n_faces[3] != faces)
        v_normals = FaceView(v_normals, f_uv_n_faces[3])
    end

    return GeometryBasics.mesh(
        points, faces, facetype = facetype; 
        uv = isempty(uv) ? nothing : uv, 
        normal = isempty(v_normals) ? nothing : v_normals
    )
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

function _typemax(::Type{OffsetInteger{O, T}}) where {O, T}
    typemax(T)
end

function save(f::Stream{format"OBJ"}, mesh::AbstractMesh)
    # TODO: allow saving with faceviews (i.e. build the / or // syntax)
    if any(v -> v isa FaceView, values(vertex_attributes(mesh)))
        mesh = GeometryBasics.clear_faceviews(mesh)
    end

    io = stream(f)
    for p in decompose(Point3f, mesh)
        println(io, "v ", p[1], " ", p[2], " ", p[3])
    end

    if hasproperty(mesh, :uv)
        for uv in mesh.uv
            println(io, "vt ", uv[1], " ", uv[2])
        end
    end

    if hasproperty(mesh, :normal)
        for n in decompose_normals(mesh)
            println(io, "vn ", n[1], " ", n[2], " ", n[3])
        end
    end

    F = eltype(faces(mesh))
    for f in decompose(F, mesh)
        println(io, "f ", join(convert.(Int, f), " "))
    end
end
