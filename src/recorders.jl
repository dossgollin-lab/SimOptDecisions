# ============================================================================
# NoRecorder - Zero overhead for production/optimization
# ============================================================================

struct NoRecorder <: AbstractRecorder end

@inline record!(::NoRecorder, state, step_record, t, action) = nothing

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
    SimulationTrace{I,S,R,T,A}

Immutable trace of a simulation run.

# Fields
- `initial_state::I`: State at t=0 before any actions
- `states::Vector{S}`: States after each timestep (length = n_timesteps)
- `step_records::Vector{R}`: Records from each timestep (length = n_timesteps)
- `times::Vector{T}`: Time values for each timestep (length = n_timesteps)
- `actions::Vector{A}`: Actions taken at each timestep (length = n_timesteps)

All vectors are aligned: `states[i]`, `step_records[i]`, `times[i]`, `actions[i]`
correspond to timestep i.

Created from TraceRecorderBuilder via `build_trace`.
Implements Tables.jl interface for the per-timestep data.
"""
struct SimulationTrace{I,S,R,T,A}
    initial_state::I
    states::Vector{S}
    step_records::Vector{R}
    times::Vector{T}
    actions::Vector{A}
end

"""
    build_trace(r::TraceRecorderBuilder) -> SimulationTrace

Convert TraceRecorderBuilder to typed SimulationTrace.
The first recorded state becomes `initial_state`; subsequent entries form the vectors.
"""
function build_trace(r::TraceRecorderBuilder)
    if length(r.states) < 2
        error("Cannot build trace: need at least initial state + one timestep")
    end

    # Initial state is at index 1 (before any actions)
    initial_state = r.states[1]

    # Timestep data starts at index 2
    I = typeof(initial_state)
    S = typeof(r.states[2])
    R = typeof(r.step_records[2])
    T = typeof(r.times[2])
    A = typeof(r.actions[2])

    return SimulationTrace{I,S,R,T,A}(
        initial_state,
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

function Tables.schema(t::SimulationTrace{I,S,R,T,A}) where {I,S,R,T,A}
    return Tables.Schema((:state, :step_record, :time, :action), (S, R, T, A))
end
