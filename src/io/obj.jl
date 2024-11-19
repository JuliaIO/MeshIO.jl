##############################
#
# obj-Files
#
##############################

function load(fn::File{format"OBJ"}; facetype=GLTriangleFace,
        pointtype=Point3f, normaltype=Vec3f, uvtype=Any)

    function parse_bool(x)
        if lowercase(x) == "off" || x == "0"
            return false
        elseif lowercase(x) == "on" || x == "1"
            return true
        else
            error("Failed to parse $x as Bool.")
        end
    end

    points, v_normals, uv, faces = pointtype[], normaltype[], uvtype[], facetype[]
    f_uv_n_faces = (faces, facetype[], facetype[])

    # name => (first_face, value)
    group_meta = Dict{Symbol, Dict{Int, T} where T}()
    mtllibs = String[]

    open(fn) do io
        skipmagic(io)

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
                        append!(f_uv_n_faces[1], triangulated_faces(facetype, getindex.(fs, 1)))
                        append!(f_uv_n_faces[3], triangulated_faces(facetype, getindex.(fs, 2)))
                    elseif any(x-> occursin("/", x), lines)
                        fs = process_face_uv_or_normal(lines)
                        for i = 1:length(first(fs))
                            append!(f_uv_n_faces[i], triangulated_faces(facetype, getindex.(fs, i)))
                        end
                    else
                        append!(faces, triangulated_faces(facetype, lines))
                        continue
                    end

                elseif "s" == command  # Blender sets this just before faces
                    shadings = get!(() -> Dict{Int, Bool}(), group_meta, :shading)
                    shadings[length(faces)+1] = parse_bool(lines[1])

                elseif "o" == command  # Blender sets this before vertices
                    objects = get!(() -> Dict{Int, String}(), group_meta, :object)
                    objects[length(faces)+1] = join(lines, ' ')

                elseif "g" == command
                    groups = get!(() -> Dict{Int, String}(), group_meta, :groups)
                    groups[length(faces)+1] = join(lines, ' ')

                elseif "mtllib" == command
                    push!(mtllibs, join(lines, ' '))

                elseif "usemtl" == command # Blender sets this just before faces
                    materials = get!(() -> Dict{Int, String}(), group_meta, :material_names)
                    materials[length(faces)+1] = join(lines, ' ')
                else
                    # TODO:
                    # parameter space vertices
                    # line elements?
                end
            end
        end

    end

    # Generate base mesh
    if !isempty(f_uv_n_faces[2]) && (f_uv_n_faces[2] != faces)
        uv = FaceView(uv, f_uv_n_faces[2])
    end

    if !isempty(f_uv_n_faces[3]) && (f_uv_n_faces[3] != faces)
        v_normals = FaceView(v_normals, f_uv_n_faces[3])
    end

    mesh = GeometryBasics.mesh(
        points, faces, facetype = facetype;
        uv = isempty(uv) ? nothing : uv,
        normal = isempty(v_normals) ? nothing : v_normals
    )

    if !isempty(group_meta)

        # Find all the starting indices used across objects, groups, shadings, materials
        starts_set = Set{Int}()
        for meta in values(group_meta)
            union!(starts_set, keys(meta))
        end
        starts_vec = sort!(collect(starts_set))

        # generate views
        resize!(mesh.views, length(starts_vec))
        for i in 1:length(starts_vec)-1
            mesh.views[i] = starts_vec[i] : starts_vec[i+1]-1
        end
        mesh.views[end] = starts_vec[end] : length(faces)

        # generate metadata dict matching the views with nothing as the gap filler
        N = length(starts_vec)
        metadata = Dict{Symbol, Any}()
        for (name, dict) in group_meta
            if length(dict) == N
                metadata[name] = getindex.(Ref(dict), starts_vec)
            else
                metadata[name] = get.(Ref(dict), starts_vec, nothing)
            end
        end

        if isempty(mtllibs) && !haskey(group_meta, :material_names)
            return MetaMesh(mesh, metadata)
        end

        # Load material files
        materials = Dict{String, Dict{String, Any}}()
        path = joinpath(splitpath(FileIO.filename(fn))[1:end-1]...)

        # Fallback - if no mtl file exists abort and return just the mesh
        if !any(filename -> isfile(joinpath(path, filename)), mtllibs)
            @error "obj file contains references to .mtl files, but none could be found. Expected: $mtllibs in $path."
            return mesh
        end

        for filename in mtllibs
            try
                _load_mtl!(materials, joinpath(path, filename))
            catch e
                @error "While parsing $(joinpath(path, filename)):" exception = e
            end
        end
        metadata[:materials] = materials

        return MetaMesh(mesh, metadata)

    else
        # TODO: Should we have different output types here?
        return mesh

        # views = UnitRange{Int}[]
        # metadata = Dict{Symbol, Any}()
    end

    return MetaMesh(mesh, metadata)
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


function _load_mtl!(materials::Dict{String, Dict{String, Any}}, filename::String)
    endswith(filename, ".mtl") || error("Material Template Library $filename must be a .mtl file.")


    name_lookup = Dict(
        "Ka" => "ambient", "Kd" => "diffuse", "Ks" => "specular",
        "Ns" => "shininess", "d" => "alpha", "Tr" => "transmission", # 1 - alpha
        "Ni" => "refractive index", "illum" => "illumination model",
        # PBR
        "Pr" => "roughness", "Pm" => "metallic", "Ps" => "sheen",
        "Pc" => "clearcoat thickness", "Pcr" => "clearcoat roughness",
        "Ke" => "emissive", "aniso" => "anisotropy",
        "anisor" => "anisotropy rotation",
        "Tf" => "transmission filter",
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
        "map_ORM" => "occlusion roughness metalness map",
    )

    path = joinpath(splitpath(filename)[1:end-1]...)
    open(filename, "r") do file

        # Just so the variable is defined
        material = Dict{String, Any}()

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
                        command == "anisor" || command == "Tf"

                    material[name_lookup[command]] = parse.(Float32, lines[1])

                elseif command == "d"
                    alpha = parse.(Float32, lines[1])
                    if haskey(material, "alpha") && !(material["alpha"] ≈ alpha)
                        @error("Material alpha doubly defined. Overwriting $(material["alpha"]) with $alpha.")
                    end
                    material[name_lookup[command]] = alpha

                elseif command == "Tr"
                    alpha = 1f0 - parse.(Float32, lines[1])
                    if haskey(material, "alpha") && !(material["alpha"] ≈ alpha)
                        @error("Material alpha doubly defined. Overwriting $(material["alpha"]) with $alpha")
                    end
                    material[name_lookup["d"]] = alpha

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

    end

    return materials
end

# TODO: Consider generating a ShaderAbstractions Sampler?
function parse_texture_info(parent_path::String, lines::Vector{SubString{String}})
    idx = 1
    output = Dict{String, Any}()
    name_lookup = Dict(
        "o" => "offset", "s" => "scale", "t" => "turbulence",
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
