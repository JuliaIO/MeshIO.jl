@enum MSHBlockType MSHFormatBlock MSHNodesBlock MSHElementsBlock MSHUnknownBlock

function load(fs::Stream{format"MSH"}; facetype=GLTriangleFace, pointtype=Point3f)
    #GMSH MSH format (version 4)
    #http://gmsh.info/doc/texinfo/gmsh.html#MSH-file-format
    io = stream(fs)

    faces = facetype[]
    nodes = pointtype[]
    node_tags = Int[]

    while !eof(io)
        BlockType = parse_blocktype!(io)
        if BlockType == MSHNodesBlock
            parse_nodes!(io, nodes, node_tags)
        elseif BlockType == MSHElementsBlock
            parse_elements!(io, faces)
        else
            skip_block!(io)
        end
    end

    remap_faces!(faces, node_tags)

    return Mesh(nodes, faces)
end

function parse_blocktype!(io)
    header = readline(io)
    if header == "\$MeshFormat"
        return MSHFormatBlock
    elseif header == "\$Nodes"
        return MSHNodesBlock
    elseif header == "\$Elements"
        return MSHElementsBlock
    else
        return MSHUnknownBlock
    end
end

function skip_block!(io)
    while true
        line = readline(io)
        if line[1:4] == "\$End"
            break
        end
    end
    return nothing
end

function parse_nodes!(io, nodes, node_tags)
    entity_blocks, num_nodes, min_node_tag, max_node_tag = parse.(Int, split(readline(io)))
    for index_entity in 1:entity_blocks
        dim, tag, parametric, nodes_in_block = parse.(Int, split(readline(io)))
        for i in 1:nodes_in_block
            push!(node_tags, parse(eltype(node_tags), readline(io)))
        end
        for i in 1:nodes_in_block
            xyz = parse.(Float64, split(readline(io)))
            push!(nodes, xyz)
        end
    end
    endblock = readline(io)
    if endblock != "\$EndNodes"
        error("expected end block tag, got $endblock")
    end
    return nodes, node_tags
end

function parse_elements!(io, faces::Vector{T}) where T <: TriangleFace

    num_elements = parse.(Int, split(readline(io)))

    num_entity_blocks, num_elements, min_element_tag, max_element_tag = num_elements

    for index_entity in 1:num_entity_blocks

        dim, tag, element_type, elements_in_block = parse.(Int, split(readline(io)))
        if element_type == 2 # Triangles
            for i in 1:elements_in_block
                tag, n1, n2, n3 = parse.(Int, split(readline(io)))
                push!(faces, (n1, n2, n3))
            end
        else
            # for now we ignore all other elements (points, lines, hedrons, etc)
            for i in 1:elements_in_block
                readline(io)
            end
        end
    end
    endblock = readline(io)
    if endblock != "\$EndElements"
        error("expected end block tag, got $endblock")
    end
    return faces
end

function remap_faces!(faces, node_tags)
    node_map = indexin(1:maximum(node_tags), node_tags)
    for (i, face) in enumerate(faces)
        faces[i] = (node_map[face[1]], node_map[face[2]], node_map[face[3]])
    end
    return faces
end
