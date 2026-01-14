module SimOptCSVExt

using SimOptDecisions
using CSV

import SimOptDecisions: AbstractFileSink, write_header!, write_rows!, close!

"""
    CSVSink(filepath::String)

File sink that writes exploration results to CSV format.

# Example
```julia
using CSV  # triggers extension loading
sink = StreamingSink(CSVSink("results.csv"); flush_every=100)
result = explore(config, sows, policies; sink=sink)
# Returns filepath to the CSV file
```
"""
struct CSVSink <: AbstractFileSink
    filepath::String
    io::IOStream
end

function CSVSink(filepath::String)
    io = open(filepath, "w")
    CSVSink(filepath, io)
end

function SimOptDecisions.write_header!(sink::CSVSink, columns)
    header = join(String.(columns), ",")
    println(sink.io, header)
    flush(sink.io)
    return nothing
end

function SimOptDecisions.write_rows!(sink::CSVSink, rows::Vector{<:NamedTuple})
    for row in rows
        line = join([_csv_escape(v) for v in values(row)], ",")
        println(sink.io, line)
    end
    flush(sink.io)
    return nothing
end

function SimOptDecisions.close!(sink::CSVSink)
    close(sink.io)
    return nothing
end

# Helper for CSV escaping
function _csv_escape(v)
    s = string(v)
    if occursin(r"[,\"\n\r]", s)
        return "\"" * replace(s, "\"" => "\"\"") * "\""
    end
    return s
end

# Export the sink type
export CSVSink

end # module SimOptCSVExt
