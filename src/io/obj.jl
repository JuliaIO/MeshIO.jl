##############################
#
# obj-Files
#
##############################

function load{MT <: AbstractMesh}(io::Stream{format"OBJ"}, MeshType::Type{MT}=GLNormalMesh)
    io           = stream(io)
    lineNumber   = 1
    mesh         = MeshType()
    last_command = ""
    attrib_type  = nothing
    for line in eachline(io)
        # read a line, remove newline and leading/trailing whitespaces
        line = strip(chomp(line))
        !isvalid(line) && error("non valid ascii in obj")

        if !startswith(line, "#") && !isempty(line) && !iscntrl(line) #ignore comments
            lines   = split(line)
            command = shift!(lines) #first is the command, rest the data

            if "v" == command # mesh always has vertices
                push!(vertices(mesh), Point{3, Float32}(lines)) # should automatically convert to the right type in vertices(mesh)
            elseif "vn" == command && hasnormals(mesh)
                push!(normals(mesh), Normal{3, Float32}(lines))
            elseif "vt" == command && hastexturecoordinates(mesh)
                length(lines) == 2 && push!(lines, "0.0") # length can be two, but obj normaly does three coordinates with the third equals 0.
                push!(texturecoordinates(mesh), UVW{Float32}(lines))
            elseif "f" == command #mesh always has faces
                if any(x->contains(x, "/"), lines)
                    fs = process_face_uv_or_normal(lines)
                elseif any(x->contains(x, "//"), lines)
                    fs = process_face_normal(lines)
                else
                    return push!(faces(mesh), Triangle{Uint32}(lines))
                end
                push!(faces(mesh), Triangle{Uint32}(map(first, fs)))
            else
                #TODO
            end
        end
        # read next line
        lineNumber += 1
    end
    if isempty(mesh.normals) || length(mesh.normals) != length(mesh.vertices) # silly way of dealing with normals that are not per vertex.
        empty!(mesh.normals)
        append!(mesh.normals, normals(mesh.vertices, mesh.faces))
    end
    return mesh
end

# face indices are allowed to be negative, this methods handles this correctly
function handle_index{T <: Integer}(bufferlength::Integer, s::AbstractString, index_type::Type{T})
    i = parse(T, s)
    i < 0 && return convert(T, bufferlength) + i + one(T) # account for negative indexes
    return i
end
function push_index!{T}(buffer::Vector{T}, s::AbstractString)
    push!(buffer, handle_index(length(buffer), s, eltype(T)))
end

immutable SplitFunctor <: Base.Func{1}
    seperator::ASCIIString
end
call(s::SplitFunctor, array) = split(array, s.seperator)

# of form "f v1 v2 v3 ....""
process_face{S <: AbstractString}(lines::Vector{S}) = (lines,) # just put it in the same format as the others
# of form "f v1//vn1 v2//vn2 v3//vn3 ..."
process_face_normal{S <: AbstractString}(lines::Vector{S}) = map(SplitFunctor("//"), lines)
# of form "f v1/vt1 v2/vt2 v3/vt3 ..." or of form "f v1/vt1/vn1 v2/vt2/vn2 v3/vt3/vn3 ...."
process_face_uv_or_normal{S <: AbstractString}(lines::Vector{S}) = map(SplitFunctor("/"), lines)

