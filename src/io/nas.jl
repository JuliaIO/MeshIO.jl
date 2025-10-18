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
    cards = Vector{Vector{String}}()
    current = Vector{String}()
    in_bulk = false
    for raw in lines
        line = rstrip(raw)
        # strip inline comments starting with $
        if occursin('\$', line)
            line = first(split(line, '\$'))
            line = rstrip(line)
        end
        if isempty(strip(line))
            continue
        end
        uline = uppercase(strip(line))
        if startswith(uline, "CEND")
            # case control end; continue until BEGIN BULK
            continue
        elseif startswith(uline, "BEGIN BULK")
            in_bulk = true
            continue
        elseif startswith(uline, "ENDDATA")
            break
        end
        # If file has no BEGIN BULK, assume entire file is bulk
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

# Improved loader with robust parsing for both free and fixed formats
function load(fs::Stream{format"NAS"}; facetype=GLTriangleFace, pointtype=Point3f)
    io = stream(fs)
    card_groups = _collect_cards(io)

    node_id_to_index = Dict{Int, Int}()
    vertices = pointtype[]
    faces = facetype[]

    metadata = Dict{String, Vector{String}}()

    for group in card_groups
        card_str = join(group, "\n")
        cardname, fields = _get_fields(group)
        if isempty(fields)
            continue
        end
        if cardname == "GRID"
            index = 1
            if index > length(fields) continue end
            nid = tryparse(Int, fields[index])
            if nid === nothing continue end
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
                continue
            end
            x, y, z = coords
            push!(vertices, pointtype(Float32(x), Float32(y), Float32(z)))
            node_id_to_index[nid] = length(vertices)
        elseif cardname == "CTRIA3"
            if length(fields) < 4 continue end
            index = 1
            eid = tryparse(Int, fields[index])  # optional, skip if needed
            index += 1
            # PID may be blank; default to EID per spec
            rawpid = index <= length(fields) ? fields[index] : ""
            index += 1
            pid = tryparse(Int, rawpid)
            if pid === nothing
                pid = eid
            end
            gs = [tryparse(Int, fields[i]) for i in index:index+2]
            if any(x->x===nothing, gs) || length(gs) < 3 continue end
            n1, n2, n3 = gs
            if all(haskey(node_id_to_index, x) for x in (n1, n2, n3))
                push!(faces, facetype(node_id_to_index[n1], node_id_to_index[n2], node_id_to_index[n3]))
            else
                push!(get!(metadata, "missing_nodes", String[]), card_str)
            end
        elseif cardname == "CQUAD4"
            if length(fields) < 5 continue end
            index = 1
            eid = tryparse(Int, fields[index])
            index += 1
            rawpid = index <= length(fields) ? fields[index] : ""
            index += 1
            pid = tryparse(Int, rawpid)
            if pid === nothing
                pid = eid
            end
            gs = [tryparse(Int, fields[i]) for i in index:index+3]
            if any(x->x===nothing, gs) || length(gs) < 4 continue end
            n1, n2, n3, n4 = gs
            if all(haskey(node_id_to_index, x) for x in (n1, n2, n3, n4))
                q = QuadFace{Int}(node_id_to_index[n1], node_id_to_index[n2], node_id_to_index[n3], node_id_to_index[n4])
                try
                    push!(faces, convert(facetype, q))
                catch
                    push!(faces, facetype(node_id_to_index[n1], node_id_to_index[n2], node_id_to_index[n3]))
                    push!(faces, facetype(node_id_to_index[n1], node_id_to_index[n3], node_id_to_index[n4]))
                end
            else
                push!(get!(metadata, "missing_nodes", String[]), card_str)
            end
        elseif cardname == "CTETRA"
            if length(fields) < 5 continue end
            index = 1
            eid = tryparse(Int, fields[index])
            index += 1
            rawpid = index <= length(fields) ? fields[index] : ""
            index += 1
            pid = tryparse(Int, rawpid)
            if pid === nothing
                pid = eid
            end
            gs = [tryparse(Int, fields[i]) for i in index:index+3]
            if any(x->x===nothing, gs) || length(gs) < 4 continue end
            n1, n2, n3, n4 = gs
            if all(haskey(node_id_to_index, x) for x in (n1, n2, n3, n4))
                # Expand tetra to its 4 triangular faces if facetype is triangle-based
                try
                    # Try to push as a 4-node poly face if supported by facetype
                    t = NGonFace{4, Int}(node_id_to_index[n1], node_id_to_index[n2], node_id_to_index[n3], node_id_to_index[n4])
                    push!(faces, convert(facetype, t))
                catch
                    # Fallback: add 4 triangular faces (surface of tetra)
                    push!(faces, facetype(node_id_to_index[n1], node_id_to_index[n2], node_id_to_index[n3]))
                    push!(faces, facetype(node_id_to_index[n1], node_id_to_index[n2], node_id_to_index[n4]))
                    push!(faces, facetype(node_id_to_index[n2], node_id_to_index[n3], node_id_to_index[n4]))
                    push!(faces, facetype(node_id_to_index[n1], node_id_to_index[n3], node_id_to_index[n4]))
                end
            else
                push!(get!(metadata, "missing_nodes", String[]), card_str)
            end
        else
            push!(get!(metadata, "other_cards", String[]), card_str)
        end
    end

    return Mesh(vertices, faces), metadata
end

# File wrapper: avoid FileIO.skipmagic, NAS has no magic header
function load(fn::File{format"NAS"}; kwargs...)
    open(fn) do s
        load(s; kwargs...)
    end
end
