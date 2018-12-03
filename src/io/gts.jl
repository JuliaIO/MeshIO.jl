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

function load( st::Stream{format"GTS"}, MeshType=GLNormalMesh )
    io = stream(st)
    head = readline( io )
    body = readlines( io )
    FT = facetype(MeshType)
    VT = vertextype(MeshType)

    nVertices, nEdges, nFacets = parseGtsLine( head, Tuple{Int,Int,Int} )

    vertices = parseGtsLine.( body[1:nVertices], VT )
    edges = parseGtsLine.( body[nVertices+1:nVertices+nEdges], Array{Int} )
    facets = parseGtsLine.( body[nVertices+nEdges+1:end], Array{Int} )
    faces = [ FT( union( edges[facets[i][1]], edges[facets[i][2]], edges[facets[i][3]] ) ) for i in 1:length(facets) ]  # orientation not guaranteed
    return MeshType( vertices, faces )
end
