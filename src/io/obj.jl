##############################
#
# obj-Files
#
##############################

function load(io::Stream{format"OBJ"}; facetype=GLTriangleFace,
    pointtype=Point3f, normaltype=Vec3f, uvtype=Vec2f)

    points, v_normals, uv, faces = pointtype[], normaltype[], uvtype[], Any[]
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
                    pos_faces    = triangulated_faces(facetype, getindex.(fs, 1))
                    normal_faces = triangulated_faces(facetype, getindex.(fs, 2))
                    append!(faces, GeometryBasics.NormalFace.(pos_faces, normal_faces))

                elseif any(x-> occursin("/", x), lines)
                    fs = process_face_uv_or_normal(lines)
                    pos_faces = triangulated_faces(facetype, getindex.(fs, 1))
                    uv_faces  = triangulated_faces(facetype, getindex.(fs, 2))
                    if length(fs[1]) == 2
                        append!(faces, GeometryBasics.UVFace.(pos_faces, uv_faces))
                    else
                        normal_faces = triangulated_faces(facetype, getindex.(fs, 3))
                        append!(faces, GeometryBasics.NormalUVFace.(pos_faces, normal_faces, uv_faces))
                    end
                else
                    append!(faces, triangulated_faces(facetype, lines))
                end
            else
                #TODO
            end
        end
    end

    vertex_attributes = Dict{Symbol, Any}()

    # TODO: add GeometryBasics convenience for dropping nothing vertex attributes?
    if !isempty(v_normals)
        vertex_attributes[:normal] = v_normals
    end

    if !isempty(uv)
        vertex_attributes[:uv] = uv
    end

    # TODO: Can we avoid this conversion?
    #       Also, is it safe to do? Or can an obj file define different face types for different groups?
    faces = convert(Vector{typeof(first(faces))}, faces)

    return GeometryBasics.mesh(points, faces, facetype = facetype; vertex_attributes...)
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
    io = stream(f)
    for p in decompose(Point3f, mesh)
        println(io, "v ", p[1], " ", p[2], " ", p[3])
    end

    if hasproperty(mesh, :uv)
        for uv in mesh.uv
            println(io, "vt ", uv[1], " ", uv[2])
        end
    end

    if hasproperty(mesh, :normals)
        for n in decompose_normals(mesh)
            println(io, "vn ", n[1], " ", n[2], " ", n[3])
        end
    end

    F = eltype(faces(mesh))
    for f in decompose(F, mesh)
        println(io, "f ", join(convert.(Int, f), " "))
    end
end
