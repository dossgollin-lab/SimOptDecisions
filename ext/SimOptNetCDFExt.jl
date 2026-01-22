module SimOptNetCDFExt

using SimOptDecisions
using NCDatasets
using YAXArrays: Dataset, YAXArray, Dim, caxes

# Helper to extract dimension name from YAXArrays Dim type parameter
_dimname(dim) = string(typeof(dim).parameters[1])

"""Export Dataset to NetCDF file."""
function SimOptDecisions.save_netcdf(ds::Dataset, path::String)
    endswith(path, ".nc") || (path = path * ".nc")

    NCDataset(path, "c") do nc
        defined_dims = Set{String}()

        for (varname, cube) in pairs(ds.cubes)
            # Define dimensions if not already defined
            for dim in caxes(cube)
                dimname = _dimname(dim)
                if dimname ∉ defined_dims
                    defDim(nc, dimname, length(dim))
                    push!(defined_dims, dimname)
                end
            end

            # Define and write variable
            dimnames = tuple([_dimname(d) for d in caxes(cube)]...)
            v = defVar(nc, string(varname), eltype(cube), dimnames)
            v[:] = Array(cube)
        end
    end
    return path
end

"""Load Dataset from NetCDF file."""
function SimOptDecisions.load_netcdf(path::String)
    nc = NCDataset(path, "r")
    try
        cubes = Dict{Symbol,YAXArray}()
        for varname in keys(nc)
            v = nc[varname]
            dnames = dimnames(v)
            isempty(dnames) && continue

            data = Array(v)
            dims = tuple([Dim{Symbol(d)}(1:size(data, i)) for (i, d) in enumerate(dnames)]...)
            cubes[Symbol(varname)] = YAXArray(dims, data)
        end
        return Dataset(; cubes...)
    finally
        close(nc)
    end
end

end # module SimOptNetCDFExt
