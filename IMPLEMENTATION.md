# Implementation Roadmap

Address documentation clarity, vocabulary consistency, interface simplification, visualization, and code cleanup.

## Key Decisions

| Issue | Decision |
|-------|----------|
| index.qmd clarity | Reframe as "framework that requires coding" |
| Visualization | Convention + Interface approach (see Phase 6) |
| is_first/is_last | Keep current (field for is_last) |
| get_action deps | Keep flexible signature, document use cases |
| Actions | Document NamedTuple convention |
| Vocabulary | Rename `step_output` → `step_record` |
| Interface | Callbacks only - simulate() auto-calls callbacks |
| Naming | Rename `params`/`AbstractFixedParams` → `config`/`AbstractConfig` |

---

## Phase 1: Vocabulary and Naming Changes

### 1.1 Rename AbstractFixedParams → AbstractConfig

**Files to modify:**

- [src/types.jl](src/types.jl) - abstract type definition
- [src/timestepping.jl](src/timestepping.jl) - all references
- [src/simulation.jl](src/simulation.jl) - all references
- [src/optimization.jl](src/optimization.jl) - OptimizationProblem field
- [src/validation.jl](src/validation.jl) - validation functions
- [docs/index.qmd](docs/index.qmd) - documentation
- [docs/examples/investment_growth.qmd](docs/examples/investment_growth.qmd)
- [docs/examples/house_elevation.qmd](docs/examples/house_elevation.qmd)
- All test files

**Changes:**

```julia
# Before
abstract type AbstractFixedParams end
function simulate(params::AbstractFixedParams, ...)

# After
abstract type AbstractConfig end
function simulate(config::AbstractConfig, ...)
```

### 1.2 Rename step_output → step_record

**Files to modify:**

- [src/timestepping.jl](src/timestepping.jl) - docstrings, comments, variable names
- [docs/index.qmd](docs/index.qmd) - table and explanations
- [docs/examples/*.qmd](docs/examples/) - comments

**Changes:**

- All docstrings: "step_output" → "step_record"
- Variable names in run_simulation: `outputs` → `step_records`
- Add formal definition to docs

---

## Phase 2: Interface Simplification

### 2.1 Consolidate to Callbacks-Only Pattern

**Current state:** Users can either:

1. Implement simulate() directly
2. Implement callbacks and call TimeStepping.run_simulation

**New approach:** Auto-call callbacks. Users just implement the 4 callbacks.

**Changes to [src/simulation.jl](src/simulation.jl):**

- Remove the generic `simulate` fallback that throws "not implemented"
- Make `simulate` automatically call `TimeStepping.run_simulation`
- Users no longer need to write the connection boilerplate

```julia
# New default: simulate automatically uses TimeStepping callbacks
function simulate(config::AbstractConfig, sow::AbstractSOW, policy::AbstractPolicy, rng::AbstractRNG)
    return TimeStepping.run_simulation(config, sow, policy, rng)
end

# Users can still override for special cases (external simulators, closed-form)
```

**Update docs to reflect:**

- "Implement the four callbacks: initialize, run_timestep, time_axis, finalize"
- "simulate() automatically calls them - no boilerplate needed"
- Brief note: "Override simulate() for non-timestepped models (rare)"

### 2.2 Remove Utils.run_timesteps

**Rationale:** With callbacks-only pattern, this low-level helper is redundant.

**Changes to [src/utils.jl](src/utils.jl):**

- Remove `run_timesteps` function (lines 76-152)
- Keep `discount_factor` and `timeindex` utilities
- Update module docstring to remove run_timesteps from list

### 2.3 Update Documentation for Callbacks-Only

**[docs/index.qmd](docs/index.qmd):**

- Remove "When to use TimeStepping vs direct simulate" table (lines 147-154)
- Make TimeStepping the primary and default pattern
- Add brief note about overriding for special cases

---

## Phase 3: Documentation Improvements

### 3.1 Reframe index.qmd Introduction

**Current:** Makes it sound like a turnkey solution

**New framing (lines 13-30 area):**

```markdown
## What is SimOptDecisions.jl?

SimOptDecisions.jl is a **framework** for building simulation-optimization models in Julia.
It is **not** a turnkey solution—you write Julia code for your model. The framework provides:

1. **Structured vocabulary** — Clear concepts: Config, SOW, Policy, State, Outcome, Metric
2. **Pluggable components** — Swap optimization backends, recording strategies
3. **Boilerplate handled** — Batching, parallel evaluation, checkpointing, type stability

**You still need to:**
- Define your system dynamics (the `run_timestep` function)
- Specify your policy structure and action space
- Implement your metric aggregation logic
```

### 3.2 Add StepRecord Definition

Add to docs/index.qmd in the vocabulary section:

```markdown
**StepRecord**: Data tracked at each timestep within a simulation.
Returned as the second element of the tuple from `run_timestep`.
All step records are collected into a Vector and passed to `finalize`.
```

### 3.3 Fix Style Violations

**[docs/index.qmd:58](docs/index.qmd#L58):**

```julia
# Before
struct MyParams <: AbstractFixedParams
    horizon::Int
    initial_value::Float64
end

# After
struct MyConfig{T<:AbstractFloat} <: AbstractConfig
    horizon::Int
    initial_value::T
end
```

### 3.4 Document get_action Use Cases

Add section explaining when get_action might depend on different arguments:

```markdown
### get_action Dependencies

The `get_action(policy, state, sow, t)` signature provides flexibility:

| Dependency | Use case |
|------------|----------|
| state only | Most policies: "if inventory < threshold, order" |
| state + sow | Using forecasts: "if expected demand > inventory, order" |
| state + t | Time-adaptive: "be conservative early, aggressive later" |
| state + sow + t | Complex adaptive policies with time-varying SOW data |

If your policy doesn't need `sow` or `t`, simply ignore them:
```julia
get_action(p::MyPolicy, state, ::AbstractSOW, ::TimeStep) = (action=f(state),)
```

```

### 3.5 Add CLAUDE.md

Create `/CLAUDE.md`:

```markdown
# Claude Instructions

Before making code changes, read [STYLE.md](STYLE.md) for project conventions.

Key rules:
- Use `T<:AbstractFloat` instead of `Float64` for numeric fields
- Keep docstrings minimal (1-2 lines)
- Interface methods should use `interface_not_implemented()` for fallbacks
```

---

## Phase 4: Code Cleanup

### 4.1 Fix Vestigial References

**[src/simulation.jl](src/simulation.jl):** Remove/update comment that mentions `run_timestepped` (should be `run_simulation`)

### 4.2 Review for Unused Code

Check and remove:

- Any unused functions
- Dead code paths
- Overly complex abstractions

### 4.3 Type Stability Audit

Verify these are acceptable:

- `TraceRecorderBuilder` using `Vector{Any}` (acceptable - converted at finalization)
- `MetaheuristicsBackend.options::Dict{Symbol,Any}` (acceptable - config, not hot path)

---

## Phase 5: Testing and Verification

### 5.1 Update Tests

- Rename all `params` → `config` in test files
- Rename `step_output` references → `step_record`
- Verify tests still pass

### 5.2 Run Full Test Suite

```bash
julia --project -e 'using Pkg; Pkg.test()'
```

### 5.3 Run Aqua.jl Checks

```julia
using Aqua
Aqua.test_all(SimOptDecisions)
```

### 5.4 Build Documentation

```bash
cd docs && quarto render
```

---

## Phase 6: Visualization (Convention + Interface)

### 6.1 Design Philosophy

Inspired by [Mimi.jl's explore() function](https://www.mimiframework.org/Mimi.jl/stable/howto/howto_2/) but without requiring macros.

**Approach:** Document NamedTuple conventions, provide plot functions that work when conventions are followed.

**Two main use cases:**

1. **Trace visualization** - View state variables and step records over time within a single simulation
2. **Policy comparison** - Parallel axis plots comparing metrics across different policies

### 6.2 Conventions to Document

**Step records should be NamedTuples with scalar fields:**

```julia
function run_timestep(state, config, sow, policy, t, rng)
    damage = compute_damage(...)
    new_state = MyState(...)
    step_record = (damage=damage, cost=cost, npv=discounted_cost)  # NamedTuple
    return (new_state, step_record)
end
```

**States should implement `to_scalars`:**

```julia
to_scalars(s::MyState) = (elevation=s.elevation, cumulative_damage=s.cumulative_damage)
```

**SOWs can optionally implement `to_scalars` for sensitivity plots:**

```julia
to_scalars(sow::MySOW) = (temperature=sow.temperature_trend, storm_rate=sow.storm_rate)
```

### 6.3 New Plot Functions

**`plot_trace(result; fields=:all)`**

Plot time series from a simulation trace.

```julia
# result contains states and step_records over time
fig, axes = plot_trace(result)
fig, axes = plot_trace(result; fields=[:damage, :npv])  # specific fields
```

Implementation:

- Extract field names from step_record NamedTuple keys
- Create one subplot per field (or selected fields)
- X-axis: time (from TimeStep.val)
- Y-axis: field values

**`plot_parallel(results; objectives, decisions)`**

Parallel axis plot for policy comparison.

```julia
# results: Vector of (policy_params, metrics) from evaluate_policy or optimization
fig, ax = plot_parallel(results;
    objectives=[:expected_cost, :worst_case],  # which metrics to show
    decisions=[:threshold, :order_quantity],    # which policy params to show
)
```

Implementation:

- Each axis represents one dimension (decision parameter or objective)
- Each line represents one policy configuration
- Optional: highlight Pareto-optimal solutions

### 6.4 Implementation in Extension

**[ext/SimOptMakieExt.jl](ext/SimOptMakieExt.jl):**

Add to existing extension:

```julia
# plot_trace implementation
function SimOptDecisions.plot_trace(result::SimulationTrace; fields=:all, kwargs...)
    # Extract step_records
    # Get field names from first record
    # Create subplots
end

# plot_parallel implementation
function SimOptDecisions.plot_parallel(results::Vector; objectives, decisions, kwargs...)
    # Build parallel coordinates plot
    # Highlight Pareto front if requested
end
```

**[src/plotting.jl](src/plotting.jl):**

Add interface definitions:

```julia
"""
    plot_trace(result; fields=:all) -> (Figure, Vector{Axis})

Plot simulation trace over time.
Requires step_records to be NamedTuples.
"""
function plot_trace end

"""
    plot_parallel(results; objectives, decisions) -> (Figure, Axis)

Parallel axis plot for comparing policies.
"""
function plot_parallel end
```

### 6.5 SimulationTrace Type

May need a new type to bundle trace data:

```julia
struct SimulationTrace{S, R, T}
    states::Vector{S}
    step_records::Vector{R}
    times::Vector{T}
end

# run_simulation returns this when recording is enabled
function run_simulation(...; record=true)
    # ... simulation loop ...
    return SimulationTrace(states, step_records, times)
end
```

Or extend existing `TraceRecorder` to also capture step_records.

### 6.6 Documentation

Add to docs/index.qmd:

- New "Visualization" section explaining conventions
- Example showing `to_scalars` implementation
- Example showing `plot_trace` usage
- Example showing `plot_parallel` usage

Add example to docs/examples/house_elevation.qmd demonstrating both plot types.

---

## Files Summary

| File | Changes |
|------|---------|
| src/types.jl | Rename AbstractFixedParams → AbstractConfig |
| src/timestepping.jl | Rename params → config, step_output → step_record, add SimulationTrace |
| src/simulation.jl | Update to default to callbacks, fix comments |
| src/optimization.jl | Rename params → config |
| src/validation.jl | Rename params → config |
| src/recorders.jl | Rename params → config if present |
| src/utils.jl | Remove run_timesteps, update docstring |
| src/plotting.jl | Add plot_parallel interface |
| ext/SimOptMakieExt.jl | Add plot_trace and plot_parallel implementations |
| docs/index.qmd | Major rewrite of intro, vocabulary, examples, add Visualization section |
| docs/examples/*.qmd | Rename params → config, add visualization examples |
| test/*.jl | Rename params → config |
| test/ext/test_makie_ext.jl | Add tests for new plot functions |
| CLAUDE.md | New file |

---

## Out of Scope (Deferred)

- Interactive `explore()` browser UI (Mimi-style)
- VegaLite integration
- @tracked macros
- is_first field addition
