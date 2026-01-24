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
