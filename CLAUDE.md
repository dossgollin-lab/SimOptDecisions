# Claude Instructions

Before making code changes, read [STYLE.md](STYLE.md) for project conventions.

## Key Rules

1. **Use parametric types** - Always use `T<:AbstractFloat` instead of `Float64` for numeric fields
2. **Keep docstrings minimal** - 1-2 lines for simple functions, structured format for complex ones
3. **Interface methods** - Use `interface_not_implemented()` helper for fallback errors
4. **No over-engineering** - Avoid abstractions unless clearly needed
5. **Five callbacks pattern** - Users implement `initialize`, `get_action`, `run_timestep`, `time_axis`, `finalize`; `simulate()` auto-calls them

## Vocabulary

- **Config** (AbstractConfig) - Fixed simulation parameters
- **SOW** (AbstractSOW) - State of the World, exogenous uncertainty
- **Policy** (AbstractPolicy) - Decision strategy that produces Actions
- **Action** (AbstractAction) - Decision at a specific timestep (returned from `get_action`)
- **State** (AbstractState) - Internal simulation state
- **StepRecord** - Per-timestep tracking data (returned from `run_timestep`)
- **Outcome** - Result of one simulation (returned from `finalize`)
- **Metric** - Aggregate statistic across multiple SOWs

## Callback Signatures

| Callback | Signature | Returns |
|----------|-----------|---------|
| `initialize` | `(config, sow, rng)` | `state` (or `nothing` for stateless) |
| `get_action` | `(policy, state, sow, t)` | `<:AbstractAction` |
| `run_timestep` | `(state, action, sow, config, t, rng)` | `(new_state, step_record)` |
| `time_axis` | `(config, sow)` | Iterable with `length()` |
| `finalize` | `(final_state, step_records, config, sow)` | Outcome |

All five callbacks are **required**. The framework throws helpful errors if missing.

## Recording

`SimulationTrace` captures simulation history with `initial_state` field separate from per-timestep vectors:
- `initial_state`: State at t=0 (before any actions)
- `states`, `step_records`, `times`, `actions`: Aligned vectors for each timestep
