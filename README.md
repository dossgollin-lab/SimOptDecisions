# SimOptDecisions.jl

[![Tests](https://github.com/dossgollin-lab/SimOptDecisions/actions/workflows/test.yml/badge.svg?branch=main)](https://github.com/dossgollin-lab/SimOptDecisions/actions/workflows/test.yml)
[![Documentation](https://github.com/dossgollin-lab/SimOptDecisions/actions/workflows/docs.yml/badge.svg?branch=main)](https://dossgollin-lab.github.io/SimOptDecisions/)
![Julia 1.10+](https://img.shields.io/badge/Julia-1.10%2B-blue)

A Julia framework for simulation-based decision analysis under uncertainty.

## What is SimOptDecisions?

SimOptDecisions helps you find good decision strategies when the future is uncertain.

You provide a simulation model and a parameterized policy. The framework runs your model across many possible futures, aggregates the results, and searches for policy parameters that perform well.

## Key Vocabulary

| Term | What it means |
|------|---------------|
| **Config** | Fixed parameters that don't change across scenarios |
| **SOW** | "State of the World" — one possible future (your uncertain parameters) |
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

# Run
result = simulate(MyConfig(10), MySOW(0.05), MyPolicy())
```

## Documentation

See the [full documentation](https://dossgollin-lab.github.io/SimOptDecisions/) for:

- [Getting Started](https://dossgollin-lab.github.io/SimOptDecisions/guide/getting-started.html) — checklist + minimal working example
- [House Elevation Example](https://dossgollin-lab.github.io/SimOptDecisions/examples/house_elevation.html) — complete tutorial with multi-objective optimization

## Installation

```julia
using Pkg
Pkg.add(url="https://github.com/dossgollin-lab/SimOptDecisions")
```
