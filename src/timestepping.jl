# ============================================================================
# TimeStepping - Structured interface for time-stepped simulations
# ============================================================================

"""
    TimeStepping

Submodule for time-stepped simulations. Implement five callbacks:

| Function | Purpose | Returns |
|----------|---------|---------|
| `initialize(config, sow, rng)` | Create initial state | `state` |
| `get_action(policy, state, sow, t)` | Map state to action | `<:AbstractAction` |
| `run_timestep(state, action, sow, config, t, rng)` | Execute one step | `(new_state, step_record)` |
| `time_axis(config, sow)` | Define time points | Iterable |
| `finalize(final_state, step_records, config, sow)` | Aggregate results | `Outcome` |

`simulate()` automatically calls these via `run_simulation`. See docs for examples.
"""
module TimeStepping

using Random: AbstractRNG, default_rng

using ..SimOptDecisions:
    AbstractConfig,
    AbstractSOW,
    AbstractPolicy,
    AbstractAction,
    AbstractRecorder,
    TimeStep,
    NoRecorder,
    record!,
    get_action,
    interface_not_implemented,
    _validate_time_axis

using ..SimOptDecisions.Utils: timeindex

# ============================================================================
# TimeSeriesParameter - Time-indexed data for SOWs
# ============================================================================

"""Error thrown when accessing TimeSeriesParameter beyond its length."""
struct TimeSeriesParameterBoundsError <: Exception
    index::Int
    length::Int
end

function Base.showerror(io::IO, e::TimeSeriesParameterBoundsError)
    print(
        io,
        "TimeSeriesParameterBoundsError: index $(e.index) exceeds data length $(e.length). ",
    )
    print(io, "Extend your time series data or shorten the simulation horizon.")
end

"""Wrapper for time-indexed data in SOWs. Index via `ts[t]` using TimeStep or integer."""
struct TimeSeriesParameter{T<:AbstractFloat}
    data::Vector{T}
    function TimeSeriesParameter(data::Vector{T}) where {T<:AbstractFloat}
        isempty(data) && throw(ArgumentError("TimeSeriesParameter cannot be empty"))
        new{T}(data)
    end
end

TimeSeriesParameter(data) = TimeSeriesParameter(collect(Float64, data))

Base.getindex(ts::TimeSeriesParameter, t::TimeStep) = ts[t.t]

function Base.getindex(ts::TimeSeriesParameter{T}, i::Integer) where {T}
    (i < 1 || i > length(ts.data)) &&
        throw(TimeSeriesParameterBoundsError(i, length(ts.data)))
    ts.data[i]
end

Base.length(ts::TimeSeriesParameter) = length(ts.data)
Base.iterate(ts::TimeSeriesParameter) = iterate(ts.data)
Base.iterate(ts::TimeSeriesParameter, state) = iterate(ts.data, state)

# ============================================================================
# User-Implemented Interface Functions
# ============================================================================

"""
    initialize(config::AbstractConfig, sow::AbstractSOW, rng::AbstractRNG) -> state

Create initial state for simulation. Must be implemented.
Return `nothing` for stateless models, or `<:AbstractState` for stateful models.
"""
function initialize end

function initialize(config::AbstractConfig, ::AbstractSOW, ::AbstractRNG)
    interface_not_implemented(
        :initialize, typeof(config), "sow::AbstractSOW, rng::AbstractRNG"
    )
end

"""
    run_timestep(state, action::AbstractAction, sow::AbstractSOW, config::AbstractConfig, t::TimeStep, rng::AbstractRNG) -> (new_state, step_record)

Execute one timestep transition. Must be implemented.

The framework calls `get_action(policy, state, sow, t)` before this function
and passes the resulting action. Implement the transition logic here.
"""
function run_timestep end

"""
    time_axis(config::AbstractConfig, sow::AbstractSOW) -> Iterable

Return time points iterable with defined `length()`. Must be implemented.
"""
function time_axis end

"""
    finalize(final_state, step_records::Vector, config::AbstractConfig, sow::AbstractSOW) -> Outcome

Aggregate step records into final outcome. Must be implemented.
"""
function finalize end

function finalize(final_state, step_records::Vector, config::AbstractConfig, ::AbstractSOW)
    interface_not_implemented(
        :finalize, typeof(config), "final_state, step_records::Vector, sow::AbstractSOW"
    )
end

# ============================================================================
# Framework-Provided Runner
# ============================================================================

"""
    run_simulation(config, sow, policy, recorder, rng) -> Outcome

Run time-stepped simulation using callbacks. Called automatically by `simulate()`.

The framework calls user-implemented callbacks in sequence:
1. `initialize(config, sow, rng)` - create initial state
2. For each timestep:
   - `get_action(policy, state, sow, t)` - get action from policy
   - `run_timestep(state, action, sow, config, t, rng)` - execute transition
3. `finalize(final_state, step_records, config, sow)` - aggregate results
"""
function run_simulation(
    config::AbstractConfig,
    sow::AbstractSOW,
    policy::AbstractPolicy,
    recorder::AbstractRecorder,
    rng::AbstractRNG,
)
    times = time_axis(config, sow)
    _validate_time_axis(times)
    n = length(times)

    state = initialize(config, sow, rng)
    record!(recorder, state, nothing, nothing, nothing)

    timesteps = timeindex(times)
    first_ts, rest = Iterators.peel(timesteps)

    # Framework calls get_action, then run_timestep
    first_action = get_action(policy, state, sow, first_ts)
    state, first_step_record = run_timestep(state, first_action, sow, config, first_ts, rng)
    record!(recorder, state, first_step_record, first_ts.val, first_action)

    step_records = Vector{typeof(first_step_record)}(undef, n)
    step_records[1] = first_step_record

    for ts in rest
        action = get_action(policy, state, sow, ts)
        state, step_record = run_timestep(state, action, sow, config, ts, rng)
        step_records[ts.t] = step_record
        record!(recorder, state, step_record, ts.val, action)
    end

    return finalize(state, step_records, config, sow)
end

# Method overloads for optional arguments (avoiding kwargs for performance)

# Without recorder (rng only)
function run_simulation(
    config::AbstractConfig, sow::AbstractSOW, policy::AbstractPolicy, rng::AbstractRNG
)
    return run_simulation(config, sow, policy, NoRecorder(), rng)
end

# Without rng (recorder only)
function run_simulation(
    config::AbstractConfig,
    sow::AbstractSOW,
    policy::AbstractPolicy,
    recorder::AbstractRecorder,
)
    return run_simulation(config, sow, policy, recorder, default_rng())
end

# Minimal (no recorder, no rng)
function run_simulation(config::AbstractConfig, sow::AbstractSOW, policy::AbstractPolicy)
    return run_simulation(config, sow, policy, NoRecorder(), default_rng())
end

end # module TimeStepping
