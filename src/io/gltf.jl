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
    load(fn::File{format"GLB"}; facetype=GLTriangleFace, pointtype=Point3f, normaltype=Vec3f, uvtype=Vec2f, up=Vec3f(0, 0, 1))

Load a GLB (binary glTF) file and return a MetaMesh with materials and submesh views.
`up` specifies the target up-axis: `Vec3f(0,0,1)` (default) rotates glTF Y-up to Z-up,
`Vec3f(0,1,0)` keeps native glTF Y-up.
"""
function load(fn::File{format"GLB"}; facetype=GLTriangleFace, pointtype=Point3f,
              normaltype=Vec3f, uvtype=Vec2f, up=Vec3f(0, 0, 1))
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

        return extract_gltf_mesh(gltf, binary_data, nothing; facetype, pointtype, normaltype, uvtype, up)
    end
end

"""
    load(fn::File{format"GLTF"}; facetype=GLTriangleFace, pointtype=Point3f, normaltype=Vec3f, uvtype=Vec2f, up=Vec3f(0, 0, 1))

Load a glTF (JSON) file and return a MetaMesh with materials and submesh views.
External .bin files are loaded relative to the glTF file location.
`up` specifies the target up-axis: `Vec3f(0,0,1)` (default) rotates glTF Y-up to Z-up,
`Vec3f(0,1,0)` keeps native glTF Y-up.
"""
function load(fn::File{format"GLTF"}; facetype=GLTriangleFace, pointtype=Point3f,
              normaltype=Vec3f, uvtype=Vec2f, up=Vec3f(0, 0, 1))
    open(fn) do io
        s = stream(io)
        json_data = read(s, String)
        gltf = JSON3.read(json_data)

        # Get the directory containing the glTF file for resolving relative URIs
        base_path = dirname(FileIO.filename(fn))

        return extract_gltf_mesh(gltf, UInt8[], base_path; facetype, pointtype, normaltype, uvtype, up)
    end
end

"""
    gltf_node_transform(node) -> Mat4f

Get the 4x4 transformation matrix for a glTF node.
"""
function gltf_node_transform(node)
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
    gltf_transform_point(p, mat::Mat4f, ::Type{PT}) where PT

Apply a 4x4 transformation matrix to a 3D point.
"""
function gltf_transform_point(p, mat::Mat4f, ::Type{PT}) where PT
    v = Vec4f(p[1], p[2], p[3], 1.0f0)
    result = mat * v
    return PT(result[1], result[2], result[3])
end

"""
    gltf_transform_normal(n, mat::Mat4f, ::Type{NT}) where NT

Apply a 4x4 transformation matrix to a normal vector (using inverse transpose of upper 3x3).
"""
function gltf_transform_normal(n, mat::Mat4f, ::Type{NT}) where NT
    m3 = Mat3f(mat[1:3, 1:3])
    normal_mat = transpose(inv(m3))
    v = Vec3f(n[1], n[2], n[3])
    transformed = normal_mat * v
    len = sqrt(transformed[1]^2 + transformed[2]^2 + transformed[3]^2)
    result = len > 0 ? transformed / len : transformed
    return NT(result[1], result[2], result[3])
end

"`attribute` filled with `default` up to `n` vertices, for primitives that lack it."
function pad!(attribute::Vector, n::Integer, default)
    length(attribute) < n && append!(attribute, Iterators.repeated(default, n - length(attribute)))
    return attribute
end

"A vertex colour as `COLOR_0`'s linear RGBA; RGB gets alpha 1."
gltf_rgba(c::GeometryBasics.VecTypes{4}) = Vec4f(c)
gltf_rgba(c::GeometryBasics.VecTypes{3}) = Vec4f(c..., 1)
gltf_rgba(c::Union{AbstractRGB, TransparentRGB}) = Vec4f(red(c), green(c), blue(c), alpha(c))

"The triangles of a primitive whose vertices start after `offset` others."
gltf_triangles(::Type{F}, indices::AbstractVector{<:Integer}, offset::Int) where {F} =
    F[F(indices[i] + offset + 1, indices[i + 1] + offset + 1, indices[i + 2] + offset + 1)
      for i in 1:3:length(indices) - 2]

"""
    gltf_load_buffer_data(gltf, embedded_binary::Vector{UInt8}, base_path::Union{String,Nothing}, buffer_idx::Int) -> Vector{UInt8}

Load buffer data either from embedded binary or external file.
"""
function gltf_load_buffer_data(gltf, embedded_binary::Vector{UInt8}, base_path::Union{String,Nothing}, buffer_idx::Int)
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
                    return base64decode(data_part)
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
    gltf_accessor_data(gltf, binary_data::Vector{UInt8}, base_path, accessor_idx::Int)

Get data from a glTF accessor.
"""
function gltf_accessor_data(gltf, binary_data::Vector{UInt8}, base_path, accessor_idx::Int)
    accessor = gltf.accessors[accessor_idx + 1]
    buffer_view = gltf.bufferViews[accessor.bufferView + 1]

    # Get the correct buffer data
    buffer_idx = get(buffer_view, :buffer, 0)
    buffer_data = if buffer_idx == 0 && !isempty(binary_data)
        binary_data
    else
        gltf_load_buffer_data(gltf, binary_data, base_path, buffer_idx)
    end

    component_type = accessor.componentType
    type_info = gltf_component_type_info(component_type)
    count = accessor.count
    num_components = gltf_type_components(get(accessor, :type, "SCALAR"))

    offset = get(buffer_view, :byteOffset, 0) + get(accessor, :byteOffset, 0)
    stride = get(buffer_view, :byteStride, 0)

    if stride == 0
        stride = type_info.size * num_components
    end

    ET = num_components == 1 ? type_info.type : NTuple{num_components, type_info.type}
    data = gltf_read_elements(ET, buffer_data, offset, stride, count)
    # `normalized` integers stand for reals on [0, 1] or [-1, 1] (quantized weights, colours).
    return get(accessor, :normalized, false) ? map(gltf_denormalize, data) : data
end

"`count` elements of type `T`, `stride` bytes apart from `offset` (0-based)."
gltf_read_elements(::Type{T}, bytes::Vector{UInt8}, offset::Int, stride::Int, count::Int) where {T} =
    T[only(reinterpret(T, view(bytes, offset + i * stride .+ (1:sizeof(T))))) for i in 0:count-1]

"A `normalized` component as glTF decodes it; -1 has two signed encodings, both kept at -1."
gltf_denormalize(v::Tuple) = map(gltf_denormalize, v)
gltf_denormalize(v::Unsigned) = Float32(v) / typemax(v)
gltf_denormalize(v::Signed) = max(Float32(v) / typemax(v), -1f0)

"""
    gltf_component_type_info(component_type::Int)

Get Julia type and size for glTF component type.
"""
function gltf_component_type_info(component_type::Int)
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
    gltf_type_components(type_str::String) -> Int

Get number of components for glTF type.
"""
function gltf_type_components(type_str::String)
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
    extract_gltf_textures(gltf, binary_data::Vector{UInt8}, base_path) -> Dict{String, Any}

Extract all textures from glTF data and return a dictionary.
"""
function extract_gltf_textures(gltf, binary_data::Vector{UInt8}, base_path)
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
                gltf_load_buffer_data(gltf, binary_data, base_path, buffer_idx)
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
                    image_bytes = base64decode(data_part)
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
    gltf_texture_transform(texture_info) -> NamedTuple

Extract KHR_texture_transform parameters from a texture info object.
Returns (offset, scale, rotation) with defaults if not present.
"""
function gltf_texture_transform(texture_info)
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
    apply_gltf_uv_transform(uv, transform) -> Vec2f

Apply KHR_texture_transform to a UV coordinate.
Formula: uv' = rotation_matrix * (uv * scale) + offset
UVs are normalized to [0,1] range using mod to handle texture wrapping.
"""
function apply_gltf_uv_transform(uv, transform)
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
    extract_gltf_materials(gltf, textures::Dict{String, Any}) -> Dict{String, Any}

Extract materials from glTF JSON structure and return a dictionary.
Also extracts UV transform info for KHR_texture_transform extension.
"""
function extract_gltf_materials(gltf, textures::Dict{String, Any})
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
                uv_transform = gltf_texture_transform(pbr.baseColorTexture)
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

const IDENTITY_MAT4F = Mat4f(
    1, 0, 0, 0,
    0, 1, 0, 0,
    0, 0, 1, 0,
    0, 0, 0, 1
)

# +90° rotation around X axis: rotates Y-up to Z-up
const Y_TO_Z_UP_MAT4F = Mat4f(
    1, 0, 0, 0,
    0, 0, 1, 0,
    0, -1, 0, 0,
    0, 0, 0, 1
)

"""
    gltf_up_rotation(up::Vec3f) -> Mat4f

Compute a 4x4 rotation matrix that rotates glTF's native Y-up to the target `up` axis.
Fast paths for common cases (Z-up, Y-up), general Rodrigues rotation otherwise.
"""
function gltf_up_rotation(up::Vec3f)
    gltf_up = Vec3f(0, 1, 0)
    # Normalize
    len = sqrt(up[1]^2 + up[2]^2 + up[3]^2)
    up_n = up / len

    # Fast path: Z-up (most common)
    if abs(up_n[1]) < 1f-6 && abs(up_n[2]) < 1f-6 && up_n[3] > 0.9999f0
        return Y_TO_Z_UP_MAT4F
    end

    # Fast path: Y-up (native glTF, no rotation)
    dot_val = gltf_up[1]*up_n[1] + gltf_up[2]*up_n[2] + gltf_up[3]*up_n[3]
    if dot_val > 0.9999f0
        return IDENTITY_MAT4F
    end

    # Anti-parallel (180° rotation around X)
    if dot_val < -0.9999f0
        return Mat4f(
            1, 0, 0, 0,
            0, -1, 0, 0,
            0, 0, -1, 0,
            0, 0, 0, 1
        )
    end

    # General rotation from gltf_up to up_n via Rodrigues' formula
    # R = I + K + K^2 * (1-c)/s^2  where K is skew-symmetric of cross(from, to)
    cx = gltf_up[2]*up_n[3] - gltf_up[3]*up_n[2]
    cy = gltf_up[3]*up_n[1] - gltf_up[1]*up_n[3]
    cz = gltf_up[1]*up_n[2] - gltf_up[2]*up_n[1]
    s = sqrt(cx^2 + cy^2 + cz^2)
    c = dot_val

    k1, k2, k3 = cx/s, cy/s, cz/s
    K = Mat3f(
        0, k3, -k2,
        -k3, 0, k1,
        k2, -k1, 0
    )
    K2 = K * K
    I3 = Mat3f(
        1, 0, 0,
        0, 1, 0,
        0, 0, 1
    )
    rot3 = I3 + s * K + (1 - c) * K2

    return Mat4f(
        rot3[1,1], rot3[2,1], rot3[3,1], 0,
        rot3[1,2], rot3[2,2], rot3[3,2], 0,
        rot3[1,3], rot3[2,3], rot3[3,3], 0,
        0, 0, 0, 1
    )
end

"""
    extract_gltf_mesh(gltf, binary_data::Vector{UInt8}, base_path; kwargs...) -> MetaMesh

Extract mesh data from glTF structure with node hierarchy transforms.
"""
function extract_gltf_mesh(gltf, binary_data::Vector{UInt8}, base_path;
                            facetype=GLTriangleFace, pointtype=Point3f,
                            normaltype=Vec3f, uvtype=Vec2f,
                            up=Vec3f(0, 0, 1))

    textures_dict = extract_gltf_textures(gltf, binary_data, base_path)
    materials_dict = extract_gltf_materials(gltf, textures_dict)

    if !haskey(gltf, :meshes)
        empty_mesh = GeometryBasics.Mesh(pointtype[], facetype[])
        return MetaMesh(empty_mesh)
    end

    # A primitive lacking an attribute that others have gets it `pad!`ded.
    all_positions = pointtype[]
    all_normals = normaltype[]
    all_uvs = uvtype[]
    all_colors = Vec4f[]                # COLOR_0, linear RGBA
    all_joints = Vec{4, Int32}[]        # 1-based bones of `skeleton`
    all_weights = Vec4f[]
    all_faces = facetype[]

    views = UnitRange{Int}[]
    material_names = String[]

    current_vertex_offset = Ref(0)
    current_face_offset = Ref(0)

    # Root transform to convert from glTF Y-up to target up axis
    up_matrix = gltf_up_rotation(up)

    node_table = gltf_node_table(gltf)
    node_clips = gltf_node_animations(gltf, binary_data, base_path)
    # A second skin numbers its joints from zero again; merging would need a remap per primitive.
    skins = get(gltf, :skins, ())
    length(skins) > 1 && @warn "glTF file has $(length(skins)) skins; only the first is read."
    skeleton, joint_remap, node_to_bone = isempty(skins) ? (nothing, Int32[], Dict{Int, Int}()) :
        gltf_skeleton(gltf, binary_data, base_path, first(skins), node_table, up_matrix)

    function process_node(node_idx::Int, parent_transform::Mat4f)
        node = gltf.nodes[node_idx + 1]

        local_transform = gltf_node_transform(node)
        world_transform = parent_transform * local_transform

        if haskey(node, :mesh)
            mesh_idx = node.mesh
            mesh = gltf.meshes[mesh_idx + 1]

            for primitive in mesh.primitives
                positions = nothing
                if haskey(primitive.attributes, :POSITION)
                    positions = gltf_accessor_data(gltf, binary_data, base_path, primitive.attributes.POSITION)
                end

                if isnothing(positions)
                    continue
                end

                attribute(name) = haskey(primitive.attributes, name) ?
                    gltf_accessor_data(gltf, binary_data, base_path, primitive.attributes[name]) : nothing
                normals, uvs, colors = attribute(:NORMAL), attribute(:TEXCOORD_0), attribute(:COLOR_0)
                indices = haskey(primitive, :indices) ?
                    gltf_accessor_data(gltf, binary_data, base_path, primitive.indices) : 0:length(positions)-1

                # glTF ignores a skinned mesh's node transform: its joints carry it,
                # and the up rotation rides on the skeleton's root.
                skinned = !isnothing(skeleton) && haskey(node, :skin) && haskey(primitive.attributes, :JOINTS_0)
                vertex_transform = skinned ? IDENTITY_MAT4F : world_transform
                offset = current_vertex_offset[]

                append!(all_positions, map(p -> gltf_transform_point(p, vertex_transform, pointtype), positions))
                isnothing(normals) || append!(pad!(all_normals, offset, normaltype(0, 0, 1)),
                    map(n -> gltf_transform_normal(n, vertex_transform, normaltype), normals))
                isnothing(colors) || append!(pad!(all_colors, offset, Vec4f(1)), map(gltf_rgba, colors))
                if skinned
                    # JOINTS_0 indexes the skin's joint list; `joint_remap` makes that a bone.
                    joints = attribute(:JOINTS_0)
                    append!(pad!(all_joints, offset, Vec{4, Int32}(1)),
                            map(j -> Vec{4, Int32}(map(k -> joint_remap[k + 1], j)), joints))
                    weights = attribute(:WEIGHTS_0)
                    append!(pad!(all_weights, offset, Vec4f(0)),
                            isnothing(weights) ? fill(Vec4f(1, 0, 0, 0), length(joints)) : Vec4f.(weights))
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
                isnothing(uvs) || append!(pad!(all_uvs, offset, uvtype(0, 0)), map(uvs) do uv
                    isnothing(uv_transform) && return uvtype(uv[1], 1.0f0 - uv[2])
                    transformed_uv = apply_gltf_uv_transform(uv, uv_transform)
                    return uvtype(1.0f0 - transformed_uv[2], 1.0f0 - transformed_uv[1])
                end)

                primitive_faces = gltf_triangles(facetype, indices, offset)
                append!(all_faces, primitive_faces)
                num_faces = length(primitive_faces)

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
                process_node(root_node_idx, up_matrix)
            end
        end
    else
        # Fallback: process all root-level nodes
        foreach(i -> process_node(i - 1, up_matrix), findall(iszero, node_table.parents))
    end

    # Create mesh with appropriate attributes
    n = length(all_positions)
    kwargs_mesh = Pair{Symbol, Any}[]
    isempty(all_normals) || push!(kwargs_mesh, :normal => pad!(all_normals, n, normaltype(0, 0, 1)))
    isempty(all_uvs) || push!(kwargs_mesh, :uv => pad!(all_uvs, n, uvtype(0, 0)))
    isempty(all_colors) || push!(kwargs_mesh, :color => pad!(all_colors, n, Vec4f(1)))
    if !isempty(all_joints)
        push!(kwargs_mesh, :skinjoints => pad!(all_joints, n, Vec{4, Int32}(1)),
                           :skinweights => pad!(all_weights, n, Vec4f(0)))
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
    isempty(all_joints) || (metadata[:skeleton] = skeleton)
    animations = gltf_bone_animations(node_clips, node_to_bone)
    isempty(animations) || (metadata[:animations] = animations)
    isempty(node_table.parents) || (metadata[:nodes] = node_table)
    isempty(node_clips) || (metadata[:node_animations] = node_clips)

    return MetaMesh(mesh, metadata)
end

##############################
#
# Saving GLB
#
##############################

"""
    save(fn::File{format"GLB"}, mesh; up = Vec3f(0, 0, 1))

Write a mesh as binary glTF, the inverse of `load`: views become primitives,
`meta[:materials]` and `meta[:material_names]` materials with PNG-embedded
textures. Positions, `:normal`, `:uv` and `:color` (linear, as `COLOR_0`) are
written, rotated from `up` to glTF's Y-up with UVs flipped back to `(u, 1 - v)`.
"""
function save(f::Stream{format"GLB"}, mesh; up = Vec3f(0, 0, 1))
    m = GeometryBasics.expand_faceviews(GeometryBasics.Mesh(mesh))
    meta = mesh isa MetaMesh ? mesh.meta : Dict{Symbol, Any}()
    toglb = Mat3f(transpose(gltf_up_rotation(Vec3f(up))[Vec(1, 2, 3), Vec(1, 2, 3)]))

    bin = UInt8[]
    views = Dict{String, Any}[]
    accessors = Dict{String, Any}[]
    function blob!(bytes::AbstractVector{UInt8}; target = nothing)
        align!(bin)
        v = Dict{String, Any}("buffer" => 0, "byteOffset" => length(bin), "byteLength" => length(bytes))
        target === nothing || (v["target"] = target)
        append!(bin, bytes)
        push!(views, v)
        return length(views) - 1
    end
    function accessor!(data::AbstractVector, ctype, type; target = 34962, fields...)
        push!(accessors, Dict{String, Any}("bufferView" => blob!(reinterpret(UInt8, data); target),
              "componentType" => ctype, "count" => length(data), "type" => type,
              (string(k) => v for (k, v) in fields)...))
        return length(accessors) - 1
    end

    points = coordinates(m)
    va = GeometryBasics.vertex_attributes(m)
    normals, uvs, colors = get(va, :normal, nothing), get(va, :uv, nothing), get(va, :color, nothing)
    # `load` reads each primitive's vertices as its own, so a primitive carries
    # exactly the vertices its faces use.
    function attributes!(vids)
        position = [Point3f(toglb * Vec3f(points[v])) for v in vids]
        bounds = Rect3f(position)
        a = Dict("POSITION" => accessor!(position, 5126, "VEC3"; min = minimum(bounds), max = maximum(bounds)))
        isnothing(normals) || (a["NORMAL"] = accessor!([Vec3f(toglb * Vec3f(normals[v])) for v in vids], 5126, "VEC3"))
        isnothing(uvs) || (a["TEXCOORD_0"] = accessor!([Vec2f(uvs[v][1], 1f0 - uvs[v][2]) for v in vids], 5126, "VEC2"))
        isnothing(colors) || (a["COLOR_0"] = accessor!([gltf_rgba(colors[v]) for v in vids], 5126, "VEC4"))
        return a
    end

    materials = get(meta, :materials, Dict{String, Any}())
    names = get(meta, :material_names, String[])
    images = Dict{String, Any}[]
    textures = Dict{String, Any}[]
    function texture!(img)
        buf = IOBuffer()
        FileIO.save(FileIO.Stream{FileIO.format"PNG"}(buf), img)
        push!(images, Dict{String, Any}("bufferView" => blob!(take!(buf)), "mimeType" => "image/png"))
        push!(textures, Dict{String, Any}("source" => length(images) - 1))
        return Dict{String, Any}("index" => length(textures) - 1)
    end
    order = unique(filter(n -> haskey(materials, n), names))
    gltfmaterials = [gltfmaterial(n, materials[n], texture!) for n in order]

    fs = faces(m)
    local_index = zeros(UInt32, length(points))
    primitives = Dict{String, Any}[]
    for (i, r) in enumerate(isempty(m.views) ? [1:length(fs)] : m.views)
        vids = sort!(unique!([Int(value(v)) for f in view(fs, r) for v in f]))
        local_index[vids] .= 0:length(vids)-1
        indices = UInt32[local_index[value(v)] for f in view(fs, r) for v in f]
        p = Dict{String, Any}("attributes" => attributes!(vids), "mode" => 4,
                              "indices" => accessor!(indices, 5125, "SCALAR"; target = 34963))
        mat = i <= length(names) ? findfirst(==(names[i]), order) : nothing
        mat === nothing || (p["material"] = mat - 1)
        push!(primitives, p)
    end

    gltf = Dict{String, Any}(
        "asset" => Dict("version" => "2.0", "generator" => "MeshIO.jl"),
        "scene" => 0,
        "scenes" => [Dict("nodes" => [0])],
        "nodes" => [Dict("mesh" => 0)],
        "meshes" => [Dict("primitives" => primitives)],
        "buffers" => [Dict("byteLength" => length(align!(bin)))],
        "bufferViews" => views,
        "accessors" => accessors)
    isempty(gltfmaterials) || (gltf["materials"] = gltfmaterials)
    isempty(images) || (gltf["images"] = images; gltf["textures"] = textures)

    json = align!(Vector{UInt8}(JSON3.write(gltf)), UInt8(' '))
    io = stream(f)
    write(io, UInt32(GLB_MAGIC), UInt32(2), UInt32(12 + 8 + length(json) + 8 + length(bin)))
    write(io, UInt32(length(json)), UInt32(GLB_JSON_CHUNK), json)
    write(io, UInt32(length(bin)), UInt32(GLB_BIN_CHUNK), bin)
    return nothing
end

"`bytes` padded with `byte` to glTF's 4-byte alignment."
align!(bytes::Vector{UInt8}, byte::UInt8 = 0x00) = append!(bytes, fill(byte, mod(-length(bytes), 4)))

"""
One material as `extract_gltf_materials` reads it back: the same keys, turned
into glTF's `pbrMetallicRoughness` and the textures `texture!` embeds.
"""
function gltfmaterial(name, mat::AbstractDict, texture!)
    pbr = Dict{String, Any}()
    diffuse = get(mat, "diffuse", Vec3f(1, 1, 1))
    pbr["baseColorFactor"] = [diffuse[1], diffuse[2], diffuse[3], get(mat, "alpha", 1f0)]
    haskey(mat, "metallic") && (pbr["metallicFactor"] = mat["metallic"])
    haskey(mat, "roughness") && (pbr["roughnessFactor"] = mat["roughness"])
    haskey(mat, "diffuse map") && (pbr["baseColorTexture"] = texture!(mat["diffuse map"]["image"]))
    haskey(mat, "metallic roughness map") &&
        (pbr["metallicRoughnessTexture"] = texture!(mat["metallic roughness map"]["image"]))
    out = Dict{String, Any}("name" => name, "pbrMetallicRoughness" => pbr)
    haskey(mat, "normal map") && (out["normalTexture"] = texture!(mat["normal map"]["image"]))
    haskey(mat, "occlusion map") && (out["occlusionTexture"] = texture!(mat["occlusion map"]["image"]))
    haskey(mat, "emissive") && (out["emissiveFactor"] = collect(mat["emissive"]))
    haskey(mat, "emissive map") && (out["emissiveTexture"] = texture!(mat["emissive map"]["image"]))
    haskey(mat, "alpha mode") && (out["alphaMode"] = mat["alpha mode"])
    haskey(mat, "alpha cutoff") && (out["alphaCutoff"] = mat["alpha cutoff"])
    haskey(mat, "double sided") && (out["doubleSided"] = mat["double sided"])
    return out
end
