function save(str::Stream{format"OFF"}, msh::AbstractMesh)
    # writes an OFF geometry file, with colors
    #  see http://people.sc.fsu.edu/~jburkardt/data/off/off.html
    #  for format description
    io = stream(str)
    vts = coordinates(msh)
    fcs = faces(msh)

    cs  = hasproperty(msh, :color) ? msh.color : RGBA{Float32}(0,0,0,1)

    nV = size(vts, 1)
    nF = size(fcs, 1)
    nE = nF*3

    # write the header
    println(io, "OFF")
    println(io, "$nV $nF $nE")
    # write the data
    for v in vts
        println(io, join(Vec{3, Float32}(v), " "))
    end

    for i = 1:nF
        f = fcs[i]
        c = isa(cs, Array) ? RGBA{Float32}(cs[i]) : cs
        facelen = length(f)
        println(io,
            facelen, " ", join(raw.(ZeroIndex.(f)), " "), " ",
            join((red(c), green(c), blue(c), alpha(c)), " ")
        )
    end
    close(io)
end

function load(st::Stream{format"OFF"}; facetype=GLTriangleFace, pointtype=Point3f)
    io = stream(st)
    points = pointtype[]
    faces = facetype[] # faces might be triangulated, so we can't assume count
    n_points = 0
    n_faces = 0
    found_counts = false
    read_verts = 0

    while !eof(io)
        txt = readline(io)
        if startswith(txt, "#") || isempty(txt) || all(iscntrl, txt) #comment or others
            continue
        elseif found_counts && read_verts < n_points # read verts
            vert = pointtype(parse.(eltype(pointtype), split(txt)))
            if length(vert) == 3
                read_verts += 1
                points[read_verts] = vert
            end
            continue
        elseif found_counts # read faces
            splitted = split(txt)
            facelen = parse(Int, popfirst!(splitted))
            if facelen == 3
                push!(faces, GLTriangleFace(reinterpret(ZeroIndex{Cuint}, parse.(Cuint, splitted[1:3]))))
            elseif facelen == 4
                push!(faces, convert_simplex(facetype, QuadFace{Cuint}(reinterpret(ZeroIndex{Cuint}, parse.(Cuint, splitted[1:4]))))...)
            end
            continue
        elseif !found_counts && all(isdigit, split(txt)[1]) # vertex and face counts
            counts = Int[parse(Int, s) for s in split(txt)]
            n_points = counts[1]
            n_faces = counts[2]
            resize!(points, n_points)
            found_counts = true
        end
    end
    return Mesh(points, faces)
end
