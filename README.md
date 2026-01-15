# SimOptDecisions.jl

[![Tests](https://github.com/dossgollin-lab/SimOptDecisions/actions/workflows/test.yml/badge.svg?branch=main)](https://github.com/dossgollin-lab/SimOptDecisions/actions/workflows/test.yml)
[![Documentation](https://github.com/dossgollin-lab/SimOptDecisions/actions/workflows/docs.yml/badge.svg?branch=main)](https://dossgollin-lab.github.io/SimOptDecisions/)
![Julia 1.10+](https://img.shields.io/badge/Julia-1.10%2B-blue)

A Julia framework for simulation-based decision analysis under uncertainty.

## What is SimOptDecisions?

SimOptDecisions helps you find good decision strategies when the future is uncertain.

You provide a simulation model and a parameterized policy. The framework:

1. **Simulates** your model across many possible futures (States of the World)
2. **Optimizes** policy parameters using multi-objective evolutionary algorithms
3. **Explores** how policies perform across the full uncertainty space

## Key Features

- **Five-callback simulation interface** — implement `initialize`, `get_action`, `run_timestep`, `time_axis`, and `finalize`
- **Multi-objective optimization** — find Pareto-optimal policies with Metaheuristics.jl
- **Exploratory modeling** — analyze policy performance across all SOW combinations
- **Streaming output** — handle large-scale analyses with CSV/NetCDF file sinks
- **Visualization** — built-in plotting with Makie

## Key Vocabulary

| Term | What it means |
|------|---------------|
| **Config** | Fixed parameters that don't change across scenarios |
| **SOW** | "State of the World" — one possible future (uncertain parameters) |
| **Policy** | A decision rule with tunable parameters |
| **Action** | What the policy decides at each timestep |
| **State** | Your model's internal state that evolves over time |
| **Outcome** | Result of one simulation |
| **Metric** | Summary statistic across many simulations |

## Quick Start

```julia
using SimOptDecisions
using Random

# Define your types
struct MyConfig <: AbstractConfig
    horizon::Int
end

struct MySOW{T<:AbstractFloat} <: AbstractSOW
    growth_rate::T
end

struct MyState{T<:AbstractFloat} <: AbstractState
    value::T
end

struct MyAction <: AbstractAction end

struct MyPolicy <: AbstractPolicy end

# Implement the five callbacks
SimOptDecisions.initialize(::MyConfig, ::MySOW, ::AbstractRNG) = MyState(1.0)
SimOptDecisions.time_axis(c::MyConfig, ::MySOW) = 1:c.horizon
SimOptDecisions.get_action(::MyPolicy, ::MyState, ::MySOW, ::TimeStep) = MyAction()

function SimOptDecisions.run_timestep(state::MyState, ::MyAction, sow::MySOW, ::MyConfig, ::TimeStep, ::AbstractRNG)
    new_state = MyState(state.value * (1 + sow.growth_rate))
    return (new_state, (value=state.value,))
end

function SimOptDecisions.finalize(state::MyState, ::Vector, ::MyConfig, ::MySOW)
    return (final_value=state.value,)
end

# Run a single simulation
result = simulate(MyConfig(10), MySOW(0.05), MyPolicy())
```

## Exploratory Modeling

For systematic analysis across policies and SOWs, use typed parameters and `explore()`:

```julia
using SimOptDecisions
using DataFrames

# Define types with parameter fields for exploration
struct MySOW{T} <: AbstractSOW
    growth_rate::ContinuousParameter{T}
    scenario::CategoricalParameter{Symbol}
end

struct MyPolicy{T} <: AbstractPolicy
    threshold::ContinuousParameter{T}
end

struct MyOutcome{T}
    final_value::ContinuousParameter{T}
end

# Create SOWs and policies
sows = [
    MySOW(ContinuousParameter(r), CategoricalParameter(s, [:low, :high]))
    for r in 0.01:0.01:0.10, s in [:low, :high]
]
policies = [MyPolicy(ContinuousParameter(t)) for t in 0.1:0.1:0.5]

# Run all combinations
result = explore(config, vec(sows), policies)

# Analyze as DataFrame
df = DataFrame(result)
```

For large-scale analyses, stream directly to file:

```julia
using CSV  # or NCDatasets for NetCDF

sink = StreamingSink(csv_sink("results.csv"); flush_every=100)
explore(config, sows, policies; sink=sink)
```

## Documentation

See the [full documentation](https://dossgollin-lab.github.io/SimOptDecisions/) for:

- [Getting Started](https://dossgollin-lab.github.io/SimOptDecisions/guide/getting-started.html) — checklist + minimal working example
- [Exploratory Modeling](https://dossgollin-lab.github.io/SimOptDecisions/guide/exploration.html) — parameter types, streaming output, visualization
- [House Elevation Example](https://dossgollin-lab.github.io/SimOptDecisions/examples/house_elevation.html) — complete tutorial with multi-objective optimization

## Installation

```julia
using Pkg
Pkg.add(url="https://github.com/dossgollin-lab/SimOptDecisions")
```

## Optional Dependencies

Load these packages to enable additional features:

| Package | Feature |
|---------|---------|
| `Metaheuristics` | Multi-objective optimization |
| `CairoMakie` / `GLMakie` | Visualization |
| `CSV` | CSV file streaming |
| `NCDatasets` | NetCDF file streaming |
