##############################
#
# obj-Files
#
##############################

function load(io::Stream{format"OBJ"}; facetype=GLTriangleFace,
    pointtype=Point3f, normaltype=Vec3f, uvtype=Any)

    # function parse_bool(x, default)
    #     if lowercase(x) == "off" || x == "0"
    #         return false
    #     elseif lowercase(x) == "on" || x == "1"
    #         return true
    #     else
    #         error("Failed to parse $x as Bool.")
    #     end
    # end

    points, v_normals, uv, faces = pointtype[], normaltype[], uvtype[], facetype[]
    f_uv_n_faces = (faces, facetype[], facetype[], facetype[])

    # TODO: Allow GeometryBasics to keep track of this in Mesh?
    material_ids = Int[]
    materials = Dict{String, Int}()
    current_material = 0
    material_counter = 0

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
                # add material

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
            
            # elseif "s" == command  # Blender sets this just before faces
            #     shading = parse_bool(lines[1])

            # elseif "o" == command  # Blender sets this before vertices
            #     object_name = join(lines, ' ')

            # elseif "g" == command
            #     group_name = join(lines, ' ')
            
            # elseif "mtllib" == command
            #     filename = join(lines, ' ')

            elseif "usemtl" == command # Blender sets this just before faces
                name = join(lines, ' ')
                last_material = current_material
                current_material = get!(materials, name) do 
                    material_counter += 1
                end
                if current_material != last_material
                    push!(material_ids, current_material)
                    last_material == 0 && continue # first material

                    # find material face buffer and push all the material faces
                    target_N = length(faces)
                    face = facetype(last_material)
                    for i in 2:4
                        if length(f_uv_n_faces[i]) < target_N
                            sizehint!(f_uv_n_faces[i], target_N)
                            while length(f_uv_n_faces[i]) < target_N
                                push!(f_uv_n_faces[i], face)
                            end
                            break
                        end
                    end
                end
            else
                #TODO
            end
        end
    end
    
    # drop material ids if no materials were specified
    if material_counter == 1
        for i in 4:-1:1
            if !isempty(f_uv_n_faces[i])
                empty!(f_uv_n_faces[i])
                break
            end
        end
        empty!(material_ids)
    else
        face = facetype(current_material)
        target_N = length(faces)
        for i in 2:4
            if length(f_uv_n_faces[i]) < target_N
                sizehint!(f_uv_n_faces[i], target_N)
                while length(f_uv_n_faces[i]) < target_N
                    push!(f_uv_n_faces[i], face)
                end
                break
            end
        end
    end

    point_attributes = Dict{Symbol, Any}()
    non_empty_faces = filtertuple(!isempty, f_uv_n_faces)

    # Do we have faces with different indices for positions and normals 
    # (and texture coordinates) per vertex?
    if length(non_empty_faces) > 1

        # map vertices with distinct indices for possition and normal (and uv)
        # to new indices, updating faces along the way
        faces, attrib_maps = merge_vertex_attribute_indices(non_empty_faces)

        # Update order of vertex attributes
        points = points[attrib_maps[1]]
        counter = 2
        if !isempty(uv)
            point_attributes[:uv] = uv[attrib_maps[counter]]
            counter += 1
        end
        if !isempty(v_normals)
            point_attributes[:normals] = v_normals[attrib_maps[counter]]
            counter += 1
        end
        if !isempty(material_ids)
            point_attributes[:material] = material_ids[attrib_maps[counter]]
        end

    else # we have vertex indexing - no need to remap

        if !isempty(v_normals)
            point_attributes[:normals] = v_normals
        end
        if !isempty(uv)
            point_attributes[:uv] = uv
        end
        if !isempty(material_ids)
            point_attributes[:material] = material_ids
        end

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
