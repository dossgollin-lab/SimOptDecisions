# API Redesign Plan

This document outlines a comprehensive redesign of the SimOptDecisions.jl API to improve user-friendliness, consistency, and alignment with Julia idioms. The changes are organized into four self-contained sections that should be implemented in order.

## Overview

### Goals

1. **Clarity**: Remove jargon and naming conflicts with Base Julia
2. **Consistency**: Standardize argument ordering across all callbacks
3. **Ergonomics**: Reduce boilerplate and add convenience functions
4. **Discoverability**: Improve documentation with visual aids and recipes

### Execution Order

```
Section 1 (Renames) ──► Section 2 (Signatures) ──► Section 3 (Metrics) ──► Section 4 (Ergonomics)
        │                       │                        │                        │
        └───────────────────────┴────────────────────────┘                        │
                    Breaking changes (major version bump)              Non-breaking (minor bump)
```

### Summary of Changes

| Change | Breaking? | Section |
|--------|-----------|---------|
| `finalize` → `compute_outcome` | Yes | 1 |
| `AbstractSOW` → `AbstractScenario` | Yes | 1 |
| Remove `AbstractAction` requirement | No | 1 |
| Add `index(t)` and `value(t)` for TimeStep | No | 1 |
| Reorder callback arguments | Yes | 2 |
| Remove `final_state` from `compute_outcome` | Yes | 2 |
| Add fallback `initialize(config, scenario)` | No | 2 |
| Add declarative `AbstractMetric` types | No | 3 |
| Auto-derive `param_bounds` from ContinuousParameter | No | 3 |
| Export utility functions directly | No | 4 |
| Add `simulate_traced()` convenience | No | 4 |
| Add `@inline` to hot-path functions | No | 4 |
| Documentation diagrams and recipes | No | 4 |

## Section 1: Rename Core Elements

### Background and Discussion

#### 1.1 `finalize` Shadows `Base.finalize`

`Base.finalize` is Julia's mechanism for registering finalizers for garbage collection. While multiple dispatch prevents direct conflicts (users define `SimOptDecisions.finalize`), the name collision creates confusion and potential tooling issues (IDE autocompletion, documentation searches).

The callback's purpose is to aggregate step records into a final outcome—`compute_outcome` better describes this action.

#### 1.2 "SOW" is Domain Jargon

"SOW" (State of the World) comes from decision analysis and robust decision-making literature. While precise, it's not immediately clear to users from other backgrounds. Additionally, the lowercase `sow` reads like the verb "to sow seeds."

"Scenario" is universally understood across domains (climate modeling, finance, operations research, machine learning) and clearly conveys "one possible realization of uncertain conditions."

#### 1.3 `AbstractAction` Adds Unnecessary Boilerplate

Currently, `get_action` must return an `AbstractAction` subtype. For many use cases, the action is a simple value (a number, symbol, or tuple). Requiring a custom type adds boilerplate:

```julia
# Current: must define a type
struct MyAction <: AbstractAction
    value::Float64
end

# User wants to just return a number
get_action(policy, state, t, scenario) = 0.5
```

Since actions are stored in `Vector{Any}` during tracing anyway (via the builder pattern), there's no type-stability benefit to requiring `AbstractAction`.

#### 1.4 `TimeStep` Accessors

`TimeStep{V}` wraps both an index (`t::Int`) and value (`val::V`). Currently, users access these as `t.t` and `t.val`, which is not self-documenting. Adding `index(t)` and `value(t)` methods improves readability and aligns with the `value(p)` pattern for parameters.

### Proposed Fix

#### 1.1 Rename `finalize` → `compute_outcome`

**Files affected:**

- `src/SimOptDecisions.jl` (export)
- `src/timestepping.jl` (function definition and fallback)
- `src/simulation.jl` (call site)
- `test/` (all tests using finalize)
- `docs/` (all documentation)
- `CLAUDE.md` (vocabulary table)

**Before:**

```julia
# src/timestepping.jl
function finalize end

function finalize(
    final_state::AbstractState,
    step_records::AbstractVector,
    config::AbstractConfig,
    sow::AbstractSOW,
)
    interface_not_implemented(:finalize, typeof(config))
end

# src/simulation.jl
outcome = finalize(current_state, step_records, config, sow)
```

**After:**

```julia
# src/timestepping.jl
function compute_outcome end

function compute_outcome(
    final_state::AbstractState,
    step_records::AbstractVector,
    config::AbstractConfig,
    scenario::AbstractScenario,
)
    interface_not_implemented(:compute_outcome, typeof(config))
end

# src/simulation.jl
outcome = compute_outcome(current_state, step_records, config, scenario)
```

#### 1.2 Rename `AbstractSOW` → `AbstractScenario`

**Files affected:**

- `src/types.jl` (type definition)
- `src/SimOptDecisions.jl` (export)
- All files referencing `AbstractSOW` or `sow`

**Before:**

```julia
# src/types.jl
abstract type AbstractSOW end

# Throughout codebase
function simulate(config::AbstractConfig, sow::AbstractSOW, ...)
```

**After:**

```julia
# src/types.jl
abstract type AbstractScenario end

# Throughout codebase
function simulate(config::AbstractConfig, scenario::AbstractScenario, ...)
```

**Variable naming convention:**

- Singular: `scenario` (not `scen`)
- Plural: `scenarios` (not `scens`)

#### 1.3 Remove `AbstractAction` Requirement

**Files affected:**

- `src/types.jl` (keep type but make optional)
- `src/simulation.jl` (remove type assertion)
- `src/recorders.jl` (already handles `Any`)
- Documentation (update to show both patterns)

**Before:**

```julia
# src/types.jl
abstract type AbstractAction end

# src/timestepping.jl - implied contract
get_action(policy, state, sow, t) -> AbstractAction
```

**After:**

```julia
# src/types.jl - keep for users who want it
abstract type AbstractAction end

# src/timestepping.jl - document relaxed contract
"""
    get_action(policy, state, t, scenario) -> action

Return the action for the current timestep. The action can be any type
(number, symbol, tuple, NamedTuple, or custom AbstractAction subtype).
"""
function get_action end
```

**Documentation update:**

```julia
# Simple case: return any value
get_action(p::SimplePolicy, state, t, scenario) = p.constant_action

# Complex case: use AbstractAction for structure
struct HouseAction <: AbstractAction
    elevate::Bool
    elevation_amount::Float64
end
get_action(p::HousePolicy, state, t, scenario) = HouseAction(true, 2.0)
```

#### 1.4 Add `index()` and `value()` for TimeStep

**Files affected:**

- `src/timestepping.jl` (add methods)
- `src/SimOptDecisions.jl` (export)

**Addition:**

```julia
# src/timestepping.jl

"""
    index(t::TimeStep) -> Int

Return the 1-based index of the timestep.
"""
index(t::TimeStep) = t.t

"""
    value(t::TimeStep) -> V

Return the value (e.g., year, date) of the timestep.
"""
value(t::TimeStep) = t.val
```

**Export:**

```julia
# src/SimOptDecisions.jl
export index  # Note: value is already exported for parameters
```

### Migration Guide (Section 1)

Users must update their code:

```julia
# Before
using SimOptDecisions: AbstractSOW, finalize

struct MyScenario <: AbstractSOW
    rainfall::Float64
end

function SimOptDecisions.finalize(state, records, config, sow::MyScenario)
    # ...
end

# After
using SimOptDecisions: AbstractScenario, compute_outcome

struct MyScenario <: AbstractScenario
    rainfall::Float64
end

function SimOptDecisions.compute_outcome(state, records, config, scenario::MyScenario)
    # ...
end
```

### Checklist (Section 1)

- [ ] Rename `finalize` to `compute_outcome` in `src/timestepping.jl`
- [ ] Rename `AbstractSOW` to `AbstractScenario` in `src/types.jl`
- [ ] Update all `sow` variable names to `scenario` throughout `src/`
- [ ] Update exports in `src/SimOptDecisions.jl`
- [ ] Add `index(t::TimeStep)` and `value(t::TimeStep)` to `src/timestepping.jl`
- [ ] Export `index` from `src/SimOptDecisions.jl`
- [ ] Update all tests in `test/`
- [ ] Update `CLAUDE.md` vocabulary and callback tables
- [ ] Update `README.md`
- [ ] Search for any remaining `sow` or `finalize` references

## Section 2: Standardize Callback Signatures

### Background and Discussion

#### 2.1 Inconsistent Argument Ordering

The current callbacks have inconsistent argument ordering, making them difficult to memorize:

| Callback | Current Signature |
|----------|-------------------|
| `initialize` | `(config, scenario, rng)` |
| `get_action` | `(policy, state, scenario, t)` |
| `run_timestep` | `(state, action, scenario, config, t, rng)` |
| `time_axis` | `(config, scenario)` |
| `compute_outcome` | `(final_state, step_records, config, scenario)` |

**Issues:**

- `config` is 1st, 4th, or 3rd depending on callback
- `scenario` is 2nd, 3rd, or 4th
- `t` (TimeStep) is last in `get_action` but 5th in `run_timestep`
- No clear pattern for "what comes first"

#### 2.2 Redundant `final_state` in `compute_outcome`

The `final_state` argument to `compute_outcome` is redundant—it's always `step_records[end]`'s resulting state, or accessible via the trace. Including it adds visual noise and suggests it's somehow different from the state progression.

#### 2.3 `rng` Handling

Currently `rng` is required for `initialize` and `run_timestep`, but many simulations don't need randomness in initialization. A fallback that errors only when randomness is actually used would be more ergonomic.

**Important constraint:** `rng` must NOT be a keyword argument for functions called in hot loops (`get_action`, `run_timestep`). Keyword arguments prevent certain compiler optimizations and add overhead.

### Proposed Fix

#### 2.1 Standardized Argument Order

**Principle:** Subject first, then temporal context, then structural context, then environmental context, then auxiliary.

| Position | Meaning | Examples |
|----------|---------|----------|
| 1st | Primary subject | `config`, `policy`, `state` |
| 2nd | Secondary subject / temporal | `scenario`, `state`, `action`, `t` |
| 3rd | Temporal (if not 2nd) | `t` |
| 4th+ | Context | `config`, `scenario` |
| Last | Auxiliary | `rng` |

**New signatures:**

| Callback | New Signature | Rationale |
|----------|---------------|-----------|
| `initialize` | `(config, scenario, rng)` | Config-centric, no change |
| `get_action` | `(policy, state, t, scenario)` | Policy decides; t before scenario |
| `run_timestep` | `(state, action, t, config, scenario, rng)` | State transitions; t early |
| `time_axis` | `(config, scenario)` | Config-centric, no change |
| `compute_outcome` | `(step_records, config, scenario)` | Records are primary input |

**Changes from current:**

- `get_action`: `scenario` and `t` swapped (`t` moves earlier)
- `run_timestep`: `t` moves from position 5 to position 3; `config` and `scenario` move later
- `compute_outcome`: `final_state` removed; `step_records` becomes first

#### 2.2 Remove `final_state` from `compute_outcome`

**Before:**

```julia
function compute_outcome(
    final_state::AbstractState,
    step_records::AbstractVector,
    config::AbstractConfig,
    scenario::AbstractScenario,
)
```

**After:**

```julia
function compute_outcome(
    step_records::AbstractVector,
    config::AbstractConfig,
    scenario::AbstractScenario,
)
```

Users who need the final state can access it from their step records or state history.

#### 2.3 Add Fallback `initialize(config, scenario)`

**Addition to `src/timestepping.jl`:**

```julia
"""
    _DummyRNG

A placeholder RNG that throws an informative error if actually used.
Enables `initialize(config, scenario)` for deterministic initialization.
"""
struct _DummyRNG <: Random.AbstractRNG end

function Random.rand(::_DummyRNG, ::Type{T}) where {T}
    error(
        "Randomness requested but no RNG provided. " *
        "Define `initialize(config, scenario, rng)` instead of `initialize(config, scenario)` " *
        "if your initialization requires randomness."
    )
end

# Fallback for deterministic initialization
function initialize(config::AbstractConfig, scenario::AbstractScenario)
    return initialize(config, scenario, _DummyRNG())
end
```

This allows users to define either:

```julia
# Deterministic initialization (no rng needed)
function SimOptDecisions.initialize(config::MyConfig, scenario::MyScenario)
    return MyState(0.0, 0)
end

# Stochastic initialization (rng required)
function SimOptDecisions.initialize(config::MyConfig, scenario::MyScenario, rng)
    return MyState(rand(rng), 0)
end
```

### Detailed Changes

**`src/timestepping.jl`:**

```julia
# Before
function get_action(
    policy::AbstractPolicy,
    state::AbstractState,
    sow::AbstractSOW,
    t::TimeStep,
)
    interface_not_implemented(:get_action, typeof(policy))
end

# After
function get_action(
    policy::AbstractPolicy,
    state::AbstractState,
    t::TimeStep,
    scenario::AbstractScenario,
)
    interface_not_implemented(:get_action, typeof(policy))
end
```

```julia
# Before
function run_timestep(
    state::AbstractState,
    action::AbstractAction,
    sow::AbstractSOW,
    config::AbstractConfig,
    t::TimeStep,
    rng::Random.AbstractRNG,
)
    interface_not_implemented(:run_timestep, typeof(config))
end

# After
function run_timestep(
    state::AbstractState,
    action,  # Any type now allowed
    t::TimeStep,
    config::AbstractConfig,
    scenario::AbstractScenario,
    rng::Random.AbstractRNG,
)
    interface_not_implemented(:run_timestep, typeof(config))
end
```

```julia
# Before
function finalize(
    final_state::AbstractState,
    step_records::AbstractVector,
    config::AbstractConfig,
    sow::AbstractSOW,
)
    interface_not_implemented(:finalize, typeof(config))
end

# After
function compute_outcome(
    step_records::AbstractVector,
    config::AbstractConfig,
    scenario::AbstractScenario,
)
    interface_not_implemented(:compute_outcome, typeof(config))
end
```

**`src/simulation.jl`:**

Update the main simulation loop to use new signatures:

```julia
# Before
action = get_action(policy, current_state, sow, t)
new_state, step_record = run_timestep(current_state, action, sow, config, t, rng)
outcome = finalize(current_state, step_records, config, sow)

# After
action = get_action(policy, current_state, t, scenario)
new_state, step_record = run_timestep(current_state, action, t, config, scenario, rng)
outcome = compute_outcome(step_records, config, scenario)
```

### Migration Guide (Section 2)

Users must update their callback implementations:

```julia
# Before
function SimOptDecisions.get_action(p::MyPolicy, state, sow, t)
    # ...
end

function SimOptDecisions.run_timestep(state, action, sow, config, t, rng)
    # ...
end

function SimOptDecisions.finalize(final_state, records, config, sow)
    total = sum(r.cost for r in records)
    return (total_cost=total,)
end

# After
function SimOptDecisions.get_action(p::MyPolicy, state, t, scenario)
    # ...
end

function SimOptDecisions.run_timestep(state, action, t, config, scenario, rng)
    # ...
end

function SimOptDecisions.compute_outcome(records, config, scenario)
    total = sum(r.cost for r in records)
    return (total_cost=total,)
end
```

### Checklist (Section 2)

- [ ] Update `get_action` signature in `src/timestepping.jl`
- [ ] Update `run_timestep` signature in `src/timestepping.jl`
- [ ] Update `compute_outcome` signature (remove `final_state`)
- [ ] Add `_DummyRNG` and fallback `initialize(config, scenario)`
- [ ] Update simulation loop in `src/simulation.jl`
- [ ] Update all call sites in `src/optimization.jl`
- [ ] Update all call sites in `src/exploration.jl`
- [ ] Update all tests
- [ ] Update `CLAUDE.md` callback signature table
- [ ] Update all documentation examples

## Section 3: Declarative Metrics System

### Background and Discussion

#### 3.1 Anonymous Function Metric Calculator

Currently, users pass an anonymous function to `OptimizationProblem`:

```julia
function my_metrics(outcomes)
    (
        expected_cost = mean(o.total_cost for o in outcomes),
        prob_no_flood = mean(o.n_floods == 0 for o in outcomes),
    )
end

prob = OptimizationProblem(config, scenarios, PolicyType, my_metrics, objectives)
```

**Issues:**

- Not inspectable: can't programmatically list what metrics are computed
- Hard to validate: if user specifies `maximize(:expected_profit)` but metric returns `:expected_cost`, error only surfaces at runtime
- Not composable: can't easily combine or modify metric sets
- No documentation: metric semantics are hidden in function body

#### 3.2 `param_bounds` Duplication

Users currently must implement `param_bounds(::Type{MyPolicy})` separately from their policy definition:

```julia
struct MyPolicy <: AbstractPolicy
    threshold::ContinuousParameter{Float64}
    rate::ContinuousParameter{Float64}
end

# Redundant! Bounds already in ContinuousParameter
SimOptDecisions.param_bounds(::Type{MyPolicy}) = [(0.0, 1.0), (0.0, 0.1)]
```

Since we're standardizing on `ContinuousParameter` (which includes bounds), we can auto-derive `param_bounds`.

### Proposed Fix

#### 3.1 Declarative Metric Types

**New types in `src/metrics.jl` (new file):**

```julia
"""
Abstract base type for declarative metric specifications.
"""
abstract type AbstractMetric end

"""
    ExpectedValue(name::Symbol, field::Symbol)

Compute the mean of `field` across all outcomes.

# Example
```julia
ExpectedValue(:expected_cost, :total_cost)
# Computes: mean(o.total_cost for o in outcomes)
```

"""
struct ExpectedValue <: AbstractMetric
    name::Symbol
    field::Symbol
end

"""
    Probability(name::Symbol, predicate)

Compute the fraction of outcomes satisfying `predicate`.

# Example

```julia
Probability(:prob_no_flood, o -> o.n_floods == 0)
# Computes: mean(o.n_floods == 0 for o in outcomes)
```

"""
struct Probability{F} <: AbstractMetric
    name::Symbol
    predicate::F
end

"""
    MeanAndVariance(mean_name::Symbol, var_name::Symbol, field::Symbol)

Compute both mean and variance of `field` across all outcomes.

# Example

```julia
MeanAndVariance(:mean_loss, :var_loss, :flood_loss)
# Computes both mean and variance
```

"""
struct MeanAndVariance <: AbstractMetric
    mean_name::Symbol
    var_name::Symbol
    field::Symbol
end

"""
    Variance(name::Symbol, field::Symbol)

Compute the variance of `field` across all outcomes.
"""
struct Variance <: AbstractMetric
    name::Symbol
    field::Symbol
end

"""
    Quantile(name::Symbol, field::Symbol, q::Float64)

Compute the `q`-th quantile of `field` across all outcomes.

# Example

```julia
Quantile(:cost_95, :total_cost, 0.95)
# Computes: quantile([o.total_cost for o in outcomes], 0.95)
```

"""
struct Quantile{T<:AbstractFloat} <: AbstractMetric
    name::Symbol
    field::Symbol
    q::T

    function Quantile(name::Symbol, field::Symbol, q::T) where {T<:AbstractFloat}
        0 < q < 1 || throw(ArgumentError("Quantile q must be in (0, 1), got $q"))
        new{T}(name, field, q)
    end
end

"""
    CustomMetric(name::Symbol, func)

Compute a custom metric using an arbitrary function.

# Example

```julia
CustomMetric(:sharpe_ratio, outcomes -> mean_return(outcomes) / std_return(outcomes))
```

"""
struct CustomMetric{F} <: AbstractMetric
    name::Symbol
    func::F  # outcomes -> value
end

```

**Computation functions:**

```julia
"""
    compute_metric(metric::AbstractMetric, outcomes) -> Pair{Symbol, Float64} or Vector{Pair}

Compute a single metric from outcomes.
"""
function compute_metric(m::ExpectedValue, outcomes)
    return m.name => mean(getfield(o, m.field) for o in outcomes)
end

function compute_metric(m::Probability, outcomes)
    return m.name => mean(m.predicate(o) for o in outcomes)
end

function compute_metric(m::Variance, outcomes)
    values = [getfield(o, m.field) for o in outcomes]
    return m.name => var(values)
end

function compute_metric(m::MeanAndVariance, outcomes)
    values = [getfield(o, m.field) for o in outcomes]
    return [m.mean_name => mean(values), m.var_name => var(values)]
end

function compute_metric(m::Quantile, outcomes)
    values = [getfield(o, m.field) for o in outcomes]
    return m.name => quantile(values, m.q)
end

function compute_metric(m::CustomMetric, outcomes)
    return m.name => m.func(outcomes)
end

"""
    compute_metrics(metrics::Vector{<:AbstractMetric}, outcomes) -> NamedTuple

Compute all metrics and return as a NamedTuple.
"""
function compute_metrics(metrics::Vector{<:AbstractMetric}, outcomes)
    pairs = Pair{Symbol,Float64}[]
    for m in metrics
        result = compute_metric(m, outcomes)
        if result isa Vector
            append!(pairs, result)
        else
            push!(pairs, result)
        end
    end
    return NamedTuple(pairs)
end
```

**Usage example (house elevation problem):**

```julia
# Outcomes from simulation contain:
# - npv_flood_loss::Float64
# - n_floods::Int
# - npv_total_cost::Float64

metrics = [
    ExpectedValue(:expected_total_cost, :npv_total_cost),
    Probability(:prob_never_flood, o -> o.n_floods == 0),
    MeanAndVariance(:mean_flood_loss, :var_flood_loss, :npv_flood_loss),
]

objectives = [
    minimize(:expected_total_cost),
    maximize(:prob_never_flood),
]

prob = OptimizationProblem(
    config,
    scenarios,
    ElevationPolicy,
    metrics,  # Vector{AbstractMetric} instead of function
    objectives,
)
```

**Validation at construction:**

```julia
function OptimizationProblem(
    config, scenarios, policy_type, metrics::Vector{<:AbstractMetric}, objectives; kwargs...
)
    # Validate that all objectives reference metrics that will be computed
    metric_names = Set{Symbol}()
    for m in metrics
        if m isa MeanAndVariance
            push!(metric_names, m.mean_name)
            push!(metric_names, m.var_name)
        else
            push!(metric_names, m.name)
        end
    end

    for obj in objectives
        if obj.name ∉ metric_names
            available = join(sort(collect(metric_names)), ", ")
            throw(ArgumentError(
                "Objective references :$(obj.name) but no metric produces it. " *
                "Available metrics: $available"
            ))
        end
    end

    # Convert to function for internal use (backward compatible)
    metric_func = outcomes -> compute_metrics(metrics, outcomes)

    return OptimizationProblem(config, scenarios, policy_type, metric_func, objectives; kwargs...)
end
```

**Backward compatibility:**

```julia
# Function-based metrics still work
prob = OptimizationProblem(config, scenarios, PolicyType, my_metrics_function, objectives)
```

#### 3.2 Auto-derive `param_bounds` from ContinuousParameter

**New default implementation in `src/optimization.jl`:**

```julia
"""
    param_bounds(policy::AbstractPolicy) -> Vector{Tuple{Float64,Float64}}

Extract parameter bounds from a policy's ContinuousParameter fields.
"""
function param_bounds(policy::AbstractPolicy)
    bounds = Tuple{Float64,Float64}[]
    for fname in fieldnames(typeof(policy))
        field = getfield(policy, fname)
        if field isa ContinuousParameter
            push!(bounds, (Float64(field.bounds[1]), Float64(field.bounds[2])))
        elseif field isa DiscreteParameter
            throw(ArgumentError(
                "Field :$fname is DiscreteParameter. " *
                "Optimization backends like Metaheuristics only support continuous parameters. " *
                "Use ContinuousParameter or implement a custom optimizer."
            ))
        elseif field isa CategoricalParameter
            throw(ArgumentError(
                "Field :$fname is CategoricalParameter. " *
                "Optimization backends like Metaheuristics only support continuous parameters. " *
                "Use ContinuousParameter or implement a custom optimizer."
            ))
        end
    end

    if isempty(bounds)
        throw(ArgumentError(
            "Policy $(typeof(policy)) has no ContinuousParameter fields. " *
            "Add at least one ContinuousParameter field for optimization."
        ))
    end

    return bounds
end

"""
    param_bounds(::Type{P}) where {P<:AbstractPolicy}

Extract bounds by constructing a default instance.
Requires P to have a zero-argument constructor or all ContinuousParameter fields
with default values.
"""
function param_bounds(::Type{P}) where {P<:AbstractPolicy}
    # Try to construct with midpoint of reasonable defaults
    try
        # This is a heuristic - may need adjustment
        dummy = P([0.0 for _ in 1:100])  # Will error with correct count
    catch e
        if e isa MethodError
            throw(ArgumentError(
                "Cannot auto-derive param_bounds for $P. " *
                "Either pass a policy instance to param_bounds(policy) " *
                "or implement param_bounds(::Type{$P})."
            ))
        end
        rethrow(e)
    end
end

"""
    params(policy::AbstractPolicy) -> Vector{Float64}

Extract parameter values from a policy's ContinuousParameter fields.
"""
function params(policy::AbstractPolicy)
    vals = Float64[]
    for fname in fieldnames(typeof(policy))
        field = getfield(policy, fname)
        if field isa ContinuousParameter
            push!(vals, Float64(value(field)))
        end
    end
    return vals
end
```

**Update `OptimizationProblem` to accept policy instance:**

```julia
# Now works with instance (preferred)
prob = OptimizationProblem(config, scenarios, initial_policy, metrics, objectives)

# Still works with type (backward compatible, if param_bounds(::Type{P}) is implemented)
prob = OptimizationProblem(config, scenarios, PolicyType, metrics, objectives)
```

### Checklist (Section 3)

- [ ] Create `src/metrics.jl` with `AbstractMetric` hierarchy
- [ ] Add `compute_metric` and `compute_metrics` functions
- [ ] Update `src/SimOptDecisions.jl` to include metrics.jl
- [ ] Export new metric types
- [ ] Add constructor overload for `OptimizationProblem` accepting `Vector{AbstractMetric}`
- [ ] Add validation that objectives match metric names
- [ ] Implement auto-derive `param_bounds(policy::AbstractPolicy)`
- [ ] Implement auto-derive `params(policy::AbstractPolicy)`
- [ ] Add clear error messages for DiscreteParameter/CategoricalParameter in optimization
- [ ] Update house-elevation example to use declarative metrics
- [ ] Add tests for new metric types
- [ ] Update documentation

## Section 4: API Ergonomics and Documentation

### Background and Discussion

#### 4.1 Nested `Utils` Access

Currently, utility functions require `Utils.discount_factor()` or a qualified import. This is slightly awkward for commonly-used helpers.

#### 4.2 TraceRecorderBuilder Verbosity

Recording a trace requires three steps:

```julia
builder = TraceRecorderBuilder()
outcome = simulate(config, scenario, policy, builder, rng)
trace = build_trace(builder)
```

A convenience function would reduce this to one call.

#### 4.3 Missing `@inline` Hints

Small functions called in tight loops (`record!`, `value`, `index`) could benefit from inlining hints to eliminate function call overhead.

#### 4.4 Documentation Gaps

The current documentation lacks:

- Visual type hierarchy diagram
- Callback flow diagram
- Common pattern recipes/cookbook

### Proposed Fix

#### 4.1 Export Utility Functions Directly

**Update `src/SimOptDecisions.jl`:**

```julia
# Before
export Utils

# After
export Utils  # Keep submodule for namespacing option
export discount_factor, is_first, is_last, timeindex  # Also export directly
```

**Update `src/utils.jl` to define at module level:**

```julia
# These become SimOptDecisions.discount_factor etc.
"""
    discount_factor(rate, t) -> Float64

Compute the discount factor 1/(1+rate)^t for time period t.
"""
function discount_factor(rate, t)
    return 1.0 / (1.0 + rate)^t
end

"""
    is_first(t::TimeStep) -> Bool

Return true if this is the first timestep (index == 1).
"""
is_first(t::TimeStep) = index(t) == 1

"""
    is_last(t::TimeStep, times) -> Bool

Return true if this is the last timestep.
"""
is_last(t::TimeStep, times) = index(t) == length(times)

is_last(t::TimeStep, n::Integer) = index(t) == n

# Keep Utils submodule as alias for backward compatibility
module Utils
    using ..SimOptDecisions: discount_factor, is_first, is_last, timeindex, TimeStep
    export discount_factor, is_first, is_last, timeindex
end
```

#### 4.2 Add `simulate_traced` Convenience Function

**Add to `src/simulation.jl`:**

```julia
"""
    simulate_traced(config, scenario, policy, [rng]) -> (outcome, trace)

Run a simulation and return both the outcome and a typed SimulationTrace.

This is a convenience wrapper around simulate() with TraceRecorderBuilder.

# Example
```julia
outcome, trace = simulate_traced(config, scenario, policy, rng)
# trace.states, trace.actions, etc. are now available
```

"""
function simulate_traced(
    config::AbstractConfig,
    scenario::AbstractScenario,
    policy::AbstractPolicy,
    rng::Random.AbstractRNG,
)
    builder = TraceRecorderBuilder()
    outcome = simulate(config, scenario, policy, builder, rng)
    trace = build_trace(builder)
    return (outcome, trace)
end

# Overload without rng

function simulate_traced(
    config::AbstractConfig,
    scenario::AbstractScenario,
    policy::AbstractPolicy,
)
    return simulate_traced(config, scenario, policy, Random.default_rng())
end

```

**Export:**
```julia
export simulate_traced
```

#### 4.3 Add `@inline` to Hot-Path Functions

**Update `src/recorders.jl`:**

```julia
@inline record!(::NoRecorder, state, step_record, t, action) = nothing
```

**Update `src/timestepping.jl`:**

```julia
@inline index(t::TimeStep) = t.t
@inline value(t::TimeStep) = t.val
```

**Update `src/types.jl` (for parameters):**

```julia
@inline value(p::ContinuousParameter) = p.value
@inline value(p::DiscreteParameter) = p.value
@inline value(p::CategoricalParameter) = p.value
@inline value(ts::TimeSeriesParameter) = ts.data
```

#### 4.4 Documentation Additions

**Callback Flow Diagram (for tutorial):**

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                              simulate(config, scenario, policy, rng)            │
└─────────────────────────────────────────────────────────────────────────────────┘
                                            │
                                            ▼
                            ┌───────────────────────────────┐
                            │  times = time_axis(config,    │
                            │                    scenario)  │
                            └───────────────────────────────┘
                                            │
                                            ▼
                            ┌───────────────────────────────┐
                            │  state = initialize(config,   │
                            │              scenario, rng)   │
                            └───────────────────────────────┘
                                            │
                                            ▼
                            ┌───────────────────────────────┐
                            │     for t in times:           │
                            │  ┌─────────────────────────┐  │
                            │  │ action = get_action(    │  │
                            │  │   policy, state, t,     │  │
                            │  │   scenario)             │  │
                            │  └───────────┬─────────────┘  │
                            │              │                │
                            │              ▼                │
                            │  ┌─────────────────────────┐  │
                            │  │ state, record =         │  │
                            │  │   run_timestep(state,   │  │
                            │  │   action, t, config,    │  │
                            │  │   scenario, rng)        │  │
                            │  └─────────────────────────┘  │
                            └───────────────────────────────┘
                                            │
                                            ▼
                            ┌───────────────────────────────┐
                            │  outcome = compute_outcome(   │
                            │    step_records, config,      │
                            │    scenario)                  │
                            └───────────────────────────────┘
                                            │
                                            ▼
                                    ┌───────────────┐
                                    │    outcome    │
                                    └───────────────┘
```

**Common Patterns / Recipes (new doc page):**

```markdown
# Common Patterns

## Static Policy (same action every timestep)

```julia
struct ConstantPolicy <: AbstractPolicy
    action::ContinuousParameter{Float64}
end

function SimOptDecisions.get_action(p::ConstantPolicy, state, t, scenario)
    return value(p.action)
end
```

## Adaptive Policy (state-dependent action)

```julia
struct ThresholdPolicy <: AbstractPolicy
    threshold::ContinuousParameter{Float64}
    low_action::Float64
    high_action::Float64
end

function SimOptDecisions.get_action(p::ThresholdPolicy, state, t, scenario)
    if state.level > value(p.threshold)
        return p.high_action
    else
        return p.low_action
    end
end
```

## Time-Varying Policy (different behavior by phase)

```julia
struct PhasedPolicy <: AbstractPolicy
    early_action::Float64
    late_action::Float64
    switch_year::Int
end

function SimOptDecisions.get_action(p::PhasedPolicy, state, t, scenario)
    if value(t) < p.switch_year
        return p.early_action
    else
        return p.late_action
    end
end
```

## Scenario-Dependent Policy

```julia
function SimOptDecisions.get_action(p::AdaptivePolicy, state, t, scenario)
    # Adjust based on scenario parameters
    base_action = value(p.base)
    adjustment = value(scenario.severity) * p.sensitivity
    return base_action + adjustment
end
```

```

### Checklist (Section 4)

- [ ] Export `discount_factor`, `is_first`, `is_last`, `timeindex` directly
- [ ] Add `simulate_traced` convenience function
- [ ] Export `simulate_traced`
- [ ] Add `@inline` to `record!(::NoRecorder, ...)`
- [ ] Add `@inline` to `index(t::TimeStep)` and `value(t::TimeStep)`
- [ ] Add `@inline` to `value(p::ContinuousParameter)` etc.
- [ ] Add type hierarchy diagram to README.md
- [ ] Add callback flow diagram to tutorial
- [ ] Create recipes/cookbook documentation page
- [ ] Add at least 4 common pattern examples

## Appendix: Complete Callback Signature Reference (After Redesign)

| Callback | Signature | Returns |
|----------|-----------|---------|
| `initialize` | `(config, scenario, rng)` | `<:AbstractState` |
| `initialize` | `(config, scenario)` | `<:AbstractState` (fallback, errors if rng used) |
| `get_action` | `(policy, state, t, scenario)` | Any value |
| `run_timestep` | `(state, action, t, config, scenario, rng)` | `(new_state, step_record)` |
| `time_axis` | `(config, scenario)` | Iterable with `length()` |
| `compute_outcome` | `(step_records, config, scenario)` | Outcome value |

## Appendix: Exports After Redesign

```julia
# Core types
export AbstractState, AbstractPolicy, AbstractConfig, AbstractScenario
export AbstractRecorder, AbstractAction  # AbstractAction now optional

# TimeStep
export TimeStep, index, value

# Simulation
export simulate, simulate_traced, get_action

# Callbacks
export initialize, run_timestep, time_axis, compute_outcome

# Utilities (direct export)
export discount_factor, is_first, is_last, timeindex
export Utils  # Keep submodule for backward compatibility

# Parameters
export AbstractParameter, ContinuousParameter, DiscreteParameter, CategoricalParameter
export TimeSeriesParameter, TimeSeriesParameterBoundsError

# Recorders
export NoRecorder, TraceRecorderBuilder, SimulationTrace, record!, build_trace

# Metrics (new)
export AbstractMetric, ExpectedValue, Probability, Variance, MeanAndVariance, Quantile, CustomMetric
export compute_metric, compute_metrics

# Optimization
export OptimizationDirection, Minimize, Maximize
export Objective, minimize, maximize
export AbstractBatchSize, FullBatch, FixedBatch, FractionBatch
export AbstractOptimizationBackend, MetaheuristicsBackend
export params, param_bounds
export OptimizationProblem, OptimizationResult
export evaluate_policy, optimize, optimize_backend, pareto_front
export merge_into_pareto!, dominates, get_bounds

# Validation & Constraints
export validate, AbstractConstraint, FeasibilityConstraint, PenaltyConstraint

# Persistence
export SharedParameters, ExperimentConfig
export save_checkpoint, load_checkpoint, save_experiment, load_experiment

# Exploration
export ExplorationResult, explore, outcomes_for_policy, outcomes_for_sow
export ExploratoryInterfaceError

# Sinks
export AbstractResultSink, NoSink, InMemorySink
export AbstractFileSink, StreamingSink
export write_header!, write_rows!, close!
export csv_sink, netcdf_sink

# Plotting (requires Makie extension)
export to_scalars, plot_trace, plot_pareto, plot_parallel
export plot_exploration, plot_exploration_parallel, plot_exploration_scatter
```
