using LightXML
using Base.Iterators: partition
using Compat

function only(x)
    state = start(x)
    @assert !done(x, state)
    i, state = next(x, state)
    @assert done(x, state)
    i
end

only(x::AbstractArray) = (@assert length(x) == 1; first(x))

function find_source(mesh::XMLElement, source_label::AbstractString)
    @assert source_label[1] == '#'
    only(filter(get_elements_by_tagname(mesh, "source")) do source
        attribute(source, "id") == source_label[2:end]
    end)
end

function read_source(::Type{V}, source::XMLElement) where {T, V <: AbstractVector{T}}
    N = length(V)
    array = find_element(source, "float_array")
    result = Vector{V}(undef,
        convert(Int, parse(Int, attribute(array, "count")) / N))
    i = 1
    for values in partition(split(content(array), ' '), N)
        result[i] = let values = values
            V(ntuple(i -> parse(T, values[i]), Val(N)))
        end
        i += 1
    end
    @assert i == length(result) + 1
    result
end

function read_polylist(polylist::XMLElement)
    count = parse(Int, attribute(polylist, "count"))
    inputs = get_elements_by_tagname(polylist, "input")
    V = Face{3, OffsetInteger{-1, Int32}}
    offsets = parse.(Int, attribute.(inputs, "offset"))
    width = maximum(offsets) + 1
    vectors = [Vector{V}(undef, count) for i in inputs]
    i = 1
    for values in partition(split(content(find_element(polylist, "p")), ' '), 3 * width)
        for j in 1:length(vectors)
            offset = offsets[j]
            vectors[j][i] = V(ntuple(k -> 1 + parse(Int32, values[(k - 1) * width + offset + 1]), Val(3)))
        end
        i += 1
    end
    @assert i == length(vectors[1]) + 1 == length(vectors[2]) + 1
    Dict{String, Vector{V}}(zip(attribute.(inputs, "semantic"), vectors))
end

function load(io::Stream{format"DAE"}, MeshType::Type{MT} = GLNormalMesh) where {MT <: AbstractMesh}
    doc = parse_string(read(stream(io), String))
    xml = root(doc)
    @assert name(xml) == "COLLADA"
    geometry = find_element(find_element(xml, "library_geometries"), "geometry")
    mesh = find_element(geometry, "mesh")
    vertices = find_element(mesh, "vertices")
    position_input = only(Iterators.filter(child_elements(vertices)) do input
        attribute(input, "semantic") == "POSITION"
    end)
    position_source = find_source(mesh, attribute(position_input, "source"))
    positions = read_source(Point{3, Float32}, position_source)



    polylist = find_element(mesh, "polylist")
    semantics = read_polylist(polylist)
    normal_input = only(Iterators.filter(child_elements(polylist)) do input
        attribute(input, "semantic") == "NORMAL"
    end)
    normal_source = find_source(mesh, attribute(normal_input, "source"))
    normals = read_source(Normal{3, Float32}, normal_source)
    face_normals = semantics["NORMAL"]

    normals_in_vertex_order = Vector{eltype(normals)}(undef, length(positions))
    for (fv, fn) in zip(semantics["VERTEX"], semantics["NORMAL"])
        for i in 1:3
            normals_in_vertex_order[fv[i]] = normals[fn[i]]
        end
    end

    MT(GLNormalMesh(vertices=positions, faces=semantics["VERTEX"], normals=normals_in_vertex_order))
end


