# ============================================================================
# Result Sinks for Exploratory Modeling
# ============================================================================

"""
    AbstractResultSink

Base type for sinks that collect or stream exploration results.

Implement `record!(sink, row::NamedTuple)` to store results.
"""
abstract type AbstractResultSink end

"""
    record!(sink::AbstractResultSink, row::NamedTuple)

Record a single result row to the sink.
"""
function record! end

# ============================================================================
# NoSink - Zero overhead (used during optimization)
# ============================================================================

"""
    NoSink()

A no-op sink that discards all results. Used as default when results aren't needed.
"""
struct NoSink <: AbstractResultSink end

record!(::NoSink, row) = nothing
finalize(::NoSink, n_policies, n_scenarios) = nothing

# ============================================================================
# InMemorySink - Collect results in memory
# ============================================================================

"""
    InMemorySink()

Collects exploration results in memory. Returns `ExplorationResult` on finalize.
"""
mutable struct InMemorySink <: AbstractResultSink
    results::Vector{NamedTuple}
    InMemorySink() = new(NamedTuple[])
end

function record!(sink::InMemorySink, row::NamedTuple)
    push!(sink.results, row)
    return nothing
end

# finalize implemented in exploration.jl after ExplorationResult is defined

# ============================================================================
# File Sink Infrastructure
# ============================================================================

"""
    AbstractFileSink <: AbstractResultSink

Base type for sinks that write to files. Extensions implement specific formats.

Required methods for subtypes:
- `write_header!(sink, columns)` - Write column headers
- `write_rows!(sink, rows)` - Write data rows
- `close!(sink)` - Close file handle
"""
abstract type AbstractFileSink <: AbstractResultSink end

"""Interface method for writing header row."""
function write_header! end

"""Interface method for writing data rows."""
function write_rows! end

"""Interface method for closing file."""
function close! end

"""
    StreamingSink(file_sink; flush_every=100)

Wraps a file sink with buffered writes. Flushes to disk every `flush_every` rows.

# Example
```julia
using CSV  # load extension
sink = StreamingSink(CSVSink("results.csv"); flush_every=100)
explore(config, scenarios, policies; sink=sink)
```
"""
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
    # Write header on first row
    if !sink.header_written
        write_header!(sink.file_sink, keys(row))
        sink.header_written = true
    end

    push!(sink.buffer, row)
    sink.count += 1

    if sink.count >= sink.flush_every
        _flush!(sink)
    end
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

"""
    csv_sink(filepath::String)

Create a CSV file sink for streaming exploration results.
Requires `using CSV` to load the extension.

# Example
```julia
using SimOptDecisions
using CSV

sink = StreamingSink(csv_sink("results.csv"); flush_every=100)
explore(config, scenarios, policies; sink=sink)
```
"""
function csv_sink end

function csv_sink(filepath::String)
    error(
        "csv_sink requires the CSV package.\n" *
        "Run `using CSV` to load the SimOptCSVExt extension.",
    )
end

"""
    netcdf_sink(filepath::String; flush_every=100)

Create a NetCDF file sink for streaming exploration results.
Requires `using NCDatasets` to load the extension.

# Example
```julia
using SimOptDecisions
using NCDatasets

sink = netcdf_sink("results.nc"; flush_every=100)
explore(config, scenarios, policies; sink=sink)
```
"""
function netcdf_sink end

function netcdf_sink(filepath::String; kwargs...)
    error(
        "netcdf_sink requires the NCDatasets package.\n" *
        "Run `using NCDatasets` to load the SimOptNetCDFExt extension.",
    )
end
