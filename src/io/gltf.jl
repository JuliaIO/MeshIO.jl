##############################
#
# glTF/GLB Files
#
##############################

using JSON3

# GLB magic number: "glTF" in little-endian
const GLB_MAGIC = 0x46546C67
const GLB_JSON_CHUNK = 0x4E4F534A  # "JSON" in ASCII
const GLB_BIN_CHUNK = 0x004E4942   # "BIN\0" in ASCII

"""
    load(fn::File{format"GLB"}; facetype=GLTriangleFace, pointtype=Point3f, normaltype=Vec3f, uvtype=Vec2f)

Load a GLB (binary glTF) file and return a MetaMesh with materials and submesh views.
"""
function load(fn::File{format"GLB"}; facetype=GLTriangleFace, pointtype=Point3f,
              normaltype=Vec3f, uvtype=Vec2f)
    open(fn) do io
        s = stream(io)
        # Read GLB header (12 bytes)
        magic = read(s, UInt32)
        if magic != GLB_MAGIC
            error("Not a valid GLB file: magic number mismatch")
        end

        version = read(s, UInt32)
        file_length = read(s, UInt32)

        # Read JSON chunk
        json_length = read(s, UInt32)
        json_type = read(s, UInt32)
        if json_type != GLB_JSON_CHUNK
            error("Expected JSON chunk, got type: $json_type")
        end

        json_data = String(read(s, json_length))
        gltf = JSON3.read(json_data)

        # Read binary chunk (if present)
        binary_data = UInt8[]
        if !eof(s)
            bin_length = read(s, UInt32)
            bin_type = read(s, UInt32)
            if bin_type != GLB_BIN_CHUNK
                error("Expected BIN chunk, got type: $bin_type")
            end
            binary_data = read(s, bin_length)
        end

        return _extract_gltf_mesh(gltf, binary_data, nothing; facetype, pointtype, normaltype, uvtype)
    end
end

"""
    load(fn::File{format"GLTF"}; facetype=GLTriangleFace, pointtype=Point3f, normaltype=Vec3f, uvtype=Vec2f)

Load a glTF (JSON) file and return a MetaMesh with materials and submesh views.
External .bin files are loaded relative to the glTF file location.
"""
function load(fn::File{format"GLTF"}; facetype=GLTriangleFace, pointtype=Point3f,
              normaltype=Vec3f, uvtype=Vec2f)
    open(fn) do io
        s = stream(io)
        json_data = read(s, String)
        gltf = JSON3.read(json_data)

        # Get the directory containing the glTF file for resolving relative URIs
        base_path = dirname(FileIO.filename(fn))

        return _extract_gltf_mesh(gltf, UInt8[], base_path; facetype, pointtype, normaltype, uvtype)
    end
end

"""
    _get_node_transform(node) -> Mat4f

Get the 4x4 transformation matrix for a glTF node.
"""
function _get_node_transform(node)
    if haskey(node, :matrix)
        m = node.matrix
        return Mat4f(
            m[1], m[2], m[3], m[4],
            m[5], m[6], m[7], m[8],
            m[9], m[10], m[11], m[12],
            m[13], m[14], m[15], m[16]
        )
    else
        T = haskey(node, :translation) ? Vec3f(node.translation...) : Vec3f(0, 0, 0)
        R = haskey(node, :rotation) ? Vec4f(node.rotation...) : Vec4f(0, 0, 0, 1)
        S = haskey(node, :scale) ? Vec3f(node.scale...) : Vec3f(1, 1, 1)

        # Quaternion to rotation matrix
        qx, qy, qz, qw = R
        rot = Mat3f(
            1 - 2*(qy^2 + qz^2), 2*(qx*qy + qz*qw), 2*(qx*qz - qy*qw),
            2*(qx*qy - qz*qw), 1 - 2*(qx^2 + qz^2), 2*(qy*qz + qx*qw),
            2*(qx*qz + qy*qw), 2*(qy*qz - qx*qw), 1 - 2*(qx^2 + qy^2)
        )

        return Mat4f(
            rot[1,1]*S[1], rot[2,1]*S[1], rot[3,1]*S[1], 0,
            rot[1,2]*S[2], rot[2,2]*S[2], rot[3,2]*S[2], 0,
            rot[1,3]*S[3], rot[2,3]*S[3], rot[3,3]*S[3], 0,
            T[1], T[2], T[3], 1
        )
    end
end

"""
    _transform_point(p, mat::Mat4f, ::Type{PT}) where PT

Apply a 4x4 transformation matrix to a 3D point.
"""
function _transform_point(p, mat::Mat4f, ::Type{PT}) where PT
    v = Vec4f(p[1], p[2], p[3], 1.0f0)
    result = mat * v
    return PT(result[1], result[2], result[3])
end

"""
    _transform_normal(n, mat::Mat4f, ::Type{NT}) where NT

Apply a 4x4 transformation matrix to a normal vector (using inverse transpose of upper 3x3).
"""
function _transform_normal(n, mat::Mat4f, ::Type{NT}) where NT
    m3 = Mat3f(mat[1:3, 1:3])
    normal_mat = transpose(inv(m3))
    v = Vec3f(n[1], n[2], n[3])
    transformed = normal_mat * v
    len = sqrt(transformed[1]^2 + transformed[2]^2 + transformed[3]^2)
    result = len > 0 ? transformed / len : transformed
    return NT(result[1], result[2], result[3])
end

"""
    _load_buffer_data(gltf, embedded_binary::Vector{UInt8}, base_path::Union{String,Nothing}, buffer_idx::Int) -> Vector{UInt8}

Load buffer data either from embedded binary or external file.
"""
function _load_buffer_data(gltf, embedded_binary::Vector{UInt8}, base_path::Union{String,Nothing}, buffer_idx::Int)
    buffer = gltf.buffers[buffer_idx + 1]

    if haskey(buffer, :uri)
        uri = buffer.uri
        # Check for data URI
        if startswith(uri, "data:")
            # Parse data URI: data:[<mediatype>][;base64],<data>
            comma_idx = findfirst(',', uri)
            if comma_idx !== nothing
                data_part = uri[comma_idx+1:end]
                if occursin(";base64", uri[1:comma_idx])
                    return Base64.base64decode(data_part)
                else
                    return Vector{UInt8}(data_part)
                end
            end
        elseif !isnothing(base_path)
            # External file
            filepath = joinpath(base_path, uri)
            return read(filepath)
        end
    end

    # Fallback to embedded binary
    return embedded_binary
end

"""
    _get_accessor_data(gltf, binary_data::Vector{UInt8}, base_path, accessor_idx::Int)

Get data from a glTF accessor.
"""
function _get_accessor_data(gltf, binary_data::Vector{UInt8}, base_path, accessor_idx::Int)
    accessor = gltf.accessors[accessor_idx + 1]
    buffer_view = gltf.bufferViews[accessor.bufferView + 1]

    # Get the correct buffer data
    buffer_idx = get(buffer_view, :buffer, 0)
    buffer_data = if buffer_idx == 0 && !isempty(binary_data)
        binary_data
    else
        _load_buffer_data(gltf, binary_data, base_path, buffer_idx)
    end

    component_type = accessor.componentType
    type_info = _get_component_type_info(component_type)
    count = accessor.count
    num_components = _get_type_components(get(accessor, :type, "SCALAR"))

    offset = get(buffer_view, :byteOffset, 0) + get(accessor, :byteOffset, 0)
    stride = get(buffer_view, :byteStride, 0)

    if stride == 0
        stride = type_info.size * num_components
    end

    data = []
    for i in 0:(count-1)
        element_offset = offset + i * stride + 1
        element = _read_typed_data(buffer_data, element_offset, type_info.type, num_components)
        push!(data, element)
    end

    return data
end

"""
    _get_component_type_info(component_type::Int)

Get Julia type and size for glTF component type.
"""
function _get_component_type_info(component_type::Int)
    types = Dict(
        5120 => (type=Int8, size=1),
        5121 => (type=UInt8, size=1),
        5122 => (type=Int16, size=2),
        5123 => (type=UInt16, size=2),
        5125 => (type=UInt32, size=4),
        5126 => (type=Float32, size=4),
    )
    return types[component_type]
end

"""
    _get_type_components(type_str::String) -> Int

Get number of components for glTF type.
"""
function _get_type_components(type_str::String)
    components = Dict(
        "SCALAR" => 1,
        "VEC2" => 2,
        "VEC3" => 3,
        "VEC4" => 4,
        "MAT2" => 4,
        "MAT3" => 9,
        "MAT4" => 16,
    )
    return components[type_str]
end

"""
    _read_typed_data(data::Vector{UInt8}, offset::Int, T::Type, count::Int)

Read typed data from byte array.
"""
function _read_typed_data(data::Vector{UInt8}, offset::Int, T::Type, count::Int)
    if count == 1
        return reinterpret(T, data[offset:offset+sizeof(T)-1])[1]
    else
        values = [reinterpret(T, data[offset+(i-1)*sizeof(T):offset+i*sizeof(T)-1])[1] for i in 1:count]
        return Tuple(values)
    end
end

"""
    _extract_gltf_textures(gltf, binary_data::Vector{UInt8}, base_path) -> Dict{String, Any}

Extract all textures from glTF data and return a dictionary.
"""
function _extract_gltf_textures(gltf, binary_data::Vector{UInt8}, base_path)
    textures = Dict{String, Any}()

    if !haskey(gltf, :textures) || !haskey(gltf, :images)
        return textures
    end

    for (tex_idx, texture) in enumerate(gltf.textures)
        texture_name = "texture_$(tex_idx - 1)"
        image_idx = texture.source + 1

        if image_idx > length(gltf.images)
            continue
        end

        image_info = gltf.images[image_idx]

        if haskey(image_info, :bufferView)
            buffer_view_idx = image_info.bufferView + 1
            buffer_view = gltf.bufferViews[buffer_view_idx]

            buffer_idx = get(buffer_view, :buffer, 0)
            buffer_data = if buffer_idx == 0 && !isempty(binary_data)
                binary_data
            else
                _load_buffer_data(gltf, binary_data, base_path, buffer_idx)
            end

            offset = get(buffer_view, :byteOffset, 0) + 1
            length_bytes = buffer_view.byteLength
            image_bytes = buffer_data[offset:offset + length_bytes - 1]

            try
                io = IOBuffer(image_bytes)
                mime_type = get(image_info, :mimeType, "image/png")
                if mime_type == "image/png"
                    img = FileIO.load(FileIO.Stream{FileIO.format"PNG"}(io))
                elseif mime_type == "image/jpeg"
                    img = FileIO.load(FileIO.Stream{FileIO.format"JPEG"}(io))
                else
                    img = FileIO.load(io)
                end
                textures[texture_name] = img
            catch e
                @warn "Failed to load texture $texture_name: $e"
            end
        elseif haskey(image_info, :uri)
            uri = image_info.uri
            if startswith(uri, "data:")
                # Data URI
                comma_idx = findfirst(',', uri)
                if comma_idx !== nothing && occursin(";base64", uri[1:comma_idx])
                    data_part = uri[comma_idx+1:end]
                    image_bytes = Base64.base64decode(data_part)
                    try
                        io = IOBuffer(image_bytes)
                        img = FileIO.load(io)
                        textures[texture_name] = img
                    catch e
                        @warn "Failed to load texture $texture_name from data URI: $e"
                    end
                end
            elseif !isnothing(base_path)
                # External file
                filepath = joinpath(base_path, uri)
                if isfile(filepath)
                    try
                        textures[texture_name] = FileIO.load(filepath)
                    catch e
                        @warn "Failed to load texture $texture_name from $filepath: $e"
                    end
                end
            end
        end
    end

    return textures
end

"""
    _get_texture_transform(texture_info) -> NamedTuple

Extract KHR_texture_transform parameters from a texture info object.
Returns (offset, scale, rotation) with defaults if not present.
"""
function _get_texture_transform(texture_info)
    offset = Vec2f(0, 0)
    scale = Vec2f(1, 1)
    rotation = 0.0f0

    if haskey(texture_info, :extensions)
        exts = texture_info.extensions
        if haskey(exts, Symbol("KHR_texture_transform"))
            transform = exts[Symbol("KHR_texture_transform")]
            if haskey(transform, :offset)
                offset = Vec2f(transform.offset[1], transform.offset[2])
            end
            if haskey(transform, :scale)
                scale = Vec2f(transform.scale[1], transform.scale[2])
            end
            if haskey(transform, :rotation)
                rotation = Float32(transform.rotation)
            end
        end
    end

    return (offset=offset, scale=scale, rotation=rotation)
end

"""
    _apply_uv_transform(uv, transform) -> Vec2f

Apply KHR_texture_transform to a UV coordinate.
Formula: uv' = rotation_matrix * (uv * scale) + offset
UVs are normalized to [0,1] range using mod to handle texture wrapping.
"""
function _apply_uv_transform(uv, transform)
    # Apply scale
    scaled = Vec2f(uv[1] * transform.scale[1], uv[2] * transform.scale[2])

    # Apply rotation (around origin)
    if transform.rotation != 0
        c = cos(transform.rotation)
        s = sin(transform.rotation)
        rotated = Vec2f(c * scaled[1] + s * scaled[2], -s * scaled[1] + c * scaled[2])
    else
        rotated = scaled
    end

    # Apply offset
    result = Vec2f(rotated[1] + transform.offset[1], rotated[2] + transform.offset[2])

    # Normalize to [0,1] range to handle texture wrapping (equivalent to GL_REPEAT)
    return Vec2f(mod(result[1], 1.0f0), mod(result[2], 1.0f0))
end

"""
    _extract_gltf_materials(gltf, textures::Dict{String, Any}) -> Dict{String, Any}

Extract materials from glTF JSON structure and return a dictionary.
Also extracts UV transform info for KHR_texture_transform extension.
"""
function _extract_gltf_materials(gltf, textures::Dict{String, Any})
    materials = Dict{String, Any}()

    if !haskey(gltf, :materials)
        return materials
    end

    function get_texture_dict(tex_idx)
        tex_name = "texture_$(tex_idx)"
        if haskey(textures, tex_name)
            return Dict{String, Any}("image" => textures[tex_name])
        end
        return nothing
    end

    for (idx, mat) in enumerate(gltf.materials)
        mat_dict = Dict{String, Any}()
        material_name = get(mat, :name, "material_$(idx-1)")

        if haskey(mat, :pbrMetallicRoughness)
            pbr = mat.pbrMetallicRoughness

            if haskey(pbr, :baseColorFactor)
                color = pbr.baseColorFactor
                mat_dict["diffuse"] = Vec3f(color[1], color[2], color[3])
                mat_dict["alpha"] = Float32(color[4])
            end

            if haskey(pbr, :metallicFactor)
                mat_dict["metallic"] = Float32(pbr.metallicFactor)
            end

            if haskey(pbr, :roughnessFactor)
                mat_dict["roughness"] = Float32(pbr.roughnessFactor)
            end

            if haskey(pbr, :baseColorTexture)
                tex_dict = get_texture_dict(pbr.baseColorTexture.index)
                if !isnothing(tex_dict)
                    mat_dict["diffuse map"] = tex_dict
                end
                # Store UV transform for this material
                uv_transform = _get_texture_transform(pbr.baseColorTexture)
                if uv_transform.offset != Vec2f(0, 0) || uv_transform.scale != Vec2f(1, 1) || uv_transform.rotation != 0
                    mat_dict["uv_transform"] = uv_transform
                end
            end

            if haskey(pbr, :metallicRoughnessTexture)
                tex_dict = get_texture_dict(pbr.metallicRoughnessTexture.index)
                if !isnothing(tex_dict)
                    mat_dict["metallic roughness map"] = tex_dict
                end
            end
        end

        if haskey(mat, :normalTexture)
            tex_dict = get_texture_dict(mat.normalTexture.index)
            if !isnothing(tex_dict)
                mat_dict["normal map"] = tex_dict
            end
        end

        if haskey(mat, :occlusionTexture)
            tex_dict = get_texture_dict(mat.occlusionTexture.index)
            if !isnothing(tex_dict)
                mat_dict["occlusion map"] = tex_dict
            end
        end

        if haskey(mat, :emissiveFactor)
            emissive = mat.emissiveFactor
            mat_dict["emissive"] = Vec3f(emissive[1], emissive[2], emissive[3])
        end

        if haskey(mat, :emissiveTexture)
            tex_dict = get_texture_dict(mat.emissiveTexture.index)
            if !isnothing(tex_dict)
                mat_dict["emissive map"] = tex_dict
            end
        end

        if haskey(mat, :alphaMode)
            mat_dict["alpha mode"] = String(mat.alphaMode)
        end

        if haskey(mat, :alphaCutoff)
            mat_dict["alpha cutoff"] = Float32(mat.alphaCutoff)
        end

        if haskey(mat, :doubleSided)
            mat_dict["double sided"] = mat.doubleSided
        end

        materials[material_name] = mat_dict
    end

    return materials
end

"""
    _extract_gltf_mesh(gltf, binary_data::Vector{UInt8}, base_path; kwargs...) -> MetaMesh

Extract mesh data from glTF structure with node hierarchy transforms.
"""
function _extract_gltf_mesh(gltf, binary_data::Vector{UInt8}, base_path;
                            facetype=GLTriangleFace, pointtype=Point3f,
                            normaltype=Vec3f, uvtype=Vec2f)

    textures_dict = _extract_gltf_textures(gltf, binary_data, base_path)
    materials_dict = _extract_gltf_materials(gltf, textures_dict)

    if !haskey(gltf, :meshes)
        empty_mesh = GeometryBasics.Mesh(pointtype[], facetype[])
        return MetaMesh(empty_mesh)
    end

    all_positions = pointtype[]
    all_normals = normaltype[]
    all_uvs = uvtype[]
    all_faces = facetype[]

    views = UnitRange{Int}[]
    material_names = String[]

    has_normals = false
    has_uvs = false

    current_vertex_offset = Ref(0)
    current_face_offset = Ref(0)

    # Correction matrix to convert coordinate system if needed
    identity_mat = Mat4f(
        1, 0, 0, 0,
        0, 1, 0, 0,
        0, 0, 1, 0,
        0, 0, 0, 1
    )

    function process_node(node_idx::Int, parent_transform::Mat4f)
        node = gltf.nodes[node_idx + 1]

        local_transform = _get_node_transform(node)
        world_transform = parent_transform * local_transform

        if haskey(node, :mesh)
            mesh_idx = node.mesh
            mesh = gltf.meshes[mesh_idx + 1]

            for primitive in mesh.primitives
                positions = nothing
                if haskey(primitive.attributes, :POSITION)
                    positions = _get_accessor_data(gltf, binary_data, base_path, primitive.attributes.POSITION)
                end

                if isnothing(positions)
                    continue
                end

                normals = nothing
                if haskey(primitive.attributes, :NORMAL)
                    normals = _get_accessor_data(gltf, binary_data, base_path, primitive.attributes.NORMAL)
                    has_normals = true
                end

                uvs = nothing
                if haskey(primitive.attributes, :TEXCOORD_0)
                    uvs = _get_accessor_data(gltf, binary_data, base_path, primitive.attributes.TEXCOORD_0)
                    has_uvs = true
                end

                indices = nothing
                if haskey(primitive, :indices)
                    indices = _get_accessor_data(gltf, binary_data, base_path, primitive.indices)
                end

                for p in positions
                    push!(all_positions, _transform_point(p, world_transform, pointtype))
                end

                if !isnothing(normals)
                    for n in normals
                        push!(all_normals, _transform_normal(n, world_transform, normaltype))
                    end
                elseif has_normals
                    for _ in 1:length(positions)
                        push!(all_normals, normaltype(0, 0, 1))
                    end
                end

                # Get UV transform from material if KHR_texture_transform is used
                uv_transform = nothing
                if haskey(primitive, :material) && haskey(gltf, :materials)
                    material_idx = primitive.material
                    gltf_material = gltf.materials[material_idx + 1]
                    mat_name = get(gltf_material, :name, "material_$material_idx")
                    if haskey(materials_dict, String(mat_name)) && haskey(materials_dict[String(mat_name)], "uv_transform")
                        uv_transform = materials_dict[String(mat_name)]["uv_transform"]
                    end
                end

                # Apply UV coordinates
                # - Without KHR_texture_transform: flip V only (u, 1-v)
                # - With KHR_texture_transform: apply transform then swap+flip (1-v, 1-u)
                if !isnothing(uvs)
                    for uv in uvs
                        if !isnothing(uv_transform)
                            transformed_uv = _apply_uv_transform(uv, uv_transform)
                            push!(all_uvs, uvtype(1.0f0 - transformed_uv[2], 1.0f0 - transformed_uv[1]))
                        else
                            push!(all_uvs, uvtype(uv[1], 1.0f0 - uv[2]))
                        end
                    end
                elseif has_uvs
                    for _ in 1:length(positions)
                        push!(all_uvs, uvtype(0, 0))
                    end
                end

                num_faces = 0
                if !isnothing(indices)
                    for i in 0:(length(indices)÷3-1)
                        face = facetype(
                            indices[i*3+1] + current_vertex_offset[] + 1,
                            indices[i*3+2] + current_vertex_offset[] + 1,
                            indices[i*3+3] + current_vertex_offset[] + 1
                        )
                        push!(all_faces, face)
                        num_faces += 1
                    end
                else
                    for i in 1:3:length(positions)-2
                        face = facetype(
                            i + current_vertex_offset[],
                            i + 1 + current_vertex_offset[],
                            i + 2 + current_vertex_offset[]
                        )
                        push!(all_faces, face)
                        num_faces += 1
                    end
                end

                if num_faces > 0
                    view_start = current_face_offset[] + 1
                    view_end = current_face_offset[] + num_faces
                    push!(views, view_start:view_end)

                    material_idx = get(primitive, :material, nothing)
                    if !isnothing(material_idx)
                        gltf_material = gltf.materials[material_idx + 1]
                        mat_name = get(gltf_material, :name, "material_$material_idx")
                        push!(material_names, String(mat_name))
                    else
                        push!(material_names, "default")
                    end

                    current_face_offset[] += num_faces
                end

                current_vertex_offset[] += length(positions)
            end
        end

        if haskey(node, :children)
            for child_idx in node.children
                process_node(child_idx, world_transform)
            end
        end
    end

    # Get scene root nodes and traverse
    if haskey(gltf, :scenes) && haskey(gltf, :scene)
        scene = gltf.scenes[gltf.scene + 1]
        if haskey(scene, :nodes)
            for root_node_idx in scene.nodes
                process_node(root_node_idx, identity_mat)
            end
        end
    elseif haskey(gltf, :nodes)
        # Fallback: process all root-level nodes
        all_children = Set{Int}()
        for node in gltf.nodes
            if haskey(node, :children)
                for c in node.children
                    push!(all_children, c)
                end
            end
        end
        for i in 0:(length(gltf.nodes)-1)
            if !(i in all_children)
                process_node(i, identity_mat)
            end
        end
    end

    # Create mesh with appropriate attributes
    kwargs_mesh = Pair{Symbol, Any}[]
    if has_normals && length(all_normals) == length(all_positions)
        push!(kwargs_mesh, :normal => all_normals)
    end
    if has_uvs && length(all_uvs) == length(all_positions)
        push!(kwargs_mesh, :uv => all_uvs)
    end

    mesh = GeometryBasics.Mesh(all_positions, all_faces; views=views, kwargs_mesh...)

    # Create metadata
    metadata = Dict{Symbol, Any}()
    if !isempty(materials_dict)
        metadata[:materials] = materials_dict
    end
    if !isempty(textures_dict)
        metadata[:textures] = textures_dict
    end
    if !isempty(material_names)
        metadata[:material_names] = material_names
    end

    return MetaMesh(mesh, metadata)
end

# Register formats with FileIO
function __init__()
    # GLB format: binary glTF with magic number
    FileIO.add_format(
        format"GLB",
        UInt8[0x67, 0x6C, 0x54, 0x46],  # "glTF" magic bytes
        ".glb",
        [:MeshIO => Base.UUID("7269a6da-0436-5bbc-96c2-40638cbb6118")]
    )

    # GLTF format: JSON-based glTF (no reliable magic, use extension)
    FileIO.add_format(
        format"GLTF",
        (),
        [".gltf"],
        [:MeshIO => Base.UUID("7269a6da-0436-5bbc-96c2-40638cbb6118")]
    )
end
