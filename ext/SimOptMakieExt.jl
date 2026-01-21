module SimOptMakieExt

using SimOptDecisions
using YAXArrays

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
# Exploration Plotting Implementations (YAXArray Dataset)
# ============================================================================

"""Plot exploration results as heatmap from YAXArray Dataset."""
function SimOptDecisions.plot_exploration(
    result::Dataset;
    outcome_field::Symbol,
    policy_param::Union{Symbol,Nothing}=nothing,
    scenario_param::Union{Symbol,Nothing}=nothing,
    figure_kwargs::NamedTuple=NamedTuple(),
    axis_kwargs::NamedTuple=NamedTuple(),
    heatmap_kwargs::NamedTuple=NamedTuple(),
)
    if outcome_field ∉ keys(result.cubes)
        error("Outcome field `$outcome_field` not found. Available: $(keys(result.cubes))")
    end

    outcome_arr = result[outcome_field]
    values = Matrix{Float64}(outcome_arr.data)

    n_p, n_s = size(values)

    # Determine axis labels
    if isnothing(policy_param)
        x_labels = string.(1:n_p)
        x_title = "Policy Index"
    else
        policy_col = Symbol(:policy_, policy_param)
        if policy_col ∈ keys(result.cubes)
            x_labels = string.(result[policy_col].data)
        elseif policy_param ∈ keys(result.cubes)
            x_labels = string.(result[policy_param].data)
        else
            x_labels = string.(1:n_p)
        end
        x_title = String(policy_param)
    end

    if isnothing(scenario_param)
        y_labels = string.(1:n_s)
        y_title = "Scenario Index"
    else
        scenario_col = Symbol(:scenario_, scenario_param)
        if scenario_col ∈ keys(result.cubes)
            y_labels = string.(result[scenario_col].data)
        elseif scenario_param ∈ keys(result.cubes)
            y_labels = string.(result[scenario_param].data)
        else
            y_labels = string.(1:n_s)
        end
        y_title = String(scenario_param)
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

"""Parallel coordinates for exploration results (YAXArray Dataset)."""
function SimOptDecisions.plot_exploration_parallel(
    result::Dataset;
    columns::Vector{Symbol}=Symbol[],
    figure_kwargs::NamedTuple=NamedTuple(),
    axis_kwargs::NamedTuple=NamedTuple(),
    line_kwargs::NamedTuple=NamedTuple(),
    color_by::Union{Symbol,Nothing}=nothing,
)
    available = keys(result.cubes)

    # Default: use 2D arrays (policy × scenario outcomes)
    if isempty(columns)
        columns = Symbol[k for k in available if ndims(result[k]) == 2]
    end

    n_axes = length(columns)
    if n_axes == 0
        error("No columns specified for parallel coordinates plot")
    end

    # Get first array dimensions to determine data structure
    first_arr = result[columns[1]]
    n_p, n_s = size(first_arr)

    # Extract and flatten data (policy × scenario → rows)
    all_data = Vector{Vector{Float64}}()
    for p in 1:n_p
        for s in 1:n_s
            row = [Float64(result[c][p, s]) for c in columns]
            push!(all_data, row)
        end
    end

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
    if !isnothing(color_by) && color_by ∈ available
        color_arr = result[color_by]
        color_vals = vec(color_arr.data)
        color_min, color_max = extrema(color_vals)
        color_range = color_max - color_min
        if color_range ≈ 0
            color_range = 1.0
        end
        color_norm = (color_vals .- color_min) ./ color_range

        for (i, data) in enumerate(all_data)
            norm_data = normalize(data)
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

"""Scatter plot for exploration results (YAXArray Dataset)."""
function SimOptDecisions.plot_exploration_scatter(
    result::Dataset;
    x::Symbol,
    y::Symbol,
    color_by::Union{Symbol,Nothing}=nothing,
    figure_kwargs::NamedTuple=NamedTuple(),
    axis_kwargs::NamedTuple=NamedTuple(),
    scatter_kwargs::NamedTuple=NamedTuple(),
)
    available = keys(result.cubes)

    x_col = x ∈ available ? x : Symbol(:outcome_, x)
    y_col = y ∈ available ? y : Symbol(:outcome_, y)

    x_arr = result[x_col]
    y_arr = result[y_col]

    x_vals = vec(Float64.(x_arr.data))
    y_vals = vec(Float64.(y_arr.data))

    fig = Figure(; figure_kwargs...)
    ax = Axis(
        fig[1, 1];
        xlabel=String(x),
        ylabel=String(y),
        title="Exploration Scatter",
        axis_kwargs...,
    )

    if !isnothing(color_by)
        color_col = color_by ∈ available ? color_by : Symbol(:outcome_, color_by)
        if color_col ∈ available
            color_arr = result[color_col]
            color_vals = vec(Float64.(color_arr.data))
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
