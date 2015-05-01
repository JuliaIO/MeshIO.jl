using MeshIO, FileIO, GeometryTypes, ColorTypes, Meshes
using GLVisualize, GLAbstraction, Meshes, MeshIO, GeometryTypes, Reactive, ModernGL

using Base.Test
typealias Vec3 Vector3{Float32}

dirlen 	= 1f0
baselen = 0.02f0
mesh 	= [
	(Cube(Vec3(baselen), Vec3(dirlen, baselen, baselen)), RGBA(1f0,0f0,0f0,1f0)), 
	(Cube(Vec3(baselen), Vec3(baselen, dirlen, baselen)), RGBA(0f0,1f0,0f0,1f0)), 
	(Cube(Vec3(baselen), Vec3(baselen, baselen, dirlen)), RGBA(0f0,0f0,1f0,1f0))
]
mesh = merge(map(GLNormalMesh, mesh))

write(mesh, file"test.ply_ascii")
write(mesh, file"test.ply_binary")

msh = read(file"bunny.ply_ascii")

msh2 = GLNormalMesh(file"test.ply_ascii")

robj = visualize(msh2)

push!(GLVisualize.ROOT_SCREEN.renderlist, robj)

renderloop()