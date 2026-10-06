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
                    return base64_to_bytes(data_part)
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
    data = Vector{ET}(undef, count)
    for i in 0:(count-1)
        element_offset = offset + i * stride + 1
        data[i + 1] = gltf_read_typed_data(buffer_data, element_offset, type_info.type, num_components)
    end

    # `normalized` says the integers stand for reals on [0, 1] or [-1, 1]. A
    # quantized exporter writes WEIGHTS_0 this way, and read at face value the
    # weights come back as 255 or 65535 and the mesh inflates by that factor.
    get(accessor, :normalized, false) || return data
    return gltf_denormalize(data)
end

"""
    gltf_denormalize(data)

Decode a `normalized` accessor to floats, by the divisors glTF specifies:
255 and 65535 for the unsigned types, 127 and 32767 for the signed ones, with
the signed results clamped at -1 so the two encodings of -1 agree.
"""
gltf_denormalize(data::Vector{<:AbstractFloat}) = data
gltf_denormalize(data::Vector{<:Tuple{Vararg{AbstractFloat}}}) = data
gltf_denormalize(data::Vector{T}) where {T <: Integer} =
    [gltf_denormalize(v) for v in data]
gltf_denormalize(data::Vector{<:NTuple{N, <:Integer}}) where {N} =
    [map(gltf_denormalize, v) for v in data]
gltf_denormalize(v::UInt8) = Float32(v) / 255f0
gltf_denormalize(v::UInt16) = Float32(v) / 65535f0
gltf_denormalize(v::UInt32) = Float32(v) / 4294967295f0
gltf_denormalize(v::Int8) = max(Float32(v) / 127f0, -1f0)
gltf_denormalize(v::Int16) = max(Float32(v) / 32767f0, -1f0)

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
    gltf_read_typed_data(data::Vector{UInt8}, offset::Int, T::Type, count::Int)

Read typed data from byte array.
"""
function gltf_read_typed_data(data::Vector{UInt8}, offset::Int, T::Type, count::Int)
    if count == 1
        return reinterpret(T, data[offset:offset+sizeof(T)-1])[1]
    else
        values = [reinterpret(T, data[offset+(i-1)*sizeof(T):offset+i*sizeof(T)-1])[1] for i in 1:count]
        return Tuple(values)
    end
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
                    image_bytes = base64_to_bytes(data_part)
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

const BASE64_ALPHABET = codeunits(
    "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/")

"Byte to its 6-bit value; 0xff for anything that is not a base64 digit."
const BASE64_LOOKUP = let table = fill(0xff, 256)
    for (i, c) in enumerate(BASE64_ALPHABET)
        table[Int(c) + 1] = UInt8(i - 1)
    end
    table
end

"""
    base64_to_bytes(s) -> Vector{UInt8}

Decode the payload of a `data:` URI. Whitespace and `=` padding are ignored.

Written out rather than taken from the `Base64` stdlib because this is the only
base64 a mesh loader ever meets, and the decoder is shorter than the dependency.
"""
function base64_to_bytes(s::AbstractString)
    out = UInt8[]
    sizehint!(out, 3 * (ncodeunits(s) >> 2))
    acc = UInt32(0)
    nbits = 0
    for b in codeunits(s)
        v = BASE64_LOOKUP[Int(b) + 1]
        v == 0xff && continue
        acc = (acc << 6) | v
        nbits += 6
        if nbits >= 8
            nbits -= 8
            push!(out, UInt8((acc >> nbits) & 0xff))
        end
    end
    return out
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

    all_positions = pointtype[]
    all_normals = normaltype[]
    all_uvs = uvtype[]
    # `COLOR_0`, as linear RGBA whatever the file stored (VEC3 gets alpha 1).
    all_colors = Vec4f[]
    all_faces = facetype[]
    # Per-vertex skin data, and the skeleton it indexes. Accumulated alongside the
    # positions so a multi-primitive mesh concatenates them the same way. Joint
    # indices are integers: they index the skinning matrices, and holding them as Float32
    # costs a conversion per bone per vertex per frame.
    all_joints = Vec{4, Int32}[]
    all_weights = Vec4f[]
    has_skin = false

    views = UnitRange{Int}[]
    material_names = String[]

    has_normals = false
    has_uvs = false
    has_colors = false

    current_vertex_offset = Ref(0)
    current_face_offset = Ref(0)

    # Root transform to convert from glTF Y-up to target up axis
    up_matrix = gltf_up_rotation(up)

    # One skin is the overwhelmingly common case and the only one whose joint
    # indices can be trusted as written: a second skin numbers its joints from
    # zero again, so merging two would need every vertex remapped against the
    # skin its primitive names. Read the first and say so rather than silently
    # posing half the mesh with the wrong bones.
    skeleton = nothing
    joint_remap = Int32[]
    node_to_bone = Dict{Int, Int}()
    if haskey(gltf, :skins) && !isempty(gltf.skins)
        length(gltf.skins) > 1 && @warn(
            "glTF file has $(length(gltf.skins)) skins; only the first is read. " *
            "Vertices bound to the others keep their bind pose."
        )
        skeleton, joint_remap, node_to_bone =
            gltf_skeleton(gltf, binary_data, base_path, 0, up_matrix)
    end
    animation_clips = gltf_animations(gltf, binary_data, base_path, node_to_bone)
    # The scene graph as authored, and every animation channel against it. The
    # bone-indexed clips above cannot carry a channel aimed at anything but a
    # joint; these can, which is what an animated camera or prop needs.
    node_table = gltf_node_table(gltf)
    node_clips = gltf_node_animations(gltf, binary_data, base_path)

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

                normals = nothing
                if haskey(primitive.attributes, :NORMAL)
                    normals = gltf_accessor_data(gltf, binary_data, base_path, primitive.attributes.NORMAL)
                    has_normals = true
                end

                uvs = nothing
                if haskey(primitive.attributes, :TEXCOORD_0)
                    uvs = gltf_accessor_data(gltf, binary_data, base_path, primitive.attributes.TEXCOORD_0)
                    has_uvs = true
                end

                colors = nothing
                if haskey(primitive.attributes, :COLOR_0)
                    colors = gltf_accessor_data(gltf, binary_data, base_path, primitive.attributes.COLOR_0)
                    has_colors = true
                end

                indices = nothing
                if haskey(primitive, :indices)
                    indices = gltf_accessor_data(gltf, binary_data, base_path, primitive.indices)
                end

                # A SKINNED primitive is placed by its bones, not by its node.
                # glTF is explicit: the transform of a skinned mesh's node must be
                # ignored. Baking it in would apply it twice — the joints' world
                # matrices already carry it — and the up rotation rides on the
                # skeleton's roots for the same reason (see `gltf_skeleton`).
                skinned = !isnothing(skeleton) && haskey(node, :skin) &&
                          haskey(primitive.attributes, :JOINTS_0)
                vertex_transform = skinned ? IDENTITY_MAT4F : world_transform

                for p in positions
                    push!(all_positions, gltf_transform_point(p, vertex_transform, pointtype))
                end

                if !isnothing(normals)
                    for n in normals
                        push!(all_normals, gltf_transform_normal(n, vertex_transform, normaltype))
                    end
                elseif has_normals
                    for _ in 1:length(positions)
                        push!(all_normals, normaltype(0, 0, 1))
                    end
                end

                # `skinjoints` are 1-based indices into the skeleton's matrices — Julia's
                # convention, converted once here rather than on every read. The
                # file's values index the SKIN's joint array, which `joint_remap`
                # turns into bone indices in topological order.
                if skinned
                    has_skin = true
                    js = gltf_accessor_data(gltf, binary_data, base_path, primitive.attributes.JOINTS_0)
                    ws = haskey(primitive.attributes, :WEIGHTS_0) ?
                         gltf_accessor_data(gltf, binary_data, base_path, primitive.attributes.WEIGHTS_0) :
                         nothing
                    for (k, j) in enumerate(js)
                        push!(all_joints, Vec{4, Int32}(
                            joint_remap[Int(j[1]) + 1], joint_remap[Int(j[2]) + 1],
                            joint_remap[Int(j[3]) + 1], joint_remap[Int(j[4]) + 1]
                        ))
                        w = isnothing(ws) ? (1.0f0, 0.0f0, 0.0f0, 0.0f0) : ws[k]
                        push!(all_weights, Vec4f(w[1], w[2], w[3], w[4]))
                    end
                else
                    # Every unskinned primitive is padded, not only those that
                    # follow a skinned one: whether the mesh has a skin at all is
                    # not known until one is seen, so a file whose first primitive
                    # is unskinned would otherwise finish with fewer joints than
                    # vertices and drop the skin from the whole mesh. Bone 1 at
                    # zero weight is what `skinvertex` leaves alone.
                    for _ in 1:length(positions)
                        push!(all_joints, Vec{4, Int32}(1, 1, 1, 1))
                        push!(all_weights, Vec4f(0, 0, 0, 0))
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
                            transformed_uv = apply_gltf_uv_transform(uv, uv_transform)
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

                if !isnothing(colors)
                    for c in colors
                        push!(all_colors, length(c) == 4 ? Vec4f(c...) : Vec4f(c[1], c[2], c[3], 1))
                    end
                elseif has_colors
                    for _ in 1:length(positions)
                        push!(all_colors, Vec4f(1, 1, 1, 1))
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
                process_node(root_node_idx, up_matrix)
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
                process_node(i, up_matrix)
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
    if has_colors && length(all_colors) == length(all_positions)
        push!(kwargs_mesh, :color => all_colors)
    end
    if has_skin && length(all_joints) == length(all_positions)
        push!(kwargs_mesh, :skinjoints => all_joints)
        push!(kwargs_mesh, :skinweights => all_weights)
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
    if has_skin && !isnothing(skeleton)
        metadata[:skeleton] = skeleton
    end
    if !isempty(animation_clips)
        metadata[:animations] = animation_clips
    end
    if !isempty(node_table.parents)
        metadata[:nodes] = node_table
    end
    if !isempty(node_clips)
        metadata[:node_animations] = node_clips
    end

    return MetaMesh(mesh, metadata)
end

##############################
#
# Saving GLB
#
##############################

"""
    save(fn::File{format"GLB"}, mesh; up = Vec3f(0, 0, 1))

Write a mesh as binary glTF, the inverse of `load`: a `MetaMesh` as `load` returns
one — its views as primitives, `meta[:materials]` and `meta[:material_names]` as
materials with their textures embedded as PNG — or a plain mesh as one primitive
with no material.

Vertex attributes: positions, and `:normal`, `:uv` and `:color` when present
(`COLOR_0`, linear as glTF defines it: nothing is converted). Positions and
normals are rotated from `up` to glTF's Y-up and UVs flipped back to glTF's
`(u, 1 - v)`, which is exactly what `load` undid.
"""
function save(f::Stream{format"GLB"}, mesh; up = Vec3f(0, 0, 1))
    io = stream(f)
    m = GeometryBasics.Mesh(mesh)
    meta = mesh isa MetaMesh ? mesh.meta : Dict{Symbol,Any}()
    toglb = Mat3f(transpose(gltf_up_rotation(Vec3f(up))[Vec(1, 2, 3), Vec(1, 2, 3)]))

    bin = UInt8[]
    views = Dict{String,Any}[]
    accessors = Dict{String,Any}[]
    # One buffer view per blob, four-byte aligned, as glTF requires of every
    # accessor's element.
    function blob!(bytes::AbstractVector{UInt8}; target = nothing)
        while length(bin) % 4 != 0
            push!(bin, 0x00)
        end
        v = Dict{String,Any}("buffer" => 0, "byteOffset" => length(bin), "byteLength" => length(bytes))
        target === nothing || (v["target"] = target)
        append!(bin, bytes)
        push!(views, v)
        return length(views) - 1
    end
    function accessor!(data::AbstractVector, ctype, type; target = 34962, normalized = false,
                       bounds = false)
        v = blob!(collect(reinterpret(UInt8, data)); target)
        a = Dict{String,Any}("bufferView" => v, "componentType" => ctype, "count" => length(data),
                             "type" => type)
        normalized && (a["normalized"] = true)
        if bounds
            a["min"] = [minimum(p[k] for p in data) for k in 1:3]
            a["max"] = [maximum(p[k] for p in data) for k in 1:3]
        end
        push!(accessors, a)
        return length(accessors) - 1
    end

    points = coordinates(m)
    va = GeometryBasics.vertex_attributes(m)
    attr(name) = haskey(va, name) && va[name] isa AbstractVector ? va[name] : nothing
    normals_, uvs_, colors_ = attr(:normal), attr(:uv), attr(:color)
    # The vertices of one primitive, `vids` of the mesh's: `load` reads every
    # primitive's vertices as its own, so a primitive carries exactly the ones its
    # faces use and a single-view mesh comes back vertex for vertex.
    function attributes!(vids)
        a = Dict{String,Int}()
        a["POSITION"] = accessor!([Point3f(toglb * Vec3f(points[v])) for v in vids], 5126, "VEC3";
                                  bounds = true)
        normals_ === nothing ||
            (a["NORMAL"] = accessor!([Vec3f(toglb * Vec3f(normals_[v])) for v in vids], 5126, "VEC3"))
        uvs_ === nothing ||
            (a["TEXCOORD_0"] = accessor!([Vec2f(uvs_[v][1], 1f0 - uvs_[v][2]) for v in vids], 5126, "VEC2"))
        colors_ === nothing ||
            (a["COLOR_0"] = accessor!([Vec{4,UInt8}(gltfcolor(colors_[v])) for v in vids], 5121, "VEC4";
                                      normalized = true))
        return a
    end

    # Materials in the order `material_names` first names them.
    materials = get(meta, :materials, Dict{String,Any}())
    names = get(meta, :material_names, String[])
    images = Dict{String,Any}[]
    textures = Dict{String,Any}[]
    function texture!(img)
        buf = IOBuffer()
        FileIO.save(FileIO.Stream{FileIO.format"PNG"}(buf), img)
        push!(images, Dict{String,Any}("bufferView" => blob!(take!(buf)), "mimeType" => "image/png"))
        push!(textures, Dict{String,Any}("source" => length(images) - 1))
        return Dict{String,Any}("index" => length(textures) - 1)
    end
    order = String[]
    for n in names
        haskey(materials, n) && !(n in order) && push!(order, n)
    end
    gltfmaterials = Dict{String,Any}[]
    for n in order
        push!(gltfmaterials, gltfmaterial(n, materials[n], texture!))
    end

    fs = faces(m)
    ranges = isempty(m.views) ? [1:length(fs)] : m.views
    primitives = Dict{String,Any}[]
    for (i, r) in enumerate(ranges)
        vids = sort!(unique!([Int(value(f[k])) for f in view(fs, r) for k in 1:3]))
        local_index = zeros(UInt32, length(points))
        for (k, v) in enumerate(vids)
            local_index[v] = UInt32(k - 1)
        end
        idx = UInt32[local_index[Int(value(f[k]))] for f in view(fs, r) for k in 1:3]
        p = Dict{String,Any}("attributes" => attributes!(vids), "mode" => 4,
                             "indices" => accessor!(idx, 5125, "SCALAR"; target = 34963))
        mat = i <= length(names) ? findfirst(==(names[i]), order) : nothing
        mat === nothing || (p["material"] = mat - 1)
        push!(primitives, p)
    end

    gltf = Dict{String,Any}(
        "asset" => Dict("version" => "2.0", "generator" => "MeshIO.jl"),
        "scene" => 0,
        "scenes" => [Dict("nodes" => [0])],
        "nodes" => [Dict("mesh" => 0)],
        "meshes" => [Dict("primitives" => primitives)],
        "buffers" => [Dict("byteLength" => length(bin))],
        "bufferViews" => views,
        "accessors" => accessors)
    isempty(gltfmaterials) || (gltf["materials"] = gltfmaterials)
    isempty(images) || (gltf["images"] = images; gltf["textures"] = textures)

    json = Vector{UInt8}(JSON3.write(gltf))
    while length(json) % 4 != 0
        push!(json, UInt8(' '))
    end
    while length(bin) % 4 != 0
        push!(bin, 0x00)
    end
    write(io, UInt32(GLB_MAGIC), UInt32(2), UInt32(12 + 8 + length(json) + 8 + length(bin)))
    write(io, UInt32(length(json)), UInt32(GLB_JSON_CHUNK), json)
    write(io, UInt32(length(bin)), UInt32(GLB_BIN_CHUNK), bin)
    return nothing
end

"""
One material as `extract_gltf_materials` reads it back: the same keys, turned
into glTF's `pbrMetallicRoughness` and the textures `texture!` embeds.
"""
function gltfmaterial(name, mat::AbstractDict, texture!)
    pbr = Dict{String,Any}()
    diffuse = get(mat, "diffuse", Vec3f(1, 1, 1))
    pbr["baseColorFactor"] = [diffuse[1], diffuse[2], diffuse[3], get(mat, "alpha", 1f0)]
    haskey(mat, "metallic") && (pbr["metallicFactor"] = mat["metallic"])
    haskey(mat, "roughness") && (pbr["roughnessFactor"] = mat["roughness"])
    haskey(mat, "diffuse map") && (pbr["baseColorTexture"] = texture!(mat["diffuse map"]["image"]))
    haskey(mat, "metallic roughness map") &&
        (pbr["metallicRoughnessTexture"] = texture!(mat["metallic roughness map"]["image"]))
    out = Dict{String,Any}("name" => name, "pbrMetallicRoughness" => pbr)
    haskey(mat, "normal map") && (out["normalTexture"] = texture!(mat["normal map"]["image"]))
    haskey(mat, "occlusion map") && (out["occlusionTexture"] = texture!(mat["occlusion map"]["image"]))
    haskey(mat, "emissive") && (out["emissiveFactor"] = collect(mat["emissive"]))
    haskey(mat, "emissive map") && (out["emissiveTexture"] = texture!(mat["emissive map"]["image"]))
    haskey(mat, "alpha mode") && (out["alphaMode"] = mat["alpha mode"])
    haskey(mat, "alpha cutoff") && (out["alphaCutoff"] = mat["alpha cutoff"])
    haskey(mat, "double sided") && (out["doubleSided"] = mat["double sided"])
    return out
end

"""A vertex colour as the four normalised bytes of `COLOR_0`."""
gltfcolor(c::GeometryBasics.VecTypes{3}) = (plychannel(c[1]), plychannel(c[2]), plychannel(c[3]), 0xff)
gltfcolor(c::GeometryBasics.VecTypes{4}) = plychannel.((c[1], c[2], c[3], c[4]))
gltfcolor(c::RGB) = (plychannel(red(c)), plychannel(green(c)), plychannel(blue(c)), 0xff)
gltfcolor(c::RGBA) = (plychannel(red(c)), plychannel(green(c)), plychannel(blue(c)), plychannel(alpha(c)))
