# SimOptDecisions.jl

[![Tests](https://github.com/dossgollin-lab/SimOptDecisions/actions/workflows/test.yml/badge.svg?branch=main)](https://github.com/dossgollin-lab/SimOptDecisions/actions/workflows/test.yml)
[![Documentation](https://github.com/dossgollin-lab/SimOptDecisions/actions/workflows/docs.yml/badge.svg?branch=main)](https://dossgollin-lab.github.io/SimOptDecisions/)
![Julia 1.10+](https://img.shields.io/badge/Julia-1.10%2B-blue)

A Julia framework for simulation-based decision analysis under uncertainty.

## What is SimOptDecisions?

SimOptDecisions helps you find good decision strategies for nonlinear sequential decision problems under uncertainty.

You define a time-stepped simulation model and candidate decision rules. The framework:

1. **Simulates** your model across many possible futures (Scenarios)
2. **Explores** how policies perform across the full uncertainty space with `explore()`
3. **Optimizes** policy parameters using multi-objective evolutionary algorithms with `optimize()`

## Key Features

- **Five-callback simulation interface** — implement `initialize`, `get_action`, `run_timestep`, `time_axis`, and `compute_outcome`
- **Definition macros** — `@scenariodef`, `@policydef`, `@outcomedef` auto-wrap fields in parameter types
- **Exploratory modeling** — `explore()` returns a YAXArray Dataset indexed by policy and scenario
- **Multi-objective optimization** — find Pareto-optimal policies with Metaheuristics.jl
- **Parallel execution** — Sequential, Threaded, and Distributed executors with Common Random Numbers
- **Storage backends** — InMemory (default) or Zarr for large experiments; NetCDF export

## Quick Start

```julia
using SimOptDecisions
using Random

# Define your types
struct MyConfig <: AbstractConfig
    horizon::Int
end

@scenariodef MyScenario begin
    @continuous growth_rate
end

struct MyState{T<:AbstractFloat} <: AbstractState
    value::T
end

struct MyAction <: AbstractAction end

@policydef MyPolicy begin
    @continuous threshold 0.0 10.0
end

# Implement the five callbacks
SimOptDecisions.initialize(::MyConfig, ::MyScenario, ::AbstractRNG) = MyState(1.0)
SimOptDecisions.time_axis(c::MyConfig, ::MyScenario) = 1:c.horizon
SimOptDecisions.get_action(::MyPolicy, ::MyState, ::TimeStep, ::MyScenario) = MyAction()

function SimOptDecisions.run_timestep(state::MyState, ::MyAction, ::TimeStep, ::MyConfig, scenario::MyScenario, ::AbstractRNG)
    new_state = MyState(state.value * (1 + value(scenario.growth_rate)))
    return (new_state, (value=state.value,))
end

function SimOptDecisions.compute_outcome(step_records::Vector, ::MyConfig, ::MyScenario)
    return (final_value=step_records[end].value,)
end

# Run a single simulation
result = simulate(MyConfig(10), MyScenario(growth_rate=0.05), MyPolicy(threshold=5.0))
```

## Exploratory Modeling

For systematic analysis across policies and scenarios, define an outcome type with `@outcomedef` and use `explore()`:

```julia
@outcomedef MyOutcome begin
    @continuous final_value
end

# Update compute_outcome to return the wrapped type
function SimOptDecisions.compute_outcome(step_records::Vector, ::MyConfig, ::MyScenario)
    return MyOutcome(final_value=step_records[end].value)
end

# Create scenarios and policies (macros auto-wrap plain values)
scenarios = [MyScenario(growth_rate=r) for r in 0.01:0.01:0.10]
policies = [MyPolicy(threshold=t) for t in 1.0:1.0:5.0]

# Run all combinations → YAXArray Dataset
result = explore(MyConfig(50), scenarios, policies)
result[:final_value]  # indexed by (policy, scenario)
```

For large experiments, use parallel execution and disk-backed storage:

```julia
result = explore(config, scenarios, policies;
    executor=ThreadedExecutor(; crn=true, seed=42),
    backend=ZarrBackend("results.zarr"))
```

## Documentation

See the [full documentation](https://dossgollin-lab.github.io/SimOptDecisions/) for:

- [Quick Reference](https://dossgollin-lab.github.io/SimOptDecisions/guide/getting-started.html) — checklist + minimal working example
- [Tutorial](https://dossgollin-lab.github.io/SimOptDecisions/tutorial/01-the-problem.html) — complete house elevation tutorial with exploration and optimization

## Installation

```julia
using Pkg
Pkg.add(url="https://github.com/dossgollin-lab/SimOptDecisions")
```

## Optional Dependencies

Load these packages to enable additional features:

| Package | Feature |
|---------|---------|
| `Metaheuristics` | Multi-objective optimization (`optimize()`) |
| `CairoMakie` / `GLMakie` | Visualization |
| `NCDatasets` | NetCDF export/import (`save_netcdf`, `load_netcdf`) |
