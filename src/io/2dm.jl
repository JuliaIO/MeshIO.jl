export import2dm,
       export2dm

import Base.writemime

function import2dm(file::String)
    con = open(file, "r")
    mesh = import2dm(con)
    close(con)
    return mesh
end

parseNode(w::Array{String}) = Vertex(float64(w[3]), float64(w[4]), float64(w[5]))

parseTriangle(w::Array{String}) = Face{Int}(int(w[3]), int(w[4]), int(w[5]))

# Qudrilateral faces are split up into triangles
function parseQuad(w::Array{String})
    w[7] = w[3]                     # making a circle
    Face{Int}[Face{Int}(w[i], w[i+1], w[i+2]) for i = [3,5]]
end

# | Read a .2dm (SMS Aquaveo) mesh-file and construct a @Mesh@
function import2dm(con::IO)
    nd =  Vertex[]
    ele = Face{Int}[]
    for line = readlines(con)
        line = chomp(line)
        w = split(line)
        if w[1] == "ND"
            push!(nd, parseNode(w))
        elseif w[1] == "E3T"
            push!(ele,parseTriangle(w))
        elseif w[1] == "E4Q"
            append!(ele, parseQuad(w))
        else
            continue
        end
    end
    Mesh{Vertex, Face{Int}}(nd,ele)
end


# | Write @Mesh@ to an IOStream
function export2dm(con::IO,m::Mesh)
    function renderVertex(i::Int,v::Vertex)
        "ND $i $(v.e1) $(v.e2) $(v.e3)\n"
    end
    function renderFace(i::Int, f::Face)
        "E3T $i $(f.v1) $(f.v2) $(f.v3) 0\n"
    end
    write(con, "MESH2D\n")
    for i = 1:length(m.faces)
        write(con, renderFace(i, m.faces[i]))
    end
    for i = 1:length(m.vertices)
        write(con, renderVertex(i, m.vertices[i]))
    end
    nothing
end

function writemime(io::IO, ::MIME"model/2dm", mesh::Mesh)
    export2dm(io, mesh)
end

# | Write a @Mesh@ to file in SMS-.2dm-file-format
function exportTo2dm(f::String,m::Mesh)
    con = open(f, "w")
    export2dm(con, m)
    close(con)
    nothing
end
