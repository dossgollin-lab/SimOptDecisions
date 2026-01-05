# Abstract type hierarchy - kept simple and unparameterized
# Julia's multiple dispatch catches type mismatches via MethodError at runtime

abstract type AbstractState end
abstract type AbstractPolicy end
abstract type AbstractSystemModel end
abstract type AbstractSOW end
abstract type AbstractRecorder end

"""
Wraps time information passed to the `step` function.

- `t`: 1-based index into time_axis
- `val`: Actual time value (Int, Float64, Date, etc.)
- `is_last`: Whether this is the final time step
"""
struct TimeStep{V}
    t::Int
    val::V
    is_last::Bool
end

# Helper for validation - called at simulation start
function _validate_time_axis(times)
    T = eltype(times)
    if T === Any
        throw(
            ArgumentError(
                "time_axis must return a homogeneously-typed collection. " *
                "Got eltype=Any. Use a concrete type like Vector{Int} or StepRange{Date}.",
            ),
        )
    end
    return nothing
end
