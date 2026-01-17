# Claude Instructions

Before making code changes, read [STYLE.md](STYLE.md) for project conventions.

## Key Rules

1. **Parametric types** — Use `T<:AbstractFloat` instead of `Float64` for numeric fields
2. **Minimal docstrings** — 1-2 lines max; no verbose documentation
3. **Interface methods** — Use `interface_not_implemented()` helper for fallback errors
4. **No backward compatibility** — This is a breaking release; remove deprecated code, don't add aliases
5. **No over-engineering** — Avoid abstractions unless clearly needed
6. **Git commits** — Keep messages short; no coauthors or email addresses

## Parameter Types

All explorable parameters use typed wrappers:

- `ContinuousParameter{T}` — Floating-point values
- `DiscreteParameter{T}` — Integer values
- `CategoricalParameter{T}` — Symbolic categories
- `TimeSeriesParameter{T,I}` — Time-indexed data
- `GenericParameter{T}` — Complex objects (skipped in explore)

## Definition Macros

Use macros to define types with typed parameter fields:

```julia
MyScenario = @scenariodef begin
    @continuous growth_rate
    @categorical climate [:low, :high]
end

MyPolicy = @policydef begin
    @continuous threshold 0.0 1.0
end
```

Available macros: `@scenariodef`, `@policydef`, `@configdef`, `@statedef`

Field macros: `@continuous`, `@discrete`, `@categorical`, `@timeseries`, `@generic`

## Core Files

- `types.jl` — Abstract types, TimeStep, parameter types
- `simulation.jl` — simulate() entry point
- `timestepping.jl` — TimeSeriesParameter, time_axis callbacks
- `exploration.jl` — explore(), ExplorationResult
- `macros.jl` — Definition macros (@scenariodef, etc.)
- `utils.jl` — discount_factor, timeindex, is_first, is_last
