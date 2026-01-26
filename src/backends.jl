# ============================================================================
# Storage Backends for Exploration Results
# ============================================================================

using YAXArrays
using Zarr

# ============================================================================
# Backend Types
# ============================================================================

"""Base type for result storage backends."""
abstract type AbstractStorageBackend end

"""Store results in memory as YAXArray."""
struct InMemoryBackend <: AbstractStorageBackend end

"""Save exploration results to Zarr storage on disk."""
struct ZarrBackend <: AbstractStorageBackend
    path::String
    overwrite::Bool
end

ZarrBackend(path::String; overwrite::Bool=true) = ZarrBackend(path, overwrite)

# ============================================================================
# Zarr Storage Functions
# ============================================================================

"""Save a YAXArray Dataset to Zarr format (excludes string metadata)."""
function save_zarr(ds::Dataset, path::String; overwrite::Bool=true)
    overwrite && isdir(path) && rm(path; recursive=true)

    # Filter out String/Symbol coordinate arrays which Zarr can't handle well
    numeric_cubes = Dict{Symbol,Any}()
    for (name, cube) in ds.cubes
        T = eltype(cube.data)
        if T <: Number
            numeric_cubes[name] = cube
        end
    end

    if isempty(numeric_cubes)
        throw(ArgumentError("No numeric arrays to save to Zarr"))
    end

    filtered_ds = Dataset(; numeric_cubes...)
    savedataset(filtered_ds; path, driver=:zarr)
end

"""Load Zarr store as YAXArray Dataset."""
function load_zarr_results(path::String)
    open_dataset(path)
end

# ============================================================================
# NetCDF I/O (stub functions - actual implementation in NetCDF extension)
# ============================================================================

"""Export Dataset to NetCDF file. Requires NCDatasets.jl to be loaded."""
function save_netcdf end

"""Load Dataset from NetCDF file. Requires NCDatasets.jl to be loaded."""
function load_netcdf end
