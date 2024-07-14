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
    material_faces = facetype[]
    f_uv_n_faces = (faces, facetype[], facetype[], material_faces)


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
                    sizehint!(material_faces, target_N)
                    while length(material_faces) < target_N
                        push!(material_faces, face)
                    end
                end
            else
                #TODO
            end
        end
    end
    
    # drop material ids if no materials were specified
    if material_counter == 0
        empty!(material_ids)
    else
        face = facetype(current_material)
        target_N = length(faces)
        sizehint!(material_faces, target_N)
        while length(material_faces) < target_N
            push!(material_faces, face)
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
        # With materials we can have merged position-uv-normal faces
        # but still end up in this branch because of the material index, so
        # we need to check if the uv/normals faces are set before remapping
        if !isempty(uv)
            if !isempty(f_uv_n_faces[counter])
                point_attributes[:uv] = uv[attrib_maps[counter]]
                counter += 1
            else
                point_attributes[:uv] = uv[attrib_maps[counter-1]]
            end
        end
        if !isempty(v_normals)
            if !isempty(f_uv_n_faces[counter])
                point_attributes[:normals] = v_normals[attrib_maps[counter]]
                counter += 1
            else
                point_attributes[:normals] = v_normals[attrib_maps[counter-1]]
            end
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


# Experimental stuff for loading .mtl files and working with multiple materials

"""
    MehsIO.split_mesh(mesh)

Experimental function for splitting a mesh based material indices.
Also remaps vertices to avoid passing all vertices with a submesh.
"""
function split_mesh(mesh)
    ps = coordinates(mesh)
    ns = normals(mesh)
    uvs = texturecoordinates(mesh)
    ids = mesh.material
    fs = faces(mesh)

    meshes = Dict{Int, Any}()
    target_ids = unique(ids)
    IndexType = eltype(eltype(fs))

    for target_id in target_ids
        _fs = eltype(fs)[]
        indexmap = Dict{UInt32, UInt32}()
        counter = MeshIO._typemin(IndexType)

        for f in fs
            if any(ids[f] .== target_id)
                f = map(f) do _i
                    i = GeometryBasics.value(_i)
                    if haskey(indexmap, i)
                        return indexmap[i]
                    else
                        indexmap[i] = counter
                        counter += 1
                        return counter-1
                    end
                end
                push!(_fs, f)
            end
        end

        indices = Vector{UInt32}(undef, counter-1)
        for (old, new) in indexmap
            indices[new] = old
        end

        meshes[target_id] = GeometryBasics.Mesh(
            meta(ps[indices], normals = ns[indices], uv = uvs[indices]), _fs
        )
    end

    return meshes
end

"""
    load_materials(obj_filename)

Experimental functionality for loading am mtl file attached to an obj file. Also
recovers loads the object_group_id -> (object, group) name mapping from the obj
file.
"""
function load_materials(filename::String)
    endswith(filename, ".obj") || error("File should be a .obj file!")

    data = Dict{String, Any}()
    mat2id = Dict{String, Int}()
    current_material = 0
    material_counter = 0

    path = joinpath(splitpath(filename)[1:end-1])
    file = open(filename, "r")

    for full_line in eachline(file)
        # read a line, remove newline and leading/trailing whitespaces
        line = strip(chomp(full_line))
        !isascii(line) && error("non valid ascii in obj")
  
        if !startswith(line, "#") && !isempty(line) && !all(iscntrl, line) #ignore comments
            lines = split(line)
            command = popfirst!(lines) #first is the command, rest the data
  
            if "usemtl" == command
                name = join(lines, ' ')
                current_material = get!(mat2id, name) do 
                    material_counter += 1
                end
              
            elseif "mtllib" == command
                filename = join(lines, ' ')
                materials = _load_mtl(joinpath(path, filename))
                for (k, v) in materials
                    data[k] = v
                end
            else
                # Skipped
            end
        end
    end

    close(file)

    data["id to material"] = Dict([v => k for (k, v) in mat2id])

    return data
end

function _load_mtl(filename::String)
    endswith(filename, ".mtl") || error("File should be a .mtl file!")
    materials = Dict{String, Dict{String, Any}}()
    material = Dict{String, Any}()

    name_lookup = Dict(
        "Ka" => "ambient", "Kd" => "diffuse", "Ks" => "specular",
        "Ns" => "shininess", "d" => "alpha", "Tr" => "transmission", # 1 - alpha
        "Ni" => "refractive index", "illum" => "illumination model",
        # PBR
        "Pr" => "roughness", "Pm" => "metallic", "Ps" => "sheen", 
        "Pc" => "clearcoat thickness", "Pcr" => "clearcoat roughness", 
        "Ke" => "emissive", "aniso" => "anisotropy", 
        "anisor" => "anisotropy rotation", 
        # texture maps
        "map_Ka" => "ambient map",  "map_Kd" => "diffuse map", 
        "map_Ks" => "specular map", "map_Ns" => "shininess map", 
        "map_d" => "alpha map", "map_Tr" => "transmission map",
        "map_bump" => "bump map", "bump" => "bump map",
        "disp" => "displacement map", "decal" => "decal map",
        "refl" => "reflection map", "norm" => "normal map",
        "map_Pr" => "roughness map", "map_Pm" => "metallic map", 
        "map_Ps" => "sheen map", "map_Ke" => "emissive map",
        "map_RMA" => "roughness metalness occlusion map",
        "map_ORM" => "occlusion roughness metalness map"
    )

    path = joinpath(splitpath(filename)[1:end-1])
    file = open(filename, "r")

    try
        for full_line in eachline(file)
            # read a line, remove newline and leading/trailing whitespaces
            line = strip(chomp(full_line))
            !isascii(line) && error("non valid ascii in obj")

            if !startswith(line, "#") && !isempty(line) && !all(iscntrl, line) #ignore comments
                lines = split(line)
                command = popfirst!(lines) #first is the command, rest the data

                if command == "newmtl"
                    name = join(lines, ' ')
                    materials[name] = material = Dict{String, Any}()

                elseif command == "Ka" || command == "Kd" || command == "Ks"
                    material[name_lookup[command]] = Vec3f(parse.(Float32, lines)...)

                elseif command == "Ns" || command == "Ni" || command == "Pr" ||
                        command == "Pm" || command == "Ps" || command == "Pc" ||
                        command == "Pcr" || command == "Ke" || command == "aniso" ||
                        command == "anisor"

                    material[name_lookup[command]] = parse.(Float32, lines[1])

                elseif command == "d"
                    haskey(material, "alpha") && error("Material alpha doubly defined.")
                    material[name_lookup[command]] = parse.(Float32, lines[1])

                elseif command == "Tr"
                    haskey(material, "alpha") && error("Material alpha doubly defined.")
                    material[name_lookup["d"]] = 1f0 - parse.(Float32, lines[1])

                # elseif Tf # transmission filter

                elseif command == "illum"
                    # See https://en.wikipedia.org/wiki/Wavefront_.obj_file#Basic_materials
                    material[name_lookup[command]] = parse.(Int, lines[1])

                elseif startswith(command, "map") || command == "bump" || command == "norm" ||
                        command == "refl" || command == "disp" || command == "decal"

                    # TODO: treat all the texture options
                    material[get(name_lookup, command, command)] = parse_texture_info(path, lines)

                else
                    material[command] = lines
                end
            end
        end

    finally
        close(file)
    end

    return materials
end

function parse_texture_info(parent_path::String, lines::Vector{SubString{String}})
    idx = 1
    output = Dict{String, Any}()
    name_lookup = Dict(
        "o" => "origin offset", "s" => "scale", "t" => "turbulence",
        "blendu" => "blend horizontal", "blendv" => "blend vertical",
        "boost" => "mipmap sharpness", "bm" => "bump multiplier"
    )

    function parse_bool(x, default)
        if lowercase(x) == "off" || x == "0"
            return false
        elseif lowercase(x) == "on" || x == "1"
            return true
        else
            error("Failed to parse $x as Bool.")
        end
    end

    while idx < length(lines) + 1
        if startswith(lines[idx], '-')
            command = lines[idx][2:end]

            if command == "blendu" || command == "blendv"
                name = name_lookup[command]
                output[name] = parse_bool(lines[idx+1], true)
                idx += 2

            elseif command == "boost" || command == "bm"
                output[name_lookup[command]] = parse(Float32, lines[idx+1])
                idx += 2
                
            elseif command == "mm"
                output["brightness"] = parse(Float32, lines[idx+1])
                output["contrast"]   = parse(Float32, lines[idx+2])
                idx += 3

            elseif command == "o" || command == "s" || command == "t"
                default = command == "s" ? 1f0 : 0f0
                x = parse(Float32, lines[idx+1])
                y = length(lines) >= idx+2 ? tryparse(Float32, lines[idx+2]) : nothing
                z = length(lines) >= idx+3 ? tryparse(Float32, lines[idx+3]) : nothing
                output[name_lookup[command]] = Vec3f(
                    x, something(y, default), something(z, default)
                )
                idx += 2 + (y !== nothing) + (z !== nothing)

            elseif command == "texres" # is this only one value?
                output["resolution"] = parse(Float32, lines[idx+1])
                idx += 2

            elseif command == "clamp"
                output["clamp"] = parse_bool(lines[idx+1])
                idx += 2

            elseif command == "imfchan"
                output["channel"] = lines[idx+1]
                idx += 2

            elseif command == "type"
                output[command] = lines[idx+1]
                idx += 2

            # TODO: PBR tags

            else
                @warn "Failed to parse -$command"
                idx += 1
            end
        else
            filepath = joinpath(parent_path, lines[idx])
            i = idx+1
            while i <= length(lines) && !startswith(lines[i], '-')
                filepath = filepath * ' ' * lines[i]
                i += 1
            end
            filepath = replace(filepath, "\\\\" => "/")
            filepath = replace(filepath, "\\" => "/")
            if isfile(filepath) || endswith(lowercase(filepath), r"\.(png|jpg|jpeg|tiff|bmp)")
                output["filename"] = filepath
                idx = i
            else
                idx += 1
            end
        end
    end

    return output
end