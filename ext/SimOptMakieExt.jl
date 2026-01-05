module SimOptMakieExt

using SimOptDecisions

# Import types and functions we need
import SimOptDecisions:
    plot_trace,
    plot_pareto,
    to_scalars,
    TraceRecorder,
    OptimizationResult,
    AbstractState

# For Julia extensions, we use the Makie common interface
# The extension is loaded when either CairoMakie or GLMakie is imported by the user
using Makie: Figure, Axis, lines!, scatter!, axislegend

# ============================================================================
# plot_trace Implementation
# ============================================================================

"""
    plot_trace(recorder::TraceRecorder; kwargs...) -> (Figure, Vector{Axis})

Plot the simulation trace from a TraceRecorder.
Creates one subplot per scalar field returned by `to_scalars`.

# Keyword Arguments
- `figure_kwargs`: NamedTuple of kwargs passed to Figure()
- `axis_kwargs`: NamedTuple of kwargs passed to each Axis()
- `line_kwargs`: NamedTuple of kwargs passed to lines!()

# Returns
- `fig`: Makie Figure object
- `axes`: Vector of Axis objects, one per scalar field
"""
function SimOptDecisions.plot_trace(
    recorder::TraceRecorder;
    figure_kwargs::NamedTuple=NamedTuple(),
    axis_kwargs::NamedTuple=NamedTuple(),
    line_kwargs::NamedTuple=NamedTuple(),
)
    times = recorder.times
    states = recorder.states

    # Convert states to scalars
    scalars = [to_scalars(s) for s in states]

    # Get field names from first scalar
    if isempty(scalars)
        error("Cannot plot empty trace")
    end
    field_names = keys(scalars[1])
    n_fields = length(field_names)

    # Create figure with subplots
    fig = Figure(; figure_kwargs...)
    axes = Axis[]

    for (i, field) in enumerate(field_names)
        ax = Axis(
            fig[i, 1];
            xlabel=i == n_fields ? "Time" : "",
            ylabel=String(field),
            axis_kwargs...,
        )
        push!(axes, ax)

        # Extract values for this field
        values = [s[field] for s in scalars]
        lines!(ax, times, values; line_kwargs...)
    end

    return (fig, axes)
end

# ============================================================================
# plot_pareto Implementation
# ============================================================================

"""
    plot_pareto(result::OptimizationResult; kwargs...) -> (Figure, Axis)

Plot the Pareto front from a multi-objective optimization result.
For 2-objective problems, creates a 2D scatter plot.

# Keyword Arguments
- `figure_kwargs`: NamedTuple of kwargs passed to Figure()
- `axis_kwargs`: NamedTuple of kwargs passed to Axis()
- `scatter_kwargs`: NamedTuple of kwargs passed to scatter!()
- `highlight_best`: Bool, whether to highlight the best solution (default: true)
- `objective_names`: Vector{String} of names for axes (default: ["Objective 1", "Objective 2"])

# Returns
- `fig`: Makie Figure object
- `ax`: Axis object
"""
function SimOptDecisions.plot_pareto(
    result::OptimizationResult;
    figure_kwargs::NamedTuple=NamedTuple(),
    axis_kwargs::NamedTuple=NamedTuple(),
    scatter_kwargs::NamedTuple=NamedTuple(),
    highlight_best::Bool=true,
    objective_names::Vector{String}=String[],
)
    pareto_objs = result.pareto_objectives
    n_solutions = length(pareto_objs)

    if n_solutions == 0
        error("No Pareto front data in result. Is this a multi-objective optimization?")
    end

    n_objectives = length(pareto_objs[1])

    if n_objectives < 2
        error("plot_pareto requires at least 2 objectives, got $n_objectives")
    end

    # Default objective names
    if isempty(objective_names)
        objective_names = ["Objective $i" for i in 1:n_objectives]
    end

    # Extract objective values
    obj1 = [o[1] for o in pareto_objs]
    obj2 = [o[2] for o in pareto_objs]

    # Create figure
    fig = Figure(; figure_kwargs...)
    ax = Axis(
        fig[1, 1];
        xlabel=objective_names[1],
        ylabel=objective_names[2],
        title="Pareto Front",
        axis_kwargs...,
    )

    # Plot Pareto front
    scatter!(ax, obj1, obj2; label="Pareto solutions", scatter_kwargs...)

    # Highlight best solution if requested
    if highlight_best
        best_obj = result.best_objectives
        scatter!(
            ax,
            [best_obj[1]],
            [best_obj[2]];
            color=:red,
            markersize=15,
            marker=:star5,
            label="Best",
        )
    end

    # Add legend if we have labels
    if highlight_best
        axislegend(ax; position=:rt)
    end

    return (fig, ax)
end

end # module SimOptMakieExt
