##############################
#
# obj-Files
#
##############################

function load{MT <: AbstractMesh}(io::Stream{format"OBJ"}, MeshType::Type{MT} = GLNormalMesh)
    io           = stream(io)
    lineNumber   = 1
    Tv, Tn, Tuv, Tf = vertextype(MT), normaltype(MT), texturecoordinatetype(MT), facetype(MT)
    v, n, uv, f  = Tv[], Tn[], Tuv[], Tf[]
    last_command = ""
    attrib_type  = nothing
    for line in eachline(io)
        # read a line, remove newline and leading/trailing whitespaces
        line = strip(chomp(line))
        if !startswith(line, "#") && !isempty(line) && !all(iscntrl, line) #ignore comments
            lines   = split(line)
            command = shift!(lines) #first is the command, rest the data
            if command in ("v", "vn", "vt")
                length(lines) == 2 && push!(lines, "0.0") # length can be two, but obj normaly does three coordinates with the third equals 0.
                numbers = map(i-> parse(Float32, lines[i]), Vec(1,2,3))
                if "v" == command # mesh always has vertices
                    push!(v, numbers) # should automatically convert to the right type in vertices(mesh)
                elseif "vn" == command && hasnormals(MT)
                    push!(n, numbers)
                elseif "vt" == command && hastexturecoordinates(MT)
                    push!(uv, numbers)
                end
            elseif "f" == command
                fs = if any(x-> contains(x, "/"), lines)
                    process_face_uv_or_normal(lines)
                elseif any(x->contains(x, "//"), lines)
                    process_face_normal(lines)
                else
                    push!(f, triangulated_faces(Tf, lines)...)
                    continue
                end
                push!(f, triangulated_faces(Tf, map(first, fs))...)
            else
                #TODO
            end
        end
        # read next line
        lineNumber += 1
    end
    attributes = Dict{Symbol, Any}()
    !isempty(f) && (attributes[:faces] = f)
    !isempty(v) && (attributes[:vertices] = v)
    if !isempty(n)
        if length(v) != length(n) # these are not per vertex normals, which we
            # can't deal with at the moment
            n = normals(v, f, Tn)
        end
        attributes[:normals] = n
    end
    !isempty(uv) && (attributes[:texturecoordinates] = uv)

    return MT(GeometryTypes.homogenousmesh(attributes))
end


immutable SplitFunctor
    seperator::Compat.UTF8String
end
@compat (s::SplitFunctor)(array) = split(array, s.seperator)

# of form "f v1 v2 v3 ....""
process_face{S <: AbstractString}(lines::Vector{S}) = (lines,) # just put it in the same format as the others
# of form "f v1//vn1 v2//vn2 v3//vn3 ..."
process_face_normal{S <: AbstractString}(lines::Vector{S}) = map(SplitFunctor("//"), lines)
# of form "f v1/vt1 v2/vt2 v3/vt3 ..." or of form "f v1/vt1/vn1 v2/vt2/vn2 v3/vt3/vn3 ...."
process_face_uv_or_normal{S <: AbstractString}(lines::Vector{S}) = map(SplitFunctor("/"), lines)


function triangulated_faces{Tf}(::Type{Tf}, vertex_indices::Vector)
    parsed = map(x-> parse(UInt32, x), vertex_indices)
    poly_face = Face(parsed...)
    decompose(Tf, poly_face)
end
