# ============================================================================
# Utils - Helper utilities for simulation and analysis
# ============================================================================

"""
    Utils

Helper utilities for common simulation tasks.

# Available Functions
- `discount_factor(rate, t)`: Compute discount factor for time t
- `timeindex(times)`: Create iterator of TimeStep from a time axis
- `run_timesteps(step_fn, init_state, time_axis)`: Run a time-stepped simulation with preallocation
"""
module Utils

using ..SimOptDecisions: TimeStep

# ============================================================================
# Discounting
# ============================================================================

"""
    discount_factor(rate, t)

Compute discount factor for time `t` at the given discount rate.

Returns `1 / (1 + rate)^t`.

# Example
```julia
# 5% discount rate, year 10
df = discount_factor(0.05, 10)  # ≈ 0.614
```
"""
discount_factor(rate, t) = 1 / (1 + rate)^t

# ============================================================================
# Time Indexing
# ============================================================================

"""
    timeindex(times)

Create an iterator of `TimeStep` from a time axis.

Works with any iterable that has a defined `length()`: integer ranges,
date ranges, vectors, etc.

# Example
```julia
# Integer range
for ts in timeindex(1:10)
    println("Step \$(ts.t), value \$(ts.val), last=\$(ts.is_last)")
end

# Date range
using Dates
for ts in timeindex(Date(2020):Year(1):Date(2090))
    println("Year \$(ts.t): \$(ts.val)")
end
```
"""
function timeindex(times)
    n = length(times)
    return (TimeStep(i, v, i == n) for (i, v) in enumerate(times))
end

# ============================================================================
# Time-Stepped Simulation Helper
# ============================================================================

"""
    run_timesteps(step_fn, init_state, time_axis) -> (final_state, outputs)

Run a time-stepped simulation with preallocation, collecting outputs at each step.

This helper eliminates the need for `push!` and manual preallocation when running
time-stepped simulations. The step function returns both a new state and an output
value, and all outputs are collected into a preallocated vector.

# Arguments
- `step_fn`: Function `(state, ts::TimeStep) -> (new_state, output)` called at each time step
- `init_state`: Initial state value (can be any type, including `nothing` for stateless models)
- `time_axis`: Iterable with `length()` defining time steps (e.g., `1:100`, date ranges)

# Returns
- `final_state`: State after the last time step
- `outputs`: `Vector{O}` of outputs, one per time step (type `O` inferred from first step)

# Example

```julia
function SimOptDecisions.simulate(params, sow, policy, rng)
    init_storage = 0.0

    final_state, damages = Utils.run_timesteps(init_storage, 1:params.horizon) do state, ts
        damage = compute_damage(state, ts, sow, policy)
        new_storage = state + policy.investment
        return (new_storage, damage)
    end

    # Post-process collected outputs
    npv = sum(damages[t] * Utils.discount_factor(rate, t) for t in eachindex(damages))
    return (npv_damages=npv, final_storage=final_state)
end
```

For models without state, pass `nothing` as `init_state`:

```julia
_, annual_damages = Utils.run_timesteps(nothing, 1:horizon) do state, ts
    damage = compute_damage(ts, sow, policy)
    return (state, damage)  # state unchanged
end
```

Output can be any type (scalar, NamedTuple, custom struct):

```julia
_, results = Utils.run_timesteps(init, 1:n) do state, ts
    return (new_state, (damage=d, cost=c, emissions=e))  # NamedTuple output
end
# results[t].damage, results[t].cost, etc.
```
"""
function run_timesteps(step_fn, init_state, time_axis)
    n = length(time_axis)
    times = timeindex(time_axis)

    state = init_state
    first_ts, rest = Iterators.peel(times)
    state, first_out = step_fn(state, first_ts)

    outputs = Vector{typeof(first_out)}(undef, n)
    outputs[1] = first_out

    for ts in rest
        state, out = step_fn(state, ts)
        outputs[ts.t] = out
    end

    return (state, outputs)
end

end # module Utils
