module SimOptCSVExt

using SimOptDecisions
using CSV
using Tables

import SimOptDecisions: AbstractFileSink, write_header!, write_rows!, close!, csv_sink

"""
    CSVSink

File sink that writes exploration results to CSV format using CSV.jl.
Create via `csv_sink(filepath)` after loading CSV.jl.
"""
struct CSVSink <: AbstractFileSink
    filepath::String
    io::IOStream
end

"""
    csv_sink(filepath::String) -> CSVSink

Create a CSV file sink for streaming exploration results.

# Example
```julia
using SimOptDecisions
using CSV

sink = StreamingSink(csv_sink("results.csv"); flush_every=100)
explore(config, sows, policies; sink=sink)
```
"""
function SimOptDecisions.csv_sink(filepath::String)
    io = open(filepath, "w")
    CSVSink(filepath, io)
end

function SimOptDecisions.write_header!(sink::CSVSink, columns)
    # Write header using CSV.jl
    header_row = NamedTuple{Tuple(columns...)}(Tuple(columns))
    CSV.write(sink.io, Tables.table([header_row]); header=true, append=false)
    # Seek back and truncate to just keep the header line
    # Actually, CSV.write writes the whole table. Let's just write header manually
    # and use CSV for rows only
    seekstart(sink.io)
    truncate(sink.io, 0)
    println(sink.io, join(String.(columns), ","))
    flush(sink.io)
    return nothing
end

function SimOptDecisions.write_rows!(sink::CSVSink, rows::Vector{<:NamedTuple})
    # Use CSV.jl to write rows
    CSV.write(sink.io, Tables.table(rows); header=false, append=true)
    flush(sink.io)
    return nothing
end

function SimOptDecisions.close!(sink::CSVSink)
    close(sink.io)
    return nothing
end

end # module SimOptCSVExt
