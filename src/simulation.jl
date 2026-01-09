# ============================================================================
# Core Simulation Interface
# ============================================================================

using Random: default_rng

"""
    simulate(config, sow, policy[, recorder][, rng]) -> outcome

Run a simulation. Calls `TimeStepping.run_simulation` which uses five callbacks:
`initialize`, `get_action`, `run_timestep`, `time_axis`, `finalize`.

# Arguments
- `config::AbstractConfig`: Fixed simulation parameters
- `sow::AbstractSOW`: State of the World (exogenous uncertainty)
- `policy::AbstractPolicy`: Decision strategy
- `recorder::AbstractRecorder`: Optional, defaults to `NoRecorder()`
- `rng::AbstractRNG`: Optional, defaults to `Random.default_rng()`

# Examples
```julia
# All valid calling conventions:
simulate(config, sow, policy)                      # minimal
simulate(config, sow, policy, rng)                 # with RNG
simulate(config, sow, policy, recorder)            # with recorder
simulate(config, sow, policy, recorder, rng)       # full
```
"""
function simulate end

# Full signature (all arguments)
function simulate(
    config::AbstractConfig,
    sow::AbstractSOW,
    policy::AbstractPolicy,
    recorder::AbstractRecorder,
    rng::AbstractRNG,
)
    return TimeStepping.run_simulation(config, sow, policy, recorder, rng)
end

# Without recorder (rng only)
function simulate(
    config::AbstractConfig,
    sow::AbstractSOW,
    policy::AbstractPolicy,
    rng::AbstractRNG,
)
    return simulate(config, sow, policy, NoRecorder(), rng)
end

# Without rng (recorder only)
function simulate(
    config::AbstractConfig,
    sow::AbstractSOW,
    policy::AbstractPolicy,
    recorder::AbstractRecorder,
)
    return simulate(config, sow, policy, recorder, default_rng())
end

# Minimal (no recorder, no rng)
function simulate(
    config::AbstractConfig,
    sow::AbstractSOW,
    policy::AbstractPolicy,
)
    return simulate(config, sow, policy, NoRecorder(), default_rng())
end
