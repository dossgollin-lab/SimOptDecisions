# SimOptDecisions.jl

[![Tests](https://github.com/dossgollin-lab/SimOptDecisions.jl/actions/workflows/test.yml/badge.svg?branch=main)](https://github.com/dossgollin-lab/SimOptDecisions.jl/actions/workflows/test.yml)
[![Documentation](https://github.com/dossgollin-lab/SimOptDecisions.jl/actions/workflows/docs.yml/badge.svg?branch=main)](https://dossgollin-lab.github.io/SimOptDecisions.jl/)

A Julia framework for simulation-optimization under deep uncertainty.

## What is SimOptDecisions.jl?

Many real-world decisions must be made under deep uncertainty—we don't know exactly what the future holds, but we need to choose strategies that will perform well across a range of possible futures. SimOptDecisions.jl provides a structured approach for:

1. **Simulating** how policies perform across many possible futures (States of World)
2. **Aggregating** outcomes into performance metrics
3. **Optimizing** policy parameters to improve those metrics

The core abstraction is simple: `outcome = simulate(config, sow, policy, rng)`.

## Quick Start

```julia
using SimOptDecisions
using Random

# 1. Define your types
struct MyConfig <: AbstractConfig
    horizon::Int
end

struct MySOW <: AbstractSOW
    growth_rate::Float64
end

struct MyPolicy <: AbstractPolicy
    invest_fraction::Float64
end

# 2. Implement TimeStepping callbacks (simulate() auto-calls these)
function SimOptDecisions.TimeStepping.run_timestep(
    state::Float64, config::MyConfig, sow::MySOW,
    policy::MyPolicy, t::TimeStep, rng::AbstractRNG
)
    growth = state * sow.growth_rate * policy.invest_fraction
    return (state + growth, growth)  # (new_state, step_record)
end

SimOptDecisions.TimeStepping.time_axis(config::MyConfig, sow::MySOW) = 1:config.horizon
SimOptDecisions.TimeStepping.initialize(::MyConfig, ::MySOW, ::AbstractRNG) = 100.0

function SimOptDecisions.TimeStepping.finalize(final_state, outputs, config::MyConfig, sow::MySOW)
    return (final_value=final_state, total_growth=sum(outputs))
end

# 3. Run simulation (RNG required for reproducibility)
config = MyConfig(10)
sow = MySOW(0.05)
policy = MyPolicy(0.5)
rng = Random.Xoshiro(42)

result = simulate(config, sow, policy, rng)
# result.final_value ≈ 128, result.total_growth ≈ 28
```

## Documentation

See the [full documentation](https://dossgollin-lab.github.io/SimOptDecisions.jl/) for:

- Detailed API reference
- The TimeStepping interface for time-stepped simulations
- Optimization with multi-objective support
- The house elevation example demonstrating flood risk decision-making

## Installation

```julia
using Pkg
Pkg.add(url="https://github.com/dossgollin-lab/SimOptDecisions.jl")
```

## Key Features

- **Type-stable simulation** — Zero-allocation hot loops with `NoRecorder`
- **Flexible time axes** — Works with integers, floats, or `Date` ranges
- **Structured TimeStepping** — Clean interface with `initialize`, `run_timestep`, `time_axis`, `finalize`
- **Optional recording** — Trace simulation history for debugging
- **Extensible optimization** — Plug in Metaheuristics.jl or custom backends
- **Multi-objective support** — Pareto frontier extraction
