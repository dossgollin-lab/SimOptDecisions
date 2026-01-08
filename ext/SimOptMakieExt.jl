module SimOptMakieExt

using SimOptDecisions

import SimOptDecisions:
    plot_trace,
    plot_pareto,
    plot_parallel,
    to_scalars,
    SimulationTrace,
    OptimizationResult,
    AbstractState

using Makie: Figure, Axis, lines!, scatter!, axislegend

# ============================================================================
# plot_trace Implementation
# ============================================================================

"""Plot simulation trace from SimulationTrace."""
function SimOptDecisions.plot_trace(
    trace::SimulationTrace;
    fields::Union{Symbol,Vector{Symbol}}=:all,
    figure_kwargs::NamedTuple=NamedTuple(),
    axis_kwargs::NamedTuple=NamedTuple(),
    line_kwargs::NamedTuple=NamedTuple(),
)
    times = trace.times
    step_records = trace.step_records

    if isempty(step_records)
        error("Cannot plot empty trace")
    end

    # Get field names from step_records (assumed to be NamedTuples)
    first_record = step_records[1]
    if !(first_record isa NamedTuple)
        error("step_records must be NamedTuples for plotting")
    end

    all_fields = keys(first_record)
    plot_fields = fields === :all ? collect(all_fields) : fields
    n_fields = length(plot_fields)

    fig = Figure(; figure_kwargs...)
    axes = Axis[]

    for (i, field) in enumerate(plot_fields)
        ax = Axis(
            fig[i, 1];
            xlabel=i == n_fields ? "Time" : "",
            ylabel=String(field),
            axis_kwargs...,
        )
        push!(axes, ax)

        values = [r[field] for r in step_records]
        lines!(ax, times, values; line_kwargs...)
    end

    return (fig, axes)
end

# ============================================================================
# plot_pareto Implementation
# ============================================================================

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
        error("No Pareto front data. Is this a multi-objective optimization?")
    end

    n_objectives = length(pareto_objs[1])

    if n_objectives < 2
        error("plot_pareto requires at least 2 objectives, got $n_objectives")
    end

    if isempty(objective_names)
        objective_names = ["Objective $i" for i in 1:n_objectives]
    end

    obj1 = [o[1] for o in pareto_objs]
    obj2 = [o[2] for o in pareto_objs]

    fig = Figure(; figure_kwargs...)
    ax = Axis(
        fig[1, 1];
        xlabel=objective_names[1],
        ylabel=objective_names[2],
        title="Pareto Front",
        axis_kwargs...,
    )

    scatter!(ax, obj1, obj2; label="Pareto solutions", scatter_kwargs...)

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
        axislegend(ax; position=:rt)
    end

    return (fig, ax)
end

# ============================================================================
# plot_parallel Implementation
# ============================================================================

"""
Parallel coordinates plot for comparing policies.

`results` should be a vector of (params, metrics) tuples or an OptimizationResult.
"""
function SimOptDecisions.plot_parallel(
    result::OptimizationResult;
    objectives::Vector{Symbol}=Symbol[],
    decisions::Vector{Symbol}=Symbol[],
    figure_kwargs::NamedTuple=NamedTuple(),
    axis_kwargs::NamedTuple=NamedTuple(),
    line_kwargs::NamedTuple=NamedTuple(),
    highlight_best::Bool=true,
)
    pareto_params = result.pareto_params
    pareto_objs = result.pareto_objectives

    if isempty(pareto_params)
        error("No Pareto data available for parallel plot")
    end

    n_params = length(pareto_params[1])
    n_objs = length(pareto_objs[1])

    # Build axis labels
    param_labels = isempty(decisions) ? [Symbol("p$i") for i in 1:n_params] : decisions
    obj_labels = isempty(objectives) ? [Symbol("obj$i") for i in 1:n_objs] : objectives

    all_labels = vcat(param_labels, obj_labels)
    n_axes = length(all_labels)

    # Normalize data to [0,1] for each axis
    all_data = [vcat(pareto_params[i], pareto_objs[i]) for i in eachindex(pareto_params)]

    mins = [minimum(d[j] for d in all_data) for j in 1:n_axes]
    maxs = [maximum(d[j] for d in all_data) for j in 1:n_axes]

    function normalize(data)
        return [(maxs[j] == mins[j] ? 0.5 : (data[j] - mins[j]) / (maxs[j] - mins[j])) for j in 1:n_axes]
    end

    fig = Figure(; figure_kwargs...)
    ax = Axis(
        fig[1, 1];
        xticks=(1:n_axes, String.(all_labels)),
        ylabel="Normalized Value",
        title="Parallel Coordinates",
        axis_kwargs...,
    )

    # Plot each solution as a line
    for data in all_data
        norm_data = normalize(data)
        lines!(ax, 1:n_axes, norm_data; color=(:blue, 0.3), line_kwargs...)
    end

    # Highlight best
    if highlight_best
        best_data = vcat(result.best_params, result.best_objectives)
        norm_best = normalize(best_data)
        lines!(ax, 1:n_axes, norm_best; color=:red, linewidth=2, label="Best")
        axislegend(ax; position=:rt)
    end

    return (fig, ax)
end

end # module SimOptMakieExt
