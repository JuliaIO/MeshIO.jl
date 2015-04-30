# http://en.wikipedia.org/wiki/Additive_Manufacturing_File_Format

function importAMF(io::IO; topology=false)
    str = readall(io)
    xml = parse_string(str)
    xml_root = root(xml)
    object = find_element(xml_root, "object")
    mesh = find_element(object, "mesh")
    vertices = find_element(mesh, "vertices")
    volumes = get_elements_by_tagname(mesh, "volume")

    vts = Vertex[]

    for vertex in child_elements(vertices)
        coords = find_element(vertex, "coordinates")
        x = content(find_element(coords, "x"))
        y = content(find_element(coords, "y"))
        z = content(find_element(coords, "z"))
        push!(vts, Vertex(float64(x), float64(y), float64(z)))
    end

    meshes = Mesh{Vertex, Face{Int}}[]

    for volume in volumes
        fcs = Face{Int}[]
        triangles = get_elements_by_tagname(volume, "triangle")
        for triangle in triangles
            v1 = content(find_element(triangle, "v1"))
            v2 = content(find_element(triangle, "v2"))
            v3 = content(find_element(triangle, "v3"))
            push!(fcs, Face{Int}(int(v1), int(v2), int(v3)))
        end
        push!(meshes, Mesh(vts, fcs))
    end
    return meshes
end

