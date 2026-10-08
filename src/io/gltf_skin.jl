##############################
#
# glTF scene graph, skins and animations
#
##############################

"""
    gltf_decompose_trs(m::Mat4f) -> (translation, rotation, scale)

Split a transform into TRS, with `rotation` as `Vec4f(x, y, z, w)`. A bone given
as a `matrix` needs this: an animation overwrites its TRS, so it cannot stay a
matrix. A mirrored transform has no rotation; the x axis takes the flip as a
negative scale.
"""
function gltf_decompose_trs(m::Mat4f)
    c1 = Vec3f(m[1, 1], m[2, 1], m[3, 1])
    c2 = Vec3f(m[1, 2], m[2, 2], m[3, 2])
    c3 = Vec3f(m[1, 3], m[2, 3], m[3, 3])
    s = Vec3f(norm(c1), norm(c2), norm(c3))
    if dot(c1, cross(c2, c3)) < 0
        s = s .* Vec3f(-1, 1, 1)
    end
    # A zero-scaled axis has no direction left; keep the unit axis.
    axis(c, s, e) = s == 0 ? e : c / s
    R = Mat3f(axis(c1, s[1], Vec3f(1, 0, 0))..., axis(c2, s[2], Vec3f(0, 1, 0))...,
              axis(c3, s[3], Vec3f(0, 0, 1))...)
    return Vec3f(m[1, 4], m[2, 4], m[3, 4]), gltf_rotationquaternion(R), s
end

"A rotation matrix as glTF's `(x, y, z, w)` quaternion."
function gltf_rotationquaternion(A::Mat3f)
    t = A[1, 1] + A[2, 2] + A[3, 3]
    if t > 0
        s = sqrt(t + 1f0) * 2
        return Vec4f((A[3, 2] - A[2, 3]) / s, (A[1, 3] - A[3, 1]) / s, (A[2, 1] - A[1, 2]) / s, s / 4)
    elseif A[1, 1] > A[2, 2] && A[1, 1] > A[3, 3]
        s = sqrt(1f0 + A[1, 1] - A[2, 2] - A[3, 3]) * 2
        return Vec4f(s / 4, (A[1, 2] + A[2, 1]) / s, (A[1, 3] + A[3, 1]) / s, (A[3, 2] - A[2, 3]) / s)
    elseif A[2, 2] > A[3, 3]
        s = sqrt(1f0 + A[2, 2] - A[1, 1] - A[3, 3]) * 2
        return Vec4f((A[1, 2] + A[2, 1]) / s, s / 4, (A[2, 3] + A[3, 2]) / s, (A[1, 3] - A[3, 1]) / s)
    else
        s = sqrt(1f0 + A[3, 3] - A[1, 1] - A[2, 2]) * 2
        return Vec4f((A[1, 3] + A[3, 1]) / s, (A[2, 3] + A[3, 2]) / s, s / 4, (A[2, 1] - A[1, 2]) / s)
    end
end

"A node's own transform as TRS; a `matrix` is decomposed."
function gltf_node_trs(node)
    haskey(node, :matrix) && return gltf_decompose_trs(gltf_node_transform(node))
    return Vec3f(get(node, :translation, (0, 0, 0))...), Vec4f(get(node, :rotation, (0, 0, 0, 1))...),
           Vec3f(get(node, :scale, (1, 1, 1))...)
end

"""
    gltf_node_table(gltf) -> (; parents, translation, rotation, scale, names)

Every node, flat and 1-based: `parents[i]` is node `i`'s parent (0 for a root),
TRS as authored. Animation targets nodes, so this is what node clips index.
"""
function gltf_node_table(gltf)
    nodes = get(gltf, :nodes, ())
    parents = zeros(Int32, length(nodes))
    for (i, node) in enumerate(nodes), c in get(node, :children, ())
        parents[c + 1] = i
    end
    trs = [gltf_node_trs(node) for node in nodes]
    return (; parents, translation = Vec3f[t[1] for t in trs], rotation = Vec4f[t[2] for t in trs],
              scale = Vec3f[t[3] for t in trs],
              names = String[get(node, :name, "node_$(i - 1)") for (i, node) in enumerate(nodes)])
end

"""
The transform of everything above `node`, root first. A rig's root joint often
hangs off a non-joint node (an armature carrying a scale), which the inverse
bind matrices already account for.
"""
function gltf_ancestor_transform(gltf, parents::Vector{Int32}, node::Integer)
    m = IDENTITY_MAT4F
    p = parents[node]
    while p != 0
        m = gltf_node_transform(gltf.nodes[p]) * m
        p = parents[p]
    end
    return m
end

"""
    gltf_node_animations(gltf, binary_data, base_path) -> Vector

Every animation as `(; name, tracks, duration)`, each track
`(; node, property, times, values, interpolation)` with `node` indexing
[`gltf_node_table`](@ref). Morph target `weights` channels are skipped.
"""
function gltf_node_animations(gltf, binary_data::Vector{UInt8}, base_path)
    clips = NamedTuple[]
    for (ai, anim) in enumerate(get(gltf, :animations, ()))
        name = String(get(anim, :name, "animation_$ai"))
        tracks = NamedTuple[]
        for channel in anim.channels
            property = Symbol(channel.target.path)
            haskey(channel.target, :node) && property in (:translation, :rotation, :scale) || continue
            curve = gltf_sampler_curve(gltf, binary_data, base_path, anim.samplers[channel.sampler + 1],
                                       property, name)
            isnothing(curve) || push!(tracks, (; node = channel.target.node + 1, property, curve...))
        end
        isempty(tracks) || push!(clips, gltf_clip(name, tracks))
    end
    return clips
end

gltf_clip(name, tracks) = (; name, tracks, duration = maximum(t -> last(t.times), tracks))

"""
One sampler's `(; times, values, interpolation)`, or `nothing` for a malformed
channel. CUBICSPLINE keeps its key values and is read as linear.
"""
function gltf_sampler_curve(gltf, binary_data, base_path, sampler, property::Symbol, clip)
    times = Float32.(gltf_accessor_data(gltf, binary_data, base_path, sampler.input))
    raw = gltf_accessor_data(gltf, binary_data, base_path, sampler.output)
    interpolation = Symbol(lowercase(get(sampler, :interpolation, "LINEAR")))
    if interpolation === :cubicspline
        @warn "glTF animation $clip: CUBICSPLINE is read as LINEAR; tangents are ignored." maxlog = 1
        raw, interpolation = raw[2:3:end], :linear
    end
    values = property === :rotation ? Vec4f.(raw) : Vec3f.(raw)
    length(values) == length(times) && return (; times, values, interpolation)
    @warn "glTF animation $clip: a channel has $(length(times)) times and $(length(values)) values; skipped." maxlog = 3
    return nothing
end

"""
    gltf_skeleton(gltf, binary_data, base_path, skin, table, up_matrix)
        -> (skeleton, joint_remap, node_to_bone)

A skin as plain data, its bones sorted parents first (glTF does not promise
that order). `joint_remap[k]` is the bone of the skin's `k`-th joint, which is
what `JOINTS_0` indexes; `node_to_bone` maps table nodes to bones.

`up_matrix` goes on the skeleton's `root`, not into the vertices: the inverse
bind matrices would undo it there.
"""
function gltf_skeleton(gltf, binary_data::Vector{UInt8}, base_path, skin, table, up_matrix::Mat4f)
    joints = Int.(skin.joints) .+ 1
    n = length(joints)
    inverse_binds = haskey(skin, :inverseBindMatrices) ?
        [Mat4f(m...) for m in gltf_accessor_data(gltf, binary_data, base_path, skin.inverseBindMatrices)] :
        fill(IDENTITY_MAT4F, n)
    length(inverse_binds) == n ||
        error("glTF skin has $n joints but $(length(inverse_binds)) inverse bind matrices")

    position = Dict(node => k for (k, node) in enumerate(joints))
    parentjoint(k) = get(position, table.parents[joints[k]], 0)
    order = Int[]
    visited = falses(n)
    function emit!(k)
        visited[k] && return
        visited[k] = true
        parentjoint(k) == 0 || emit!(parentjoint(k))
        push!(order, k)
    end
    foreach(emit!, 1:n)
    joint_remap = Int32.(invperm(order))

    parents = Int32[parentjoint(k) == 0 ? 0 : joint_remap[parentjoint(k)] for k in order]
    nodes = joints[order]
    root = up_matrix * gltf_ancestor_transform(gltf, table.parents, nodes[findfirst(iszero, parents)])
    skeleton = (; parents, translation = table.translation[nodes], rotation = table.rotation[nodes],
                  scale = table.scale[nodes], inverse_bind = inverse_binds[order],
                  names = table.names[nodes], root)
    return skeleton, joint_remap, Dict(zip(joints, Int.(joint_remap)))
end

"""
The node clips' channels on a skin's joints, by bone: what a skeleton is posed
from. Channels on other nodes (a camera, a prop) stay in the node clips.
"""
function gltf_bone_animations(node_clips, node_to_bone::Dict{Int, Int})
    clips = NamedTuple[]
    for clip in node_clips
        tracks = NamedTuple[(; bone = node_to_bone[t.node], t.property, t.times, t.values, t.interpolation)
                            for t in clip.tracks if haskey(node_to_bone, t.node)]
        isempty(tracks) || push!(clips, gltf_clip(clip.name, tracks))
    end
    return clips
end
