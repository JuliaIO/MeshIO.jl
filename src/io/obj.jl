##############################
#
# obj-Files
#
##############################

function load{MT <: AbstractMesh}(io::Stream{format"OBJ"}, MeshType::Type{MT}=GLNormalMesh)
    io           = stream(io)
    lineNumber   = 1
    Tv,Tn,Tuv,Tf = vertextype(MT), normaltype(MT), texturecoordinatetype(MT), facetype(MT)
    v,n,uv,f     = Tv[], Tn[], Tuv[], Tf[]
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
                push!(v, Point{3, Float32}(lines)) # should automatically convert to the right type in vertices(mesh)
            elseif "vn" == command && hasnormals(MT)
                push!(n, Normal{3, Float32}(lines))
            elseif "vt" == command && hastexturecoordinates(MT)
                length(lines) == 2 && push!(lines, "0.0") # length can be two, but obj normaly does three coordinates with the third equals 0.
                push!(uv, UVW{Float32}(lines))
            elseif "f" == command #mesh always has faces
                if any(x->contains(x, "/"), lines)
                    fs = process_face_uv_or_normal(lines)
                elseif any(x->contains(x, "//"), lines)
                    fs = process_face_normal(lines)
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

    return MT(HomogenousMesh(attributes))
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

immutable ParseFunctor{T}
    T::Type{T}
end
@compat (::ParseFunctor{T}){T}(x) = parse(T, x)

function triangulated_faces{Tf}(::Type{Tf}, vertex_indices::Vector{SubString{Compat.ASCIIString}})
    poly_face = Face{length(vertex_indices), UInt32, 0}(map(ParseFunctor(UInt32), vertex_indices))
    decompose(Tf, poly_face)
end
