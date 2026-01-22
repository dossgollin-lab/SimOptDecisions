# ============================================================================
# Exploratory Modeling Infrastructure with YAXArrays
# ============================================================================

using OrderedCollections: OrderedDict
using ProgressMeter: Progress, next!
using YAXArrays

# ============================================================================
# Error Types
# ============================================================================

"""Thrown when types don't meet requirements for exploratory modeling."""
struct ExploratoryInterfaceError <: Exception
    msg::String
end

Base.showerror(io::IO, e::ExploratoryInterfaceError) = print(io, e.msg)

# ============================================================================
# Flattening Infrastructure
# ============================================================================

function _flatten_parameter(name::Symbol, p::ContinuousParameter, prefix::Symbol)
    OrderedDict{Symbol,Any}(Symbol(prefix, :_, name) => p.value)
end

function _flatten_parameter(name::Symbol, p::DiscreteParameter, prefix::Symbol)
    OrderedDict{Symbol,Any}(Symbol(prefix, :_, name) => p.value)
end

function _flatten_parameter(name::Symbol, p::CategoricalParameter, prefix::Symbol)
    OrderedDict{Symbol,Any}(Symbol(prefix, :_, name) => p.value)
end

function _flatten_parameter(name::Symbol, p::TimeSeriesParameter, prefix::Symbol)
    result = OrderedDict{Symbol,Any}()
    for (t, val) in zip(p.time_axis, p.values)
        result[Symbol(prefix, :_, name, "[", t, "]")] = val
    end
    return result
end

function _flatten_parameter(::Symbol, ::GenericParameter, ::Symbol)
    return OrderedDict{Symbol,Any}()
end

"""Flatten a struct with parameter fields to a NamedTuple. GenericParameter fields are skipped."""
function _flatten_to_namedtuple(obj, prefix::Symbol)
    T = typeof(obj)
    result = OrderedDict{Symbol,Any}()

    for fname in fieldnames(T)
        field = getfield(obj, fname)

        if field isa GenericParameter
            continue
        elseif field isa AbstractParameter
            merge!(result, _flatten_parameter(fname, field, prefix))
        elseif field isa TimeSeriesParameter
            merge!(result, _flatten_parameter(fname, field, prefix))
        else
            throw(ExploratoryInterfaceError(_format_field_error(T, fname, typeof(field))))
        end
    end

    return NamedTuple{tuple(keys(result)...)}(values(result))
end

function _format_field_error(T, fname, ftype)
    "Field `$fname::$ftype` in `$T` is not a parameter type."
end

# ============================================================================
# Outcome Field Extraction
# ============================================================================

"""Extract outcome field names and types from a sample outcome."""
function _extract_outcome_info(outcome)
    T = typeof(outcome)
    names = Symbol[]
    types = Type[]
    is_timeseries = Bool[]

    for fname in fieldnames(T)
        field = getfield(outcome, fname)

        if field isa GenericParameter
            continue
        elseif field isa TimeSeriesParameter
            push!(names, fname)
            push!(types, eltype(field.values))
            push!(is_timeseries, true)
        elseif field isa AbstractParameter
            push!(names, fname)
            push!(types, typeof(field.value))
            push!(is_timeseries, false)
        else
            throw(ExploratoryInterfaceError(_format_field_error(T, fname, typeof(field))))
        end
    end

    return names, types, is_timeseries
end

# _get_outcome_value is defined in parameters.jl

# ============================================================================
# Validation
# ============================================================================

function _validate_exploratory_interface(::Type{S}, ::Type{P}, ::Type{O}) where {S,P,O}
    errors = String[]

    _collect_field_errors!(errors, S, "Scenario")
    _collect_field_errors!(errors, P, "Policy")
    _collect_field_errors!(errors, O, "Outcome")

    if !isempty(errors)
        throw(
            ExploratoryInterfaceError(
                "Cannot use `explore()` with current types:\n\n" *
                join(errors, "\n") *
                "\n\n" *
                "All fields must be: ContinuousParameter, DiscreteParameter, " *
                "CategoricalParameter, TimeSeriesParameter, or GenericParameter.\n\n" *
                "Note: `simulate()` and `evaluate_policy()` still work without this.",
            ),
        )
    end
end

function _collect_field_errors!(errors, T, label)
    for (fname, ftype) in zip(fieldnames(T), fieldtypes(T))
        _is_parameter_type(ftype) || push!(errors, "  - $label.$fname :: $ftype")
    end
end

# ============================================================================
# YAXArray Result Construction
# ============================================================================

"""Build a YAXArray Dataset from exploration results."""
function _build_yaxarray_result(
    outcomes::Matrix,
    outcome_names::Vector{Symbol},
    outcome_types::Vector{Type},
    is_timeseries::Vector{Bool},
    n_policies::Int,
    n_scenarios::Int,
    time_axes::Union{Nothing,Dict{Symbol,Vector}},
    policies::AbstractVector,
    scenarios::AbstractVector,
)
    policy_axis = Dim{:policy}(1:n_policies)
    scenario_axis = Dim{:scenario}(1:n_scenarios)

    arrays = Dict{Symbol,YAXArray}()

    for (i, name) in enumerate(outcome_names)
        if is_timeseries[i] && !isnothing(time_axes) && haskey(time_axes, name)
            time_vec = time_axes[name]
            time_axis = Dim{:time}(time_vec)

            n_times = length(time_vec)
            T = outcome_types[i]
            data = Array{T,3}(undef, n_policies, n_scenarios, n_times)

            for p in 1:n_policies
                for s in 1:n_scenarios
                    vals = _get_outcome_value(getfield(outcomes[p, s], name))
                    data[p, s, :] .= vals
                end
            end

            arrays[name] = YAXArray((policy_axis, scenario_axis, time_axis), data)
        else
            T = outcome_types[i]
            data = Matrix{T}(undef, n_policies, n_scenarios)

            for p in 1:n_policies
                for s in 1:n_scenarios
                    data[p, s] = _get_outcome_value(getfield(outcomes[p, s], name))
                end
            end

            arrays[name] = YAXArray((policy_axis, scenario_axis), data)
        end
    end

    _add_coordinate_metadata!(arrays, policies, scenarios, policy_axis, scenario_axis)

    return Dataset(; arrays...)
end

"""Add policy and scenario parameter metadata as coordinates."""
function _add_coordinate_metadata!(
    arrays::Dict{Symbol,YAXArray},
    policies::AbstractVector,
    scenarios::AbstractVector,
    policy_axis,
    scenario_axis,
)
    if !isempty(policies)
        policy_flat = _flatten_to_namedtuple(first(policies), :policy)
        for (key, _) in pairs(policy_flat)
            vals = [_flatten_to_namedtuple(p, :policy)[key] for p in policies]
            arrays[key] = YAXArray((policy_axis,), _make_zarr_compatible(vals))
        end
    end

    if !isempty(scenarios)
        scenario_flat = _flatten_to_namedtuple(first(scenarios), :scenario)
        for (key, _) in pairs(scenario_flat)
            vals = [_flatten_to_namedtuple(s, :scenario)[key] for s in scenarios]
            arrays[key] = YAXArray((scenario_axis,), _make_zarr_compatible(vals))
        end
    end
end

"""Convert values to Zarr-compatible types (Symbols -> Strings)."""
_make_zarr_compatible(vals::Vector{Symbol}) = String.(vals)
_make_zarr_compatible(vals) = vals

# ============================================================================
# Main explore() Function
# ============================================================================

"""
Run simulations for all (policy, scenario) combinations. Returns YAXArray Dataset.

All fields in Scenario, Policy, and Outcome must use parameter types.
Dimensions: (:policy, :scenario), with time series adding (:time).
"""
function explore(
    config::AbstractConfig,
    scenarios::AbstractVector{<:AbstractScenario},
    policies::AbstractVector{<:AbstractPolicy};
    executor::AbstractExecutor=SequentialExecutor(),
    backend::AbstractStorageBackend=InMemoryBackend(),
    progress::Bool=true,
)
    isempty(scenarios) && throw(ArgumentError("scenarios cannot be empty"))
    isempty(policies) && throw(ArgumentError("policies cannot be empty"))

    rng = create_scenario_rng(executor.crn, 1)
    first_outcome = simulate(config, first(scenarios), first(policies), rng)
    _validate_exploratory_interface(
        eltype(scenarios), eltype(policies), typeof(first_outcome)
    )

    n_policies = length(policies)
    n_scenarios = length(scenarios)

    outcome_names, outcome_types, is_timeseries = _extract_outcome_info(first_outcome)

    time_axes = _extract_time_axes(first_outcome, outcome_names, is_timeseries)

    if backend isa InMemoryBackend
        return _explore_inmemory(
            config,
            scenarios,
            policies,
            executor,
            outcome_names,
            outcome_types,
            is_timeseries,
            time_axes;
            progress,
        )
    elseif backend isa ZarrBackend
        return _explore_zarr(
            config,
            scenarios,
            policies,
            executor,
            backend,
            outcome_names,
            outcome_types,
            is_timeseries,
            time_axes;
            progress,
        )
    else
        throw(ArgumentError("Unknown backend type: $(typeof(backend))"))
    end
end

function _extract_time_axes(
    outcome, outcome_names::Vector{Symbol}, is_timeseries::Vector{Bool}
)
    time_axes = Dict{Symbol,Vector}()

    for (i, name) in enumerate(outcome_names)
        if is_timeseries[i]
            field = getfield(outcome, name)
            if field isa TimeSeriesParameter
                time_axes[name] = collect(field.time_axis)
            end
        end
    end

    return isempty(time_axes) ? nothing : time_axes
end

function _explore_inmemory(
    config::AbstractConfig,
    scenarios::AbstractVector{<:AbstractScenario},
    policies::AbstractVector{<:AbstractPolicy},
    executor::AbstractExecutor,
    outcome_names::Vector{Symbol},
    outcome_types::Vector{Type},
    is_timeseries::Vector{Bool},
    time_axes::Union{Nothing,Dict{Symbol,Vector}};
    progress::Bool=true,
)
    n_policies = length(policies)
    n_scenarios = length(scenarios)

    outcomes = Matrix{Any}(undef, n_policies, n_scenarios)

    callback = (p_idx, s_idx, outcome) -> begin
        outcomes[p_idx, s_idx] = outcome
    end

    execute_exploration(executor, config, scenarios, policies, callback; progress)

    return _build_yaxarray_result(
        outcomes,
        outcome_names,
        outcome_types,
        is_timeseries,
        n_policies,
        n_scenarios,
        time_axes,
        policies,
        scenarios,
    )
end

function _explore_zarr(
    config::AbstractConfig,
    scenarios::AbstractVector{<:AbstractScenario},
    policies::AbstractVector{<:AbstractPolicy},
    executor::AbstractExecutor,
    backend::ZarrBackend,
    outcome_names::Vector{Symbol},
    outcome_types::Vector{Type},
    is_timeseries::Vector{Bool},
    time_axes::Union{Nothing,Dict{Symbol,Vector}};
    progress::Bool=true,
)
    # Build in-memory first, then save to Zarr
    result = _explore_inmemory(
        config,
        scenarios,
        policies,
        executor,
        outcome_names,
        outcome_types,
        is_timeseries,
        time_axes;
        progress,
    )

    save_zarr(result, backend.path; overwrite=backend.overwrite)
    return load_zarr_results(backend.path)
end

# ============================================================================
# Traced Exploration
# ============================================================================

"""
Run traced simulations for all combinations. Returns (Dataset, traces::Matrix).

Only supported with SequentialExecutor and ThreadedExecutor.
"""
function explore_traced(
    config::AbstractConfig,
    scenarios::AbstractVector{<:AbstractScenario},
    policies::AbstractVector{<:AbstractPolicy};
    executor::AbstractExecutor=SequentialExecutor(),
    progress::Bool=true,
)
    isempty(scenarios) && throw(ArgumentError("scenarios cannot be empty"))
    isempty(policies) && throw(ArgumentError("policies cannot be empty"))

    rng = create_scenario_rng(executor.crn, 1)
    first_outcome, _ = simulate_traced(config, first(scenarios), first(policies), rng)
    _validate_exploratory_interface(
        eltype(scenarios), eltype(policies), typeof(first_outcome)
    )

    n_policies = length(policies)
    n_scenarios = length(scenarios)

    outcome_names, outcome_types, is_timeseries = _extract_outcome_info(first_outcome)
    time_axes = _extract_time_axes(first_outcome, outcome_names, is_timeseries)

    outcomes = Matrix{Any}(undef, n_policies, n_scenarios)
    traces = Matrix{Any}(undef, n_policies, n_scenarios)

    callback = (p_idx, s_idx, outcome, trace) -> begin
        outcomes[p_idx, s_idx] = outcome
        traces[p_idx, s_idx] = trace
    end

    execute_traced_exploration(executor, config, scenarios, policies, callback; progress)

    result = _build_yaxarray_result(
        outcomes,
        outcome_names,
        outcome_types,
        is_timeseries,
        n_policies,
        n_scenarios,
        time_axes,
        policies,
        scenarios,
    )

    return result, traces
end

# ============================================================================
# Convenience Overloads
# ============================================================================

function explore(
    config::AbstractConfig,
    scenarios::AbstractVector{<:AbstractScenario},
    policy::AbstractPolicy;
    kwargs...,
)
    explore(config, scenarios, [policy]; kwargs...)
end

function explore(
    prob::OptimizationProblem, policies::AbstractVector{<:AbstractPolicy}; kwargs...
)
    explore(prob.config, prob.scenarios, policies; kwargs...)
end

function explore(prob::OptimizationProblem, policy::AbstractPolicy; kwargs...)
    explore(prob.config, prob.scenarios, [policy]; kwargs...)
end

# ============================================================================
# Result Utilities
# ============================================================================

"""Get dimension names from a YAXArray."""
_dim_names(arr) = [typeof(d).parameters[1] for d in arr.axes]

"""Get outcomes for a specific policy (returns Dataset slice)."""
function outcomes_for_policy(ds::Dataset, p::Int)
    Dict(
        name => ds[name][policy = p] for
        name in keys(ds.cubes) if :policy in _dim_names(ds[name])
    )
end

"""Get outcomes for a specific scenario (returns Dataset slice)."""
function outcomes_for_scenario(ds::Dataset, s::Int)
    Dict(
        name => ds[name][scenario = s] for
        name in keys(ds.cubes) if :scenario in _dim_names(ds[name])
    )
end
