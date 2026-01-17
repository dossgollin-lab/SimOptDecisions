# ============================================================================
# Plotting Interface Functions
# ============================================================================
# Implementations are in ext/SimOptMakieExt.jl

"""Convert a state to a NamedTuple of scalar values for plotting."""
function to_scalars end

to_scalars(state::AbstractState) = interface_not_implemented(:to_scalars, typeof(state))

"""Plot simulation trace over time. Requires Makie."""
function plot_trace end

"""Plot Pareto front from multi-objective optimization. Requires Makie."""
function plot_pareto end

"""Parallel coordinates plot for comparing policies. Requires Makie."""
function plot_parallel end

"""Create a heatmap of exploration results. Requires Makie."""
function plot_exploration end

"""Parallel coordinates plot of exploration results. Requires Makie."""
function plot_exploration_parallel end

"""Scatter plot of exploration results. Requires Makie."""
function plot_exploration_scatter end
