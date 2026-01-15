# ============================================================================
# Time-stepped simulation interface
# ============================================================================
#
# Users implement five callbacks:
# | Function | Purpose | Returns |
# |----------|---------|---------|
# | `initialize(config, sow, rng)` | Create initial state | `state` |
# | `get_action(policy, state, sow, t)` | Map state to action | `<:AbstractAction` |
# | `run_timestep(state, action, sow, config, t, rng)` | Execute one step | `(new_state, step_record)` |
# | `time_axis(config, sow)` | Define time points | Iterable |
# | `finalize(final_state, step_records, config, sow)` | Aggregate results | `Outcome` |
#
# `simulate()` automatically calls these via `run_simulation`. See docs for examples.

using Random: AbstractRNG, default_rng

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

"""
    value(ts::TimeSeriesParameter) -> Vector{T}

Extract the underlying data vector from a TimeSeriesParameter.
"""
value(ts::TimeSeriesParameter) = ts.data

# ============================================================================
# User-Implemented Callback Functions
# ============================================================================

"""
    initialize(config::AbstractConfig, sow::AbstractSOW, rng::AbstractRNG) -> AbstractState

Create initial state for simulation. Required callback.
Must return `<:AbstractState`. Every simulation should have explicit state.
"""
function initialize end

function initialize(config::AbstractConfig, ::AbstractSOW, ::AbstractRNG)
    interface_not_implemented(
        :initialize, typeof(config), "sow::AbstractSOW, rng::AbstractRNG"
    )
end

"""
    run_timestep(state::AbstractState, action::AbstractAction, sow::AbstractSOW, config::AbstractConfig, t::TimeStep, rng::AbstractRNG) -> (new_state, step_record)

Execute one timestep transition. Required callback.

The framework calls `get_action(policy, state, sow, t)` before this function
and passes the resulting action. Implement the transition logic here.
"""
function run_timestep end

function run_timestep(
    state::AbstractState,
    action::AbstractAction,
    sow::AbstractSOW,
    config::AbstractConfig,
    t::TimeStep,
    rng::AbstractRNG,
)
    interface_not_implemented(
        :run_timestep,
        typeof(config),
        "state::AbstractState, action::AbstractAction, sow::AbstractSOW, t::TimeStep, rng::AbstractRNG",
    )
end

"""
    time_axis(config::AbstractConfig, sow::AbstractSOW) -> Iterable

Return time points iterable with defined `length()`. Required callback.
"""
function time_axis end

function time_axis(config::AbstractConfig, sow::AbstractSOW)
    interface_not_implemented(:time_axis, typeof(config), "sow::AbstractSOW")
end

"""
    finalize(final_state::AbstractState, step_records::Vector, config::AbstractConfig, sow::AbstractSOW) -> Outcome

Aggregate step records into final outcome. Required callback.
"""
function finalize end

function finalize(
    final_state::AbstractState, step_records, config::AbstractConfig, ::AbstractSOW
)
    interface_not_implemented(
        :finalize,
        typeof(config),
        "final_state::AbstractState, step_records::Vector, sow::AbstractSOW",
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

    timesteps = Utils.timeindex(times)
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
