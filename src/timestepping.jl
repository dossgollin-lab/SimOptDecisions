# ============================================================================
# Time-stepped simulation interface
# ============================================================================
# Users implement five callbacks:
# - initialize(config, scenario, rng) -> state
# - get_action(policy, state, t, scenario) -> action
# - run_timestep(state, action, t, config, scenario, rng) -> (new_state, step_record)
# - time_axis(config, scenario) -> Iterable
# - compute_outcome(step_records, config, scenario) -> Outcome

using Random: AbstractRNG, default_rng

# ============================================================================
# TimeSeriesParameter
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

"""Time-indexed data. Index via `ts[t]` using TimeStep or integer position."""
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

function TimeSeriesParameter(time_axis, values::Vector{T}) where {T<:AbstractFloat}
    TimeSeriesParameter(collect(time_axis), values)
end
function TimeSeriesParameter(time_axis, values)
    TimeSeriesParameter(collect(time_axis), collect(Float64, values))
end
function TimeSeriesParameter(values::Vector{T}) where {T<:AbstractFloat}
    TimeSeriesParameter(collect(1:length(values)), values)
end
TimeSeriesParameter(values) = TimeSeriesParameter(collect(Float64, values))

function Base.getindex(ts::TimeSeriesParameter{T,I}, t::TimeStep) where {T,I}
    idx = findfirst(==(t.val), ts.time_axis)
    isnothing(idx) && throw(TimeSeriesParameterBoundsError(t.val, ts.time_axis))
    ts.values[idx]
end

function Base.getindex(ts::TimeSeriesParameter{T,I}, i::Integer) where {T,I}
    (i < 1 || i > length(ts.values)) && throw(BoundsError(ts, i))
    ts.values[i]
end

Base.length(ts::TimeSeriesParameter) = length(ts.values)
Base.iterate(ts::TimeSeriesParameter) = iterate(ts.values)
Base.iterate(ts::TimeSeriesParameter, state) = iterate(ts.values, state)

"""Extract the underlying values vector."""
@inline value(ts::TimeSeriesParameter) = ts.values

"""Extract the time axis."""
@inline time_axis(ts::TimeSeriesParameter) = ts.time_axis

# ============================================================================
# TimeStep Accessors
# ============================================================================

"""Return the 1-based index of the timestep."""
@inline index(t::TimeStep) = t.t

"""Return the value (e.g., year, date) of the timestep."""
@inline value(t::TimeStep) = t.val

# ============================================================================
# User-Implemented Callbacks
# ============================================================================

"""Create initial state for simulation. Required callback."""
function initialize end

function initialize(config::AbstractConfig, scenario::AbstractScenario, ::AbstractRNG)
    return initialize(config, scenario)
end

function initialize(config::AbstractConfig, ::AbstractScenario)
    interface_not_implemented(
        :initialize, typeof(config), "scenario::AbstractScenario[, rng::AbstractRNG]"
    )
end

"""Execute one timestep transition. Required callback."""
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

"""Return time points iterable with defined `length()`. Required callback."""
function time_axis end

function time_axis(config::AbstractConfig, scenario::AbstractScenario)
    interface_not_implemented(:time_axis, typeof(config), "scenario::AbstractScenario")
end

"""Aggregate step records into final outcome. Required callback."""
function compute_outcome end

function compute_outcome(step_records, config::AbstractConfig, ::AbstractScenario)
    interface_not_implemented(
        :compute_outcome, typeof(config), "step_records::Vector, scenario::AbstractScenario"
    )
end

# ============================================================================
# Framework Runner
# ============================================================================

"""Run time-stepped simulation using callbacks. Called automatically by `simulate()`."""
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

function run_simulation(
    config::AbstractConfig,
    scenario::AbstractScenario,
    policy::AbstractPolicy,
    rng::AbstractRNG,
)
    run_simulation(config, scenario, policy, NoRecorder(), rng)
end

function run_simulation(
    config::AbstractConfig,
    scenario::AbstractScenario,
    policy::AbstractPolicy,
    recorder::AbstractRecorder,
)
    run_simulation(config, scenario, policy, recorder, default_rng())
end

function run_simulation(
    config::AbstractConfig, scenario::AbstractScenario, policy::AbstractPolicy
)
    run_simulation(config, scenario, policy, NoRecorder(), default_rng())
end
