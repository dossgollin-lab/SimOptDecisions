module SimOptNetCDFExt

using SimOptDecisions
using NCDatasets
using YAXArrays: Dataset, savedataset, open_dataset

"""Export Dataset to NetCDF file."""
function SimOptDecisions.save_netcdf(ds::Dataset, path::String)
    savedataset(ds; path, driver=:netcdf, overwrite=true)
end

"""Load Dataset from NetCDF file."""
function SimOptDecisions.load_netcdf(path::String)
    open_dataset(path)
end

end # module SimOptNetCDFExt
