# ============================================================================
# NoRecorder - Zero overhead for production/optimization
# ============================================================================

struct NoRecorder <: AbstractRecorder end

record!(::NoRecorder, state, step_record, t) = nothing

# ============================================================================
# TraceRecorderBuilder - Flexible recording during simulation
# ============================================================================

"""
Mutable builder that uses Vector{Any} during recording.
Call `finalize(builder)` after simulation to get typed SimulationTrace.
"""
mutable struct TraceRecorderBuilder <: AbstractRecorder
    states::Vector{Any}
    step_records::Vector{Any}
    times::Vector{Any}

    TraceRecorderBuilder() = new(Any[], Any[], Any[])
end

function record!(r::TraceRecorderBuilder, state, step_record, t)
    push!(r.states, state)
    push!(r.step_records, step_record)
    push!(r.times, t)
    return nothing
end

# ============================================================================
# SimulationTrace - Type-stable trace with states, step_records, and times
# ============================================================================

"""
    SimulationTrace{S,R,T}

Immutable trace of a simulation run. Contains states, step_records, and times.
Created from TraceRecorderBuilder via `finalize`.
Implements Tables.jl interface.
"""
struct SimulationTrace{S,R,T}
    states::Vector{S}
    step_records::Vector{R}
    times::Vector{T}
end

"""
Convert TraceRecorderBuilder to typed SimulationTrace.
Skips initial state (index 1) which has time=nothing.
"""
function finalize(r::TraceRecorderBuilder)
    if length(r.states) < 2
        error("Cannot finalize empty TraceRecorderBuilder")
    end

    S = typeof(r.states[2])
    R = typeof(r.step_records[2])
    T = typeof(r.times[2])

    return SimulationTrace{S,R,T}(
        convert(Vector{S}, r.states[2:end]),
        convert(Vector{R}, r.step_records[2:end]),
        convert(Vector{T}, r.times[2:end]),
    )
end

# ============================================================================
# Tables.jl Interface for SimulationTrace
# ============================================================================

Tables.istable(::Type{<:SimulationTrace}) = true
Tables.columnaccess(::Type{<:SimulationTrace}) = true
Tables.columns(t::SimulationTrace) = t

Tables.columnnames(t::SimulationTrace) = (:state, :step_record, :time)

function Tables.getcolumn(t::SimulationTrace, nm::Symbol)
    if nm === :state
        return t.states
    elseif nm === :step_record
        return t.step_records
    elseif nm === :time
        return t.times
    else
        throw(ArgumentError("SimulationTrace has no column :$nm"))
    end
end

function Tables.getcolumn(t::SimulationTrace, i::Int)
    if i == 1
        return t.states
    elseif i == 2
        return t.step_records
    elseif i == 3
        return t.times
    else
        throw(BoundsError(t, i))
    end
end

function Tables.schema(t::SimulationTrace{S,R,T}) where {S,R,T}
    return Tables.Schema((:state, :step_record, :time), (S, R, T))
end
