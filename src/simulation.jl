# ============================================================================
# Core Simulation Interface
# ============================================================================

"""
    simulate(config, sow, policy, rng) -> outcome

Run a simulation. The `rng` argument is required for reproducibility.

By default, calls `TimeStepping.run_simulation` which uses the four callbacks:
`initialize`, `run_timestep`, `time_axis`, `finalize`.

For non-time-stepped models, override `simulate` directly.
"""
function simulate end

# Default: auto-call TimeStepping.run_simulation
function simulate(
    config::AbstractConfig,
    sow::AbstractSOW,
    policy::AbstractPolicy,
    rng::AbstractRNG,
)
    return TimeStepping.run_simulation(config, sow, policy, rng)
end

# ============================================================================
# Recording Support
# ============================================================================

"""
    simulate(config, sow, policy, recorder, rng) -> outcome

Run a simulation with recording support.
"""
function simulate(
    config::AbstractConfig,
    sow::AbstractSOW,
    policy::AbstractPolicy,
    recorder::AbstractRecorder,
    rng::AbstractRNG,
)
    return TimeStepping.run_simulation(config, sow, policy, rng; recorder=recorder)
end
