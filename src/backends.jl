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

"""Stream results to Zarr storage for memory-efficient processing."""
struct ZarrBackend <: AbstractStorageBackend
    path::String
    overwrite::Bool
end

ZarrBackend(path::String; overwrite::Bool=true) = ZarrBackend(path, overwrite)

# ============================================================================
# Zarr Storage Functions
# ============================================================================

"""Create a Zarr store for streaming results."""
function zarr_sink(
    path::String,
    outcome_names::Vector{Symbol},
    outcome_types::Vector{Type},
    is_timeseries::Vector{Bool},
    n_policies::Int,
    n_scenarios::Int,
    time_axes::Union{Nothing,Dict{Symbol,Vector}};
    overwrite::Bool=true,
)
    overwrite && isdir(path) && rm(path; recursive=true)

    g = zgroup(path; attrs=Dict(
        "n_policies" => n_policies,
        "n_scenarios" => n_scenarios,
    ))

    arrays = Dict{Symbol,Any}()

    for (i, name) in enumerate(outcome_names)
        T = outcome_types[i]
        zarr_type = _julia_to_zarr_type(T)

        if is_timeseries[i] && !isnothing(time_axes) && haskey(time_axes, name)
            n_times = length(time_axes[name])
            arrays[name] = zcreate(
                zarr_type, g, String(name), n_policies, n_scenarios, n_times;
                chunks=(min(n_policies, 10), min(n_scenarios, 100), n_times),
                fill_value=_zarr_fill_value(T),
            )
        else
            arrays[name] = zcreate(
                zarr_type, g, String(name), n_policies, n_scenarios;
                chunks=(min(n_policies, 10), min(n_scenarios, 100)),
                fill_value=_zarr_fill_value(T),
            )
        end
    end

    return g, arrays
end

function _julia_to_zarr_type(::Type{T}) where {T<:AbstractFloat}
    Float64
end

function _julia_to_zarr_type(::Type{T}) where {T<:Integer}
    Int64
end

function _julia_to_zarr_type(::Type{T}) where {T}
    Float64
end

function _zarr_fill_value(::Type{T}) where {T<:AbstractFloat}
    NaN
end

function _zarr_fill_value(::Type{T}) where {T<:Integer}
    typemin(Int64)
end

function _zarr_fill_value(::Type{T}) where {T}
    NaN
end

"""Write a single result to Zarr arrays."""
function _write_to_zarr!(
    arrays::Dict{Symbol,Any},
    outcome,
    p_idx::Int,
    s_idx::Int,
    outcome_names::Vector{Symbol},
    is_timeseries::Vector{Bool},
)
    for (i, name) in enumerate(outcome_names)
        field = getfield(outcome, name)
        val = _get_outcome_value(field)

        if is_timeseries[i]
            arrays[name][p_idx, s_idx, :] = val
        else
            arrays[name][p_idx, s_idx] = val
        end
    end
end

"""Load Zarr store as YAXArray Dataset."""
function load_zarr_results(path::String)
    open_dataset(path)
end

# ============================================================================
# NetCDF I/O
# ============================================================================

"""Export Dataset to NetCDF file."""
function save_netcdf(ds::Dataset, path::String)
    savedataset(ds; path, driver=:netcdf, overwrite=true)
end

"""Load Dataset from NetCDF file."""
function load_netcdf(path::String)
    open_dataset(path)
end
