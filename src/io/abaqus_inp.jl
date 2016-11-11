# Represents a set of abaqus elements of the same type
type AbaqusElements
    numbers::Vector{Int}
    topology::Matrix{Int}
end

# Represents the nodes in the mesh
type AbaqusNodes
    numbers::Vector{Int}
    coordinates::Matrix{Float64}
end

# Represents the mesh
type AbaqusMesh
    nodes::AbaqusNodes
    elements::Dict{String, AbaqusElements}
    node_sets::Dict{String, Vector{Int}}
    element_sets::Dict{String, Vector{Int}}
end


iskeyword(l) = startswith(l, "*")

function get_string_block(f)
    data = split(readuntil(f, '*'), "\n")
    if data[end] == "*"
        deleteat!(data, length(data)) # Remove last *
        seek(f, position(f) - 1)
    end

    return data
end

function read_nodes!(f, node_numbers::Vector{Int}, coord_vec::Vector{Float64})
    node_data = get_string_block(f)
    for nodeline in node_data
        node = split(nodeline, ',', keep = false)
        length(node) == 1 && continue
        n = parse(Int, node[1])
        x = parse(Float64, node[2])
        y = parse(Float64, node[3])
        z = length(node) == 4 ? parse(Float64, node[4]) : 0.0
        push!(node_numbers, n)
        append!(coord_vec, (x, y, z))
    end
end

function read_elements!(f, elements, topology_vectors, element_number_vectors, element_type::AbstractString, element_set="", element_sets=nothing)
    if !haskey(topology_vectors, element_type)
        topology_vectors[element_type] = Int[]
        element_number_vectors[element_type] = Int[]
    end
    topology_vec = topology_vectors[element_type]
    element_numbers = element_number_vectors[element_type]

    element_data = get_string_block(f)
    for elementline in element_data
        element = split(elementline, ',', keep = false)
        length(element) == 0 && continue
        n = parse(Int, element[1])
        push!(element_numbers, n)
        vertices = [parse(Int, element[i]) for i in 2:length(element)]
        append!(topology_vec, vertices)
    end
    if element_set != ""
        element_sets[element_set] = copy(element_numbers)
    end
end

function read_set!(f, sets, setname::AbstractString)
    if endswith(setname, "generate")
        lsplit = split(strip(eat_line(f)), ',', keep = false)
        start, stop, step = [parse(Int, x) for x in lsplit]
        indices = collect(start:step:stop)
        setname = split(set_name, [','])[1]
    else
        data = get_string_block(f)
        indices = Int[]
        for line in data
            indices_str = split(line, ',', keep = false)
            for v in indices_str
                push!(indices, parse(Int, v))
            end
        end
    end
    sets[setname] = indices
end

function load(fn::File{format"ABAQUS_INP"})
    open(fn) do s
        f = stream(s)
        node_numbers = Int[]
        coord_vec = Float64[]

        topology_vectors = Dict{String, Vector{Int}}()
        element_number_vectors = Dict{String, Vector{Int}}()

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
                read_nodes!(f, node_numbers, coord_vec)
            elseif ((m = match(r"\*Element", header)) != nothing)
                if ((m = match(r"\*Element, type=(.*), ELSET=(.*)", header)) != nothing)
                    read_elements!(f, elements, topology_vectors, element_number_vectors,  m.captures[1], m.captures[2], element_sets)
                elseif ((m = match(r"\*Element, type=(.*), ELSET=(.*)", header)) != nothing)
                    read_elements!(f, elements, topology_vectors, element_number_vectors,  m.captures[1])
                end
            elseif ((m = match(r"\*Elset, elset=(.*)", header)) != nothing)
                read_set!(f, element_sets, m.captures[1])
            elseif ((m = match(r"\*Nset, nset=(.*)", header)) != nothing)
                read_set!(f, node_sets, m.captures[1])
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

        for element_type in keys(topology_vectors)
            topology_vec = topology_vectors[element_type]
            element_numbers = element_number_vectors[element_type]
            n_elements = length(element_numbers)
            elements[element_type] = AbaqusElements(element_numbers,
            reshape(topology_vec, length(topology_vec) ÷ n_elements, n_elements))
        end
        abaqus_nodes = AbaqusNodes(node_numbers, reshape(coord_vec, 3, length(coord_vec) ÷ 3))
        return AbaqusMesh(abaqus_nodes, elements, node_sets, element_sets)
    end
end
