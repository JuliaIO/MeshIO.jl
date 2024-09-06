function load(fs::Stream{format"IFS"}; facetype=GLTriangleFace, pointtype=Point3f)
    io = stream(fs)
    function str()
        n = read(io, UInt32)
        String(read(io, UInt8, n))
    end
    name = str() # just skip name for now
    vertices = str()
    if vertices != "VERTICES\0"
        error("$(filename(fs)) does not seem to be of format IFS")
    end
    nverts = read(io, UInt32)
    verts_float = read(io, Float32, nverts * 3)
    verts = reinterpret(pointtype, verts_float)
    tris = str()
    if tris != "TRIANGLES\0"
        error("$(filename(fs)) does not seem to be of format IFS")
    end
    nfaces = read(io, UInt32)
    faces_int = read(io, UInt32, nfaces * 3)
    faces = reinterpret(facetype, faces_int)
    return GeometryBasics.mesh(vertices = verts, faces = faces)
end

function save(fs::Stream{format"IFS"}, msh::AbstractMesh; meshname = "mesh")
    io = stream(fs)
    function write0str(s)
        s0 = s * "\0"
        write(io, UInt32(length(s0)))
        write(io, s0)
    end
    vts = decompose(Point3f, msh)
    fcs = decompose(GLTriangleFace, msh)

    # write the header
    write0str("IFS")
    write(io, 1f0)
    write0str(meshname)

    write0str("VERTICES")
    write(io, UInt32(length(vts)))
    write(io, reinterpret(Float32, vts))

    write0str("TRIANGLES")
    write(io, UInt32(length(fcs)))
    write(io, reinterpret(UInt32, fcs))
end
