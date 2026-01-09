# Style Guide

Code and documentation conventions for this project.

## Julia

### Types

Use parametric types with type constraints instead of concrete types:

```julia
# Good
struct MyStruct{T<:AbstractFloat}
    my_parameter::T
end

# Avoid
struct MyStruct
    my_parameter::Float64
end
```

### Naming Conventions

- `TitleCase` for structs and modules (e.g., `MyStruct`, `Utils`)
- `snake_case` for functions and files (e.g., `get_action`, `simulation.jl`)
- `Abstract` prefix for abstract types (e.g., `AbstractPolicy`)
- `_underscore` prefix for internal/private functions (e.g., `_validate_time_axis`)

### Docstrings

Keep docstrings minimal (1-2 lines). Focus on purpose, not exhaustive details.

### Comments

Minimal. Code should be self-explanatory. When comments are needed, explain "why" not "what".

### Testing

Short, focused tests. Don't exhaustively test every edge case.

### Error Messages

Throw errors with helpful guidance on how to fix the issue:

```julia
# Good - tells user what to do
throw(ArgumentError(
    "$P must have a constructor accepting AbstractVector. " *
    "Add: `$P(x::AbstractVector{T}) where T<:AbstractFloat = ...`"
))

# Avoid - unhelpful
error("Invalid policy type")
```

### Type Stability

Avoid `Vector{Any}` and ensure type-stable code. Use parametric types or builder patterns that convert to typed collections.

### Constructors

Use `Base.@kwdef` for types created infrequently (parameters, SOWs, configs):

```julia
Base.@kwdef struct MyConfig{T<:AbstractFloat}
    threshold::T = 0.5
    max_iterations::Int = 100
end
```

Use regular constructors for types created frequently inside simulations (states):

```julia
struct MyState{T<:AbstractFloat}
    value::T
    count::Int
end
```

### Interface Definitions

Define interface methods with a fallback that throws a helpful error using `interface_not_implemented`:

```julia
"""Docstring for my_interface_fn."""
my_interface_fn(p::AbstractPolicy, args...) =
    interface_not_implemented(:my_interface_fn, typeof(p), "args...")
```

This ensures users get a clear error message when they forget to implement a required method.

## Dependencies

In `Project.toml`:

- **Regular deps** (`[deps]`): Core functionality
- **Weak deps** (`[weakdeps]`): Used only in extensions (e.g., Metaheuristics, Makie)
- **Extras** (`[extras]`): Dev/test tools (e.g., JuliaFormatter, Aqua, Test)

## Quarto Files

### Math

Always use LaTeX math:

- Inline: `$x_t$`
- Display: `$$\sum_{i=1}^n x_i$$`

### Execution Settings

Define engine and execution flags per-file (not at project level):

```yaml
---
title: "Document Title"
engine: julia
execute:
  exeflags: ["+1.12", "--threads=auto"]
  freeze: false
  cache: false
---
```

## Project Structure

```text
SimOptDecisions.jl/
├── src/
│   ├── SimOptDecisions.jl    # Main module, exports
│   ├── types.jl              # Abstract types, TimeStep, Objective, AbstractAction
│   ├── simulation.jl         # simulate() entry point
│   ├── timestepping.jl       # TimeStepping submodule, callbacks
│   ├── recorders.jl          # NoRecorder, SimulationTrace, Tables.jl
│   ├── optimization.jl       # OptimizationProblem, evaluate_policy, optimize
│   ├── validation.jl         # _validate_* functions, constraints
│   ├── persistence.jl        # SharedParameters, ExperimentConfig, checkpoints
│   ├── utils.jl              # Utils submodule (discount_factor, timeindex)
│   └── plotting.jl           # Plotting interface declarations
├── ext/
│   ├── SimOptMetaheuristicsExt.jl
│   └── SimOptMakieExt.jl
├── test/
│   ├── runtests.jl
│   ├── test_types.jl
│   ├── test_simulation.jl
│   ├── test_timestepping.jl
│   ├── test_recorders.jl
│   ├── test_validation.jl
│   ├── test_optimization.jl
│   ├── test_persistence.jl
│   ├── test_aqua.jl
│   └── ext/                  # Extension tests
├── docs/                     # Quarto documentation
├── Project.toml
├── STYLE.md
├── CLAUDE.md
└── README.md
```
