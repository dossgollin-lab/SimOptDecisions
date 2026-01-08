# ============================================================================
# TimeStepping - Structured interface for time-stepped simulations
# ============================================================================

"""
    TimeStepping

Submodule for time-stepped simulations. Implement four callbacks:

| Function | Purpose | Returns |
|----------|---------|---------|
| `initialize(config, sow, rng)` | Create initial state | `state` |
| `run_timestep(state, config, sow, policy, t, rng)` | Execute one step | `(new_state, step_record)` |
| `time_axis(config, sow)` | Define time points | Iterable |
| `finalize(final_state, step_records, config, sow)` | Aggregate results | `Outcome` |

`simulate()` automatically calls these via `run_simulation`. See docs for examples.
"""
module TimeStepping

using Random: AbstractRNG

using ..SimOptDecisions:
    AbstractConfig,
    AbstractSOW,
    AbstractPolicy,
    AbstractRecorder,
    TimeStep,
    NoRecorder,
    record!,
    get_action,
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
    print(io, "TimeSeriesParameterBoundsError: index $(e.index) exceeds data length $(e.length). ")
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
    (i < 1 || i > length(ts.data)) && throw(TimeSeriesParameterBoundsError(i, length(ts.data)))
    ts.data[i]
end

Base.length(ts::TimeSeriesParameter) = length(ts.data)
Base.iterate(ts::TimeSeriesParameter) = iterate(ts.data)
Base.iterate(ts::TimeSeriesParameter, state) = iterate(ts.data, state)

# ============================================================================
# User-Implemented Interface Functions
# ============================================================================

"""Create initial state. Default returns `nothing` (stateless models)."""
function initialize end

initialize(::AbstractConfig, ::AbstractSOW, ::AbstractRNG) = nothing

"""Execute one timestep. Returns `(new_state, step_record)`."""
function run_timestep end

"""Return time points iterable with defined `length()`."""
function time_axis end

"""Aggregate step records into outcome. Default returns `final_state`."""
function finalize end

finalize(final_state, step_records::Vector, ::AbstractConfig, ::AbstractSOW) = final_state

# ============================================================================
# Framework-Provided Runner
# ============================================================================

"""
    run_simulation(config, sow, policy, rng; recorder=NoRecorder()) -> Outcome

Run time-stepped simulation using callbacks. Called automatically by `simulate()`.
"""
function run_simulation(
    config::AbstractConfig,
    sow::AbstractSOW,
    policy::AbstractPolicy,
    rng::AbstractRNG;
    recorder::AbstractRecorder=NoRecorder()
)
    times = time_axis(config, sow)
    _validate_time_axis(times)
    n = length(times)

    state = initialize(config, sow, rng)
    record!(recorder, state, nothing, nothing)

    timesteps = timeindex(times)
    first_ts, rest = Iterators.peel(timesteps)

    state, first_output = run_timestep(state, config, sow, policy, first_ts, rng)
    record!(recorder, state, first_output, first_ts.val)

    outputs = Vector{typeof(first_output)}(undef, n)
    outputs[1] = first_output

    for ts in rest
        state, output = run_timestep(state, config, sow, policy, ts, rng)
        outputs[ts.t] = output
        record!(recorder, state, output, ts.val)
    end

    return finalize(state, outputs, config, sow)
end

end # module TimeStepping
