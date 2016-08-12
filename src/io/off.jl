function save(str::Stream{format"OFF"}, msh::AbstractMesh)
    # writes an OFF geometry file, with colors
    #  see http://people.sc.fsu.edu/~jburkardt/data/off/off.html
    #  for format description
    io = stream(str)
    vts = vertices(msh)
    fcs = faces(msh)

    cs  = hascolors(msh) ? colors(msh) : RGBA{Float32}(0,0,0,1)

    nV = size(vts,1)
    nF = size(fcs,1)
    nE = nF*3

    # write the header
    println(io,"OFF")
    println(io,"$nV $nF $nE")
    # write the data
    for v in vts
        println(io, join(Vec{3, Float32}(v), " "))
    end
    for i = 1:nF
        f = fcs[i]
        c = isa(cs, Array) ? RGBA{Float32}(cs[i]) : cs
        facelen = length(f)
        println(io, 
            facelen, " ", join(Face{facelen, Cuint, -1}(f), " "), " ", 
            join((red(c), green(c), blue(c), alpha(c)), " ")
        )
    end
    close(io)
end

function load(st::Stream{format"OFF"}, MeshType=GLNormalMesh)
    io = stream(st)
    local vts
    FT = facetype(MeshType)
    VT = vertextype(MeshType)
    fcs = FT[] # faces might be triangulated, so we can't assume count
    nV = 0
    nF = 0

    found_counts = false
    read_verts = 0

    while !eof(io)
        txt = readline(io)
        if startswith(txt, "#") || isempty(txt) ||iscntrl(txt) #comment or others
            continue
        elseif found_counts && read_verts < nV # read verts
            vert = VT(split(txt))
            if length(vert) == 3
                read_verts += 1
                vts[read_verts] = vert
            end
            continue
        elseif found_counts # read faces
            splitted = split(txt)
            facelen  = @compat parse(Int, shift!(splitted))
            if facelen == 3
                push!(fcs, GLTriangle(splitted))
            elseif facelen == 4
                push!(fcs, decompose(FT, Face{4, Cuint, -1}(splitted))...)
            end
            continue
        elseif !found_counts && isdigit(split(txt)[1]) # vertex and face counts
            counts = Int[@compat parse(Int, s) for s in split(txt)]
            nV = counts[1]
            nF = counts[2]
            vts = Array(VT, nV)
            found_counts = true
        end
    end
    return MeshType(vts, fcs)
end
