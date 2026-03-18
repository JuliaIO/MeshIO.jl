# read .inp files
function load(fs::Stream{format"INP"}; facetype=GLTriangleFace, pointtype=Point3f)
    #INP file format
    io = stream(fs)

    points = pointtype[]
    faces = facetype[]
    node_idx = Int[]

    # read the first 3 lines if there is the "*heading" keyword
    line = readline(io)
    contains(line,"*heading") && (line = readline(io))
    BlockType = contains(line,"*NODE") ? Val{:NodeBlock}() : Val{:DataBlock}()

    # read the file
    while !eof(io)
        line = readline(io)
        BlockType, line = parse_blocktype!(BlockType, io, line)
        if BlockType == Val{:NodeBlock}()
            push!(node_idx, parse(Int,split(line,",")[1])) # keep track of the node index of the inp file
            push!(points, pointtype(parse.(eltype(pointtype),split(line,",")[2:4])))
        elseif BlockType == Val{:ElementBlock}()
            nodes = parse.(Int,split(line,",")[2:end])
            push!(faces, TriangleFace{Int}(facetype([findfirst(==(node),node_idx) for node in nodes])...)) # parse the face
        else
            continue
        end
    end

    return Mesh(points, faces)
end
function parse_blocktype!(block, io, line)
    contains(line,"*NODE") && return block=Val{:NodeBlock}(),readline(io)
    contains(line,"*ELEMENT") && return block=Val{:ElementBlock}(),readline(io)
    return block, line
end