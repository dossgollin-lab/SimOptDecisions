# ============================================================================
# Utils - Helper utilities for simulation and analysis
# ============================================================================

"""
    Utils

Low-level helper utilities for common simulation tasks.

For time-stepped simulations, use `simulate()` which automatically calls the
callbacks (`initialize`, `get_action`, `run_timestep`, `time_axis`, `compute_outcome`).

# Available Functions
- `discount_factor(rate, t)`: Compute discount factor for time t
- `timeindex(times)`: Create iterator of TimeStep from a time axis
- `is_first(ts)`: Check if TimeStep is the first in sequence
- `is_last(ts, times)`: Check if TimeStep is the last in sequence
"""
module Utils

using ..SimOptDecisions: TimeStep

# ============================================================================
# TimeStep Position Helpers
# ============================================================================

"""
    is_first(ts::TimeStep) -> Bool

Check if a TimeStep is the first in the sequence (t == 1).
"""
is_first(ts::TimeStep) = ts.t == 1

"""
    is_last(ts::TimeStep, times) -> Bool
    is_last(ts::TimeStep, n::Integer) -> Bool

Check if a TimeStep is the last in the sequence.

# Examples
```julia
times = 1:10
for ts in timeindex(times)
    if is_last(ts, times)
        println("Final step!")
    end
end
```
"""
is_last(ts::TimeStep, times) = ts.t == length(times)
is_last(ts::TimeStep, n::Integer) = ts.t == n

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
    println("Step \$(ts.t), value \$(ts.val)")
    if is_last(ts, 10)
        println("Done!")
    end
end

# Date range
using Dates
for ts in timeindex(Date(2020):Year(1):Date(2090))
    println("Year \$(ts.t): \$(ts.val)")
end
```
"""
function timeindex(times)
    return (TimeStep(i, v) for (i, v) in enumerate(times))
end

end # module Utils
