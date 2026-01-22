# ============================================================================
# Core Abstract Types and TimeStep
# ============================================================================

# Abstract type hierarchy
abstract type AbstractState end
abstract type AbstractPolicy end
abstract type AbstractConfig end
abstract type AbstractScenario end
abstract type AbstractRecorder end
abstract type AbstractAction end
abstract type AbstractOutcome end

"""Throw a helpful error for unimplemented interface methods."""
function interface_not_implemented(fn::Symbol, T::Type, signature::String="")
    hint = isempty(signature) ? "" : ", $signature"
    throw(
        ArgumentError(
            "Interface method `$fn` not implemented for $T.\n" *
            "Add: `SimOptDecisions.$fn(::$T$hint) = ...`",
        ),
    )
end

"""Time information for callbacks: `t` (1-based index), `val` (actual time value)."""
struct TimeStep{V}
    t::Int
    val::V
end

"""Return the 1-based index of the timestep."""
@inline index(t::TimeStep) = t.t

"""Return the value (e.g., year, date) of the timestep."""
@inline value(t::TimeStep) = t.val

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

# ============================================================================
# Action Interface
# ============================================================================

"""Map state + scenario to action. Called by framework before each `run_timestep`."""
function get_action(
    p::AbstractPolicy, state::AbstractState, t::TimeStep, scenario::AbstractScenario
)
    interface_not_implemented(
        :get_action,
        typeof(p),
        "state::AbstractState, t::TimeStep, scenario::AbstractScenario",
    )
end

# ============================================================================
# Optimization
# ============================================================================

@enum OptimizationDirection Minimize Maximize

"""Specifies which metric to optimize and in which direction."""
struct Objective
    name::Symbol
    direction::OptimizationDirection
end

"""Create an objective that minimizes the named metric."""
minimize(name::Symbol) = Objective(name, Minimize)

"""Create an objective that maximizes the named metric."""
maximize(name::Symbol) = Objective(name, Maximize)

# ============================================================================
# Batch Size Configuration
# ============================================================================

abstract type AbstractBatchSize end

"""Use all scenarios for each evaluation."""
struct FullBatch <: AbstractBatchSize end

"""Use a fixed number of scenarios per evaluation."""
struct FixedBatch <: AbstractBatchSize
    n::Int

    function FixedBatch(n::Int)
        n > 0 || throw(ArgumentError("Batch size must be positive, got $n"))
        new(n)
    end
end

"""Use a fraction of scenarios per evaluation."""
struct FractionBatch{T<:AbstractFloat} <: AbstractBatchSize
    fraction::T

    function FractionBatch(f::T) where {T<:AbstractFloat}
        0.0 < f <= 1.0 || throw(ArgumentError("Fraction must be in (0, 1], got $f"))
        new{T}(f)
    end
end

# ============================================================================
# Optimization Backend
# ============================================================================

abstract type AbstractOptimizationBackend end

"""Configuration for Metaheuristics.jl backend. Actual optimization in extension."""
struct MetaheuristicsBackend <: AbstractOptimizationBackend
    algorithm::Symbol
    max_iterations::Int
    population_size::Int
    parallel::Bool
    options::Dict{Symbol,Any}

    function MetaheuristicsBackend(;
        algorithm::Symbol=:ECA,
        max_iterations::Int=1000,
        population_size::Int=100,
        parallel::Bool=true,
        options::Dict{Symbol,Any}=Dict{Symbol,Any}(),
    )
        new(algorithm, max_iterations, population_size, parallel, options)
    end
end
