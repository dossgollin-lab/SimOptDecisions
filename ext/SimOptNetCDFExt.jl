module SimOptNetCDFExt

using SimOptDecisions
using NCDatasets

import SimOptDecisions: AbstractResultSink, record!, finalize, netcdf_sink

"""
    NetCDFSink

File sink that writes exploration results to NetCDF format.
Stores data with dimensions (policy, scenario) for efficient multidimensional access.
Create via `netcdf_sink(filepath)` after loading NCDatasets.jl.
"""
mutable struct NetCDFSink <: AbstractResultSink
    filepath::String
    flush_every::Int
    buffer::Vector{NamedTuple}
    count::Int
    ds::Union{Nothing,NCDataset}
    n_policies::Int
    n_scenarios::Int
    initialized::Bool
    column_names::Vector{Symbol}
end

"""
    netcdf_sink(filepath::String; flush_every=100) -> NetCDFSink

Create a NetCDF file sink for streaming exploration results.

# Example
```julia
using SimOptDecisions
using NCDatasets

sink = netcdf_sink("results.nc"; flush_every=100)
explore(config, sows, policies; sink=sink)
```
"""
function SimOptDecisions.netcdf_sink(filepath::String; flush_every::Int=100)
    NetCDFSink(filepath, flush_every, NamedTuple[], 0, nothing, 0, 0, false, Symbol[])
end

function SimOptDecisions.record!(sink::NetCDFSink, row::NamedTuple)
    push!(sink.buffer, row)
    sink.count += 1

    if sink.count >= sink.flush_every
        _flush_netcdf!(sink)
    end
    return nothing
end

function _flush_netcdf!(sink::NetCDFSink)
    isempty(sink.buffer) && return nothing

    if !sink.initialized
        _initialize_netcdf!(sink)
    end

    # Write buffered data
    for row in sink.buffer
        p_idx = row.policy_idx
        s_idx = row.scenario_idx

        for k in sink.column_names
            k in (:policy_idx, :scenario_idx) && continue
            varname = String(k)
            if haskey(sink.ds, varname)
                sink.ds[varname][p_idx, s_idx] = _to_netcdf_value(row[k])
            end
        end
    end

    NCDatasets.sync(sink.ds)
    empty!(sink.buffer)
    sink.count = 0
end

function _initialize_netcdf!(sink::NetCDFSink)
    # Infer dimensions from buffer
    first_row = first(sink.buffer)
    sink.column_names = collect(keys(first_row))

    sink.ds = NCDataset(sink.filepath, "c")

    # Define dimensions with unlimited size
    defDim(sink.ds, "policy", Inf)
    defDim(sink.ds, "scenario", Inf)

    # Define variables for each column (except indices)
    for k in sink.column_names
        k in (:policy_idx, :scenario_idx) && continue
        varname = String(k)
        v = first_row[k]

        # Determine NetCDF type
        nc_type = _netcdf_type(v)

        defVar(sink.ds, varname, nc_type, ("policy", "scenario"))
    end

    sink.initialized = true
end

# Convert Julia types to NetCDF-compatible types
function _netcdf_type(v)
    T = typeof(v)
    if T <: AbstractFloat
        return Float64
    elseif T <: Integer
        return Int32
    elseif T <: AbstractString || T <: Symbol
        return String
    else
        return Float64  # fallback
    end
end

function _to_netcdf_value(v)
    if v isa Symbol
        return String(v)
    else
        return v
    end
end

function SimOptDecisions.finalize(sink::NetCDFSink, n_policies::Int, n_scenarios::Int)
    sink.n_policies = n_policies
    sink.n_scenarios = n_scenarios

    _flush_netcdf!(sink)

    if !isnothing(sink.ds)
        # Add dimension metadata
        sink.ds.attrib["n_policies"] = n_policies
        sink.ds.attrib["n_scenarios"] = n_scenarios
        close(sink.ds)
    end

    return sink.filepath
end

end # module SimOptNetCDFExt
