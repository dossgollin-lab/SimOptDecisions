# ============================================================================
# Utils - Helper utilities for simulation and analysis
# ============================================================================

"""
    Utils

Low-level helper utilities for common simulation tasks.

For time-stepped simulations, use `simulate()` which automatically calls the
TimeStepping callbacks (`initialize`, `run_timestep`, `time_axis`, `finalize`).

# Available Functions
- `discount_factor(rate, t)`: Compute discount factor for time t
- `timeindex(times)`: Create iterator of TimeStep from a time axis
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

end # module Utils
