# https://github.com/mrdoob/three.js/wiki/JSON-Model-format-3

import JSON
export exportThreejs, importThreejs

import Base.writemime

function exportThreejs(msh::AbstractMesh, fn::String)
         exportThreejs(msh, open(fn, "w"))
end

function exportThreejs(msh::AbstractMesh, str::IO, closeAfterwards::Bool)
    vts = msh.vertices
    fcs = msh.faces
    nV = size(vts,1)
    nF = size(fcs,1)

    json = Dict()

    json["faces"] = Int[]
    for i=1:nF
        push!(json["faces"], 0, fcs[i].v1-1, fcs[i].v2-1, fcs[i].v3-1)
    end

    json["vertices"] = Float64[]
    for i=1:nV
        push!(json["vertices"], vts[i].e1, vts[i].e2, vts[i].e3)
    end

    json["metadata"] = Dict()
    json["metadata"]["formatVersion"] = 3

    write(str, JSON.json(json))
    if closeAfterwards
        close(str)
    end
end

exportThreejs(msh::AbstractMesh, str::IO) = exportThreejs(msh, str, true)

function writemime(io::IO, ::MIME"model/threejs", msh::AbstractMesh)
    exportSTL(msh, io)
end

function writemime(io::IO, ::MIME"text/html", msh::AbstractMesh)
    divID = string("mesh-display-", rand(Int64))
    write(io, """
        <div id="$divID"></div>
        <script src="//cdnjs.cloudflare.com/ajax/libs/require.js/2.1.14/require.min.js"></script>
        <script src="https://baconscript.github.io/Meshes.jl/files/js/require-config.js"></script>
        <div id="mesh-display"></div>
        <script>
        require([
        'https://baconscript.github.io/Meshes.jl/files/js/display-mesh.js'], function(displayMesh){ displayMesh(
    """)
    exportThreejs(msh, io, false)
    write(io, """,
        '$divID');
        });
        </script>
    """)
end

function importThreejs( fn::String, topology=true )

    json = JSON.parsefile( fn )

    if !haskey(json,"metadata") || !haskey(json["metadata"],"formatVersion") || !(json["metadata"]["formatVersion"] in [3,3.1])
        println("Only formats 3 and 3.1 supported.")
        return

    end

    function isBitSet(value, position)

        return (value & (1 << position)) > 0

    end

    vts = Vertex[]
    fcs = Face{Int}[]

    nV = length(json["vertices"])

    for i=1:3:nV
        push!(vts, Vertex(json["vertices"][i], json["vertices"][i+1], json["vertices"][i+2]))
    end

    i = 1
    zLength = length(json["faces"])

    while i <= zLength
        facetype = json["faces"][i]
        i += 1
        isQuad              = isBitSet(facetype, 0)
        hasMaterial         = isBitSet(facetype, 1)
        hasFaceUv           = isBitSet(facetype, 2)
        hasFaceVertexUv     = isBitSet(facetype, 3)
        hasFaceNormal       = isBitSet(facetype, 4)
        hasFaceVertexNormal = isBitSet(facetype, 5)
        hasFaceColor        = isBitSet(facetype, 6)
        hasFaceVertexColor  = isBitSet(facetype, 7)

        if isQuad
            # convert quad to two tri
            push!(fcs, Face{Int}(json["faces"][i]+1, json["faces"][i+1]+1, json["faces"][i+2]+1))
            push!(fcs, Face{Int}(json["faces"][i]+1, json["faces"][i+2]+1, json["faces"][i+3]+1))
            i += 4
            nVertices = 4
        else
            push!(fcs, Face{Int}(json["faces"][i]+1, json["faces"][i+1]+1, json["faces"][i+2]+1))
            i += 3
            nVertices = 3
        end

        if hasMaterial
            i += 1
        end

        if hasFaceUv
            i += 1
        end

        if hasFaceVertexUv
            i += nVertices
        end

        if hasFaceNormal
            i += 1
        end

        if hasFaceVertexNormal
            i += nVertices
        end

        if hasFaceColor
            i += 1
        end

        if hasFaceVertexColor
            i += nVertices
        end

    end

    topology = false

    return AbstractMesh{Vertex, Face{Int}}(vts, fcs, topology)
end
