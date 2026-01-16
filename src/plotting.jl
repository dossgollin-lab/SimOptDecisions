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

to_scalars(state::AbstractState) = interface_not_implemented(:to_scalars, typeof(state))

"""
    plot_trace(trace::SimulationTrace; kwargs...) -> (Figure, Vector{Axis})

Plot simulation trace over time. Requires `using CairoMakie` or `using GLMakie`.
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

# ============================================================================
# Exploration Plotting Interface
# ============================================================================

"""
    plot_exploration(result::ExplorationResult; kwargs...) -> (Figure, Axis)

Create a heatmap of exploration results.
Requires `using CairoMakie` or `using GLMakie`.

# Keyword Arguments
- `outcome_field::Symbol`: Which outcome field to visualize
- `policy_param::Union{Symbol,Nothing}=nothing`: Policy parameter for x-axis labels
- `scenario_param::Union{Symbol,Nothing}=nothing`: Scenario parameter for y-axis labels
"""
function plot_exploration end

"""
    plot_exploration_parallel(result::ExplorationResult; kwargs...) -> (Figure, Axis)

Parallel coordinates plot showing policy/scenario parameters and outcomes.
Requires `using CairoMakie` or `using GLMakie`.

# Keyword Arguments
- `columns::Vector{Symbol}=Symbol[]`: Columns to include (default: policy + outcome columns)
- `color_by::Union{Symbol,Nothing}=nothing`: Column to use for line coloring
"""
function plot_exploration_parallel end

"""
    plot_exploration_scatter(result::ExplorationResult; kwargs...) -> (Figure, Axis)

Scatter plot of exploration results.
Requires `using CairoMakie` or `using GLMakie`.

# Keyword Arguments
- `x::Symbol`: Column for x-axis
- `y::Symbol`: Column for y-axis
- `color_by::Union{Symbol,Nothing}=nothing`: Column to use for point coloring
"""
function plot_exploration_scatter end
