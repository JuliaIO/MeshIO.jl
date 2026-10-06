# `save` of a GLB is the inverse of `load`: what comes back is what went in,
# attribute for attribute, material for material, texture pixel for pixel.

using ColorTypes: RGBA, N0f8

corners(m, attr) = [attr[f[k]] for f in faces(m) for k in 1:3]

pos = [Point3f(0, 0, 0), Point3f(1, 0, 0), Point3f(0, 1, 0), Point3f(0, 0, 1)]
fcs = [GLTriangleFace(1, 2, 3), GLTriangleFace(1, 2, 4)]
nrm = [Vec3f(0, 0, 1), Vec3f(0, 0, 1), Vec3f(0, 0, 1), Vec3f(0, 1, 0)]
uvs = [Vec2f(0, 0), Vec2f(1, 0), Vec2f(0, 1), Vec2f(0.5, 0.5)]
col = [Vec4f(1, 0, 0, 1), Vec4f(0, 1, 0, 1), Vec4f(0, 0, 1, 1), Vec4f(1, 1, 1, 1)]
tex = [RGBA{N0f8}(x / 4, y / 4, 0.5, 1) for x in 1:4, y in 1:4]

mktempdir() do dir
    @testset "one view comes back vertex for vertex" begin
        m = GeometryBasics.Mesh(pos, fcs; normal = nrm, uv = uvs, color = col)
        save(joinpath(dir, "one.glb"), m)
        b = GeometryBasics.Mesh(load(joinpath(dir, "one.glb")))
        va = GeometryBasics.vertex_attributes(b)
        @test coordinates(b) ≈ pos
        @test faces(b) == fcs
        @test va[:normal] ≈ nrm
        @test va[:uv] ≈ uvs
        @test va[:color] ≈ col
    end

    @testset "views, materials and embedded textures" begin
        m = GeometryBasics.Mesh(pos, fcs; normal = nrm, uv = uvs, color = col, views = [1:1, 2:2])
        mats = Dict{String,Any}(
            "a" => Dict{String,Any}("diffuse map" => Dict{String,Any}("image" => tex),
                                    "metallic" => 0f0, "roughness" => 0.8f0, "double sided" => true),
            "b" => Dict{String,Any}("diffuse" => Vec3f(0.2, 0.3, 0.4), "alpha" => 1f0))
        save(joinpath(dir, "two.glb"),
             MetaMesh(m, Dict{Symbol,Any}(:materials => mats, :material_names => ["a", "b"])))
        back = load(joinpath(dir, "two.glb"))
        b = GeometryBasics.Mesh(back)
        va = GeometryBasics.vertex_attributes(b)
        # Each primitive carries its own vertices, so compare per face corner.
        @test corners(b, coordinates(b)) ≈ corners(m, pos)
        @test corners(b, va[:uv]) ≈ corners(m, uvs)
        @test corners(b, va[:color]) ≈ corners(m, col)
        @test b.views == [1:1, 2:2]
        @test back[:material_names] == ["a", "b"]
        @test back[:materials]["a"]["diffuse map"]["image"] == tex
        @test back[:materials]["a"]["roughness"] == 0.8f0
        @test back[:materials]["a"]["double sided"] == true
        @test back[:materials]["b"]["diffuse"] ≈ Vec3f(0.2, 0.3, 0.4)
    end

    @testset "PLY keeps vertex colours, ASCII and binary" begin
        m = GeometryBasics.Mesh(pos, fcs; normal = nrm, color = col)
        save(joinpath(dir, "a.ply"), m)
        save(File{format"PLY_BINARY"}(joinpath(dir, "b.ply")), m)
        for f in ("a.ply", "b.ply")
            b = load(joinpath(dir, f))
            @test coordinates(b) ≈ pos
            @test GeometryBasics.vertex_attributes(b)[:color] ≈ col
            @test GeometryBasics.vertex_attributes(b)[:normal] ≈ nrm
        end
    end
end
