# Claude Instructions

Before making code changes, read [STYLE.md](STYLE.md) for project conventions.

## Key Rules

1. **Use parametric types** - Always use `T<:AbstractFloat` instead of `Float64` for numeric fields
2. **Keep docstrings minimal** - 1-2 lines for simple functions, structured format for complex ones
3. **Interface methods** - Use `interface_not_implemented()` helper for fallback errors
4. **No over-engineering** - Avoid abstractions unless clearly needed
5. **Callbacks pattern** - Users implement `initialize`, `run_timestep`, `time_axis`, `finalize`; `simulate()` auto-calls them

## Vocabulary

- **Config** (AbstractConfig) - Fixed simulation parameters
- **SOW** (AbstractSOW) - State of the World, exogenous uncertainty
- **Policy** (AbstractPolicy) - Decision strategy
- **State** (AbstractState) - Internal simulation state
- **StepRecord** - Per-timestep tracking data (returned from `run_timestep`)
- **Outcome** - Result of one simulation (returned from `finalize`)
- **Metric** - Aggregate statistic across multiple SOWs
