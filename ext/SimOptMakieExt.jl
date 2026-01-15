module SimOptMakieExt

using SimOptDecisions

import SimOptDecisions:
    plot_trace,
    plot_pareto,
    plot_parallel,
    plot_exploration,
    plot_exploration_parallel,
    plot_exploration_scatter,
    to_scalars,
    SimulationTrace,
    OptimizationResult,
    ExplorationResult,
    AbstractState

using Makie: Figure, Axis, Colorbar, lines!, scatter!, heatmap!, axislegend

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
        return [
            (maxs[j] == mins[j] ? 0.5 : (data[j] - mins[j]) / (maxs[j] - mins[j])) for
            j in 1:n_axes
        ]
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

    return (fig, ax)
end

# ============================================================================
# Exploration Plotting Implementations
# ============================================================================

"""Plot exploration results as heatmap."""
function SimOptDecisions.plot_exploration(
    result::ExplorationResult;
    outcome_field::Symbol,
    policy_param::Union{Symbol,Nothing}=nothing,
    sow_param::Union{Symbol,Nothing}=nothing,
    figure_kwargs::NamedTuple=NamedTuple(),
    axis_kwargs::NamedTuple=NamedTuple(),
    heatmap_kwargs::NamedTuple=NamedTuple(),
)
    # Find the outcome column (with or without prefix)
    outcome_col = Symbol(:outcome_, outcome_field)
    first_row = first(result.rows)
    if outcome_col ∉ keys(first_row)
        # Try without prefix
        if outcome_field ∈ keys(first_row)
            outcome_col = outcome_field
        else
            error("Outcome field `$outcome_field` not found. Available: $(keys(first_row))")
        end
    end

    n_p, n_s = size(result)
    values = [Float64(result[p, s][outcome_col]) for p in 1:n_p, s in 1:n_s]

    # Determine axis labels
    if isnothing(policy_param)
        x_labels = string.(1:n_p)
        x_title = "Policy Index"
    else
        policy_col = Symbol(:policy_, policy_param)
        if policy_col ∉ keys(first_row)
            policy_col = policy_param
        end
        x_labels = [string(result[p, 1][policy_col]) for p in 1:n_p]
        x_title = String(policy_param)
    end

    if isnothing(sow_param)
        y_labels = string.(1:n_s)
        y_title = "SOW Index"
    else
        sow_col = Symbol(:sow_, sow_param)
        if sow_col ∉ keys(first_row)
            sow_col = sow_param
        end
        y_labels = [string(result[1, s][sow_col]) for s in 1:n_s]
        y_title = String(sow_param)
    end

    fig = Figure(; figure_kwargs...)
    ax = Axis(
        fig[1, 1];
        xlabel=x_title,
        ylabel=y_title,
        title="Exploration: $(outcome_field)",
        xticks=(1:n_p, x_labels),
        yticks=(1:n_s, y_labels),
        axis_kwargs...,
    )

    hm = heatmap!(ax, 1:n_p, 1:n_s, values; heatmap_kwargs...)
    Colorbar(fig[1, 2], hm; label=String(outcome_field))

    return (fig, ax)
end

"""Parallel coordinates for exploration results."""
function SimOptDecisions.plot_exploration_parallel(
    result::ExplorationResult;
    columns::Vector{Symbol}=Symbol[],
    figure_kwargs::NamedTuple=NamedTuple(),
    axis_kwargs::NamedTuple=NamedTuple(),
    line_kwargs::NamedTuple=NamedTuple(),
    color_by::Union{Symbol,Nothing}=nothing,
)
    # Default: use all policy params + outcome columns
    if isempty(columns)
        columns = vcat(result.policy_columns, result.outcome_columns)
    end

    n_axes = length(columns)
    if n_axes == 0
        error("No columns specified for parallel coordinates plot")
    end

    # Extract and normalize data
    all_data = [[Float64(row[c]) for c in columns] for row in result.rows]

    mins = [minimum(d[j] for d in all_data) for j in 1:n_axes]
    maxs = [maximum(d[j] for d in all_data) for j in 1:n_axes]

    normalize(data) = [
        (maxs[j] == mins[j] ? 0.5 : (data[j] - mins[j]) / (maxs[j] - mins[j])) for
        j in 1:n_axes
    ]

    fig = Figure(; figure_kwargs...)
    ax = Axis(
        fig[1, 1];
        xticks=(1:n_axes, String.(columns)),
        ylabel="Normalized Value",
        title="Exploration Parallel Coordinates",
        xticklabelrotation=π / 4,
        axis_kwargs...,
    )

    # Color by outcome or parameter if specified
    if !isnothing(color_by) && color_by ∈ keys(first(result.rows))
        color_vals = [Float64(row[color_by]) for row in result.rows]
        color_min, color_max = extrema(color_vals)
        color_range = color_max - color_min
        if color_range ≈ 0
            color_range = 1.0
        end
        color_norm = (color_vals .- color_min) ./ color_range

        for (i, data) in enumerate(all_data)
            norm_data = normalize(data)
            # Use color based on normalized value
            c = color_norm[i]
            lines!(ax, 1:n_axes, norm_data; color=(c, c, 1 - c, 0.5), line_kwargs...)
        end
    else
        for data in all_data
            norm_data = normalize(data)
            lines!(ax, 1:n_axes, norm_data; color=(:blue, 0.3), line_kwargs...)
        end
    end

    return (fig, ax)
end

"""Scatter plot for exploration results."""
function SimOptDecisions.plot_exploration_scatter(
    result::ExplorationResult;
    x::Symbol,
    y::Symbol,
    color_by::Union{Symbol,Nothing}=nothing,
    figure_kwargs::NamedTuple=NamedTuple(),
    axis_kwargs::NamedTuple=NamedTuple(),
    scatter_kwargs::NamedTuple=NamedTuple(),
)
    first_row = first(result.rows)

    # Resolve column names (handle prefixed vs unprefixed)
    x_col = x ∈ keys(first_row) ? x : Symbol(:outcome_, x)
    y_col = y ∈ keys(first_row) ? y : Symbol(:outcome_, y)

    x_vals = [Float64(row[x_col]) for row in result.rows]
    y_vals = [Float64(row[y_col]) for row in result.rows]

    fig = Figure(; figure_kwargs...)
    ax = Axis(
        fig[1, 1];
        xlabel=String(x),
        ylabel=String(y),
        title="Exploration Scatter",
        axis_kwargs...,
    )

    if !isnothing(color_by)
        color_col = color_by ∈ keys(first_row) ? color_by : Symbol(:outcome_, color_by)
        if color_col ∈ keys(first_row)
            color_vals = [Float64(row[color_col]) for row in result.rows]
            sc = scatter!(ax, x_vals, y_vals; color=color_vals, scatter_kwargs...)
            Colorbar(fig[1, 2], sc; label=String(color_by))
        else
            scatter!(ax, x_vals, y_vals; scatter_kwargs...)
        end
    else
        scatter!(ax, x_vals, y_vals; scatter_kwargs...)
    end

    return (fig, ax)
end

end # module SimOptMakieExt
