# Reference for NAS format:
# https://documentation-be.hexagon.com/bundle/MSC_Nastran_2022.1_Quick_Reference_Guide/raw/resource/enus/MSC_Nastran_2022.1_Quick_Reference_Guide.pdf

# Minimal free-field card builder, similar to write_nas.jl
@inline function _fieldstr(x)
    if x isa AbstractString
        return x
    elseif x isa Integer
        return string(x)
    elseif x isa AbstractFloat
        return @sprintf("%.9g", Float64(x))
    else
        return string(x)
    end
end

# Threaded collectors: distribute work and merge per-thread results to reduce contention
function _partition_cards_threads!(card_groups::Vector{Vector{String}})
    n = length(card_groups)
    t = max(1, Threads.nthreads())
    # Local per-chunk buckets preserve original order within each chunk
    local_grids = [Vector{Vector{String}}() for _ in 1:t]
    local_tris  = [Vector{Vector{String}}() for _ in 1:t]
    local_quads = [Vector{Vector{String}}() for _ in 1:t]
    local_tets  = [Vector{Vector{String}}() for _ in 1:t]

    Threads.@threads for chunk in 1:t
        start_i = fld((chunk - 1) * n, t) + 1
        end_i   = fld(chunk * n, t)
        if start_i <= end_i
            g = local_grids[chunk]
            tr = local_tris[chunk]
            q = local_quads[chunk]
            te = local_tets[chunk]
            for i in start_i:end_i
                cardname, fields = _get_fields(card_groups[i])
                if isempty(fields)
                    continue
                end
                if cardname == "GRID"
                    push!(g, card_groups[i])
                elseif cardname == "CTRIA3"
                    push!(tr, card_groups[i])
                elseif cardname == "CQUAD4"
                    push!(q, card_groups[i])
                elseif cardname == "CTETRA"
                    push!(te, card_groups[i])
                end
            end
        end
    end

    # Merge in chunk order to preserve file order per type
    grid_groups = Vector{Vector{String}}()
    tri_groups  = Vector{Vector{String}}()
    quad_groups = Vector{Vector{String}}()
    tet_groups  = Vector{Vector{String}}()
    for chunk in 1:t
        append!(grid_groups, local_grids[chunk])
        append!(tri_groups,  local_tris[chunk])
        append!(quad_groups, local_quads[chunk])
        append!(tet_groups,  local_tets[chunk])
    end
    return grid_groups, tri_groups, quad_groups, tet_groups
end
function _collect_grids_threads!(grid_groups::Vector{Vector{String}}, pointtype)
    n = length(grid_groups)
    # Fast path
    if n == 0
        return pointtype[], Dict{Int, Int}()
    end
    # Per-index buffers to preserve original file order
    valid = falses(n)
    nids = Vector{Int}(undef, n)
    verts = Vector{pointtype}(undef, n)

    t = max(1, Threads.nthreads())
    Threads.@threads for chunk in 1:t
        start_i = fld((chunk - 1) * n, t) + 1
        end_i   = fld(chunk * n, t)
        if start_i <= end_i
            for i in start_i:end_i
                _, fields = _get_fields(grid_groups[i])
                result = _parse_grid_card(fields, pointtype)
                if result !== nothing
                    valid[i] = true
                    nids[i] = result.nid
                    verts[i] = result.vertex
                end
            end
        end
    end

    # Assemble in file order
    m = count(valid)
    vertices = Vector{pointtype}(undef, m)
    node_id_to_index = Dict{Int, Int}()
    idx = 0
    for i in 1:n
        if valid[i]
            idx += 1
            vertices[idx] = verts[i]
            node_id_to_index[nids[i]] = idx
        end
    end
    return vertices, node_id_to_index
end

function _collect_trias_threads!(faces, groups::Vector{Vector{String}}, node_id_to_index::Dict{Int,Int}, ::Type{F}) where {F}
    n = length(groups)
    if n == 0
        return faces
    end
    t = max(1, Threads.nthreads())
    local_buffers = [F[] for _ in 1:t]
    Threads.@threads for chunk in 1:t
        # Compute this worker's chunk deterministically based on the loop index `chunk`
        start_i = fld((chunk - 1) * n, t) + 1
        end_i   = fld(chunk * n, t)
        if start_i <= end_i
            buf = local_buffers[chunk]
            sizehint!(buf, length(buf) + (end_i - start_i + 1))
            @inbounds for i in start_i:end_i
                _, fields = _get_fields(groups[i])
                idxs = _parse_ctria3_card(fields, node_id_to_index)
                if idxs !== nothing
                    push!(buf, F(idxs...))
                end
            end
        end
    end
    # Merge
    for buf in local_buffers
        append!(faces, buf)
    end
    return faces
end

function _collect_quads_threads!(faces, groups::Vector{Vector{String}}, node_id_to_index::Dict{Int,Int}, ::Type{F}) where {F}
    n = length(groups)
    if n == 0
        return faces
    end
    t = max(1, Threads.nthreads())
    local_buffers = [F[] for _ in 1:t]
    Threads.@threads for chunk in 1:t
        start_i = fld((chunk - 1) * n, t) + 1
        end_i   = fld(chunk * n, t)
        if start_i <= end_i
            buf = local_buffers[chunk]
            # Quads can expand into up to 2 triangles; sizehint accordingly
            sizehint!(buf, length(buf) + 2 * (end_i - start_i + 1))
            @inbounds for i in start_i:end_i
                _, fields = _get_fields(groups[i])
                idxs = _parse_cquad4_card(fields, node_id_to_index)
                if idxs !== nothing
                    i1,i2,i3,i4 = idxs
                    _push_quad!(buf, F, i1, i2, i3, i4)
                end
            end
        end
    end
    for buf in local_buffers
        append!(faces, buf)
    end
    return faces
end

function _collect_tetras_threads!(faces, groups::Vector{Vector{String}}, node_id_to_index::Dict{Int,Int}, ::Type{F}) where {F}
    n = length(groups)
    if n == 0
        return faces
    end
    t = max(1, Threads.nthreads())
    local_buffers = [F[] for _ in 1:t]
    Threads.@threads for chunk in 1:t
        start_i = fld((chunk - 1) * n, t) + 1
        end_i   = fld(chunk * n, t)
        if start_i <= end_i
            buf = local_buffers[chunk]
            # Tetra fallback can add up to 4 triangles
            sizehint!(buf, length(buf) + 4 * (end_i - start_i + 1))
            @inbounds for i in start_i:end_i
                _, fields = _get_fields(groups[i])
                idxs = _parse_ctetra_card(fields, node_id_to_index)
                if idxs !== nothing
                    i1,i2,i3,i4 = idxs
                    _push_tetra!(buf, F, i1, i2, i3, i4)
                end
            end
        end
    end
    for buf in local_buffers
        append!(faces, buf)
    end
    return faces
end

@inline function _card(name::AbstractString, fields...; comment::Union{Nothing,String}=nothing)
    s = String(name)
    if !isempty(fields)
        s *= "," * join(_fieldstr.(fields), ",")
    end
    if comment !== nothing && !isempty(comment)
        s *= "  \$ " * comment
    end
    return s
end


function save(fs::Stream{format"NAS"}, msh::AbstractMesh; meshname="mesh", write_header::Bool=true, default_pid::Int=1)
    # Similar to OBJ/STL writers: ensure no FaceViews remain for stable iteration
    if any(v -> v isa FaceView, values(vertex_attributes(msh)))
        msh = GeometryBasics.expand_faceviews(Mesh(msh))
    end
    io = stream(fs)
    points = coordinates(msh)
    meshfaces = faces(msh)  # iterate concrete faces directly

    println(io, "\$ MeshIO-generated Nastran file for $meshname")
    if write_header
        println(io, _card("CEND"))
        println(io, _card("BEGIN BULK"))
    end

    # Write GRID
    for (i, p) in enumerate(points)
        println(io, _card("GRID", i, "", p[1], p[2], p[3]))
    end

    # Write elements based on face type
    for (i, f) in enumerate(meshfaces)
        idxs = Int.(f)
        if isa(f, TriangleFace)
            println(io, _card("CTRIA3", i, default_pid, idxs[1], idxs[2], idxs[3]))
        elseif isa(f, QuadFace)
            println(io, _card("CQUAD4", i, default_pid, idxs[1], idxs[2], idxs[3], idxs[4]))
        elseif isa(f, NGonFace{4})
            # Assume CTETRA for NGonFace{4} (volume)
            println(io, _card("CTETRA", i, default_pid, idxs[1], idxs[2], idxs[3], idxs[4]))
        else
            println(io, "\$ unsupported-face, $(i)")
        end
    end

    if write_header
        println(io, _card("ENDDATA"))
    end
    return
end

# Collect logical cards as lists of raw lines (main + continuations)
function _collect_cards(io::IO)
    lines = readlines(io)
    n = length(lines)
    # Parallel cleaning: strip comments/whitespace in parallel to utilize CPU on large files
    cleaned = Vector{String}(undef, n)
    keep = falses(n)
    t = max(1, Threads.nthreads())
    Threads.@threads for chunk in 1:t
        start_i = fld((chunk - 1) * n, t) + 1
        end_i   = fld(chunk * n, t)
        if start_i <= end_i
            for i in start_i:end_i
                line = rstrip(lines[i])
                if occursin('\$', line)
                    line = first(split(line, '\$'))
                    line = rstrip(line)
                end
                if !isempty(strip(line))
                    cleaned[i] = line
                    keep[i] = true
                end
            end
        end
    end

    # Sequential grouping over cleaned lines to preserve continuation semantics
    cards = Vector{Vector{String}}()
    current = Vector{String}()
    in_bulk = false
    for i in 1:n
        if !keep[i]
            continue
        end
        line = cleaned[i]
        uline = uppercase(strip(line))
        if startswith(uline, "CEND")
            continue
        elseif startswith(uline, "BEGIN BULK")
            in_bulk = true
            continue
        elseif startswith(uline, "ENDDATA")
            break
        end
        if !in_bulk && any(startswith(uppercase(s), "GRID") || startswith(uppercase(s), "C") for s in [strip(line)])
            in_bulk = true
        end
        if !in_bulk
            continue
        end

        if startswith(line, "+") || startswith(line, " ")
            push!(current, line)
        else
            if !isempty(current)
                push!(cards, current)
            end
            current = [line]
        end
    end
    if !isempty(current)
        push!(cards, current)
    end
    return cards
end

# Extract cardname and fields based on format (free or fixed)
function _get_fields(card_lines::Vector{String})
    has_comma = any(contains(line, ",") for line in card_lines)
    fields = String[]
    cardname = ""
    if has_comma  # free format
        full_text = ""
        for line in card_lines
            line = strip(line)
            if startswith(line, "+")
                line = strip(line[2:end])
            end
            full_text *= "," * line
        end
        full_text = lstrip(full_text, ',')
    tokens = split(full_text, ",", keepempty=true)
        tokens = [strip(t) for t in tokens]
        if !isempty(tokens)
            cardname = uppercase(tokens[1])
            fields = tokens[2:end]  # keep blanks as "" to preserve positions
        end
    else  # fixed format
        all_fields = String[]
        for (i, line) in enumerate(card_lines)
            max_col = length(line)
            # Small-field format: skip field 1 (cardname/continuation), read fields 2..10
            for j in 2:10
                start_col = (j - 1) * 8 + 1
                end_col = min(start_col + 7, max_col)
                if end_col < start_col
                    break
                end
                field = strip(line[start_col:end_col])
                push!(all_fields, field)
            end
        end
        if !isempty(card_lines)
            cardname = uppercase(strip(card_lines[1][1:min(8, length(card_lines[1]))]))
        end
        fields = all_fields
    end
    return cardname, fields
end

# Helper: push a triangle face
function _push_triangle!(faces, ::Type{F}, i1::Int, i2::Int, i3::Int) where {F}
    push!(faces, F(i1, i2, i3))
    return faces
end

# Helper: push a quad face or triangulate if conversion to facetype fails
function _push_quad!(faces, ::Type{F}, i1::Int, i2::Int, i3::Int, i4::Int) where {F}
    q = QuadFace{Int}(i1, i2, i3, i4)
    try
        push!(faces, convert(F, q))
    catch
        # Triangulate quad: split into two triangles
        push!(faces, F(i1, i2, i3))
        push!(faces, F(i1, i3, i4))
    end
    return faces
end

# Specialized: when target facetype is triangular, skip conversion and exceptions
function _push_quad!(faces, ::Type{F}, i1::Int, i2::Int, i3::Int, i4::Int) where {F<:TriangleFace}
    push!(faces, F(i1, i2, i3))
    push!(faces, F(i1, i3, i4))
    return faces
end

# Helper: push a tetrahedron (NGonFace{4}) or fall back to its 4 surface triangles
function _push_tetra!(faces, ::Type{F}, i1::Int, i2::Int, i3::Int, i4::Int) where {F}
    try
        t = NGonFace{4, Int}(i1, i2, i3, i4)
        push!(faces, convert(F, t))
    catch
        # Fallback: add 4 triangular faces (surface of tetra)
        push!(faces, F(i1, i2, i3))
        push!(faces, F(i1, i2, i4))
        push!(faces, F(i2, i3, i4))
        push!(faces, F(i1, i3, i4))
    end
    return faces
end

# Specialized: when facetype is triangular, emit 4 triangles directly
function _push_tetra!(faces, ::Type{F}, i1::Int, i2::Int, i3::Int, i4::Int) where {F<:TriangleFace}
    push!(faces, F(i1, i2, i3))
    push!(faces, F(i1, i2, i4))
    push!(faces, F(i2, i3, i4))
    push!(faces, F(i1, i3, i4))
    return faces
end

# Helper: Parse element ID and property ID from fields (common pattern for element cards)
# Returns (start_index_for_nodes, pid) or nothing if invalid
function _parse_element_header(fields::Vector{<:AbstractString}, start_index::Int=1)
    if start_index > length(fields) return nothing end
    
    eid = tryparse(Int, fields[start_index])
    if eid === nothing return nothing end
    
    # PID may be blank; default to EID per spec
    pid_index = start_index + 1
    rawpid = pid_index <= length(fields) ? fields[pid_index] : ""
    pid = tryparse(Int, rawpid)
    if pid === nothing
        pid = eid
    end
    
    return (node_start=pid_index + 1, pid=pid)
end

# Helper: Convert node IDs to vertex indices, returns tuple of indices or nothing
function _get_node_indices(fields::Vector{<:AbstractString}, start_index::Int, count::Int, 
                           node_id_to_index::Dict{Int, Int})
    if start_index + count - 1 > length(fields) return nothing end
    
    node_ids = [tryparse(Int, fields[i]) for i in start_index:start_index+count-1]
    if any(x->x===nothing, node_ids) || length(node_ids) < count return nothing end
    
    # Check all nodes exist in the mapping
    if !all(haskey(node_id_to_index, nid) for nid in node_ids)
        return nothing
    end
    
    # Return tuple of indices
    return Tuple(node_id_to_index[nid] for nid in node_ids)
end

# Parse GRID card and return vertex point or nothing if invalid
function _parse_grid_card(fields::Vector{<:AbstractString}, pointtype)
    index = 1
    if index > length(fields) return nothing end
    nid = tryparse(Int, fields[index])
    if nid === nothing return nothing end
    index += 1
    
    # Optional CP field: consume only if it looks like an Int
    if index <= length(fields)
        if tryparse(Int, fields[index]) !== nothing
            index += 1
        end
    end
    
    # Collect next three numeric fields as coordinates (skip blanks/non-numeric)
    coords = Float64[]
    k = index
    while k <= length(fields) && length(coords) < 3
        v = tryparse(Float64, fields[k])
        if v !== nothing
            push!(coords, v)
        end
        k += 1
    end
    
    if length(coords) != 3
        return nothing
    end
    
    x, y, z = coords
    vertex = pointtype(Float32(x), Float32(y), Float32(z))
    return (nid=nid, vertex=vertex)
end

# Parse CTRIA3 card and return face indices or nothing if invalid
function _parse_ctria3_card(fields::Vector{<:AbstractString}, node_id_to_index::Dict{Int, Int})
    return _parse_element_nodes(fields, 3, node_id_to_index)
end

# Parse CQUAD4 card and return quad face indices or nothing if invalid
function _parse_cquad4_card(fields::Vector{<:AbstractString}, node_id_to_index::Dict{Int, Int})
    return _parse_element_nodes(fields, 4, node_id_to_index)
end

# Parse CTETRA card and return tetrahedron face indices or nothing if invalid
function _parse_ctetra_card(fields::Vector{<:AbstractString}, node_id_to_index::Dict{Int, Int})
    return _parse_element_nodes(fields, 4, node_id_to_index)
end

# Generic element nodes parser for CTRIA3/CQUAD4/CTETRA
function _parse_element_nodes(fields::Vector{<:AbstractString}, node_count::Int, node_id_to_index::Dict{Int, Int})
    min_fields = node_count + 2  # eid + pid + nodes
    if length(fields) < min_fields return nothing end
    header = _parse_element_header(fields)
    if header === nothing return nothing end
    return _get_node_indices(fields, header.node_start, node_count, node_id_to_index)
end

# Improved loader with robust parsing for both free and fixed formats
function load(fs::Stream{format"NAS"}; facetype=GLTriangleFace, pointtype=Point3f)
    io = stream(fs)
    t_cards = @elapsed begin
        card_groups = _collect_cards(io)
    end

    # Partition cards by type in parallel (order-preserving within each type)
    t_part = grid_groups, tri_groups, quad_groups, tet_groups = _partition_cards_threads!(card_groups)

    # Phase 1 (parallel, order-preserving): build vertices and node id -> index map in file order
    t_grids = vertices, node_id_to_index = _collect_grids_threads!(grid_groups, pointtype)

    # Phase 2 (parallel): parse elements into faces using per-thread buffers
    faces = facetype[]
    # Run collectors concurrently across card types using separate buffers
    tri_faces  = facetype[]
    quad_faces = facetype[]
    tet_faces  = facetype[]
    t_faces = begin
        t_tri  = Threads.@spawn _collect_trias_threads!(tri_faces,  tri_groups,  node_id_to_index, facetype)
        t_quad = Threads.@spawn _collect_quads_threads!(quad_faces, quad_groups, node_id_to_index, facetype)
        t_tet  = Threads.@spawn _collect_tetras_threads!(tet_faces, tet_groups, node_id_to_index, facetype)
        wait.(Ref(t_tri)); wait.(Ref(t_quad)); wait.(Ref(t_tet))
    end

    # Merge
    append!(faces, tri_faces)
    append!(faces, quad_faces)
    append!(faces, tet_faces)

    return Mesh(vertices, faces)
end

# File wrapper: handle NAS files without magic header by skipping skipmagic
function load(fn::File{format"NAS"}; kwargs...)
    open(fn) do s
        # Don't call skipmagic for NAS files since they have no magic header
        load(s; kwargs...)
    end
end
