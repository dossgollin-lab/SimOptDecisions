# `SimOptDecisions.jl`

- Project Name: SimOptDecisions.jl
- Project Goal: To provide a high-performance, type-stable, and student-friendly abstract foundation for Monte Carlo Simulation-Optimization Decision Problems

## Architecture Overview

The ecosystem relies on Weak Dependencies (Package Extensions) to keep the core lightweight.

### The Hub-and-Spoke Model

1. `SimOptDecisions.jl` (The Hub):
   - Defines `AbstractSystemModel`, `AbstractPolicy`, `step`, `simulate`.
   - Defines `OptimizationProblem` and `AbstractOptimizationBackend`.
   - Defines backend structs (`MetaheuristicsBackend`, etc.) so users can construct them directly.
   - Defines `plot_trace`, `plot_pareto` (as empty functions for extension).
   - Provides `save_checkpoint`, `load_checkpoint` for persistence (always available).
   - **Dependencies:** `Random`, `Dates`, `JLD2` (checkpointing is critical, not optional), `Tables` (lightweight; enables ecosystem integration with DataFrames, CSV, Arrow, etc.).
   - **Weak Dependencies:** `Metaheuristics`, `CairoMakie`, `GLMakie`.
2. Extensions (The Spokes):
   - `SimOptMetaheuristicsExt`: Loads automatically when using `Metaheuristics`. Implements `optimize_backend` for `MetaheuristicsBackend`.
   - `SimOptMakieExt`: Loads automatically when using `CairoMakie` (or `GLMakie`). Implements publication-quality plotting.
3. Domain Packages:
   - User-implemented physics (e.g., `HouseElevation.jl`).

### Design Philosophy

- **Functional Core:** We use a pure `step` function (State $\to$ State) instead of `next_step!` (mutation). This makes parallel debugging significantly easier and prevents race conditions in threaded code.
- **Policy-Owned Parameters:** Each policy type defines its own parameters, bounds, and construction from vectors. No separate parameter definition needed.
- **Composability:** Inputs are typed as `AbstractVector`, allowing integration with memory-mapped arrays or distributed data structures.

## Quick Start Example

A minimal working example demonstrating the core interface:

```julia
using SimOptDecisions
using Random

# 1. Define your state (parameterized for type flexibility)
struct CounterState{T<:AbstractFloat} <: AbstractState
    value::T
    cumulative::T
end

# 2. Define your model
struct RandomWalkModel <: AbstractSystemModel end

# 3. Define your policy (parameterized) with optimization interface
struct DriftPolicy{T<:AbstractFloat} <: AbstractPolicy
    drift::T
end

# Policy interface for optimization
SimOptDecisions.params(p::DriftPolicy) = [p.drift]
SimOptDecisions.param_bounds(::Type{<:DriftPolicy}) = [(-1.0, 1.0)]
DriftPolicy(x::AbstractVector{T}) where T<:AbstractFloat = DriftPolicy(x[1])

# 4. Implement required methods using ScalarSOW (built-in wrapper for scalar values)
function SimOptDecisions.initialize(::RandomWalkModel, sow::ScalarSOW{T}, rng) where T
    CounterState(zero(T), zero(T))
end

function SimOptDecisions.step(state::CounterState{T}, model, sow::ScalarSOW{T},
                              policy::DriftPolicy, t::TimeStep, rng) where T
    noise = randn(rng) * sow.value  # sow.value is the noise scale
    new_value = state.value + policy.drift + noise
    CounterState(new_value, state.cumulative + abs(new_value))
end

SimOptDecisions.time_axis(::RandomWalkModel, sow::ScalarSOW) = 1:100

function SimOptDecisions.aggregate_outcome(state::CounterState, ::RandomWalkModel)
    (final_value = state.value, total_movement = state.cumulative)
end

# 5. Run a simulation
model = RandomWalkModel()
sow = ScalarSOW(0.1)  # noise scale wrapped in ScalarSOW
policy = DriftPolicy(0.05)

result = simulate(model, sow, policy)  # uses defaults: NoRecorder(), Random.default_rng()
# result.final_value ≈ 5.0, result.total_movement ≈ 250.0

# 6. Run optimization (requires `using Metaheuristics`)
prob = OptimizationProblem(
    model,
    [ScalarSOW(0.1), ScalarSOW(0.2), ScalarSOW(0.5)],  # Multiple SOWs
    DriftPolicy,  # Policy type (not a builder function!)
    outcomes -> (mean_final = mean(o.final_value for o in outcomes),),  # Metric calculator
    [minimize(:mean_final)],  # Objectives
)

# result = optimize(prob, MetaheuristicsBackend())
# best = result.best_policy  # DriftPolicy with optimal parameters
```

**Why parameterize?** Using `T<:AbstractFloat` instead of hardcoded `Float64` enables:

- `Float32` for GPU computing (half the memory, faster on consumer GPUs)
- `Float64` for standard CPU work (default)
- `BigFloat` for high-precision applications

Julia infers `T` from the inputs, so users just write `CounterState(0.0, 0.0)` and get `CounterState{Float64}`.

## Core Types and Interface

### The Abstract Hierarchy

```julia
abstract type AbstractState end
abstract type AbstractPolicy end
abstract type AbstractSystemModel end
abstract type AbstractSOW end
abstract type AbstractRecorder end
```

**Rationale:** We keep abstract types simple and unparameterized. Julia's multiple dispatch already catches type mismatches via `MethodError` at runtime. Parameterizing would force students to redefine their model struct every time they change their state struct—unnecessary friction during iterative development.

### SOW (State of the World)

All SOWs must subtype `AbstractSOW`. This enables:
- Type-stable iteration over SOW collections
- Consistent `to_scalars` interface for plotting/tables
- Validation hooks via `validate(sow, model)`

```julia
# For simple scalar SOWs (noise scale, discount rate, etc.)
struct ScalarSOW{T<:Real} <: AbstractSOW
    value::T
end
to_scalars(s::ScalarSOW) = (; value=s.value)

# For NamedTuple-based SOWs (quick prototyping)
struct TupleSOW{NT<:NamedTuple} <: AbstractSOW
    data::NT
end
to_scalars(s::TupleSOW) = s.data

# For complex domain-specific SOWs
struct ClimateSOW{T<:AbstractFloat} <: AbstractSOW
    sea_level_rise::T
    storm_intensity::T
    temperature_trajectory::Vector{T}
end

function to_scalars(s::ClimateSOW)
    (; slr=s.sea_level_rise, storm=s.storm_intensity,
       temp_mean=mean(s.temperature_trajectory))
end
```

**Usage examples:**

```julia
# Quick prototyping with wrappers
sows = [ScalarSOW(0.1), ScalarSOW(0.2), ScalarSOW(0.3)]
sows = [TupleSOW((slr=0.5, storm=1.2)), TupleSOW((slr=0.6, storm=1.3))]

# Production with custom types
sows = [ClimateSOW(0.5, 1.2, temps1), ClimateSOW(0.6, 1.3, temps2)]
```

### SOW Homogeneity Requirement

**All SOWs in a problem must be the same concrete subtype of `AbstractSOW`.** Enforced at construction time.

```julia
# ✓ VALID: Concrete types or small Unions (≤4 types)
sows = [ScalarSOW(0.1), ScalarSOW(0.2)]           # Vector{ScalarSOW{Float64}}
sows = Union{HistoricalSOW, SyntheticSOW}[h1, s1] # Julia union-splits efficiently

# ✗ INVALID: Abstract types force dynamic dispatch
sows = AbstractSOW[ScalarSOW(0.1), ClimateSOW(0.2, 1.0)]  # Rejected
```

**Why this matters:** `OptimizationProblem{..., S<:AbstractSOW, ...}` captures the SOW type. With concrete `S`, the hot loop is fully specialized. With `S=AbstractSOW`, every iteration incurs dynamic dispatch.

### Required Methods

1. `initialize(model, sow, rng) -> state`
2. `step(state, model, sow, policy, t::TimeStep, rng) -> new_state`
   - Rationale: A pure transition function $s' = f(s, \pi, \omega)$ is mathematically cleaner and safer for parallel execution than in-place mutation.
   - We use explicit arguments rather than bundling into a context struct. This is more verbose (6 args) but clearer for students: `policy.threshold` beats `ctx.policy.threshold`.
3. `time_axis(model, sow) -> iterable`
   - Returns the time points for simulation (e.g., `1:100`, `Date(2020):Year(1):Date(2050)`).
4. `aggregate_outcome(state, model) -> outcome`
   - Extracts the final outcome/metrics from the terminal state.
   - Default implementation returns the state unchanged.
5. `is_terminal(state, model, t) -> Bool` (Optional)
   - For early termination; defaults to `false`.

## The Simulation Engine

### Time Handling

```julia
struct TimeStep{V}
    t::Int       # 1-based index
    val::V       # Actual time value (Int, Float64, Date, etc.)
    is_last::Bool
end
```

**Important:** `time_axis(model, sow)` must return a **homogeneously-typed** collection. If it returns `Vector{Any}`, then `V=Any` and every `step` call incurs dynamic dispatch on `TimeStep{Any}`.

```julia
# ✓ GOOD: Concrete element types
time_axis(m, sow) = 1:100                          # UnitRange{Int}
time_axis(m, sow) = Date(2020):Year(1):Date(2050)  # StepRange{Date}
time_axis(m, sow) = [0.0, 0.5, 1.0, 2.0, 5.0]      # Vector{Float64}

# ✗ BAD: Any type - defeats parameterization
time_axis(m, sow) = Any[1, 2.0, Date(2020)]        # Vector{Any} - slow!
```

We validate this at the start of simulation:

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

### The Recorder Pattern

We provide recorders for different use cases:

| Recorder | Use Case | Performance |
|----------|----------|-------------|
| `NoRecorder` | Production/Optimization | Zero overhead, no allocations |
| `TraceRecorder{S,T}` | Production analysis | Pre-allocated, type-stable |
| `TraceRecorderBuilder` | Debugging/REPL | Flexible but slower (`Vector{Any}`) |

**Choose the right recorder:**

- **Optimization runs (millions of simulations):** Use `NoRecorder()`. You only need final outcomes, not intermediate states.
- **Analyzing a single simulation:** Use `TraceRecorderBuilder` for convenience, then `finalize()` for efficient data extraction.
- **Batch analysis with known types:** Pre-allocate `TraceRecorder{MyState, Int}(n_steps)` for maximum performance.

### Data Extraction Interface

Users implement `to_scalars` for their custom state types to enable Tables.jl integration and plotting:

```julia
# Required for custom states
function to_scalars(state::HouseElevationState)
    (; elevation=state.elevation, flood_damage=state.cumulative_damage,
       npv=state.net_present_value)
end
```

Built-in implementations exist for `ScalarSOW` and `TupleSOW`. Custom SOW types also need `to_scalars` (see SOW section above).

### TraceRecorder Implementation

```julia
# Parameterized to avoid Vector{Any} - critical for performance
struct TraceRecorder{S, T}
    states::Vector{S}
    times::Vector{T}
end

# Factory function that infers types from first record
mutable struct TraceRecorderBuilder
    states::Vector{Any}
    times::Vector{Any}
    TraceRecorderBuilder() = new([], [])
end

function record!(r::TraceRecorderBuilder, state, t)
    push!(r.states, state)
    push!(r.times, t)
end

# Convert to typed recorder after simulation (for analysis)
function finalize(r::TraceRecorderBuilder)
    S = typeof(r.states[2])  # Skip initial nothing/state pair
    T = typeof(r.times[2])
    TraceRecorder{S,T}(
        convert(Vector{S}, r.states[2:end]),
        convert(Vector{T}, r.times[2:end])
    )
end

# Or: Pre-allocated recorder when you know the types
function TraceRecorder{S,T}(n::Int) where {S,T}
    TraceRecorder{S,T}(Vector{S}(undef, n), Vector{T}(undef, n))
end
```

### Tables.jl Integration

`TraceRecorder` implements the Tables.jl interface (`Tables.istable`, `Tables.rows`, `Tables.columns`), enabling direct use with the Julia data ecosystem:

```julia
recorder = finalize(builder)

# Works with ANY Tables.jl-compatible sink
using DataFrames; df = DataFrame(recorder)
using CSV; CSV.write("trajectory.csv", recorder)
using Arrow; Arrow.write("trajectory.arrow", recorder)
```

### The Universal Simulation Loop

We use **multiple dispatch** instead of keyword arguments for zero-overhead method selection:

```julia
# Full method - used by batch runners and when you need all options
function simulate(model::AbstractSystemModel, sow::AbstractSOW, policy::AbstractPolicy,
                  recorder::AbstractRecorder, rng::AbstractRNG)
    state = initialize(model, sow, rng)

    record!(recorder, state, nothing)  # Initial state recording

    times = time_axis(model, sow)
    _validate_time_axis(times)  # Catch Vector{Any} early
    n_times = length(times)

    for (i, t_val) in enumerate(times)
        step_info = TimeStep(i, t_val, i == n_times)

        # PURE FUNCTION CALL - explicit arguments for clarity
        state = step(state, model, sow, policy, step_info, rng)

        record!(recorder, state, step_info)

        # Optional early termination
        is_terminal(state, model, step_info) && break
    end

    return aggregate_outcome(state, model)
end

# Convenience methods via multiple dispatch (zero overhead vs kwargs)
simulate(model, sow, policy) =
    simulate(model, sow, policy, NoRecorder(), Random.default_rng())

simulate(model, sow, policy, recorder) =
    simulate(model, sow, policy, recorder, Random.default_rng())
```

**Why multiple dispatch over kwargs?** Julia's kwargs have ~50ns parsing overhead per call. With 10M simulations, that's 500ms of overhead. Multiple dispatch is resolved at compile time—zero runtime cost.

**Note on `time_axis` return type:** The simulation loop calls `length(times)`, so `time_axis` must return something with a defined length (e.g., `Vector`, `UnitRange`, `StepRange`). True generators/iterators without known length are not supported—use `collect()` if needed.

## Optimization Architecture

### Policy Interface for Optimization

Each policy type owns its parameters. The optimizer just needs three things from a policy type:

```julia
# Core defines these interface functions (throw "not implemented" by default)
function params end      # policy -> AbstractVector{<:AbstractFloat}
function param_bounds end  # Type -> Vector{Tuple{T,T}} where T<:AbstractFloat

# Default implementations that throw helpful errors
params(p::AbstractPolicy) = error(
    "Implement `SimOptDecisions.params(::$(typeof(p)))` to return parameter vector"
)
param_bounds(::Type{T}) where {T<:AbstractPolicy} = error(
    "Implement `SimOptDecisions.param_bounds(::Type{$T})` to return bounds"
)
```

**User implements for their policy:**

```julia
struct MyPolicy{T<:AbstractFloat} <: AbstractPolicy
    threshold::T
    risk_aversion::T
end

# Extract parameters as vector
SimOptDecisions.params(p::MyPolicy) = [p.threshold, p.risk_aversion]

# Define bounds for each parameter
SimOptDecisions.param_bounds(::Type{<:MyPolicy}) = [(0.0, 1.0), (0.0, 10.0)]

# Constructor from vector (optimizer calls this)
MyPolicy(x::AbstractVector{T}) where T<:AbstractFloat = MyPolicy(x[1], x[2])
```

The optimizer:

1. Calls `param_bounds(PolicyType)` to get bounds matrix
2. Optimizes over `Vector{T}` where `T<:AbstractFloat`
3. Calls `PolicyType(x)` to construct policies for evaluation

**Note:** Time-series uncertainty (e.g., temperature trajectories) belongs in the SOW, not the policy. Decision variables come only from the policy parameters.

### Type-Stable Objectives

We use an enum instead of symbols for optimization direction to ensure type stability and enable exhaustive pattern matching:

```julia
@enum OptimizationDirection begin
    Minimize
    Maximize
    Ignore  # For tracking metrics without optimizing
end

struct Objective
    metric_name::Symbol
    direction::OptimizationDirection
end

# Convenience constructors
minimize(name::Symbol) = Objective(name, Minimize)
maximize(name::Symbol) = Objective(name, Maximize)
```

### Batch Size Configuration

We use a type hierarchy instead of `Union` types for batch size to maintain type stability:

```julia
abstract type AbstractBatchSize end

struct FullBatch <: AbstractBatchSize end           # Use all SOWs
struct FixedBatch <: AbstractBatchSize
    n::Int
end
struct FractionBatch <: AbstractBatchSize
    fraction::Float64  # ∈ (0.0, 1.0]

    function FractionBatch(f::Float64)
        0.0 < f ≤ 1.0 || throw(ArgumentError("Fraction must be in (0, 1]"))
        new(f)
    end
end
```

### The Optimization Problem

Using `A <: AbstractVector{S}` allows for lazy loading or memory mapping of huge SOW sets.

```julia
struct OptimizationProblem{M, S, A<:AbstractVector{S}, P<:Type{<:AbstractPolicy}, F, B<:AbstractBatchSize}
    model::M
    training_sows::A
    policy_type::P              # Policy TYPE (not instance) - has params, param_bounds, constructor
    metric_calculator::F        # Function: Vector{Outcomes} -> NamedTuple
    objectives::Vector{Objective}
    batch_size::B
end

# Convenience constructor with validation
function OptimizationProblem(model, sows, policy_type::Type{<:AbstractPolicy},
                             calculator, objectives; batch_size=FullBatch())
    _validate_sows(sows)
    _validate_policy_interface(policy_type)
    OptimizationProblem(model, sows, policy_type, calculator, objectives, batch_size)
end

# Validate policy type implements required interface
function _validate_policy_interface(::Type{P}) where P<:AbstractPolicy
    # Check param_bounds is implemented
    try
        bounds = param_bounds(P)
        if !isa(bounds, AbstractVector)
            throw(ArgumentError("param_bounds must return a Vector of tuples"))
        end
    catch e
        e isa ErrorException && rethrow()  # Re-throw "not implemented" errors
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

### Policy Evaluation

Serial evaluation across SOWs. Parallelism is delegated to the optimizer backend (Metaheuristics parallelizes across population candidates).

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

**Why serial here?** Metaheuristics.jl parallelizes fitness evaluations across population candidates. If we also parallelized across SOWs, we'd get N_threads × N_threads tasks (oversubscription). Since population_size (50-200) typically exceeds thread count, letting Metaheuristics handle parallelism is simpler and equally efficient.

### Backend Interface (Defined in Core)

```julia
abstract type AbstractOptimizationBackend end

# Generic entry point
function optimize(prob::OptimizationProblem, backend::AbstractOptimizationBackend)
    validate(prob)
    return optimize_backend(prob, backend)
end

function optimize_backend end # Empty function, methods added by Extensions
```

### OptimizationResult (Defined in Core)

Extensions return a Core-defined result type, not backend-specific structs. This ensures users can inspect results without loading the extension:

```julia
struct OptimizationResult{T<:AbstractFloat, M, P<:Type{<:AbstractPolicy}}
    best_params::Vector{T}      # Optimal parameter vector
    best_objectives::M          # NamedTuple of objective values at optimum
    best_policy::P              # Constructed policy at optimum
    converged::Bool
    iterations::Int
    population::Vector{Vector{T}}  # Final population (for multi-objective: Pareto front)
    objective_values::Vector{M}    # Corresponding objective values
end

# Convenience accessor for Pareto front
pareto_front(result) = zip(result.population, result.objective_values)

# Construct policies from population (for Pareto analysis)
pareto_policies(result, prob) = [prob.policy_type(x) for x in result.population]
```

Extensions wrap backend-specific results into this common struct. The `best_policy` is constructed during result creation.

## Extensions and Utilities

### Backend Structs (Defined in Core)

Backend structs are defined in core so users can construct them directly with `using SimOptDecisions`:

```julia
# In src/SimOptDecisions.jl (core)
struct MetaheuristicsBackend <: AbstractOptimizationBackend
    algorithm::Symbol          # :DE, :ECA, :PSO, :NSGA2, :NSGA3, :SPEA2, etc.
    max_iterations::Int
    population_size::Int
    parallel::Bool             # Parallelize fitness evaluations across population
    options::NamedTuple        # Algorithm-specific options
end

MetaheuristicsBackend(;
    algorithm=:ECA,            # Evolutionary Centers Algorithm (good default)
    max_iterations=1000,
    population_size=100,
    parallel=true,             # Enable threading by default
    options=(;)
) = MetaheuristicsBackend(algorithm, max_iterations, population_size, parallel, options)

export MetaheuristicsBackend
```

**Metaheuristics.jl algorithms:** Single-objective (`:DE`, `:ECA`, `:PSO`, `:ABC`, `:GA`) and multi-objective (`:NSGA2`, `:NSGA3`, `:SPEA2`, `:MOEAD`, `:CCMO`).

**Parallelism:** When `parallel=true`, Metaheuristics evaluates population candidates across threads. Our `evaluate_policy` runs serially within each candidate to avoid nested threading.

### Optimization Extensions (`ext/SimOptMetaheuristicsExt.jl`)

- **Trigger:** `using Metaheuristics`
- **Purpose:** Implements the actual optimization logic. The struct exists in core, but the method is in the extension.

```julia
# In ext/SimOptMetaheuristicsExt.jl
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
        policy = P(x)  # Construct policy from parameter vector
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

# Helper: wrap Metaheuristics result into Core's OptimizationResult
function _wrap_result(mh_result, P, prob)
    best_x = Metaheuristics.minimizer(mh_result)
    best_f = Metaheuristics.minimum(mh_result)
    # ... extract population, convergence status, etc.
    OptimizationResult(best_x, best_f, P(best_x), ...)
end

end # module
```

- **Implementation Notes:**
  - Metaheuristics.jl uses `[lower upper]` bounds matrix format.
  - If user calls `optimize(prob, MetaheuristicsBackend())` without `using Metaheuristics`, they get: "Please run `using Metaheuristics` to use this backend."

### Visualization Extensions (`ext/SimOptMakieExt.jl`)

- **Trigger:** `using CairoMakie` (or `GLMakie`)
- **Implementation:**
  - Defines `plot_trace(recorder)`.
  - Defines `plot_pareto(optimization_result)`.
  - Uses Makie's `Observable` pattern if interactive (`GLMakie`) or static scenes (Cairo).

### Persistence (Built into Core)

JLD2 is a hard dependency—checkpointing is too critical to be optional. These functions are always available:

```julia
# In src/SimOptDecisions.jl (core)
using JLD2

"""
Save optimization state for crash recovery or later resumption.
"""
function save_checkpoint(path::String, prob::OptimizationProblem, state; metadata=nothing)
    JLD2.@save path prob state metadata timestamp=now()
end

"""
Load a checkpoint to resume optimization.
"""
function load_checkpoint(path::String)
    JLD2.@load path prob state metadata timestamp
    return (; prob, state, metadata, timestamp)
end
```

**Rationale:** For long-running scientific simulations, checkpointing isn't optional—a 10-hour run crashing without a checkpoint is unacceptable. JLD2 is stable, mature, and the de facto standard for Julia serialization.

## Validation and Constraints

### Validation Hooks

Validation functions catch configuration errors before expensive optimization runs:

```julia
validate(model::AbstractSystemModel) -> Bool          # Default: true
validate(policy::AbstractPolicy, model) -> Bool       # Default: true
validate(prob::OptimizationProblem) -> Bool           # Called by optimize()
```

`validate(prob)` checks model, SOWs, and that the policy type implements the required interface (`params`, `param_bounds`, vector constructor). Override for domain-specific validation.

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

## Reproducibility

For scientific computing, full reproducibility is critical. The framework provides:

### Shared Parameters

Many problems have parameters that are constant across all SOWs (e.g., discount rate, planning horizon). These are distinct from the policy parameters being optimized:

```julia
"""
Parameters shared across all SOWs in an experiment.
Not optimized—fixed for a given experiment run.
"""
struct SharedParameters{T<:NamedTuple}
    params::T
end

# Example
shared = SharedParameters((
    discount_rate = 0.03,
    planning_horizon = 50,
    construction_cost_per_foot = 10_000.0,
))
```

The `step` function receives shared parameters via the model:

```julia
struct MyModel <: AbstractSystemModel
    shared::SharedParameters
end

function step(state, model, sow, policy, t, rng)
    discount = model.shared.params.discount_rate
    # ...
end
```

### Experiment Configuration

SOWs are passed in directly (not generated)—they might come from files, Latin Hypercube sampling, or Monte Carlo draws:

```julia
struct ExperimentConfig{S, B<:AbstractOptimizationBackend}
    # Reproducibility
    seed::Int
    timestamp::DateTime

    # Optional metadata (user provides strings, we don't auto-fetch)
    # This avoids heavy dependencies like Pkg or LibGit2 in core
    git_commit::String      # User calls their own `read_git_commit()` or passes ""
    package_versions::String  # User serializes versions or passes ""

    # Data (passed in, not generated)
    sows::Vector{S}
    sow_source::String  # Description: "LHS samples", "BRICK ensemble", etc.

    # Shared parameters (not optimized)
    shared::SharedParameters

    # Optimization configuration (actual backend struct, not symbol)
    backend::B
end

# Convenience constructor with minimal required fields
function ExperimentConfig(seed, sows, shared, backend;
                          timestamp=now(),
                          git_commit="",
                          package_versions="",
                          sow_source="unspecified")
    ExperimentConfig(seed, timestamp, git_commit, package_versions,
                     sows, sow_source, shared, backend)
end
```

**Note on metadata:** We don't auto-fetch git commits or package versions (loading `Pkg` is slow). Users provide these as strings if needed.

### Reproducibility Guarantees

1. **RNG Seeding:** Each fitness evaluation uses a seeded RNG derived from master seed
2. **SOW Provenance:** Config stores source description and the actual SOW data
3. **Determinism:** Serial SOW evaluation ensures bitwise-identical results across runs
4. **Version Tracking:** Experiment configs capture package versions and git commit hashes
5. **Backend Serialization:** Full backend configuration is saved, not just a symbol

## Development Setup

### Project.toml Structure

**IMPORTANT:** Never edit `Project.toml` by hand. Always use Julia's package manager:

```julia
# In the package directory
julia> ]
pkg> activate .
pkg> add JLD2 Tables           # Add dependencies
pkg> add Metaheuristics --weak # Add weak dependency (Julia 1.9+)
```

The resulting structure should look like:

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

**Note:** Dev tools (`JuliaFormatter`, `Revise`, `Aqua`) go in `[extras]`, not weak dependencies. Weak deps are for runtime functionality that loads when users import a package. Dev tools are loaded manually during development.

### Test Directory Structure

Keep extension tests separate from core tests:

```text
test/
├── runtests.jl           # Main entry point
├── core/                 # Core tests (no extra deps)
└── ext/                  # Extension tests (require Metaheuristics, Makie)
```

Extension tests run only when `ENV["TEST_EXTENSIONS"] == "true"`.

### Recommended Dev Workflow

```julia
# In REPL during development
using Revise
using SimOptDecisions

# Format before committing
using JuliaFormatter
format("src/")
format("test/")

# Run tests
using Pkg
Pkg.test()
```

## Testing Checklist

1. **Allocation Check:** `@test (@allocated simulate(...)) == 0` (for scalar states).
2. **Inference Check:** `@inferred simulate(...)`.
3. **Extension Check:** Ensure Core loads instantly. Ensure `optimize` throws a helpful error if Metaheuristics isn't loaded ("Please run `using Metaheuristics` to use this backend").
4. **Aqua.jl Checks:** Run `Aqua.test_all(SimOptDecisions)` to catch ambiguities, unbound args, and other issues.
