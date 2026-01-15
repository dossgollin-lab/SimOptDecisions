# ============================================================================
# Time-stepped simulation interface
# ============================================================================
#
# Users implement five callbacks:
# | Function | Purpose | Returns |
# |----------|---------|---------|
# | `initialize(config, scenario, rng)` | Create initial state | `state` |
# | `get_action(policy, state, t, scenario)` | Map state to action | any value |
# | `run_timestep(state, action, t, config, scenario, rng)` | Execute one step | `(new_state, step_record)` |
# | `time_axis(config, scenario)` | Define time points | Iterable |
# | `compute_outcome(step_records, config, scenario)` | Aggregate results | `Outcome` |
#
# `simulate()` automatically calls these via `run_simulation`. See docs for examples.

using Random: AbstractRNG, default_rng

# ============================================================================
# TimeSeriesParameter - Time-indexed data for Scenarios
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

"""Wrapper for time-indexed data in Scenarios. Index via `ts[t]` using TimeStep or integer."""
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

"""
    value(ts::TimeSeriesParameter) -> Vector{T}

Extract the underlying data vector from a TimeSeriesParameter.
"""
@inline value(ts::TimeSeriesParameter) = ts.data

# ============================================================================
# TimeStep Accessors
# ============================================================================

"""
    index(t::TimeStep) -> Int

Return the 1-based index of the timestep.
"""
@inline index(t::TimeStep) = t.t

"""
    value(t::TimeStep) -> V

Return the value (e.g., year, date) of the timestep.
"""
@inline value(t::TimeStep) = t.val

# ============================================================================
# User-Implemented Callback Functions
# ============================================================================

"""
    initialize(config::AbstractConfig, scenario::AbstractScenario, rng::AbstractRNG) -> AbstractState
    initialize(config::AbstractConfig, scenario::AbstractScenario) -> AbstractState

Create initial state for simulation. Required callback.
Must return `<:AbstractState`. Every simulation should have explicit state.

You can implement either the 3-argument version (with rng) or the 2-argument version
(without rng) if your initialization doesn't need randomness.
"""
function initialize end

# Dummy RNG for deterministic initialization (when user doesn't need randomness)
struct _DummyRNG <: AbstractRNG end

# Fallback: if user implements 2-arg version, we call it from 3-arg version
function initialize(config::AbstractConfig, scenario::AbstractScenario, ::AbstractRNG)
    # Try calling 2-arg version first
    return initialize(config, scenario)
end

# Base fallback when neither version is implemented
function initialize(config::AbstractConfig, ::AbstractScenario)
    interface_not_implemented(
        :initialize, typeof(config), "scenario::AbstractScenario[, rng::AbstractRNG]"
    )
end

"""
    run_timestep(state::AbstractState, action, t::TimeStep, config::AbstractConfig, scenario::AbstractScenario, rng::AbstractRNG) -> (new_state, step_record)

Execute one timestep transition. Required callback.

The framework calls `get_action(policy, state, t, scenario)` before this function
and passes the resulting action. Implement the transition logic here.
"""
function run_timestep end

function run_timestep(
    state::AbstractState,
    action,
    t::TimeStep,
    config::AbstractConfig,
    scenario::AbstractScenario,
    rng::AbstractRNG,
)
    interface_not_implemented(
        :run_timestep,
        typeof(config),
        "state::AbstractState, action, t::TimeStep, scenario::AbstractScenario, rng::AbstractRNG",
    )
end

"""
    time_axis(config::AbstractConfig, scenario::AbstractScenario) -> Iterable

Return time points iterable with defined `length()`. Required callback.
"""
function time_axis end

function time_axis(config::AbstractConfig, scenario::AbstractScenario)
    interface_not_implemented(:time_axis, typeof(config), "scenario::AbstractScenario")
end

"""
    compute_outcome(step_records::Vector, config::AbstractConfig, scenario::AbstractScenario) -> Outcome

Aggregate step records into final outcome. Required callback.

Note: The final state is no longer passed as a separate parameter. If you need it,
include the state in your step_record (e.g., as a named tuple field).
"""
function compute_outcome end

function compute_outcome(step_records, config::AbstractConfig, ::AbstractScenario)
    interface_not_implemented(
        :compute_outcome,
        typeof(config),
        "step_records::Vector, scenario::AbstractScenario",
    )
end

# ============================================================================
# Framework-Provided Runner
# ============================================================================

"""
    run_simulation(config, scenario, policy, recorder, rng) -> Outcome

Run time-stepped simulation using callbacks. Called automatically by `simulate()`.

The framework calls user-implemented callbacks in sequence:
1. `initialize(config, scenario, rng)` - create initial state
2. For each timestep:
   - `get_action(policy, state, t, scenario)` - get action from policy
   - `run_timestep(state, action, t, config, scenario, rng)` - execute transition
3. `compute_outcome(step_records, config, scenario)` - aggregate results
"""
function run_simulation(
    config::AbstractConfig,
    scenario::AbstractScenario,
    policy::AbstractPolicy,
    recorder::AbstractRecorder,
    rng::AbstractRNG,
)
    times = time_axis(config, scenario)
    _validate_time_axis(times)
    n = length(times)

    state = initialize(config, scenario, rng)
    record!(recorder, state, nothing, nothing, nothing)

    timesteps = timeindex(times)
    first_ts, rest = Iterators.peel(timesteps)

    # Framework calls get_action, then run_timestep
    first_action = get_action(policy, state, first_ts, scenario)
    state, first_step_record = run_timestep(state, first_action, first_ts, config, scenario, rng)
    record!(recorder, state, first_step_record, first_ts.val, first_action)

    step_records = Vector{typeof(first_step_record)}(undef, n)
    step_records[1] = first_step_record

    for ts in rest
        action = get_action(policy, state, ts, scenario)
        state, step_record = run_timestep(state, action, ts, config, scenario, rng)
        step_records[ts.t] = step_record
        record!(recorder, state, step_record, ts.val, action)
    end

    return compute_outcome(step_records, config, scenario)
end

# Method overloads for optional arguments (avoiding kwargs for performance)

# Without recorder (rng only)
function run_simulation(
    config::AbstractConfig, scenario::AbstractScenario, policy::AbstractPolicy, rng::AbstractRNG
)
    return run_simulation(config, scenario, policy, NoRecorder(), rng)
end

# Without rng (recorder only)
function run_simulation(
    config::AbstractConfig,
    scenario::AbstractScenario,
    policy::AbstractPolicy,
    recorder::AbstractRecorder,
)
    return run_simulation(config, scenario, policy, recorder, default_rng())
end

# Minimal (no recorder, no rng)
function run_simulation(config::AbstractConfig, scenario::AbstractScenario, policy::AbstractPolicy)
    return run_simulation(config, scenario, policy, NoRecorder(), default_rng())
end
