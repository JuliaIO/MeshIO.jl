##############################
#
# glTF skins, skeletons and animations
#
##############################

"""
    gltf_decompose_trs(m::Mat4f) -> (translation, rotation, scale)

Split a transform into TRS, with `rotation` as
`Vec4f(x, y, z, w)`.

Needed for a node that gives a `matrix` instead of TRS, and for pushing the
file's up-axis rotation onto the root bones. A mesh can bake such a matrix into
its vertices; a bone cannot, because its transform is what an animation
overwrites.

A negative determinant is a mirrored transform, which no rotation can express;
the x axis absorbs the flip as a negative scale, keeping R a true rotation.
"""
function gltf_decompose_trs(m::Mat4f)
    translation = Vec3f(m[1, 4], m[2, 4], m[3, 4])
    c1 = Vec3f(m[1, 1], m[2, 1], m[3, 1])
    c2 = Vec3f(m[1, 2], m[2, 2], m[3, 2])
    c3 = Vec3f(m[1, 3], m[2, 3], m[3, 3])
    sx, sy, sz = norm(c1), norm(c2), norm(c3)
    det3 = dot(c1, cross(c2, c3))
    if det3 < 0
        sx = -sx
        c1 = -c1
    end
    # A zero-scaled axis has no direction left to recover; keep the axis rather
    # than dividing by zero.
    r1 = sx == 0 ? Vec3f(1, 0, 0) : c1 / sx
    r2 = sy == 0 ? Vec3f(0, 1, 0) : c2 / sy
    r3 = sz == 0 ? Vec3f(0, 0, 1) : c3 / sz
    R = GeometryBasics.Mat3f(r1[1], r1[2], r1[3], r2[1], r2[2], r2[3], r3[1], r3[2], r3[3])
    return translation, gltf_rotationquaternion(R), Vec3f(sx, sy, sz)
end

"Convert a rotation matrix to glTF's `(x, y, z, w)` quaternion order."
function gltf_rotationquaternion(A::Mat3f)
    t = A[1, 1] + A[2, 2] + A[3, 3]
    if t > 0
        s = sqrt(t + 1f0) * 2
        return Vec4f((A[3,2]-A[2,3])/s, (A[1,3]-A[3,1])/s,
                     (A[2,1]-A[1,2])/s, 0.25f0*s)
    elseif A[1,1] > A[2,2] && A[1,1] > A[3,3]
        s = sqrt(1f0 + A[1,1] - A[2,2] - A[3,3]) * 2
        return Vec4f(0.25f0*s, (A[1,2]+A[2,1])/s,
                     (A[1,3]+A[3,1])/s, (A[3,2]-A[2,3])/s)
    elseif A[2,2] > A[3,3]
        s = sqrt(1f0 + A[2,2] - A[1,1] - A[3,3]) * 2
        return Vec4f((A[1,2]+A[2,1])/s, 0.25f0*s,
                     (A[2,3]+A[3,2])/s, (A[1,3]-A[3,1])/s)
    else
        s = sqrt(1f0 + A[3,3] - A[1,1] - A[2,2]) * 2
        return Vec4f((A[1,3]+A[3,1])/s, (A[2,3]+A[3,2])/s,
                     0.25f0*s, (A[2,1]-A[1,2])/s)
    end
end

"""
    gltf_node_parents(gltf) -> Dict{Int, Int}

Child node index to parent node index, both 0-based. glTF names children and
never parents, so this is the one scan that inverts it.
"""
function gltf_node_parents(gltf)
    parents = Dict{Int, Int}()
    haskey(gltf, :nodes) || return parents
    for (i, node) in enumerate(gltf.nodes)
        haskey(node, :children) || continue
        for c in node.children
            parents[Int(c)] = i - 1
        end
    end
    return parents
end

"""
    gltf_node_trs(node) -> (translation, rotation, scale)

A node's own transform as TRS. A node may give either TRS or a `matrix`; the
matrix form is decomposed (see [`gltf_decompose_trs`](@ref)).
"""
function gltf_node_trs(node)
    if haskey(node, :matrix)
        return gltf_decompose_trs(gltf_node_transform(node))
    end
    t = haskey(node, :translation) ? Vec3f(node.translation...) : Vec3f(0, 0, 0)
    r = haskey(node, :rotation) ? Vec4f(node.rotation...) : Vec4f(0, 0, 0, 1)
    s = haskey(node, :scale) ? Vec3f(node.scale...) : Vec3f(1, 1, 1)
    return t, r, s
end

"""
    gltf_ancestor_transform(gltf, node_parents, node_idx) -> Mat4f

The accumulated transform of everything above `node_idx`, from the scene root
down to its parent.

A skeleton's root joint usually hangs off a node that is not itself a joint — an
armature object, say, carrying a scale. That node is not in `skin.joints`, so
walking the joint hierarchy alone drops it while the inverse bind matrices still
carry the matching factor, and the mesh comes out scaled wrong in an otherwise
correct pose.
"""
function gltf_ancestor_transform(gltf, node_parents::Dict{Int, Int}, node_idx::Int)
    chain = Int[]
    cur = node_idx
    while haskey(node_parents, cur)
        cur = node_parents[cur]
        push!(chain, cur)
    end
    m = IDENTITY_MAT4F
    # Top-down: the scene root is the last one found walking up.
    for node in Iterators.reverse(chain)
        m = m * gltf_node_transform(gltf.nodes[node + 1])
    end
    return m
end


"""
    gltf_node_table(gltf) -> NamedTuple

Every node in the file, flat, with `parents` indexing the same vectors (0 for a
root) and TRS as authored.

This is glTF's scene graph, and it is what animation is defined against: a
channel targets a NODE, not a bone. A skin is then a list of node indices, a
light or a camera hangs off a node, and an instance is a node that names a mesh.
Carrying the table means none of those have to be resolved away at load time.
"""
function gltf_node_table(gltf)
    haskey(gltf, :nodes) || return (; parents = Int32[], translation = Vec3f[],
                                      rotation = Vec4f[], scale = Vec3f[], names = String[])
    n = length(gltf.nodes)
    parents = zeros(Int32, n)
    for (i, node) in enumerate(gltf.nodes), c in get(node, :children, ())
        parents[Int(c) + 1] = Int32(i)
    end
    translation = Vector{Vec3f}(undef, n)
    rotation = Vector{Vec4f}(undef, n)
    scale = Vector{Vec3f}(undef, n)
    names = Vector{String}(undef, n)
    for (i, node) in enumerate(gltf.nodes)
        translation[i], rotation[i], scale[i] = gltf_node_trs(node)
        names[i] = String(get(node, :name, "node_$(i - 1)"))
    end
    return (; parents, translation, rotation, scale, names)
end

"""
    gltf_node_animations(gltf, binary_data, base_path) -> Vector

Every animation in the file, with its channels kept as authored — targeting node
indices into [`gltf_node_table`](@ref), 1-based.

Nothing is dropped for being aimed at something other than a joint, which is
what the skeleton-indexed reader below does: an animated camera, light or prop
is a channel like any other. `BoxAnimated` is exactly two such channels, and it
used to load with no animation at all.
"""
function gltf_node_animations(gltf, binary_data::Vector{UInt8}, base_path)
    clips = NamedTuple[]
    haskey(gltf, :animations) || return clips
    for (ai, anim) in enumerate(gltf.animations)
        tracks = NamedTuple[]
        for channel in anim.channels
            target = channel.target
            haskey(target, :node) || continue
            path = Symbol(target.path)
            path in (:translation, :rotation, :scale) || continue
            times, values, interpolation =
                gltf_sampler_curve(gltf, binary_data, base_path,
                                   anim.samplers[channel.sampler + 1], path, anim, ai)
            isnothing(times) && continue
            push!(tracks, (; node = Int(target.node) + 1, property = path,
                             times, values, interpolation))
        end
        isempty(tracks) && continue
        duration = maximum(t -> last(t.times), tracks)
        push!(clips, (; name = String(get(anim, :name, "animation_$ai")), tracks, duration))
    end
    return clips
end

"""
    gltf_sampler_curve(gltf, binary_data, base_path, sampler, path, anim, ai)

The keys of one animation sampler: `(times, values, interpolation)`, or
`(nothing, nothing, nothing)` if the channel is malformed and must be skipped.
"""
function gltf_sampler_curve(gltf, binary_data, base_path, sampler, path, anim, ai)
    times = Float32.(gltf_accessor_data(gltf, binary_data, base_path, sampler.input))
    raw = gltf_accessor_data(gltf, binary_data, base_path, sampler.output)
    interpolation = Symbol(lowercase(String(get(sampler, :interpolation, "LINEAR"))))
    if interpolation === :cubicspline
        # The output holds three values per key (in-tangent, value, out-tangent).
        # Reading it as keys would be silently wrong.
        @warn "glTF animation $(get(anim, :name, ai)): CUBICSPLINE is read as LINEAR " *
              "through its key values; tangents are ignored." maxlog = 1
        raw = raw[2:3:end]
        interpolation = :linear
    end
    values = path === :rotation ? [Vec4f(v...) for v in raw] : [Vec3f(v...) for v in raw]
    if length(values) != length(times)
        @warn "glTF animation $(get(anim, :name, ai)): a channel has $(length(times)) " *
              "times and $(length(values)) values; skipped." maxlog = 3
        return nothing, nothing, nothing
    end
    return times, values, interpolation
end

"""
    gltf_skeleton(gltf, binary_data, base_path, skin_idx, up_matrix)
        -> (skin, joint_remap, node_to_bone)

Read `gltf.skins[skin_idx + 1]` into plain constructor data.

`joint_remap[k]` is the bone index of the file's k-th joint, which is what a
vertex's `JOINTS_0` value indexes — that attribute points into the skin's joint
array, not at node indices. The runtime requires topologically ordered bones and
glTF does not promise that, so the sort happens here, where `joint_remap` can
carry the vertex data along with it.

`up_matrix` is pushed onto the root bones rather than baked into the vertices.
For a skinned mesh the two are not interchangeable: a vertex is placed by
`Σ wᵢ · worldᵢ · invbindᵢ · v`, so a rotation applied to every world matrix
rotates the result, while the same rotation applied to `v` is undone by the
inverse bind matrices.
"""
function gltf_skeleton(gltf, binary_data::Vector{UInt8}, base_path, skin_idx::Int,
                       up_matrix::Mat4f)
    skin = gltf.skins[skin_idx + 1]
    joint_nodes = Int.(skin.joints)
    n = length(joint_nodes)

    inverse_binds = if haskey(skin, :inverseBindMatrices)
        raw = gltf_accessor_data(gltf, binary_data, base_path, skin.inverseBindMatrices)
        [Mat4f(m...) for m in raw]
    else
        # Legal and rare: the bind pose is then the identity for every joint.
        fill(Mat4f(I), n)
    end
    length(inverse_binds) == n || error(
        "glTF skin $skin_idx has $n joints but $(length(inverse_binds)) inverse bind " *
        "matrices")

    node_parents = gltf_node_parents(gltf)
    joint_position = Dict(node => k for (k, node) in enumerate(joint_nodes))
    parent_joint(k) = get(joint_position, get(node_parents, joint_nodes[k], -1), 0)

    # Depth first from the roots, so a parent is always emitted before its
    # children — the runtime's ordering rule.
    order = Int[]
    visited = falses(n)
    function emit!(k::Int)
        visited[k] && return
        visited[k] = true
        pk = parent_joint(k)
        pk == 0 || emit!(pk)      # …the parent first, wherever it sits in the file
        push!(order, k)
        return
    end
    for k in 1:n
        emit!(k)
    end

    # The file's joint index to its bone index, and the only form of that mapping
    # this function keeps: `parents`, `node_to_bone` and the caller's vertex
    # remap are all reads of it.
    joint_remap = Vector{Int32}(undef, n)
    for (i, k) in enumerate(order)
        joint_remap[k] = i
    end

    parents = Vector{Int32}(undef, n)
    translation = Vector{Vec3f}(undef, n)
    rotation = Vector{Vec4f}(undef, n)
    scale = Vector{Vec3f}(undef, n)
    names = Vector{String}(undef, n)
    for (i, k) in enumerate(order)
        pk = parent_joint(k)
        parents[i] = pk == 0 ? Int32(0) : joint_remap[pk]
        node = gltf.nodes[joint_nodes[k] + 1]
        translation[i], rotation[i], scale[i] = gltf_node_trs(node)
        names[i] = String(get(node, :name, "bone_$(joint_nodes[k])"))
    end

    # Everything above the rig, on the skeleton rather than on a bone: the up
    # rotation and whatever static node the joints hang off. One skin is one
    # armature, so the ancestors of its roots are the same node.
    first_root = joint_nodes[order[findfirst(iszero, parents)]]
    root = up_matrix * gltf_ancestor_transform(gltf, node_parents, first_root)

    skeleton = (; parents, translation, rotation, scale,
                  inverse_bind = inverse_binds[order], names, root)
    node_to_bone = Dict(joint_nodes[k] => Int(joint_remap[k]) for k in 1:n)
    return skeleton, joint_remap, node_to_bone
end

"""
    gltf_animations(gltf, binary_data, base_path, node_to_bone) -> Vector

Every animation in the file, as clips over the skeleton's bone indices.

Channels aimed at a node that is not a joint of this skin are skipped — a file
may animate a camera or a prop in the same clip. `weights` channels (morph
targets) are skipped for the same reason.
"""
function gltf_animations(gltf, binary_data::Vector{UInt8}, base_path,
                         node_to_bone::Dict{Int, Int})
    clips = NamedTuple[]
    haskey(gltf, :animations) || return clips
    for (ai, anim) in enumerate(gltf.animations)
        tracks = NamedTuple[]
        for channel in anim.channels
            target = channel.target
            haskey(target, :node) || continue
            bone = get(node_to_bone, Int(target.node), 0)
            bone == 0 && continue
            path = Symbol(target.path)
            path in (:translation, :rotation, :scale) || continue

            times, values, interpolation =
                gltf_sampler_curve(gltf, binary_data, base_path,
                                   anim.samplers[channel.sampler + 1], path, anim, ai)
            isnothing(times) && continue
            push!(tracks, (; bone, property = path, times, values, interpolation))
        end
        isempty(tracks) && continue
        duration = maximum(t -> last(t.times), tracks)
        push!(clips, (; name = String(get(anim, :name, "animation_$ai")), tracks, duration))
    end
    return clips
end
