# Abstract type hierarchy - kept simple and unparameterized
# Julia's multiple dispatch catches type mismatches via MethodError at runtime

abstract type AbstractState end
abstract type AbstractPolicy end
abstract type AbstractConfig end
abstract type AbstractScenario end
abstract type AbstractRecorder end
abstract type AbstractAction end

# ============================================================================
# Parameter Types for Exploratory Modeling
# ============================================================================

"""
    AbstractParameter{T}

Base type for typed parameters used in exploratory modeling.
Subtypes enable automatic flattening of Scenarios, Policies, and Outcomes for analysis.

To use `explore()`, all fields in your types must be `<:AbstractParameter` or `TimeSeriesParameter`.
"""
abstract type AbstractParameter{T} end

"""
    ContinuousParameter{T<:AbstractFloat}

A continuous real-valued parameter with optional bounds.

# Fields
- `value::T`: The parameter value
- `bounds::Tuple{T,T}`: (lower, upper) bounds, defaults to (-Inf, Inf)

# Example
```julia
ContinuousParameter(0.5)                    # unbounded
ContinuousParameter(0.5, (0.0, 1.0))        # bounded
```
"""
struct ContinuousParameter{T<:AbstractFloat} <: AbstractParameter{T}
    value::T
    bounds::Tuple{T,T}
end
function ContinuousParameter(value::T) where {T<:AbstractFloat}
    ContinuousParameter(value, (T(-Inf), T(Inf)))
end

"""
    DiscreteParameter{T<:Integer}

An integer-valued parameter with optional valid values constraint.

# Fields
- `value::T`: The parameter value
- `valid_values::Union{Nothing,Vector{T}}`: Allowed values, or nothing for any integer

# Example
```julia
DiscreteParameter(5)                        # any integer
DiscreteParameter(2, [1, 2, 3, 4, 5])       # constrained to set
DiscreteParameter(3, 1:5)                   # constrained to range (collected)
```
"""
struct DiscreteParameter{T<:Integer} <: AbstractParameter{T}
    value::T
    valid_values::Union{Nothing,Vector{T}}

    function DiscreteParameter(value::T, valid_values::Vector{T}) where {T<:Integer}
        value ∈ valid_values || throw(ArgumentError("Value `$value` not in valid_values $valid_values"))
        new{T}(value, valid_values)
    end

    function DiscreteParameter(value::T, ::Nothing) where {T<:Integer}
        new{T}(value, nothing)
    end
end

# Convenience: unconstrained integer
DiscreteParameter(value::T) where {T<:Integer} = DiscreteParameter(value, nothing)

# Convenience: accept any iterable for valid_values (ranges, sets, tuples)
function DiscreteParameter(value::T, valid_values) where {T<:Integer}
    DiscreteParameter(value, collect(T, valid_values))
end

"""
    CategoricalParameter{T}

A categorical parameter with defined levels.

# Fields
- `value::T`: The current value (must be in levels)
- `levels::Vector{T}`: All valid categorical values

# Example
```julia
CategoricalParameter(:high, [:low, :medium, :high])
CategoricalParameter("scenario_a", ["scenario_a", "scenario_b"])
CategoricalParameter(:a, (:a, :b, :c))  # tuple converted to vector
```
"""
struct CategoricalParameter{T} <: AbstractParameter{T}
    value::T
    levels::Vector{T}

    function CategoricalParameter(value::T, levels::Vector{T}) where {T}
        value ∈ levels || throw(ArgumentError("Value `$value` not in levels $levels"))
        new{T}(value, levels)
    end
end

# Convenience: accept any iterable for levels (tuples, sets, etc.)
function CategoricalParameter(value::T, levels) where {T}
    CategoricalParameter(value, collect(T, levels))
end

"""
    GenericParameter{T}

A parameter holding any value. The framework cannot optimize, explore, or visualize this type.

Use only when you need to pass complex objects through the simulation that don't fit
other parameter types. Consider using CategoricalParameter with an identifier instead.

# Example
```julia
# Prefer this pattern:
struct MyScenario <: AbstractScenario
    model_id::CategoricalParameter{String}  # identifier
end
# Then load models from config based on model_id

# GenericParameter is a last resort:
struct MyScenario <: AbstractScenario
    complex_object::GenericParameter{MyComplexType}
end
```
"""
struct GenericParameter{T} <: AbstractParameter{T}
    value::T

    function GenericParameter(value::T) where {T}
        @warn """GenericParameter detected. This type cannot be:
  - Optimized (no bounds)
  - Explored (cannot flatten to table)
  - Visualized (no numeric representation)
Consider using CategoricalParameter with an identifier instead.""" maxlog = 1
        new{T}(value)
    end
end

"""
    value(p::AbstractParameter) -> T

Extract the value from a parameter.
"""
@inline value(p::AbstractParameter) = p.value

Base.getindex(p::AbstractParameter) = p.value

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
    get_action(policy::AbstractPolicy, state::AbstractState, t::TimeStep, scenario::AbstractScenario) -> Any

Map state + scenario to action. Called by the framework before each `run_timestep`.

Must be implemented for each policy type. Return value can be any type (AbstractAction optional).
"""
function get_action(
    p::AbstractPolicy, state::AbstractState, t::TimeStep, scenario::AbstractScenario
)
    interface_not_implemented(
        :get_action,
        typeof(p),
        "state::AbstractState, t::TimeStep, scenario::AbstractScenario",
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
Use all scenarios in the training set for each evaluation.
"""
struct FullBatch <: AbstractBatchSize end

"""
Use a fixed number of scenarios per evaluation.
"""
struct FixedBatch <: AbstractBatchSize
    n::Int

    function FixedBatch(n::Int)
        n > 0 || throw(ArgumentError("Batch size must be positive, got $n"))
        new(n)
    end
end

"""
Use a fraction of the scenarios per evaluation.
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
