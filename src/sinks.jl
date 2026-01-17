# ============================================================================
# Result Sinks for Exploratory Modeling
# ============================================================================

"""Base type for sinks that collect or stream exploration results."""
abstract type AbstractResultSink end

"""Record a single result row to the sink."""
function record! end

# ============================================================================
# NoSink - Zero overhead
# ============================================================================

"""A no-op sink that discards all results."""
struct NoSink <: AbstractResultSink end

record!(::NoSink, row) = nothing
finalize(::NoSink, n_policies, n_scenarios) = nothing

# ============================================================================
# InMemorySink - Collect results in memory
# ============================================================================

"""Collects exploration results in memory. Returns ExplorationResult on finalize."""
mutable struct InMemorySink <: AbstractResultSink
    results::Vector{NamedTuple}
    InMemorySink() = new(NamedTuple[])
end

function record!(sink::InMemorySink, row::NamedTuple)
    push!(sink.results, row)
    return nothing
end

# ============================================================================
# File Sink Infrastructure
# ============================================================================

"""Base type for sinks that write to files."""
abstract type AbstractFileSink <: AbstractResultSink end

function write_header! end
function write_rows! end
function close! end

"""Wraps a file sink with buffered writes."""
mutable struct StreamingSink{F<:AbstractFileSink} <: AbstractResultSink
    file_sink::F
    buffer::Vector{NamedTuple}
    flush_every::Int
    count::Int
    header_written::Bool
end

StreamingSink(file_sink::F; flush_every::Int=100) where {F<:AbstractFileSink} =
    StreamingSink(file_sink, NamedTuple[], flush_every, 0, false)

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
# Extension Sink Factory Functions
# ============================================================================

"""Create a CSV file sink. Requires `using CSV`."""
function csv_sink end

function csv_sink(filepath::AbstractString)
    error("csv_sink requires the CSV package. Add: using CSV")
end

"""Create a NetCDF file sink. Requires `using NCDatasets`."""
function netcdf_sink end

function netcdf_sink(filepath::AbstractString; kwargs...)
    error("netcdf_sink requires the NCDatasets package. Add: using NCDatasets")
end
