# Claude Instructions

Before making code changes, read [STYLE.md](STYLE.md) for project conventions.

## Key Rules

1. **Parametric types** — Use `T<:AbstractFloat` instead of `Float64` for numeric fields
2. **Minimal docstrings** — 1-2 lines max; no verbose documentation
3. **Interface methods** — Use `interface_not_implemented()` helper for fallback errors
4. **No backward compatibility** — This is a breaking release; remove deprecated code, don't add aliases
5. **No over-engineering** — Avoid abstractions unless clearly needed
6. **Git commits** — Keep messages short; no coauthors or email addresses
7. **NEVER touch `Project.toml` manually.** Always use `Pkg`.

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
@scenariodef MyScenario begin
    @continuous growth_rate
    @categorical climate [:low, :high]
end

@policydef MyPolicy begin
    @continuous threshold 0.0 1.0
end

@outcomedef MyOutcome begin
    @continuous total_cost
    @discrete failures
end
```

Available macros: `@scenariodef`, `@policydef`, `@configdef`, `@statedef`, `@outcomedef`

Field macros: `@continuous`, `@discrete`, `@categorical`, `@timeseries`, `@generic`

## Exploration API

The `explore()` function returns a YAXArray Dataset with dimensions `:policy` and `:scenario`. Time series outcomes add a `:time` dimension.

```julia
# Basic usage
result = explore(config, scenarios, policies)

# With executor and storage backend
result = explore(config, scenarios, policies;
    executor=ThreadedExecutor(; crn=true, seed=42),
    backend=ZarrBackend("results.zarr"),
    progress=true
)

# Access results
result[:total_cost][policy=1, scenario=2]  # Single value
result[:cost_series][:, :, :]              # Time series (policy × scenario × time)
```

## Executors

Three execution strategies with Common Random Numbers (CRN) support:

- `SequentialExecutor(; crn=true, seed=1234)` — Single-threaded execution
- `ThreadedExecutor(; crn=true, seed=1234)` — Multi-threaded with `Threads.@threads`
- `DistributedExecutor(; crn=true, seed=1234)` — Multi-process (no traced exploration)

CRN ensures identical random streams for each scenario across policies, reducing variance in comparisons.

## Storage Backends

- `InMemoryBackend()` — Default, stores results in memory as YAXArray
- `ZarrBackend(path)` — Streams results to Zarr for large datasets
- `save_netcdf(dataset, path)` / `load_netcdf(path)` — NetCDF export/import

## Core Files

- `types.jl` — Abstract types, TimeStep, optimization types (Objective, BatchSize)
- `parameters.jl` — Parameter types (Continuous, Discrete, Categorical, TimeSeries, Generic)
- `timestepping.jl` — User callbacks (initialize, run_timestep, time_axis, compute_outcome)
- `simulation.jl` — simulate() entry point
- `executors.jl` — AbstractExecutor, CRN support, Sequential/Threaded/Distributed
- `backends.jl` — Storage backends (InMemory, Zarr), NetCDF I/O
- `exploration.jl` — explore(), YAXArray result building, flattening
- `macros.jl` — Definition macros (@scenariodef, @outcomedef, etc.)
- `utils.jl` — discount_factor, timeindex, is_first, is_last

## Documentation (Quarto)

All `.qmd` files **must** use `engine: julia`, not IJulia/Jupyter:

```yaml
---
title: "Your Title"
engine: julia
execute:
  exeflags: ["--project=.."]
---
```

This uses `QuartoNotebookRunner.jl` which is simpler and more reliable in CI than IJulia.
Do **not** add IJulia to `docs/Project.toml`.
