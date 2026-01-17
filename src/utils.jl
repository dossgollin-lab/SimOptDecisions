# ============================================================================
# Utils - Helper utilities for simulation
# ============================================================================

"""Check if a TimeStep is the first in the sequence (index == 1)."""
is_first(ts::TimeStep) = ts.t == 1

"""Check if a TimeStep is the last in the sequence."""
is_last(ts::TimeStep, times) = ts.t == length(times)
is_last(ts::TimeStep, n::Integer) = ts.t == n

"""Compute discount factor for time `t` at the given rate. Returns `1 / (1 + rate)^t`."""
discount_factor(rate, t) = 1 / (1 + rate)^t

"""Create an iterator of `TimeStep` from a time axis."""
timeindex(times) = (TimeStep(i, v) for (i, v) in enumerate(times))
