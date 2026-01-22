module SimOptNetCDFExt

# This extension exists to ensure NCDatasets is loaded when users need NetCDF support.
# The actual NetCDF export/import is handled by YAXArrays via save_netcdf() and load_netcdf().

using SimOptDecisions
using NCDatasets

end # module SimOptNetCDFExt
