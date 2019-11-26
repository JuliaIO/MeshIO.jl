
function load(fs::Stream{format"MSH"}, MeshType=GLNormalMesh)
    #GMSH MSH format (version 4)
    #http://gmsh.info/doc/texinfo/gmsh.html#MSH-file-format
    io = stream(fs)

    FaceType = facetype(MeshType)
    VertexType = vertextype(MeshType)
    faces = FaceType[]
    nodes = VertexType[]
    node_tags = Int[]

    while !eof(io)
        BlockType = _parse_blocktype!(io)
        if BlockType == MSHNodesBlock()
            _parse_nodes!(io, nodes, node_tags)
        elseif BlockType == MSHElementsBlock()
            _parse_elements!(io, faces)
        else
            _skip_block!(io)
        end
    end

    _remap_faces!(faces, node_tags)

    return MeshType(nodes, faces)
end

struct MSHFormatBlock end
struct MSHNodesBlock end
struct MSHElementsBlock end
struct MSHUnknownBlock end

function _parse_blocktype!(io)
    header = readline(io)
    if header == "\$MeshFormat"
        return MSHFormatBlock()
    elseif header == "\$Nodes"
        return MSHNodesBlock()
    elseif header == "\$Elements"
        return MSHElementsBlock()
    else
        return MSHUnknownBlock()
    end
end

function _parse_format!(io)
    version, binary, size = map(parse, (Float64, Int, Int), split(readline(io)))
    if version < 4
        error("version $(version[1]) < 4.0 not supported.")
    elseif binary == 1
        error("binary format not supported.")
    end
    endblock = readline(io)
    if endblock != "\$EndMeshFormat"
        error("expected block end tag, got $endblock.")
    end
    return version
end

function _skip_block!(io)
    while true
        line = readline(io)
        if line[1:4] == "\$End"
            break
        end
    end
    return nothing
end

function _parse_nodes!(io, nodes, node_tags)
    numEntityBlocks, numNodes, minNodeTag, maxNodeTag =
        map(parse, (Int, Int, Int, Int), split(readline(io)))
    for index_entity in 1:numEntityBlocks
        entityDim, entityTag, parametric, numNodesInBlock =
            map(parse, (Int, Int, Int, Int), split(readline(io)))
        for i in 1:numNodesInBlock
            push!(node_tags, parse(eltype(node_tags), readline(io)))
        end
        for i in 1:numNodesInBlock
            x, y, z = map(parse, (Float64, Float64, Float64), split(readline(io)))
            push!(nodes, eltype(nodes)(x, y, z))
        end
    end
    endblock = readline(io)
    if endblock != "\$EndNodes"
        error("expected end block tag, got $endblock")
    end
    return nodes, node_tags
end

function _parse_elements!(io, faces::Vector{T}) where T <: Triangle
    numEntityBlocks, numElements, minElementTag, maxElementTag =
        map(parse, (Int, Int, Int, Int), split(readline(io)))
    for index_entity in 1:numEntityBlocks
        entityDim, entityTag, elementType, numElementsInBlock =
            map(parse, (Int, Int, Int, Int), split(readline(io)))
        if elementType == 2 # Triangles
            for i in 1:numElementsInBlock
                tag, n1, n2, n3 =
                    map(parse, (Int, Int, Int, Int), split(readline(io)))
                push!(faces, eltype(faces)(n1, n2, n3))
            end
        else
            # for now we ignore all other elements (points, lines, hedrons, etc)
            for i in 1:numElementsInBlock
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

function _remap_faces!(faces, node_tags)
    node_map = indexin(1:maximum(node_tags), node_tags)
    for (i, face) in enumerate(faces)
        faces[i] = eltype(faces)(
            node_map[face[1]],
            node_map[face[2]],
            node_map[face[3]]
        )
    end
    return faces
end
