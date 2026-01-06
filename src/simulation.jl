# ============================================================================
# Core Simulation Interface
# ============================================================================

"""
    simulate(params, sow, policy, rng) -> outcome

Run a simulation with the given parameters, state of the world, and policy.

This is the core interface that users must implement. The return type is
user-defined (typically a NamedTuple or custom outcome type).

# Implementation Options

## Direct Implementation (non-time-stepped)
For closed-form solutions, optimization-based models, or external simulators:
```julia
function SimOptDecisions.simulate(
    params::MyParams,
    sow::MySOW,
    policy::MyPolicy,
    rng::AbstractRNG
)
    # Direct computation, solver call, external simulator, etc.
    return (cost = compute_cost(params, sow, policy),)
end
```

## Time-Stepped Implementation
For models that iterate through discrete time steps, use the TimeStepping helper:
```julia
function SimOptDecisions.simulate(params::MyParams, sow::MySOW, policy::MyPolicy, rng)
    SimOptDecisions.TimeStepping.run_timestepped(params, sow, policy, rng)
end
```

See `SimOptDecisions.TimeStepping` module for the time-stepping interface.
"""
function simulate end

function simulate(
    params::AbstractFixedParams,
    sow::AbstractSOW,
    policy::AbstractPolicy,
    rng::AbstractRNG,
)
    return error(
        "Implement `SimOptDecisions.simulate(::$(typeof(params)), ::$(typeof(sow)), " *
        "::$(typeof(policy)), ::AbstractRNG)` to return simulation outcome",
    )
end

# ============================================================================
# Convenience Overloads
# ============================================================================

# Keyword arguments with defaults
function simulate(
    params::AbstractFixedParams,
    sow::AbstractSOW,
    policy::AbstractPolicy;
    rng::AbstractRNG=Random.default_rng(),
)
    return simulate(params, sow, policy, rng)
end

# ============================================================================
# Recording Support (Optional)
# ============================================================================

"""
    simulate(params, sow, policy, recorder, rng) -> outcome

Run a simulation with recording support.

For time-stepped models, pass the recorder to `run_timestepped()`.
For other models, handle recording in your implementation or ignore the recorder.

Default implementation ignores the recorder and calls the base simulate.
Override for time-stepped models:
```julia
function SimOptDecisions.simulate(params::MyParams, sow, policy, recorder, rng)
    SimOptDecisions.TimeStepping.run_timestepped(params, sow, policy, recorder, rng)
end
```
"""
function simulate(
    params::AbstractFixedParams,
    sow::AbstractSOW,
    policy::AbstractPolicy,
    recorder::AbstractRecorder,
    rng::AbstractRNG,
)
    # Default: ignore recorder, call base simulate
    # Users override for recording support
    return simulate(params, sow, policy, rng)
end

# Convenience: recorder with default rng
function simulate(
    params::AbstractFixedParams,
    sow::AbstractSOW,
    policy::AbstractPolicy,
    recorder::AbstractRecorder,
)
    return simulate(params, sow, policy, recorder, Random.default_rng())
end
