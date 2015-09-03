using Meshes
# jit compile
mesh("cube.stl")
Profile.clear() # in case we have any previous profiling data
@profile mesh("cube.stl")
using ProfileView
ProfileView.view()
