function _precompile_()
    ccall(:jl_generating_output, Cint, ()) == 1 || return nothing
    @assert precompile(load, (File{format"2DM"},))
    @assert precompile(load, (File{format"MSH"},))
    @assert precompile(load, (File{format"OBJ"},))
    @assert precompile(load, (File{format"OFF"},))
    @assert precompile(load, (File{format"PLY_ASCII"},))
    @assert precompile(load, (File{format"STL_ASCII"},))
    @assert precompile(load, (File{format"STL_BINARY"},))
end
