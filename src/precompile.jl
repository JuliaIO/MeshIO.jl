macro warnpcfail(ex::Expr)
    modl = __module__
    file = __source__.file === nothing ? "?" : String(__source__.file)
    line = __source__.line
    quote
        $(esc(ex)) || @warn """precompile directive
     $($(Expr(:quote, ex)))
 failed. Please report an issue in $($modl) (after checking for duplicates) or remove this directive.""" _file=$file _line=$line
    end
end

function _precompile_()
    ccall(:jl_generating_output, Cint, ()) == 1 || return nothing

    if isdefined(FileIO, :action)
        @warnpcfail precompile(load, (File{format"2DM",IOStream},))
        @warnpcfail precompile(load, (File{format"MSH",IOStream},))
        @warnpcfail precompile(load, (File{format"OBJ",IOStream},))
        @warnpcfail precompile(load, (File{format"OFF",IOStream},))
        @warnpcfail precompile(load, (File{format"PLY_ASCII",IOStream},))
        @warnpcfail precompile(load, (File{format"PLY_BINARY",IOStream},))
        @warnpcfail precompile(load, (File{format"STL_ASCII",IOStream},))
        @warnpcfail precompile(load, (File{format"STL_BINARY",IOStream},))
    else
        @warnpcfail precompile(load, (File{format"2DM"},))
        @warnpcfail precompile(load, (File{format"MSH"},))
        @warnpcfail precompile(load, (File{format"OBJ"},))
        @warnpcfail precompile(load, (File{format"OFF"},))
        @warnpcfail precompile(load, (File{format"PLY_ASCII"},))
        @warnpcfail precompile(load, (File{format"PLY_BINARY"},))
        @warnpcfail precompile(load, (File{format"STL_ASCII"},))
        @warnpcfail precompile(load, (File{format"STL_BINARY"},))
    end

end
