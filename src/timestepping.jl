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

"""Error thrown when accessing TimeSeriesParameter with invalid time value."""
struct TimeSeriesParameterBoundsError <: Exception
    requested::Any
    available::Vector
end

function Base.showerror(io::IO, e::TimeSeriesParameterBoundsError)
    print(
        io, "TimeSeriesParameterBoundsError: time value $(e.requested) not in time_axis. "
    )
    if length(e.available) <= 10
        print(io, "Available: $(e.available)")
    else
        print(io, "Available range: $(first(e.available)) to $(last(e.available))")
    end
end

"""
    TimeSeriesParameter{T,I}

Time-indexed data for Scenarios. Stores values with their associated time indices,
enabling reuse across different simulation horizons.

Index via `ts[t]` using TimeStep (matches `t.val` to time_axis) or integer position.

# Fields
- `time_axis::Vector{I}`: Time indices (e.g., years, dates)
- `values::Vector{T}`: Data values corresponding to each time index

# Example
```julia
# Sea level rise trajectory for years 2020-2100
slr = TimeSeriesParameter(2020:2100, [0.0, 0.01, 0.02, ...])

# Access by TimeStep (looks up t.val in time_axis)
slr[TimeStep(5, 2025)]  # Returns value for year 2025

# Can reuse with different simulation horizons
# 50-year sim starting 2020: uses years 2020-2069
# 80-year sim starting 2020: uses years 2020-2099
```
"""
struct TimeSeriesParameter{T<:AbstractFloat,I}
    time_axis::Vector{I}
    values::Vector{T}

    function TimeSeriesParameter(
        time_axis::Vector{I}, values::Vector{T}
    ) where {T<:AbstractFloat,I}
        isempty(values) && throw(ArgumentError("TimeSeriesParameter cannot be empty"))
        length(time_axis) != length(values) && throw(
            ArgumentError(
                "time_axis length ($(length(time_axis))) must match values length ($(length(values)))",
            ),
        )
        new{T,I}(time_axis, values)
    end
end

# Convenience constructors
function TimeSeriesParameter(time_axis, values::Vector{T}) where {T<:AbstractFloat}
    TimeSeriesParameter(collect(time_axis), values)
end

function TimeSeriesParameter(time_axis, values)
    TimeSeriesParameter(collect(time_axis), collect(Float64, values))
end

# Legacy constructor: integer-indexed (1:n)
function TimeSeriesParameter(values::Vector{T}) where {T<:AbstractFloat}
    TimeSeriesParameter(collect(1:length(values)), values)
end

TimeSeriesParameter(values) = TimeSeriesParameter(collect(Float64, values))

# Indexing by TimeStep: lookup t.val in time_axis
function Base.getindex(ts::TimeSeriesParameter{T,I}, t::TimeStep) where {T,I}
    idx = findfirst(==(t.val), ts.time_axis)
    isnothing(idx) && throw(TimeSeriesParameterBoundsError(t.val, ts.time_axis))
    ts.values[idx]
end

# Indexing by integer position (1-based)
function Base.getindex(ts::TimeSeriesParameter{T,I}, i::Integer) where {T,I}
    (i < 1 || i > length(ts.values)) && throw(BoundsError(ts, i))
    ts.values[i]
end

Base.length(ts::TimeSeriesParameter) = length(ts.values)
Base.iterate(ts::TimeSeriesParameter) = iterate(ts.values)
Base.iterate(ts::TimeSeriesParameter, state) = iterate(ts.values, state)

"""
    value(ts::TimeSeriesParameter) -> Vector{T}

Extract the underlying values vector from a TimeSeriesParameter.
"""
@inline value(ts::TimeSeriesParameter) = ts.values

"""
    time_axis(ts::TimeSeriesParameter) -> Vector{I}

Extract the time axis from a TimeSeriesParameter.
"""
@inline time_axis(ts::TimeSeriesParameter) = ts.time_axis

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
        :compute_outcome, typeof(config), "step_records::Vector, scenario::AbstractScenario"
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
    state, first_step_record = run_timestep(
        state, first_action, first_ts, config, scenario, rng
    )
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
    config::AbstractConfig,
    scenario::AbstractScenario,
    policy::AbstractPolicy,
    rng::AbstractRNG,
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
function run_simulation(
    config::AbstractConfig, scenario::AbstractScenario, policy::AbstractPolicy
)
    return run_simulation(config, scenario, policy, NoRecorder(), default_rng())
end
