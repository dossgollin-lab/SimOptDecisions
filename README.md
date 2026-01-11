# SimOptDecisions.jl

[![Tests](https://github.com/dossgollin-lab/SimOptDecisions/actions/workflows/test.yml/badge.svg?branch=main)](https://github.com/dossgollin-lab/SimOptDecisions/actions/workflows/test.yml)
[![Documentation](https://github.com/dossgollin-lab/SimOptDecisions/actions/workflows/docs.yml/badge.svg?branch=main)](https://dossgollin-lab.github.io/SimOptDecisions/)

A Julia framework for simulation-optimization under deep uncertainty.

## Framework Overview

```
Inputs you define:
  ┌────────┐  ┌────────┐  ┌────────┐  ┌────────────┐
  │ Config │  │ Policy │  │  SOWs  │  │ Objectives │
  └───┬────┘  └───┬────┘  └───┬────┘  └─────┬──────┘
      │           │           │             │
      ▼           ▼           ▼             ▼
┌─────────────────────────────────────────────────────────────────┐
│ optimize()                                                      │
│ ┌─────────────────────────────────────────────────────────────┐ │
│ │ evaluate_policy()                                           │ │
│ │   loops over SOWs                                           │ │
│ │ ┌─────────────────────────────────────────────────────────┐ │ │
│ │ │ simulate()                                              │ │ │
│ │ │                                                         │ │ │
│ │ │   initialize()     ───►  State                          │ │ │
│ │ │   time_axis()      ───►  times                          │ │ │
│ │ │                                                         │ │ │
│ │ │   ┌───────────────────────────────────────────────────┐ │ │ │
│ │ │   │ for t in times                                    │ │ │ │
│ │ │   │   get_action()   ───►  Action                     │ │ │ │
│ │ │   │   run_timestep() ───►  State, StepRecord          │ │ │ │
│ │ │   └───────────────────────────────────────────────────┘ │ │ │
│ │ │                                                         │ │ │
│ │ │   finalize(step_records)  ───►  Outcome                 │ │ │
│ │ └─────────────────────────────────────────────────────────┘ │ │
│ │                                                             │ │
│ │   calculate_metrics(outcomes)  ───►  Metrics                │ │
│ └─────────────────────────────────────────────────────────────┘ │
│                                                                 │
│   Objectives extract from Metrics  ───►  OptimizationResult     │
└─────────────────────────────────────────────────────────────────┘
                                                    │
                                                    ▼
                                          ┌─────────────────┐
                                          │  Pareto Front   │
                                          │ (params, values)│
                                          └─────────────────┘

Legend: You implement the 5 callbacks (initialize, time_axis, get_action,
        run_timestep, finalize) plus calculate_metrics. The framework
        handles the loops and optimization.
```

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

struct MyAction <: AbstractAction end

# 2. Implement the five callbacks (simulate() auto-calls these)
SimOptDecisions.initialize(::MyConfig, ::MySOW, ::AbstractRNG) = 100.0
SimOptDecisions.time_axis(config::MyConfig, ::MySOW) = 1:config.horizon

function SimOptDecisions.get_action(::MyPolicy, ::Float64, ::MySOW, ::TimeStep)
    return MyAction()
end

function SimOptDecisions.run_timestep(
    state::Float64, ::MyAction, sow::MySOW,
    config::MyConfig, t::TimeStep, rng::AbstractRNG
)
    growth = state * sow.growth_rate
    return (state + growth, growth)  # (new_state, step_record)
end

function SimOptDecisions.finalize(final_state, step_records, config::MyConfig, sow::MySOW)
    return (final_value=final_state, total_growth=sum(step_records))
end

# 3. Run simulation (RNG required for reproducibility)
config = MyConfig(10)
sow = MySOW(0.05)
policy = MyPolicy(0.5)
rng = Random.Xoshiro(42)

result = simulate(config, sow, policy, rng)
# result.final_value ≈ 163, result.total_growth ≈ 63
```

## Documentation

See the [full documentation](https://dossgollin-lab.github.io/SimOptDecisions/) for:

- Detailed API reference
- The five callbacks for time-stepped simulations
- Optimization with multi-objective support
- The house elevation example demonstrating flood risk decision-making

## Installation

```julia
using Pkg
Pkg.add(url="https://github.com/dossgollin-lab/SimOptDecisions")
```

## Key Features

- **Type-stable simulation** — Zero-allocation hot loops with `NoRecorder`
- **Flexible time axes** — Works with integers, floats, or `Date` ranges
- **Structured callbacks** — Clean interface with `initialize`, `get_action`, `run_timestep`, `time_axis`, `finalize`
- **Optional recording** — Trace simulation history for debugging
- **Extensible optimization** — Plug in Metaheuristics.jl or custom backends
- **Multi-objective support** — Pareto frontier extraction
