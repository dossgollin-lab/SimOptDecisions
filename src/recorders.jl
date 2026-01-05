# ============================================================================
# NoRecorder - Zero overhead for production/optimization
# ============================================================================

struct NoRecorder <: AbstractRecorder end

record!(::NoRecorder, state, t) = nothing

# ============================================================================
# TraceRecorderBuilder - Flexible recording during simulation
# ============================================================================

"""
Mutable builder that uses Vector{Any} during recording.
Call `finalize(builder)` after simulation to get typed TraceRecorder.
"""
mutable struct TraceRecorderBuilder <: AbstractRecorder
    states::Vector{Any}
    times::Vector{Any}

    TraceRecorderBuilder() = new(Any[], Any[])
end

function record!(r::TraceRecorderBuilder, state, t)
    push!(r.states, state)
    push!(r.times, t)
    return nothing
end

# ============================================================================
# TraceRecorder - Type-stable, Tables.jl compatible
# ============================================================================

"""
Immutable, typed recorder. Created from TraceRecorderBuilder via `finalize`.
Implements Tables.jl interface for integration with DataFrames, CSV, etc.
"""
struct TraceRecorder{S,T} <: AbstractRecorder
    states::Vector{S}
    times::Vector{T}
end

# Pre-allocated constructor when types are known
function TraceRecorder{S,T}(n::Int) where {S,T}
    return TraceRecorder{S,T}(Vector{S}(undef, n), Vector{T}(undef, n))
end

"""
Convert TraceRecorderBuilder to typed TraceRecorder.
Skips initial state (index 1) which has time=nothing.
"""
function finalize(r::TraceRecorderBuilder)
    if length(r.states) < 2
        error("Cannot finalize empty TraceRecorderBuilder")
    end

    S = typeof(r.states[2])
    T = typeof(r.times[2])

    return TraceRecorder{S,T}(
        convert(Vector{S}, r.states[2:end]),
        convert(Vector{T}, r.times[2:end]),
    )
end

# ============================================================================
# Tables.jl Interface for TraceRecorder
# ============================================================================

# Declare as a table
Tables.istable(::Type{<:TraceRecorder}) = true

# We implement column access (more natural for state vectors)
Tables.columnaccess(::Type{<:TraceRecorder}) = true
Tables.columns(r::TraceRecorder) = r

# Column names
Tables.columnnames(r::TraceRecorder) = (:state, :time)

# Column access by name
function Tables.getcolumn(r::TraceRecorder, nm::Symbol)
    if nm === :state
        return r.states
    elseif nm === :time
        return r.times
    else
        throw(ArgumentError("TraceRecorder has no column :$nm"))
    end
end

# Column access by index
function Tables.getcolumn(r::TraceRecorder, i::Int)
    if i == 1
        return r.states
    elseif i == 2
        return r.times
    else
        throw(BoundsError(r, i))
    end
end

# Schema (optional but helpful)
function Tables.schema(r::TraceRecorder{S,T}) where {S,T}
    return Tables.Schema((:state, :time), (S, T))
end
