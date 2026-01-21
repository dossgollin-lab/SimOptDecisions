# ============================================================================
# Legacy Result Sinks (Deprecated - Use Storage Backends Instead)
# ============================================================================

# Note: This file is kept for backward compatibility during the transition.
# New code should use InMemoryBackend or ZarrBackend from exploration.jl.

"""Base type for sinks that collect or stream exploration results (deprecated)."""
abstract type AbstractResultSink end

"""Record a single result row to the sink (deprecated)."""
function record! end

# ============================================================================
# NoSink - Zero overhead
# ============================================================================

"""A no-op sink that discards all results (deprecated)."""
struct NoSink <: AbstractResultSink end

record!(::NoSink, row) = nothing
finalize(::NoSink, n_policies, n_scenarios) = nothing

# ============================================================================
# InMemorySink - Collect results in memory (deprecated)
# ============================================================================

"""Collects exploration results in memory (deprecated - use InMemoryBackend)."""
mutable struct InMemorySink <: AbstractResultSink
    results::Vector{NamedTuple}
    InMemorySink() = new(NamedTuple[])
end

function record!(sink::InMemorySink, row::NamedTuple)
    push!(sink.results, row)
    return nothing
end

# ============================================================================
# File Sink Infrastructure (deprecated)
# ============================================================================

"""Base type for sinks that write to files (deprecated)."""
abstract type AbstractFileSink <: AbstractResultSink end

function write_header! end
function write_rows! end
function close! end

"""Wraps a file sink with buffered writes (deprecated)."""
mutable struct StreamingSink{F<:AbstractFileSink} <: AbstractResultSink
    file_sink::F
    buffer::Vector{NamedTuple}
    flush_every::Int
    count::Int
    header_written::Bool
end

function StreamingSink(file_sink::F; flush_every::Int=100) where {F<:AbstractFileSink}
    StreamingSink(file_sink, NamedTuple[], flush_every, 0, false)
end

function record!(sink::StreamingSink, row::NamedTuple)
    if !sink.header_written
        write_header!(sink.file_sink, keys(row))
        sink.header_written = true
    end

    push!(sink.buffer, row)
    sink.count += 1

    sink.count >= sink.flush_every && _flush!(sink)
    return nothing
end

function _flush!(sink::StreamingSink)
    if !isempty(sink.buffer)
        write_rows!(sink.file_sink, sink.buffer)
        empty!(sink.buffer)
        sink.count = 0
    end
end

function finalize(sink::StreamingSink, n_policies, n_scenarios)
    _flush!(sink)
    close!(sink.file_sink)
    return sink.file_sink.filepath
end

# ============================================================================
# NetCDF sink (via extension)
# ============================================================================

"""Create a NetCDF file sink. Requires `using NCDatasets`."""
function netcdf_sink end

function netcdf_sink(filepath::AbstractString; kwargs...)
    error("netcdf_sink requires the NCDatasets package. Add: using NCDatasets")
end
