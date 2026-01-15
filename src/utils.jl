# ============================================================================
# Utils - Helper utilities for simulation and analysis
# ============================================================================

# ============================================================================
# TimeStep Position Helpers (defined at module level)
# ============================================================================

"""
    is_first(ts::TimeStep) -> Bool

Check if a TimeStep is the first in the sequence (index == 1).
"""
is_first(ts::TimeStep) = ts.t == 1

"""
    is_last(ts::TimeStep, times) -> Bool
    is_last(ts::TimeStep, n::Integer) -> Bool

Check if a TimeStep is the last in the sequence.
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
"""
discount_factor(rate, t) = 1 / (1 + rate)^t

# ============================================================================
# Time Indexing
# ============================================================================

"""
    timeindex(times)

Create an iterator of `TimeStep` from a time axis.
Works with any iterable that has a defined `length()`.
"""
function timeindex(times)
    return (TimeStep(i, v) for (i, v) in enumerate(times))
end

# ============================================================================
# Utils Submodule (backward compatibility)
# ============================================================================

"""
    Utils

Submodule providing helper utilities for common simulation tasks.
Functions are also exported directly from SimOptDecisions.

# Available Functions
- `discount_factor(rate, t)`: Compute discount factor for time t
- `timeindex(times)`: Create iterator of TimeStep from a time axis
- `is_first(ts)`: Check if TimeStep is the first in sequence
- `is_last(ts, times)`: Check if TimeStep is the last in sequence
"""
module Utils
    # Re-export from parent module for backward compatibility
    using ..SimOptDecisions: discount_factor, is_first, is_last, timeindex, TimeStep
    export discount_factor, is_first, is_last, timeindex
end
