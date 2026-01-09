# ============================================================================
# NoRecorder - Zero overhead for production/optimization
# ============================================================================

struct NoRecorder <: AbstractRecorder end

record!(::NoRecorder, state, step_record, t, action) = nothing

# ============================================================================
# TraceRecorderBuilder - Flexible recording during simulation
# ============================================================================

"""
Mutable builder that uses Vector{Any} during recording.
Call `build_trace(builder)` after simulation to get typed SimulationTrace.
"""
mutable struct TraceRecorderBuilder <: AbstractRecorder
    states::Vector{Any}
    step_records::Vector{Any}
    times::Vector{Any}
    actions::Vector{Any}

    TraceRecorderBuilder() = new(Any[], Any[], Any[], Any[])
end

function record!(r::TraceRecorderBuilder, state, step_record, t, action)
    push!(r.states, state)
    push!(r.step_records, step_record)
    push!(r.times, t)
    push!(r.actions, action)
    return nothing
end

# ============================================================================
# SimulationTrace - Type-stable trace with states, step_records, times, actions
# ============================================================================

"""
    SimulationTrace{S,R,T,A}

Immutable trace of a simulation run. Contains states, step_records, times, and actions.
Created from TraceRecorderBuilder via `build_trace`.
Implements Tables.jl interface.
"""
struct SimulationTrace{S,R,T,A}
    states::Vector{S}
    step_records::Vector{R}
    times::Vector{T}
    actions::Vector{A}
end

"""
    build_trace(r::TraceRecorderBuilder) -> SimulationTrace

Convert TraceRecorderBuilder to typed SimulationTrace.
Skips initial state (index 1) which has time=nothing, action=nothing.
"""
function build_trace(r::TraceRecorderBuilder)
    if length(r.states) < 2
        error("Cannot build trace from empty TraceRecorderBuilder")
    end

    S = typeof(r.states[2])
    R = typeof(r.step_records[2])
    T = typeof(r.times[2])
    A = typeof(r.actions[2])

    return SimulationTrace{S,R,T,A}(
        convert(Vector{S}, r.states[2:end]),
        convert(Vector{R}, r.step_records[2:end]),
        convert(Vector{T}, r.times[2:end]),
        convert(Vector{A}, r.actions[2:end]),
    )
end

# ============================================================================
# Tables.jl Interface for SimulationTrace
# ============================================================================

Tables.istable(::Type{<:SimulationTrace}) = true
Tables.columnaccess(::Type{<:SimulationTrace}) = true
Tables.columns(t::SimulationTrace) = t

Tables.columnnames(t::SimulationTrace) = (:state, :step_record, :time, :action)

function Tables.getcolumn(t::SimulationTrace, nm::Symbol)
    if nm === :state
        return t.states
    elseif nm === :step_record
        return t.step_records
    elseif nm === :time
        return t.times
    elseif nm === :action
        return t.actions
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
    elseif i == 4
        return t.actions
    else
        throw(BoundsError(t, i))
    end
end

function Tables.schema(t::SimulationTrace{S,R,T,A}) where {S,R,T,A}
    return Tables.Schema((:state, :step_record, :time, :action), (S, R, T, A))
end
