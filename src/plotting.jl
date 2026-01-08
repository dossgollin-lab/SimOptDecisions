# ============================================================================
# Plotting Interface Functions
# ============================================================================

# Function declarations for the Makie extension.
# Implementations are in ext/SimOptMakieExt.jl

"""
    to_scalars(state) -> NamedTuple

Convert a state to a NamedTuple of scalar values for plotting.
"""
function to_scalars end

to_scalars(state::AbstractState) = error(
    "Implement `SimOptDecisions.to_scalars(::$(typeof(state)))` returning a NamedTuple"
)

"""
    plot_trace(trace; kwargs...) -> (Figure, Vector{Axis})

Plot simulation trace over time. Accepts SimulationTrace or TraceRecorder.
Requires `using CairoMakie` or `using GLMakie`.
"""
function plot_trace end

"""
    plot_pareto(result::OptimizationResult; kwargs...) -> (Figure, Axis)

Plot Pareto front from multi-objective optimization.
Requires `using CairoMakie` or `using GLMakie`.
"""
function plot_pareto end

"""
    plot_parallel(results; objectives, decisions) -> (Figure, Axis)

Parallel coordinates plot for comparing policies across objectives.
Requires `using CairoMakie` or `using GLMakie`.
"""
function plot_parallel end
