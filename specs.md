# `SimOptDecisions.jl`

- Project Name: SimOptDecisions.jl  
- Project Goal: To provide a high-performance, type-stable, and student-friendly abstract foundation for the "Abstract Simulation-Optimization Decision Problem."

## Architecture Overview

The ecosystem relies on Weak Dependencies (Package Extensions) to keep the core lightweight.

### The Hub-and-Spoke Model

1. `SimOptDecisions.jl` (The Hub):  
   - Defines `AbstractSystemModel`, `AbstractPolicy`, `step`, `simulate`.  
   - Defines `OptimizationProblem` and `AbstractOptimizationBackend`.  
   - Defines `plot_trace`, `plot_pareto` (as empty functions).  
   - Dependencies: `Random`, `Dates`, `RecipesBase` (very light).  
2. Extensions (The Spokes):  
   - `SimOptBBOExt`: Loads automatically when using `BlackBoxOptim`. Implements the BBO backend.  
   - `SimOptMakieExt`: Loads automatically when using `CairoMakie` (or `GLMakie`). Implements publication-quality plotting.  
   - `SimOptJLD2Ext`: Loads automatically when using `JLD2`. Implements checkpoint serialization.  
3. Domain Packages:  
   - User-implemented physics (e.g., `HouseElevation.jl`).

### Design Philosophy

- **Functional Core:** We use a pure `step` function (State $\to$ State) instead of `next_step!` (mutation). This makes parallel debugging significantly easier and prevents race conditions in threaded code.  
- **Type Trait Dispatch:** Use `AbstractParameter` types rather than runtime `Symbol` flags for compiler efficiency.  
- **Composability:** Inputs are typed as `AbstractVector`, allowing integration with memory-mapped arrays or distributed data structures.

## Core Types and Interface

### The Abstract Hierarchy

```julia
abstract type AbstractSystemModel end
abstract type AbstractSOW end
abstract type AbstractPolicy end
abstract type AbstractState end
abstract type AbstractRecorder end
```

### The Contract

The Exception Type:

```julia
struct NotImplementedError <: Exception
    function_name::String
    arg_types::String
end
# ... (ShowError implementation)
```

Required Methods:

1. `initialize(model, sow, rng) -> state`
2. `step(state, model, sow, policy, t::TimeStep, rng) -> new_state`
   - Rationale: A pure transition function $s' = f(s, \pi, \omega)$ is mathematically cleaner and safer for parallel execution than in-place mutation.
3. `is_terminal(state, model, t) -> Bool` (Optional)

## The Simulation Engine

### Time Handling

```julia
struct TimeStep{V}
    t::Int
    val::V
    is_last::Bool
end
```

### The Recorder Pattern

- `NoRecorder <: AbstractRecorder`: Empty struct.
- `TraceRecorder{S, A} <: AbstractRecorder`: Pre-allocates storage vectors.

### The Universal Simulation Loop

```julia
function simulate(model, sow, policy; recorder=NoRecorder(), rng=Random.default_rng())
    state = initialize(model, sow, rng)
    record!(recorder, state, nothing, 0)

    # Generic iteration supports non-standard arrays / generators
    times = time_axis(model, sow)

    for (i, t_val) in enumerate(times)
        step_info = TimeStep(i, t_val, i == length(times))

        # PURE FUNCTION CALL
        state = step(state, model, sow, policy, step_info, rng)

        record!(recorder, state, step_info)
    end

    return aggregate_outcome(state, model)
end
```

## Optimization Architecture

### Type-Stable Parameters

We use a type hierarchy to allow dispatch-based handling of parameters.

```julia
abstract type AbstractParameter end

struct ContinuousParameter <: AbstractParameter
    name::Symbol
    bounds::Tuple{Float64, Float64}
end

struct IntegerParameter <: AbstractParameter
    name::Symbol
    bounds::Tuple{Int, Int}
end

struct Objective
    metric_name::Symbol
    direction::Symbol   # :min, :max, or :ignore
end
```

### The Optimization Problem

Using `A <: AbstractVector{S}` allows for lazy loading or memory mapping of huge SOW sets.

```julia
struct OptimizationProblem{M, S, A<:AbstractVector{S}, P, F}
    model::M
    training_sows::A

    policy_builder::P           # Function: NamedTuple -> AbstractPolicy
    metric_calculator::F        # Function: Vector{Outcomes} -> NamedTuple

    parameters::Vector{AbstractParameter}
    objectives::Vector{Objective}

    batch_size::Union{Int, Float64, Nothing}
end
```

### Execution Strategies

```julia
abstract type AbstractExecutionStrategy end
struct Serial <: AbstractExecutionStrategy end
struct Threaded <: AbstractExecutionStrategy end
struct Distributed <: AbstractExecutionStrategy end
```

### The Unified Evaluation Loop

```julia
function evaluate_policy(prob::OptimizationProblem, policy;
                         sows=nothing,
                         strategy=Threaded(),
                         recorder=NoRecorder())

    target_sows = select_sows(prob, sows)

    # run_simulations dispatches on `strategy` (Serial/Threaded/Distributed)
    outcomes = run_simulations(prob.model, target_sows, policy, strategy, recorder)

    return prob.metric_calculator(outcomes)
end
```

### Backend Interface (Defined in Core)

```julia
abstract type AbstractOptimizationBackend end

# Generic entry point
function optimize(prob::OptimizationProblem, backend::AbstractOptimizationBackend)
    # 1. Check constraints
    # 2. Setup bounds
    # 3. Call backend-specific implementation (defined in Extension)
    return optimize_backend(prob, backend)
end

function optimize_backend end # Empty function, methods added by Extensions
```

## Extensions and Utilities

### Optimization Extensions (`ext/SimOptBBOExt.jl`)

- **Trigger:** `using BlackBoxOptim`
- **Struct:** `struct BBOBackend <: AbstractOptimizationBackend ... end`
- **Implementation:**
  - Defines `optimize_backend(prob, ::BBOBackend)`.
  - Maps `ContinuousParameter` to `SearchRange`.
  - Wraps `evaluate_policy` in BBO's fitness function interface.

### Visualization Extensions (`ext/SimOptMakieExt.jl`)

- **Trigger:** `using CairoMakie` (or `GLMakie`)
- **Implementation:**
  - Defines `plot_trace(recorder)`.
  - Defines `plot_pareto(optimization_result)`.
  - Uses Makie's `Observable` pattern if interactive (`GLMakie`) or static scenes (Cairo).

### Persistence Extensions (`ext/SimOptJLD2Ext.jl`)

- **Trigger:** `using JLD2`
- **Implementation:**
  - Defines `save_checkpoint(path, prob, state)`.
  - Defines `load_checkpoint(path)`.

## Implementation Strategy

### Phase 1: The Functional Core

1. Define Abstract Types.
2. Implement `TimeStep` and `simulate` (Pure Functional Version).
3. **Strict Type Stability Test:** Ensure `simulate` has 0 allocations with `NoRecorder`.

### Phase 2: Domain Model (`HouseElevation.jl`)

1. Implement `step` using immutable `HouseElevationState`.
2. Verify identical results with Serial and Threaded strategies.

### Phase 3: Extensions Wiring

1. Create `ext/` folder.
2. Add `BlackBoxOptim` and `CairoMakie` to `[weakdeps]` in `Project.toml`.
3. Implement `BBOBackend` struct in Core (so it exists) but implement the method in `ext/`.

### Phase 4: Utilities

1. Implement standard metric aggregators (`mean`, `cvar`, `reliability`).

## Testing Checklist

1. **Allocation Check:** `@test (@allocated simulate(...)) == 0` (for scalar states).
2. **Inference Check:** `@inferred simulate(...)`.
3. **Extension Check:** Ensure Core loads instantly. Ensure `optimize` throws a helpful error if BBO isn't loaded ("Please run `using BlackBoxOptim` to use this backend").
