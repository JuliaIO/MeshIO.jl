# Represents a set of abaqus elements of the same type
immutable AbaqusElements
    numbers::Vector{Int}
    topology::Matrix{Int}
end

# Represents the nodes in the mesh
immutable AbaqusNodes
    numbers::Vector{Int}
    coordinates::Matrix{Float64}
end

# Represents the mesh
immutable AbaqusMesh
    nodes::AbaqusNodes
    elements::Dict{String, AbaqusElements}
    node_sets::Dict{String, Vector{Int}}
    element_sets::Dict{String, Vector{Int}}
end


iskeyword(l) = startswith(l, "*")

function load(fn::File{format"ABAQUS_INP"})
    open(fn) do s
        f = stream(s)
        node_numbers = Int[]
        coord_vec = Float64[]

        elements = Dict{String, AbaqusElements}()
        node_sets = Dict{String, Vector{Int}}()
        element_sets = Dict{String, Vector{Int}}()
        while !eof(f)
            header = eat_line(f)
            if header == ""
                continue
            end

            if ((m = match(r"\*Part, name=(.*)", header)) != nothing)

            elseif ((m = match(r"\*Node", header)) != nothing)
                while !iskeyword(peek_line(f))
                    l = strip(eat_line(f))
                    l == "" && continue
                    lsplit = split(l, [','])
                    n = parse(Int, lsplit[1])
                    c = [parse(Float64, x) for x in lsplit[2:end]]
                    push!(node_numbers, n)
                    append!(coord_vec, c)
                end

            elseif ((m = match(r"\*Element, type=(.*)", header)) != nothing)
                element_numbers = Int[]
                topology_vec = Int[]
                n_elements = 0
                while !iskeyword(peek_line(f))
                    n_elements += 1
                    l = strip(eat_line(f))
                    l == "" && continue
                    l_split = split(l, [','])
                    ele_data = [parse(Int, x) for x in l_split]
                    push!(element_numbers, ele_data[1])
                    append!(topology_vec, ele_data[2:end])
                end
                elements[m.captures[1]] = AbaqusElements(element_numbers,
                    reshape(topology_vec, length(topology_vec) ÷ n_elements, n_elements))

            elseif ((m = match(r"\*Elset, elset=(.*)", header)) != nothing)
                if endswith(m.captures[1], "generate")
                    lsplit = split(strip(eat_line(f)), [','])
                    start, stop, step = [parse(Int, x) for x in lsplit]
                    vertices = collect(start:step:stop)
                    elsetname = split(m.captures[1], [','])[1]
                else
                    buf = IOBuffer()
                    while !iskeyword(peek_line(f))
                        print(buf, eat_line(f))
                    end
                    buf_split = split(strip(takebuf_string(buf)), [','])
                    # Deal with annoying edge case when sets have 1 element
                    buf_split = buf_split[buf_split .!= ""]
                    vertices = [parse(Int, x) for x in buf_split]
                    elsetname = m.captures[1]
                end
                element_sets[elsetname] = vertices
            elseif ((m = match(r"\*Nset, nset=(.*)", header)) != nothing)
                if endswith(m.captures[1], "generate")
                    lsplit = split(strip(eat_line(f)), [','])
                    start, stop, step = [parse(Int, x) for x in lsplit]
                    nodes = collect(start:step:stop)
                    nodesetname = split(m.captures[1], [','])[1]
                else
                    buf = IOBuffer()
                    while !iskeyword(peek_line(f))
                        print(buf, eat_line(f))
                    end
                    buf_split = split(strip(takebuf_string(buf)), [','])
                    # Deal with annoying edge case when sets have 1 node
                    buf_split = buf_split[buf_split .!= ""]
                    nodes = [parse(Int, x) for x in buf_split]
                    nodesetname = m.captures[1]
                end
                node_sets[nodesetname] = nodes

            elseif ((m = match(r"\*End Part", header)) != nothing)
                l = eat_line(f)
            # Ignore unused keywords
            elseif iskeyword(peek_line(f))
                eat_line(f)
                while !iskeyword(peek_line(f))
                    eat_line(f)
                end
            else
                if eof(f)
                    break
                else
                    error("Unknown header: $header")
                end
            end
        end
        abaqus_nodes = AbaqusNodes(node_numbers, reshape(coord_vec, 3, length(coord_vec) ÷ 3))
        return AbaqusMesh(abaqus_nodes, elements, node_sets, element_sets)
    end
end



