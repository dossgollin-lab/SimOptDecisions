# ============================================================================
# Plotting Interface Functions
# ============================================================================

# These are function declarations for the extension.
# The actual implementations are in ext/SimOptMakieExt.jl

"""
    to_scalars(state) -> NamedTuple

Convert a state to a NamedTuple of scalar values for plotting.
Override for custom state types.

# Example
```julia
struct MyState <: AbstractState
    position::Float64
    velocity::Float64
end

SimOptDecisions.to_scalars(s::MyState) = (position=s.position, velocity=s.velocity)
```
"""
function to_scalars end

to_scalars(state::AbstractState) = error(
    "Implement `SimOptDecisions.to_scalars(::$(typeof(state)))` returning a NamedTuple"
)

"""
    plot_trace(recorder::TraceRecorder; kwargs...) -> (Figure, Vector{Axis})

Plot the simulation trace from a TraceRecorder.
Creates one subplot per scalar field returned by `to_scalars`.

Requires loading a Makie backend: `using CairoMakie` or `using GLMakie`.

# Returns
- `fig`: Makie Figure object
- `axes`: Vector of Axis objects, one per scalar field
"""
function plot_trace end

"""
    plot_pareto(result::OptimizationResult; kwargs...) -> (Figure, Axis)

Plot the Pareto front from a multi-objective optimization result.
For 2-objective problems, creates a 2D scatter plot.

Requires loading a Makie backend: `using CairoMakie` or `using GLMakie`.

# Returns
- `fig`: Makie Figure object
- `ax`: Axis object
"""
function plot_pareto end
