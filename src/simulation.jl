# ============================================================================
# Core Simulation Interface
# ============================================================================

using Random: default_rng

"""Run a simulation using five callbacks: initialize, get_action, run_timestep, time_axis, compute_outcome."""
function simulate end

function simulate(
    config::AbstractConfig,
    scenario::AbstractScenario,
    policy::AbstractPolicy,
    recorder::AbstractRecorder,
    rng::AbstractRNG,
)
    _validate_simulation_types(scenario, policy)
    outcome = run_simulation(config, scenario, policy, recorder, rng)
    _validate_outcome_type(outcome)
    return outcome
end

function simulate(
    config::AbstractConfig,
    scenario::AbstractScenario,
    policy::AbstractPolicy,
    rng::AbstractRNG,
)
    simulate(config, scenario, policy, NoRecorder(), rng)
end

function simulate(
    config::AbstractConfig,
    scenario::AbstractScenario,
    policy::AbstractPolicy,
    recorder::AbstractRecorder,
)
    simulate(config, scenario, policy, recorder, default_rng())
end

function simulate(
    config::AbstractConfig, scenario::AbstractScenario, policy::AbstractPolicy
)
    simulate(config, scenario, policy, NoRecorder(), default_rng())
end

# ============================================================================
# Convenience Functions
# ============================================================================

"""Run a simulation and return both the outcome and a typed SimulationTrace."""
function simulate_traced(
    config::AbstractConfig,
    scenario::AbstractScenario,
    policy::AbstractPolicy,
    rng::AbstractRNG,
)
    builder = TraceRecorderBuilder()
    outcome = simulate(config, scenario, policy, builder, rng)
    trace = build_trace(builder)
    return (outcome, trace)
end

function simulate_traced(
    config::AbstractConfig, scenario::AbstractScenario, policy::AbstractPolicy
)
    simulate_traced(config, scenario, policy, default_rng())
end
