# Implementation Details

This document contains implementation-specific code and design decisions for building SimOptDecisions.jl. For user-facing documentation, see [README.md](README.md).

## Time Axis Validation

Validate at simulation start to catch `Vector{Any}` early:

```julia
function _validate_time_axis(times)
    T = eltype(times)
    if T === Any
        throw(ArgumentError(
            "time_axis must return a homogeneously-typed collection. " *
            "Got eltype=Any. Use a concrete type like Vector{Int} or StepRange{Date}."
        ))
    end
end
```

**Note:** The simulation loop calls `length(times)`, so `time_axis` must return something with a defined length (e.g., `Vector`, `UnitRange`, `StepRange`). True generators/iterators without known length are not supported.

## TraceRecorder Implementation

```julia
# Parameterized to avoid Vector{Any} - critical for performance
struct TraceRecorder{S, T}
    states::Vector{S}
    times::Vector{T}
end

# Factory that uses Vector{Any} during recording
mutable struct TraceRecorderBuilder
    states::Vector{Any}
    times::Vector{Any}
    TraceRecorderBuilder() = new([], [])
end

function record!(r::TraceRecorderBuilder, state, t)
    push!(r.states, state)
    push!(r.times, t)
end

# Convert to typed recorder after simulation
function finalize(r::TraceRecorderBuilder)
    S = typeof(r.states[2])  # Skip initial nothing/state pair
    T = typeof(r.times[2])
    TraceRecorder{S,T}(
        convert(Vector{S}, r.states[2:end]),
        convert(Vector{T}, r.times[2:end])
    )
end

# Pre-allocated recorder when you know the types
function TraceRecorder{S,T}(n::Int) where {S,T}
    TraceRecorder{S,T}(Vector{S}(undef, n), Vector{T}(undef, n))
end
```

### Tables.jl Integration

`TraceRecorder` must implement `Tables.istable`, `Tables.rows`, `Tables.columns`.

## Data Extraction Interface

Users implement `to_scalars` for custom state types:

```julia
function to_scalars(state::HouseElevationState)
    (; elevation=state.elevation, flood_damage=state.cumulative_damage,
       npv=state.net_present_value)
end
```

## Policy Interface Definitions

```julia
# Core defines these interface functions (throw "not implemented" by default)
function params end      # policy -> AbstractVector{<:AbstractFloat}
function param_bounds end  # Type -> Vector{Tuple{T,T}}

# Default implementations that throw helpful errors
params(p::AbstractPolicy) = error(
    "Implement `SimOptDecisions.params(::$(typeof(p)))` to return parameter vector"
)
param_bounds(::Type{T}) where {T<:AbstractPolicy} = error(
    "Implement `SimOptDecisions.param_bounds(::Type{$T})` to return bounds"
)
```

## Batch Size Configuration

Type hierarchy for batch size (maintains type stability):

```julia
abstract type AbstractBatchSize end

struct FullBatch <: AbstractBatchSize end           # Use all SOWs

struct FixedBatch <: AbstractBatchSize
    n::Int
end

struct FractionBatch <: AbstractBatchSize
    fraction::Float64  # in (0.0, 1.0]

    function FractionBatch(f::Float64)
        0.0 < f <= 1.0 || throw(ArgumentError("Fraction must be in (0, 1]"))
        new(f)
    end
end
```

## OptimizationProblem Constructor

Full constructor with validation:

```julia
function OptimizationProblem(model, sows, policy_type::Type{<:AbstractPolicy},
                             calculator, objectives; batch_size=FullBatch())
    _validate_sows(sows)
    _validate_policy_interface(policy_type)
    OptimizationProblem(model, sows, policy_type, calculator, objectives, batch_size)
end
```

### Policy Interface Validation

```julia
function _validate_policy_interface(::Type{P}) where P<:AbstractPolicy
    # Check param_bounds is implemented
    try
        bounds = param_bounds(P)
        if !isa(bounds, AbstractVector)
            throw(ArgumentError("param_bounds must return a Vector of tuples"))
        end
    catch e
        e isa ErrorException && rethrow()
        throw(ArgumentError("param_bounds(::Type{$P}) failed: $e"))
    end

    # Check constructor works with a sample vector
    bounds = param_bounds(P)
    sample_x = [(b[1] + b[2]) / 2 for b in bounds]
    try
        test_policy = P(sample_x)
        if !(test_policy isa AbstractPolicy)
            throw(ArgumentError("$P(x) must return an AbstractPolicy"))
        end
    catch e
        throw(ArgumentError(
            "$P must have a constructor accepting AbstractVector. " *
            "Add: $P(x::AbstractVector{T}) where T<:AbstractFloat = ..."
        ))
    end
end
```

## Policy Evaluation

```julia
function evaluate_policy(prob::OptimizationProblem, policy, rng::AbstractRNG)
    outcomes = map(prob.training_sows) do sow
        simulate(prob.model, sow, policy, NoRecorder(), rng)
    end
    return prob.metric_calculator(outcomes)
end

# Convenience: uses seeded RNG
evaluate_policy(prob, policy; seed=1234) =
    evaluate_policy(prob, policy, Xoshiro(seed))
```

## Backend Interface

```julia
abstract type AbstractOptimizationBackend end

# Generic entry point
function optimize(prob::OptimizationProblem, backend::AbstractOptimizationBackend)
    validate(prob)
    return optimize_backend(prob, backend)
end

function optimize_backend end # Empty function, methods added by Extensions
```

## Validation and Constraints

### Validation Hooks

```julia
validate(model::AbstractSystemModel) = true          # Override for domain-specific
validate(policy::AbstractPolicy, model) = true       # Override for domain-specific
validate(prob::OptimizationProblem) = Bool           # Called by optimize()
```

`validate(prob)` checks model, SOWs, and that the policy type implements the required interface.

### Constraint Handling

For constrained optimization problems:

```julia
abstract type AbstractConstraint end

struct FeasibilityConstraint <: AbstractConstraint
    name::Symbol
    func::Function  # policy -> Bool (true = feasible)
end

struct PenaltyConstraint <: AbstractConstraint
    name::Symbol
    func::Function  # policy -> Float64 (0.0 = no violation)
    weight::Float64
end
```

Constraints can be added to `OptimizationProblem` as an optional field. The extension applies them during fitness evaluation.

## Metaheuristics Extension

File: `ext/SimOptMetaheuristicsExt.jl`

```julia
module SimOptMetaheuristicsExt

using SimOptDecisions: OptimizationProblem, MetaheuristicsBackend, OptimizationResult,
                       evaluate_policy, optimize_backend, param_bounds
using Metaheuristics

function SimOptDecisions.optimize_backend(prob::OptimizationProblem, backend::MetaheuristicsBackend)
    P = prob.policy_type
    bounds_vec = param_bounds(P)

    # Build bounds matrix for Metaheuristics: [lb ub] per row
    bounds = hcat([b[1] for b in bounds_vec], [b[2] for b in bounds_vec])

    # Fitness function: vector -> objectives
    function f(x::AbstractVector{T}) where T<:AbstractFloat
        policy = P(x)
        metrics = evaluate_policy(prob, policy)
        return _extract_objectives(metrics, prob.objectives)
    end

    # Select and run algorithm
    algorithm = _get_algorithm(backend.algorithm, backend.population_size, backend.options)
    result = Metaheuristics.optimize(f, bounds, algorithm;
        iterations = backend.max_iterations,
        parallel_evaluation = backend.parallel
    )

    return _wrap_result(result, P, prob)
end

function _wrap_result(mh_result, P, prob)
    best_x = Metaheuristics.minimizer(mh_result)
    best_f = Metaheuristics.minimum(mh_result)
    # ... extract population, convergence status, etc.
    OptimizationResult(best_x, best_f, P(best_x), ...)
end

end # module
```

**Notes:**

- Metaheuristics.jl uses `[lower upper]` bounds matrix format
- If user calls `optimize(prob, MetaheuristicsBackend())` without `using Metaheuristics`, throw: "Please run `using Metaheuristics` to use this backend."

## Makie Extension

File: `ext/SimOptMakieExt.jl`

- `plot_trace(recorder)` - Uses Makie's `Observable` pattern if interactive (GLMakie)
- `plot_pareto(optimization_result)` - Static scenes for CairoMakie

## ExperimentConfig Full Definition

```julia
struct ExperimentConfig{S, B<:AbstractOptimizationBackend}
    # Reproducibility
    seed::Int
    timestamp::DateTime

    # Optional metadata (user provides strings, we don't auto-fetch)
    git_commit::String
    package_versions::String

    # Data (passed in, not generated)
    sows::Vector{S}
    sow_source::String  # "LHS samples", "BRICK ensemble", etc.

    # Shared parameters (not optimized)
    shared::SharedParameters

    # Optimization configuration
    backend::B
end

# Convenience constructor
function ExperimentConfig(seed, sows, shared, backend;
                          timestamp=now(),
                          git_commit="",
                          package_versions="",
                          sow_source="unspecified")
    ExperimentConfig(seed, timestamp, git_commit, package_versions,
                     sows, sow_source, shared, backend)
end
```

**Note:** We don't auto-fetch git commits or package versions (loading `Pkg` is slow). Users provide these as strings if needed.

## Project.toml Structure

```toml
[deps]
Dates = "ade2ca70-..."
JLD2 = "033835bb-..."
Random = "9a3f8284-..."
Tables = "bd369af6-..."

[weakdeps]
Metaheuristics = "bcdb8e00-..."
CairoMakie = "13f3f980-..."
GLMakie = "e9467ef8-..."

[extensions]
SimOptMetaheuristicsExt = "Metaheuristics"
SimOptMakieExt = ["CairoMakie", "GLMakie"]

[extras]
Aqua = "4c88cf16-..."
JuliaFormatter = "98e50ef6-..."
Revise = "295af30f-..."
Test = "8dfed614-..."

[targets]
test = ["Aqua", "Test"]
```

**Notes:**

- Dev tools (`JuliaFormatter`, `Revise`, `Aqua`) go in `[extras]`, not weak dependencies
- Weak deps are for runtime functionality that loads when users import a package

---

## Implementation Roadmap

### File Structure

```text
SimOptDecisions.jl/
├── src/
│   ├── SimOptDecisions.jl    # Main module, exports
│   ├── types.jl              # Abstract types, TimeStep, Objective
│   ├── simulation.jl         # simulate, initialize, step, time_axis
│   ├── recorders.jl          # NoRecorder, TraceRecorder, Tables.jl
│   ├── optimization.jl       # OptimizationProblem, evaluate_policy, optimize
│   ├── validation.jl         # _validate_* functions, constraints
│   └── persistence.jl        # SharedParameters, ExperimentConfig, checkpoints
├── ext/
│   ├── SimOptMetaheuristicsExt.jl
│   └── SimOptMakieExt.jl
├── test/
│   ├── runtests.jl
│   └── ext/                  # Extension tests (optional)
├── Project.toml
└── README.md
```

### Phase 1: Core Framework

- [ ] Abstract types: `AbstractState`, `AbstractPolicy`, `AbstractSystemModel`, `AbstractSOW`, `AbstractRecorder`
- [ ] `TimeStep{V}` struct and `_validate_time_axis`
- [ ] Interface functions: `initialize`, `step`, `time_axis`, `aggregate_outcome`, `is_terminal`
- [ ] `simulate(model, sow, policy, recorder, rng)` with convenience overload
- [ ] Recorders: `NoRecorder`, `TraceRecorderBuilder`, `TraceRecorder{S,T}`, Tables.jl integration

### Phase 2: Optimization

- [ ] Policy interface: `params`, `param_bounds`, `_validate_policy_interface`
- [ ] Objectives: `Objective` struct, `minimize`/`maximize` constructors
- [ ] Batch sizing: `AbstractBatchSize`, `FullBatch`, `FixedBatch`, `FractionBatch`
- [ ] `OptimizationProblem` struct with `_validate_sows` constructor
- [ ] `evaluate_policy` and `optimize` entry point
- [ ] Validation hooks and constraint types (`FeasibilityConstraint`, `PenaltyConstraint`)
- [ ] `SharedParameters`, `ExperimentConfig`, `save_checkpoint`/`load_checkpoint`

### Phase 3: Extensions

- [ ] `ext/SimOptMetaheuristicsExt.jl`: `optimize_backend`, algorithm selection, result wrapping
- [ ] `ext/SimOptMakieExt.jl`: `plot_trace`, `plot_pareto`
- [ ] Project.toml: `[weakdeps]` and `[extensions]` sections
- [ ] Error messages when extensions not loaded

### Phase 4: Verification

- [ ] Package structure: main module with includes, exports, Project.toml
- [ ] MWE test problem (random walk or similar)
- [ ] `Aqua.test_all(SimOptDecisions)`
- [ ] Allocation test: `@test (@allocated simulate(...)) == 0`
- [ ] Type inference test: `@inferred simulate(...)`
