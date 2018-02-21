##############################
#
# obj-Files
#
##############################

function load{MT <: AbstractMesh}(io::Stream{format"OBJ"}, MeshType::Type{MT} = GLNormalMesh)
    Tv,Tn,Tuv,Tf = vertextype(MT), normaltype(MT), texturecoordinatetype(MT), facetype(MT)
    v,n,uv,f     = Tv[], Tn[], Tuv[], Tf[]
    f_uv_n_faces = (f, GLTriangle[], GLTriangle[])
    last_command = ""
    attrib_type  = nothing
    for full_line::String in eachline(stream(io))
        # read a line, remove newline and leading/trailing whitespaces
        line = strip(chomp(full_line))
        !isascii(line) && error("non valid ascii in obj")

        if !startswith(line, "#") && !isempty(line) && !all(iscntrl, line) #ignore comments
            lines   = split(line)
            command = shift!(lines) #first is the command, rest the data

            if "v" == command # mesh always has vertices
                push!(v, Point{3, Float32}(parse.(Float32, lines))) # should automatically convert to the right type in vertices(mesh)
            elseif "vn" == command && hasnormals(MT)
                push!(n, Normal{3, Float32}(parse.(Float32, lines)))
            elseif "vt" == command && hastexturecoordinates(MT)
                if length(lines) == 2
                    push!(uv, UV{Float32}(parse.(Float32, lines)))
                elseif length(lines) == 3
                    push!(uv, UVW{Float32}(parse.(Float32, lines)))
                else
                    error("Unknown UVW coordinate: $lines")
                end
            elseif "f" == command #mesh always has faces
                if any(x->contains(x, "//"), lines)
                    fs = process_face_normal(lines)
                elseif any(x->contains(x, "/"), lines)
                    fs = process_face_uv_or_normal(lines)
                else
                    append!(f, triangulated_faces(Tf, lines))
                    continue
                end
                for i = 1:length(first(fs))
                    append!(f_uv_n_faces[i], triangulated_faces(Tf, getindex.(fs, i)))
                end
            else
                #TODO
            end
        end
    end
    attributes = Dict{Symbol, Any}()
    !isempty(f) && (attributes[:faces] = f)
    !isempty(v) && (attributes[:vertices] = v)
    if !isempty(n)
        attributes[:normals] = if !isempty(f_uv_n_faces[3])
            _n = similar(v, eltype(n))
            for (vf, nf) in zip(f, f_uv_n_faces[3])
                for (vidx, nidx) in zip(vf, nf)
                    _n[vidx] = n[nidx]
                end
            end
            _n
        else
            # these are not per vertex normals, which we
            # can't deal with at the moment
            if length(v) != length(n)
                normals(v, f, Tn)
            else
                n
            end
        end
    end
    if !isempty(uv)
        attributes[:texturecoordinates] = if !isempty(f_uv_n_faces[2])
            _uv = similar(v, eltype(uv))
            for (vf, uvf) in zip(f, f_uv_n_faces[2])
                for (vidx, uvidx) in zip(vf, uvf)
                    _uv[vidx] = uv[uvidx]
                end
            end
            _uv
        else
            uv
        end
    end
    return MT(GeometryTypes.homogenousmesh(attributes))::MT
end

# of form "f v1 v2 v3 ....""
process_face{S <: AbstractString}(lines::Vector{S}) = (lines,) # just put it in the same format as the others
# of form "f v1//vn1 v2//vn2 v3//vn3 ..."
process_face_normal{S <: AbstractString}(lines::Vector{S}) = split.(lines, "//")
# of form "f v1/vt1 v2/vt2 v3/vt3 ..." or of form "f v1/vt1/vn1 v2/vt2/vn2 v3/vt3/vn3 ...."
process_face_uv_or_normal{S <: AbstractString}(lines::Vector{S}) = split.(lines, '/')

function triangulated_faces{Tf}(::Type{Tf}, vertex_indices::Vector{<:AbstractString})
    poly_face = Face{length(vertex_indices), UInt32}(parse.(UInt32, vertex_indices))
    decompose(Tf, poly_face)
end
