# SimOptDecisions.jl

A high-performance, type-stable Julia framework for simulation-optimization under deep uncertainty.

## Conceptual Framework

### What is Simulation-Optimization?

Many real-world decisions must be made under deep uncertainty.
We don't know exactly what the future holds, but we need to choose a strategy (a "policy") that will perform well across a range of possible futures.
Simulation-optimization provides a framework for finding good policies by:

1. **Simulating** how a policy performs across many possible futures
2. **Aggregating** those results into performance metrics
3. **Optimizing** the policy parameters to improve those metrics

### The Core Loop

At its heart, this framework evaluates how well a policy performs:

```
Model(SOW, Policy) → Outcome
```

Given a **State of the World** (the uncertain future conditions) and a **Policy** (the decision strategy), the model simulates the system forward through time and produces an **Outcome** describing how well things went.

To evaluate a policy robustly, we don't just test it on one future—we run it across an ensemble of possible futures (SOWs) and aggregate the results into **performance metrics**.
This aggregation requires making assumptions about how to weight different futures (uniform weights, probability-weighted, etc.), which the user specifies.

### The Optimization Loop

Given a fixed ensemble of SOWs, we search for policy parameters that optimize our objectives:

1. The optimizer proposes candidate policy parameters
2. We construct a policy from those parameters
3. We simulate the policy across all SOWs
4. We aggregate outcomes into performance metrics
5. We extract the objective values and return them to the optimizer
6. Repeat until convergence

The framework currently uses Metaheuristics.jl as the optimization backend, supporting both single-objective algorithms (differential evolution, particle swarm, etc.) and multi-objective algorithms (NSGA-II, NSGA-III, SPEA2) for Pareto front exploration.

## Core Vocabulary

**State**
: System variables that evolve through time as the simulation progresses.
For example, in a flood risk problem: current house elevation, accumulated flood damages, net present value of costs.
States are internal to the model and change based on decisions and external conditions.

**State of the World (SOW)**
: Exogenous uncertainties that are determined before the simulation runs.
The user provides these—they might be sampled from distributions, loaded from climate model ensembles, or generated via Latin Hypercube sampling.
Examples include: discount rates, sea level rise trajectories, storm intensity parameters, or economic growth scenarios.
SOWs represent the "uncertain futures" we want our policy to be robust against.

**Policy**
: A parameterized function that maps the current state (and exogenous information) to actions or "levers."
We focus on policies with relatively few parameters—if you have hundreds of parameters, heuristic optimization algorithms will struggle.
Examples: "elevate the house in year X to height Y" or "invest fraction Z of budget when reserves drop below threshold W."

**Outcome**
: The result of simulating one (SOW, Policy) pair through the model.
Typically a set of scalar values like total cost, reliability, or environmental impact.
Outcomes are noisy because they depend on stochastic elements in the simulation.

**Performance Metrics**
: Aggregated outcomes across an ensemble of SOWs.
If you have J outcome metrics and K SOWs, you get a J x K matrix of results.
Performance metrics reduce this to summary statistics (expected cost, 95th percentile damage, probability of failure, etc.).
The aggregation method is user-specified.

**Objectives**
: Which performance metrics to optimize, and in which direction.
For example: minimize expected cost, maximize reliability, minimize worst-case regret.
Multi-objective optimization is supported for exploring trade-offs.

---

## For Users

This section is for people who want to use this framework to build simulation-optimization models.

### Quick Start Example

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

**Why parameterize with `T<:AbstractFloat`?** This enables:

- `Float32` for GPU computing (half the memory, faster on consumer GPUs)
- `Float64` for standard CPU work (default)
- `BigFloat` for high-precision applications

Julia infers `T` from the inputs, so users just write `CounterState(0.0, 0.0)` and get `CounterState{Float64}`.

### Defining Your Types

#### The Abstract Hierarchy

```julia
abstract type AbstractState end
abstract type AbstractPolicy end
abstract type AbstractSystemModel end
abstract type AbstractSOW end
abstract type AbstractRecorder end
```

We keep abstract types simple and unparameterized.
Julia's multiple dispatch catches type mismatches via `MethodError` at runtime.

#### States of the World (SOWs)

All SOWs must subtype `AbstractSOW`. Built-in options for quick prototyping:

```julia
# For simple scalar SOWs (noise scale, discount rate, etc.)
struct ScalarSOW{T<:Real} <: AbstractSOW
    value::T
end

# For NamedTuple-based SOWs (quick prototyping)
struct TupleSOW{NT<:NamedTuple} <: AbstractSOW
    data::NT
end
```

For production, define your own:

```julia
struct ClimateSOW{T<:AbstractFloat} <: AbstractSOW
    sea_level_rise::T
    storm_intensity::T
    temperature_trajectory::Vector{T}
end

# Required: implement to_scalars for plotting/tables integration
function to_scalars(s::ClimateSOW)
    (; slr=s.sea_level_rise, storm=s.storm_intensity,
       temp_mean=mean(s.temperature_trajectory))
end
```

**SOW Homogeneity Requirement:** All SOWs in a problem must be the same concrete type. This is enforced at construction time for performance reasons.

```julia
# VALID
sows = [ScalarSOW(0.1), ScalarSOW(0.2)]

# INVALID - rejected at construction
sows = AbstractSOW[ScalarSOW(0.1), ClimateSOW(0.2, 1.0, temps)]
```

#### Required Methods

You must implement these for your model:

1. **`initialize(model, sow, rng) -> state`**
   Create the initial state for a simulation.

2. **`step(state, model, sow, policy, t::TimeStep, rng) -> new_state`**
   The core simulation step. Takes current state, returns new state.
   This is a pure function (no mutation) for easier debugging and parallel safety.

3. **`time_axis(model, sow) -> iterable`**
   Returns the time points for simulation. Examples: `1:100`, `Date(2020):Year(1):Date(2050)`.

4. **`aggregate_outcome(state, model) -> outcome`** (Optional)
   Extracts final metrics from the terminal state. Default returns state unchanged.

5. **`is_terminal(state, model, t) -> Bool`** (Optional)
   For early termination. Default is `false`.

#### Policy Interface for Optimization

If you want to optimize your policy, implement:

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

### Running Simulations

#### Basic Usage

```julia
result = simulate(model, sow, policy)
```

#### With Recording (for debugging/visualization)

```julia
builder = TraceRecorderBuilder()
result = simulate(model, sow, policy, builder)
recorder = finalize(builder)

# Works with Tables.jl ecosystem
using DataFrames; df = DataFrame(recorder)
using CSV; CSV.write("trajectory.csv", recorder)
```

#### Recorder Options

| Recorder | Use Case | Performance |
|----------|----------|-------------|
| `NoRecorder` | Production/Optimization | Zero overhead |
| `TraceRecorderBuilder` | Debugging/REPL | Flexible but slower |
| `TraceRecorder{S,T}(n)` | Batch analysis | Pre-allocated, fast |

#### Time Handling

The `step` function receives a `TimeStep` struct:

```julia
struct TimeStep{V}
    t::Int       # 1-based index
    val::V       # Actual time value (Int, Float64, Date, etc.)
    is_last::Bool
end
```

**Important:** `time_axis` must return a homogeneously-typed collection for performance:

```julia
# GOOD
time_axis(m, sow) = 1:100
time_axis(m, sow) = Date(2020):Year(1):Date(2050)

# BAD - causes dynamic dispatch
time_axis(m, sow) = Any[1, 2.0, Date(2020)]
```

### Running Optimization

#### Setting Up the Problem

```julia
prob = OptimizationProblem(
    model,                    # Your AbstractSystemModel
    sows,                     # Vector of SOWs to train on
    PolicyType,               # The TYPE of your policy (not an instance)
    metric_calculator,        # Function: Vector{Outcomes} -> NamedTuple
    objectives,               # Vector of Objective
)
```

#### Defining Objectives

```julia
# Convenience constructors
minimize(:expected_cost)
maximize(:reliability)

# Or explicitly
Objective(:worst_case_damage, Minimize)
```

#### Running the Optimizer

```julia
using Metaheuristics  # Loads the extension

result = optimize(prob, MetaheuristicsBackend(
    algorithm = :ECA,        # or :DE, :PSO, :NSGA2, :NSGA3, etc.
    max_iterations = 1000,
    population_size = 100,
    parallel = true,
))

# Access results
result.best_policy          # Constructed policy with optimal parameters
result.best_params          # Raw parameter vector
result.best_objectives      # Objective values at optimum
```

#### Multi-Objective Optimization

For Pareto front exploration:

```julia
prob = OptimizationProblem(
    model, sows, PolicyType, calculator,
    [minimize(:cost), maximize(:reliability)],
)

result = optimize(prob, MetaheuristicsBackend(algorithm = :NSGA2))

# Access Pareto front
for (params, objectives) in pareto_front(result)
    println("Params: $params => $objectives")
end
```

### Reproducibility

#### Shared Parameters

For parameters constant across all SOWs (not optimized):

```julia
struct SharedParameters{T<:NamedTuple}
    params::T
end

shared = SharedParameters((
    discount_rate = 0.03,
    planning_horizon = 50,
))

# Access via model
struct MyModel <: AbstractSystemModel
    shared::SharedParameters
end

function step(state, model, sow, policy, t, rng)
    discount = model.shared.params.discount_rate
    # ...
end
```

#### Checkpointing

```julia
# Save state for crash recovery
save_checkpoint("run_001.jld2", prob, optimizer_state; metadata = "halfway done")

# Resume later
checkpoint = load_checkpoint("run_001.jld2")
```

#### Experiment Configuration

```julia
config = ExperimentConfig(
    seed = 42,
    sows = my_sows,
    shared = SharedParameters(...),
    backend = MetaheuristicsBackend(...),
    sow_source = "Latin Hypercube, n=1000",
)
```

## For Developers

This section is for people who want to contribute to or extend the framework itself. See [IMPLEMENTATION.md](IMPLEMENTATION.md) for detailed implementation code and struct definitions.

### Development Guidelines

#### Code Style

- **Variables:** `snake_case`
- **Constants:** `UPPERCASE`
- **Types/Structs:** `TitleCase`
- **Unicode:** Use appropriately (e.g., `α`, `β` for parameters, `Δ` for differences)
- **Naming:** Prefer descriptive names over concise but confusing ones. `sea_level_rise` beats `slr`.
- **Formatting:** Use [BlueStyle](https://github.com/invenia/BlueStyle) via JuliaFormatter

#### Docstrings

Keep docstrings minimal. Add them only where the function signature isn't self-explanatory. Public API functions should have brief docstrings; internal helpers usually don't need them.

#### Error Handling

Fail fast with clear error messages. Throw errors early at validation time rather than letting bad inputs propagate. The `_validate_*` functions catch configuration errors before expensive optimization runs.

#### Testing Philosophy

Be sparing with unit tests—test only the most important things. We don't need comprehensive coverage of every edge case.

- Rely heavily on the `validate_*` functions to catch user errors
- Create a simple MWE problem (e.g., biased coin flipping) that exercises the full pipeline
- Run a few optimizer iterations to verify everything connects correctly
- This integration test catches most wiring issues without exhaustive unit tests
- Use `Aqua.jl` to catch type instabilities and ambiguities automatically

#### Dependencies

**Never edit `Project.toml` by hand.** Always use Julia's package manager:

```julia
pkg> add SomePackage           # Regular dependency
pkg> add SomePackage --weak    # Weak dependency (for extensions)
```

### Setting Up the Dev Environment

Clone the repo and set up a development environment:

```bash
cd SimOptDecisions
julia --project=.
```

```julia
using Pkg
Pkg.instantiate()  # Install core dependencies from Project.toml
```

**Understanding the Project.toml sections:**

- **`[deps]`**: Core runtime dependencies (JLD2, Tables, etc.) - installed by `Pkg.instantiate()`
- **`[weakdeps]`**: Optional dependencies that trigger extensions (Metaheuristics, CairoMakie) - NOT installed automatically
- **`[extras]`**: Test dependencies (Aqua, Test) - installed when running `Pkg.test()`

**To develop/test extensions**, add the weak deps to your local project environment:

```julia
# Weak deps - needed to trigger and test extensions
Pkg.add(["Metaheuristics", "CairoMakie"])
```

This modifies your local `Manifest.toml` (which is gitignored) but not `Project.toml`.

**Personal dev tools** like Revise and JuliaFormatter should go in your **global** Julia environment, not the project. This keeps the project's `Project.toml` clean. Add them *before* activating the project:

```bash
# From any directory, add to your global environment
julia -e 'using Pkg; Pkg.add(["Revise", "JuliaFormatter"])'
```

Or if you're already in the project REPL, switch to the global environment temporarily:

```julia
# Switch to global environment, add tools, switch back
pkg> activate @v1.11    # or whatever your Julia version is
pkg> add Revise JuliaFormatter
pkg> activate .         # back to project
```

Tools in your global environment are always available, even when working in project-specific environments.

**Development workflow:**

```julia
using Revise
using SimOptDecisions
using Metaheuristics  # This triggers the extension to load

# Now changes to src/ or ext/ will hot-reload
```

**Running tests:**

```julia
Pkg.test()                           # Core tests only
ENV["TEST_EXTENSIONS"] = "true"
Pkg.test()                           # Includes extension tests
```

### Package Architecture

#### The Hub-and-Spoke Model

The ecosystem uses weak dependencies (package extensions) to keep the core lightweight:

1. **SimOptDecisions.jl (The Hub)**
   - Defines `AbstractSystemModel`, `AbstractPolicy`, `step`, `simulate`
   - Defines `OptimizationProblem` and `AbstractOptimizationBackend`
   - Defines backend structs (`MetaheuristicsBackend`, etc.) so users can construct them directly
   - Provides `save_checkpoint`, `load_checkpoint` for persistence
   - **Dependencies:** `Random`, `Dates`, `JLD2`, `Tables`
   - **Weak Dependencies:** `Metaheuristics`, `CairoMakie`, `GLMakie`

2. **Extensions (The Spokes)**
   - `SimOptMetaheuristicsExt`: Implements `optimize_backend` for `MetaheuristicsBackend`
   - `SimOptMakieExt`: Implements `plot_trace`, `plot_pareto`

3. **Domain Packages**
   - User-implemented models (e.g., `HouseElevation.jl`)

#### Design Philosophy

- **Functional Core:** Pure `step` function (State to State) instead of mutation. Easier parallel debugging, no race conditions.
- **Policy-Owned Parameters:** Each policy type defines its own parameters, bounds, and construction.
- **Composability:** Inputs typed as `AbstractVector` allow memory-mapped arrays or distributed data.

### Extensions

#### Metaheuristics Extension

**Trigger:** `using Metaheuristics`

Implements optimization via Metaheuristics.jl algorithms:

- Single-objective: `:DE`, `:ECA`, `:PSO`, `:ABC`, `:GA`
- Multi-objective: `:NSGA2`, `:NSGA3`, `:SPEA2`, `:MOEAD`, `:CCMO`

#### Makie Extension

**Trigger:** `using CairoMakie` (or `GLMakie`)

- `plot_trace(recorder)` - Plot state trajectories
- `plot_pareto(optimization_result)` - Plot Pareto fronts

#### Adding a New Backend

1. Define a struct in core: `struct MyBackend <: AbstractOptimizationBackend ... end`
2. Create extension in `ext/SimOptMyBackendExt.jl`
3. Implement `SimOptDecisions.optimize_backend(prob, backend::MyBackend)`
4. Add to `[weakdeps]` and `[extensions]` in Project.toml

### Test Structure

```text
test/
├── runtests.jl           # Main entry point
├── core/                 # Core tests (no extra deps)
└── ext/                  # Extension tests (require Metaheuristics, Makie)
```

#### Testing Checklist

1. **Allocation Check:** `@test (@allocated simulate(...)) == 0` (for scalar states)
2. **Inference Check:** `@inferred simulate(...)`
3. **Extension Check:** `optimize` throws helpful error if Metaheuristics isn't loaded
4. **Aqua.jl Checks:** `Aqua.test_all(SimOptDecisions)`

#### Formatting

Before committing:

```julia
using JuliaFormatter
format("src/", BlueStyle())
format("test/", BlueStyle())
```
