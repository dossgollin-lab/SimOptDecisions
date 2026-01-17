# ============================================================================
# NoRecorder - Zero overhead for production/optimization
# ============================================================================

struct NoRecorder <: AbstractRecorder end

@inline record!(::NoRecorder, state, step_record, t, action) = nothing

# ============================================================================
# TraceRecorderBuilder - Flexible recording during simulation
# ============================================================================

"""Mutable builder for simulation traces. Call `build_trace(builder)` after simulation."""
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
# SimulationTrace - Type-stable trace
# ============================================================================

"""Immutable trace of a simulation run. Implements Tables.jl interface."""
struct SimulationTrace{I,S,R,T,A}
    initial_state::I
    states::Vector{S}
    step_records::Vector{R}
    times::Vector{T}
    actions::Vector{A}
end

"""Convert TraceRecorderBuilder to typed SimulationTrace."""
function build_trace(r::TraceRecorderBuilder)
    if length(r.states) < 2
        error("Cannot build trace: need at least initial state + one timestep")
    end

    initial_state = r.states[1]
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
# Tables.jl Interface
# ============================================================================

Tables.istable(::Type{<:SimulationTrace}) = true
Tables.columnaccess(::Type{<:SimulationTrace}) = true
Tables.columns(t::SimulationTrace) = t
Tables.columnnames(t::SimulationTrace) = (:state, :step_record, :time, :action)

function Tables.getcolumn(t::SimulationTrace, nm::Symbol)
    nm === :state && return t.states
    nm === :step_record && return t.step_records
    nm === :time && return t.times
    nm === :action && return t.actions
    throw(ArgumentError("SimulationTrace has no column :$nm"))
end

function Tables.getcolumn(t::SimulationTrace, i::Int)
    i == 1 && return t.states
    i == 2 && return t.step_records
    i == 3 && return t.times
    i == 4 && return t.actions
    throw(BoundsError(t, i))
end

function Tables.schema(t::SimulationTrace{I,S,R,T,A}) where {I,S,R,T,A}
    return Tables.Schema((:state, :step_record, :time, :action), (S, R, T, A))
end
