# Abstract type hierarchy - kept simple and unparameterized
# Julia's multiple dispatch catches type mismatches via MethodError at runtime

abstract type AbstractState end
abstract type AbstractPolicy end
abstract type AbstractConfig end
abstract type AbstractSOW end
abstract type AbstractRecorder end
abstract type AbstractAction end

"""
Throw a helpful error for unimplemented interface methods.

Use this when defining fallback methods for interface functions.
"""
function interface_not_implemented(fn::Symbol, T::Type, signature::String="")
    hint = isempty(signature) ? "" : ", $signature"
    throw(
        ArgumentError(
            "Interface method `$fn` not implemented for $T.\n" *
            "Add: `SimOptDecisions.$fn(::$T$hint) = ...`",
        ),
    )
end

"""
Wraps time information passed to simulation callbacks.

- `t`: 1-based index into time_axis
- `val`: Actual time value (Int, Float64, Date, etc.)

Use `is_first(ts)` and `is_last(ts, times)` helper methods to check position.
"""
struct TimeStep{V}
    t::Int
    val::V
end

# ============================================================================
# Action Interface
# ============================================================================

"""
    get_action(policy::AbstractPolicy, state::AbstractState, sow::AbstractSOW, t::TimeStep) -> AbstractAction

Map state + SOW to action. Called by the framework before each `run_timestep`.

Must be implemented for each policy type. Return value must be `<:AbstractAction`.
"""
function get_action(p::AbstractPolicy, state::AbstractState, sow::AbstractSOW, t::TimeStep)
    interface_not_implemented(
        :get_action, typeof(p), "state::AbstractState, sow::AbstractSOW, t::TimeStep"
    )
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

# ============================================================================
# Optimization Direction
# ============================================================================

@enum OptimizationDirection Minimize Maximize

# ============================================================================
# Objective Definition
# ============================================================================

"""
Specifies which metric to optimize and in which direction.

# Fields
- `name::Symbol`: The name of the metric (must be returned by metric_calculator)
- `direction::OptimizationDirection`: Whether to minimize or maximize
"""
struct Objective
    name::Symbol
    direction::OptimizationDirection
end

"""
    minimize(name::Symbol) -> Objective

Create an objective that minimizes the named metric.
"""
minimize(name::Symbol) = Objective(name, Minimize)

"""
    maximize(name::Symbol) -> Objective

Create an objective that maximizes the named metric.
"""
maximize(name::Symbol) = Objective(name, Maximize)

# ============================================================================
# Batch Size Configuration
# ============================================================================

abstract type AbstractBatchSize end

"""
Use all SOWs in the training set for each evaluation.
"""
struct FullBatch <: AbstractBatchSize end

"""
Use a fixed number of SOWs per evaluation.
"""
struct FixedBatch <: AbstractBatchSize
    n::Int

    function FixedBatch(n::Int)
        n > 0 || throw(ArgumentError("Batch size must be positive, got $n"))
        new(n)
    end
end

"""
Use a fraction of the SOWs per evaluation.
"""
struct FractionBatch{T<:AbstractFloat} <: AbstractBatchSize
    fraction::T

    function FractionBatch(f::T) where {T<:AbstractFloat}
        0.0 < f <= 1.0 || throw(ArgumentError("Fraction must be in (0, 1], got $f"))
        new{T}(f)
    end
end

# ============================================================================
# Optimization Backend Abstract Type
# ============================================================================

abstract type AbstractOptimizationBackend end

# ============================================================================
# Metaheuristics Backend Configuration
# ============================================================================

"""
Configuration for Metaheuristics.jl optimization backend.
The actual optimization is implemented in the extension.

# Fields
- `algorithm::Symbol`: Algorithm name (e.g., :ECA, :DE, :PSO)
- `max_iterations::Int`: Maximum number of iterations
- `population_size::Int`: Population size for evolutionary algorithms
- `parallel::Bool`: Enable parallel fitness evaluation (requires Julia threads)
- `options::Dict{Symbol,Any}`: Additional algorithm-specific options
"""
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
