# ============================================================================
# Core Simulation Interface
# ============================================================================

using Random: default_rng

"""
    simulate(config, scenario, policy[, recorder][, rng]) -> outcome

Run a simulation. Calls `run_simulation` which uses five callbacks:
`initialize`, `get_action`, `run_timestep`, `time_axis`, `compute_outcome`.

# Arguments
- `config::AbstractConfig`: Fixed simulation parameters
- `scenario::AbstractScenario`: Scenario (exogenous uncertainty)
- `policy::AbstractPolicy`: Decision strategy
- `recorder::AbstractRecorder`: Optional, defaults to `NoRecorder()`
- `rng::AbstractRNG`: Optional, defaults to `Random.default_rng()`

# Examples
```julia
# All valid calling conventions:
simulate(config, scenario, policy)                      # minimal
simulate(config, scenario, policy, rng)                 # with RNG
simulate(config, scenario, policy, recorder)            # with recorder
simulate(config, scenario, policy, recorder, rng)       # full
```
"""
function simulate end

# Full signature (all arguments)
function simulate(
    config::AbstractConfig,
    scenario::AbstractScenario,
    policy::AbstractPolicy,
    recorder::AbstractRecorder,
    rng::AbstractRNG,
)
    return run_simulation(config, scenario, policy, recorder, rng)
end

# Without recorder (rng only)
function simulate(
    config::AbstractConfig, scenario::AbstractScenario, policy::AbstractPolicy, rng::AbstractRNG
)
    return simulate(config, scenario, policy, NoRecorder(), rng)
end

# Without rng (recorder only)
function simulate(
    config::AbstractConfig,
    scenario::AbstractScenario,
    policy::AbstractPolicy,
    recorder::AbstractRecorder,
)
    return simulate(config, scenario, policy, recorder, default_rng())
end

# Minimal (no recorder, no rng)
function simulate(config::AbstractConfig, scenario::AbstractScenario, policy::AbstractPolicy)
    return simulate(config, scenario, policy, NoRecorder(), default_rng())
end

# ============================================================================
# Convenience Functions
# ============================================================================

"""
    simulate_traced(config, scenario, policy[, rng]) -> (outcome, trace)

Run a simulation and return both the outcome and a typed SimulationTrace.
This is a convenience wrapper around simulate() with TraceRecorderBuilder.

# Example
```julia
outcome, trace = simulate_traced(config, scenario, policy, rng)
# trace.states, trace.actions, etc. are now available
```
"""
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

# Overload without rng
function simulate_traced(
    config::AbstractConfig, scenario::AbstractScenario, policy::AbstractPolicy
)
    return simulate_traced(config, scenario, policy, default_rng())
end
