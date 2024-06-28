# Graphics backends like OpenGL only have one index buffer so the indices to
# positions, normals and texture coordinates cannot be different. E.g. a face
# cannot use positional indices (1, 2, 3) and normal indices (1, 1, 2). In that
# case we need to remap normals such that new_normals[1, 2, 3] = normals[[1, 1, 2]]


# ...
_typemin(x) = typemin(x)
_typemin(::Type{OffsetInteger{N, T}}) where {N, T} = typemin(T) - N

merge_vertex_attribute_indices(faces...) = merge_vertex_attribute_indices(faces)

function merge_vertex_attribute_indices(faces::Tuple)
    FaceType = eltype(faces[1])
    IndexType = eltype(FaceType)
    D = length(faces)
    N = length(faces[1])

    # (pos_idx, normal_idx, uv_idx, ...) -> new_idx
    vertex_index_map = Dict{NTuple{D, UInt32}, IndexType}()
    # faces after remapping (0 based assumed)
    new_faces = sizehint!(FaceType[], N)
    temp = IndexType[]           # keeping track of vertex indices of a face
    counter = _typemin(IndexType)
    # for remaping attribs, i.e. `new_attrib = old_attrib[index2vertex[attrib_index]]`
    index2vertex = ntuple(_ -> sizehint!(UInt32[], N), D)

    for i in eachindex(faces[1])
        # (pos_faces[i], normal_faces[i], uv_faces[i], ...)
        attrib_faces = getindex.(faces, i)
        empty!(temp)
        
        for j in eachindex(attrib_faces[1])
            # (pos_index, normal_idx, uv_idx, ...)
            # = (pos_faces[i][j], normal_faces[i][j], uv_faces[i][j], ...)
            vertex = GeometryBasics.value.(getindex.(attrib_faces, j)) # 1 based

            # if combination of indices in vertex is new, make a new index
            if !haskey(vertex_index_map, vertex)
                vertex_index_map[vertex] = counter
                counter = IndexType(counter + 1)
                push!.(index2vertex, vertex)
            end

            # keep track of the (new) index for this vertex
            push!(temp, vertex_index_map[vertex])
        end

        # store face with new indices
        push!(new_faces, FaceType(temp...))
    end

    sizehint!(new_faces, length(new_faces))

    return new_faces, index2vertex
end