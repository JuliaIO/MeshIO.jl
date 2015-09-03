using FileIO, FactCheck, GeometryTypes

typealias Vec3 Vec{3, Float32}


facts("MeshIO") do 
	dirlen 	= 1f0
	baselen = 0.02f0
	mesh 	= [
		Cube{Float32}(Vec3(baselen), Vec3(dirlen, baselen, baselen)), 
		Cube{Float32}(Vec3(baselen), Vec3(baselen, dirlen, baselen)), 
		Cube{Float32}(Vec3(baselen), Vec3(baselen, baselen, dirlen))
	]
	mesh = merge(map(GLPlainMesh, mesh))
	mktempdir() do tmpdir
		for ext in ["2dm", "off"]
			context("load save $ext") do
				save(joinpath(tmpdir, "test.$ext"), mesh)
				mesh_loaded = GLPlainMesh(joinpath(tmpdir, "test.$ext"))
				@fact mesh_loaded --> mesh
			end
		end
		context("PLY ascii and binary") do
			f = File(format"PLY_ASCII", joinpath(tmpdir, "test.ply"))
			save(f, mesh)
			mesh_loaded = GLPlainMesh(joinpath(tmpdir, "test.ply"))
			@fact mesh_loaded --> mesh
			save(File(format"PLY_BINARY", joinpath(tmpdir, "test.ply")), mesh)
		end
		context("STL ascii and binary") do
			save(File(format"STL_ASCII", joinpath(tmpdir, "test.stl")), mesh)
			mesh_loaded = GLPlainMesh(joinpath(tmpdir, "test.stl"))
			#@fact mesh_loaded --> mesh
			#save(File(format"STL_BINARY", joinpath(tmpdir, "test.stl")), mesh)
			#mesh_loaded = GLPlainMesh(joinpath(tmpdir, "test.stl"))
			#@fact mesh_loaded --> mesh
		end
	end
	context("Real world files") do 
		tf = joinpath(dirname(@__FILE__), "testfiles")
		context("STL") do
			msh = load(joinpath(tf, "ascii.stl"))
			@fact typeof(msh) --> GLNormalMesh
			@fact length(faces(msh)) --> 12
			@fact length(vertices(msh)) --> 36
			@fact length(normals(msh)) --> 36

			msh = load(joinpath(tf, "binary.stl"))
			@fact typeof(msh) --> GLNormalMesh
			@fact length(faces(msh)) --> 828
			@fact length(vertices(msh)) --> 2484
			@fact length(normals(msh)) --> 2484

			msh = load(joinpath(tf, "binary_stl_from_solidworks.STL"))
			@fact typeof(msh) --> GLNormalMesh
			@fact length(faces(msh)) --> 12
			@fact length(vertices(msh)) --> 36
		end
		context("PLY") do
			msh = load(joinpath(tf, "ascii.ply"))
			@fact typeof(msh) --> GLNormalMesh
			@fact length(faces(msh)) --> 36
			@fact length(vertices(msh)) --> 72
			@fact length(normals(msh)) --> 72
			#msh = load(joinpath(tf, "binary.ply")) # still missing
			#@fact typeof(msh) --> GLNormalMesh
			#println(msh)
		end
		context("OFF") do
			msh = load(joinpath(tf, "test.off"))
			@fact typeof(msh) --> GLNormalMesh
			@fact length(faces(msh)) --> 16
			@fact length(vertices(msh)) --> 20
			@fact length(normals(msh)) --> 20

			msh = load(joinpath(tf, "test2.off"))
			@fact typeof(msh) --> GLNormalMesh
			@fact length(faces(msh)) --> 810
			@fact length(vertices(msh)) --> 405
			@fact length(normals(msh)) --> 405
		end
		context("OBJ") do
			msh = load(joinpath(tf, "test.obj"))
			@fact typeof(msh) --> GLNormalMesh
			@fact length(faces(msh)) --> 3954
			@fact length(vertices(msh)) --> 2248
			@fact length(normals(msh)) --> 2248
		end
		context("2DM") do
			msh = load(joinpath(tf, "test.2dm"))
			@fact typeof(msh) --> GLNormalMesh
			#@fact length(faces(msh)) --> 3954
			#@fact length(vertices(msh)) --> 2248
			#@fact length(normals(msh)) --> 2248
		end
	end
end