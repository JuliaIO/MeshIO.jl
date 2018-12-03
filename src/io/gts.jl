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
    FT = facetype(MeshType)
    VT = vertextype(MeshType)

    nVertices, nEdges, nFacets = parseGtsLine( head, Tuple{Int,Int,Int} )
    iV = iE = iF = 1
    vertices = Vector{VT}(undef, nVertices)
    edges = Vector{Vector{Int}}(undef, nEdges)
    facets = Vector{Vector{Int}}(undef, nFacets)
    for full_line::String in eachline(io)
        # read a line, remove newline and leading/trailing whitespaces
        line = strip(chomp(full_line))
        !isascii(line) && error("non valid ascii in obj")

        if !startswith(line, "#") && !isempty(line) && !all(iscntrl, line) #ignore comments
            if iV <= nVertices
                vertices[iV] = parseGtsLine( line, VT )
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
    faces = [ FT( union( edges[facets[i][1]], edges[facets[i][2]], edges[facets[i][3]] ) ) for i in 1:length(facets) ]  # orientation not guaranteed
    return MeshType( vertices, faces )
end
