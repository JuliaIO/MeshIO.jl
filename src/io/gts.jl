function parseGtsLine( s::AbstractString, C, T=eltype(C) )
    firstInd = findfirst( isequal(' '), s )
    secondInd = findnext( isequal(' '), s, firstInd+1 )
    firstNum = parse( T, s[1:firstInd] )
    if secondInd != nothing
        secondNum = parse( T, s[firstInd:secondInd] )
        thirdNum = parse( T, s[secondInd:end] )
        return C([firstNum, secondNum, thirdNum])
    else
        secondNum = parse( T, s[firstInd:end] )
        return C([firstNum, secondNum])
    end
end

function load( st::Stream{format"GTS"}; facetype=GLTriangleFace, pointtype=Point)
    io = stream(st)
    head = readline( io )

    nVertices, nEdges, nFacets = parseGtsLine( head, Tuple{Int,Int,Int} )
    iV = iE = iF = 1
    vertices = Vector{pointtype}(undef, nVertices)
    edges = Vector{Vector{Int}}(undef, nEdges)
    facets = Vector{Vector{Int}}(undef, nFacets)
    for full_line::String in eachline(io)
        # read a line, remove newline and leading/trailing whitespaces
        line = strip(chomp(full_line))
        !isascii(line) && error("non valid ascii in obj")

        if !startswith(line, "#") && !isempty(line) && !all(iscntrl, line) #ignore comments
            if iV <= nVertices
                vertices[iV] = parseGtsLine( line, pointtype )
                iV += 1
            elseif iV > nVertices && iE <= nEdges
                edges[iE] = parseGtsLine( line, Array{Int} )
                iE += 1
            elseif iE > nEdges && iF <= nFacets
                facets[iF] = parseGtsLine( line, Array{Int} )
                iF += 1
            end # if
        end # if
    end # for
    faces = [ facetype( union( edges[facets[i][1]], edges[facets[i][2]], edges[facets[i][3]] ) ) for i in 1:length(facets) ]  # orientation not guaranteed
    return Mesh( vertices, faces )
end

function save( st::Stream{format"GTS"}, mesh::AbstractMesh )
    # convert faces to edges and facets
    edges = [[ 0, 0 ]] # TODO
    facets = [[ 0, 0 ]] # TODO
    # write to file
    io = stream( st )
    println( io, length(mesh.vertices), legth(edges), length(mesh.faces) )
    for v in mesh.vertices
        println( io, v[1], v[2], v[3] )
    end
    for e in edges
        println( io, e[1], e[2] )
    end
    for f in facets
        println( io, f[1], f[2], f[3] )
    end
end
