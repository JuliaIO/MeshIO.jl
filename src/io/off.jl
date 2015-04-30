export exportOFF

function exportOFF(msh::Mesh, fn::String, rgba)
    # writes an OFF geometry file, with colors
    #  see http://people.sc.fsu.edu/~jburkardt/data/off/off.html
    #  for format description
    vts = msh.vertices
    fcs = msh.faces
    nV = size(vts,1)
    nF = size(fcs,1)
    nE = nF*3

    str = open(fn,"w")

    # write the header
    write(str,"OFF\n")
    write(str,"$nV $nF $nE\n")

    # write the data
    for i = 1:nV
        v = vts[i]
        txt = @sprintf " %f %f %f\n" float32(v.e1) float32(v.e2) float32(v.e3)
        write(str,txt)
    end

    for i = 1:nF
        f = fcs[i]
        c = rgba[i,:]
        txt = @sprintf "  3 %i %i %i  %f %f %f %f\n" int32(f.v1-1) int32(f.v2-1) int32(f.v3-1)  float32(c[1]) float32(c[2]) float32(c[3]) float32(c[4])
        write(str,txt)
    end
    close(str)
end

function importOFF(fn::String; topology=false)
    str = open(fn,"r")
    mesh = importOFF(str, topology=topology)
    close(str)
    return mesh
end


function importOFF(io::IO; topology=false)

    local vts
    fcs = Face{Int}[] # faces might be triangulated, so we can't assume count
    nV = 0
    nF = 0

    found_counts = false
    read_verts = 0

    while !eof(io)
        txt = readline(io)
        if startswith(txt, "#") #comment
            continue
        elseif found_counts && read_verts < nV # read verts
            vert = map(float64, split(txt))
            if length(vert) == 3
                read_verts += 1
                vts[read_verts] = Vertex(vert...)
            end
            continue
        elseif found_counts # read faces
            face = map(int, split(txt))
            if length(face) >= 4
                for i = 4:length(face) #triangulate
                    push!(fcs, Face{Int}(face[2]+1, face[i-1]+1, face[i]+1))
                end
            end
            continue
        elseif !found_counts && isdigit(split(txt)[1]) # vertex and face counts
            counts = map(int, split(txt))
            nV = counts[1]
            nF = counts[2]
            vts = Array(Vertex, nV)
            found_counts = true
        end
    end

    if topology
        uvts = unique(vts)
        for i = 1:length(fcs)
            #repoint indices to unique vertices
            v1 = findfirst(uvts, vts[fcs[i].v1])
            v2 = findfirst(uvts, vts[fcs[i].v2])
            v3 = findfirst(uvts, vts[fcs[i].v3])
            fcs[i] = Face{Int}(v1,v2,v3)
        end
        vts = uvts
    end

    return Mesh{Vertex, Face{Int}}(vts, fcs, topology)
end
