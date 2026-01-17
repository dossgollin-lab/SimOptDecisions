# ============================================================================
# Exploratory Modeling Infrastructure
# ============================================================================

using OrderedCollections: OrderedDict
using ProgressMeter: Progress, next!

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
# ExplorationResult
# ============================================================================

"""Results from `explore()`. Indexable via `result[p, s]` and Tables.jl compatible."""
struct ExplorationResult
    rows::Vector{NamedTuple}
    n_policies::Int
    n_scenarios::Int
    policy_columns::Vector{Symbol}
    scenario_columns::Vector{Symbol}
    outcome_columns::Vector{Symbol}
end

function ExplorationResult(rows::Vector{NamedTuple}, n_policies::Int, n_scenarios::Int)
    if isempty(rows)
        return ExplorationResult(
            rows, n_policies, n_scenarios, Symbol[], Symbol[], Symbol[]
        )
    end

    all_cols = collect(keys(first(rows)))
    policy_cols = filter(
        c -> startswith(String(c), "policy_") && c != :policy_idx, all_cols
    )
    scenario_cols = filter(
        c -> startswith(String(c), "scenario_") && c != :scenario_idx, all_cols
    )
    outcome_cols = filter(c -> startswith(String(c), "outcome_"), all_cols)

    ExplorationResult(
        rows, n_policies, n_scenarios, policy_cols, scenario_cols, outcome_cols
    )
end

function Base.getindex(r::ExplorationResult, p::Int, s::Int)
    @boundscheck begin
        1 <= p <= r.n_policies || throw(BoundsError(r, (p, s)))
        1 <= s <= r.n_scenarios || throw(BoundsError(r, (p, s)))
    end
    idx = (p - 1) * r.n_scenarios + s
    return r.rows[idx]
end

Base.size(r::ExplorationResult) = (r.n_policies, r.n_scenarios)
Base.length(r::ExplorationResult) = length(r.rows)
Base.iterate(r::ExplorationResult) = iterate(r.rows)
Base.iterate(r::ExplorationResult, state) = iterate(r.rows, state)
Base.eltype(::Type{ExplorationResult}) = NamedTuple

Tables.istable(::Type{<:ExplorationResult}) = true
Tables.rowaccess(::Type{<:ExplorationResult}) = true
Tables.rows(r::ExplorationResult) = r.rows

function Tables.schema(r::ExplorationResult)
    isempty(r.rows) && return nothing
    row = first(r.rows)
    Tables.Schema(keys(row), typeof.(values(row)))
end

"""Get all outcomes for a specific policy across all scenarios."""
outcomes_for_policy(r::ExplorationResult, p::Int) = [r[p, s] for s in 1:r.n_scenarios]

"""Get all outcomes for a specific scenario across all policies."""
outcomes_for_scenario(r::ExplorationResult, s::Int) = [r[p, s] for p in 1:r.n_policies]

function Base.filter(f, r::ExplorationResult)
    filtered = filter(f, r.rows)
    ExplorationResult(
        filtered,
        r.n_policies,
        r.n_scenarios,
        r.policy_columns,
        r.scenario_columns,
        r.outcome_columns,
    )
end

function finalize(sink::InMemorySink, n_policies::Int, n_scenarios::Int)
    ExplorationResult(sink.results, n_policies, n_scenarios)
end

# ============================================================================
# Main explore() Function
# ============================================================================

"""
Run simulations for all (policy, scenario) combinations. Returns ExplorationResult.

All fields in Scenario, Policy, and Outcome must use parameter types.
"""
function explore(
    config::AbstractConfig,
    scenarios::AbstractVector{<:AbstractScenario},
    policies::AbstractVector{<:AbstractPolicy};
    sink::AbstractResultSink=InMemorySink(),
    rng::AbstractRNG=Random.default_rng(),
    progress::Bool=true,
)
    isempty(scenarios) && throw(ArgumentError("scenarios cannot be empty"))
    isempty(policies) && throw(ArgumentError("policies cannot be empty"))

    first_outcome = simulate(config, first(scenarios), first(policies), rng)
    _validate_exploratory_interface(
        eltype(scenarios), eltype(policies), typeof(first_outcome)
    )

    n_policies = length(policies)
    n_scenarios = length(scenarios)
    n_total = n_policies * n_scenarios

    prog = progress ? Progress(n_total; desc="Exploring: ", showspeed=true) : nothing

    for (p_idx, policy) in enumerate(policies)
        for (s_idx, scenario) in enumerate(scenarios)
            outcome = if p_idx == 1 && s_idx == 1
                first_outcome
            else
                simulate(config, scenario, policy, rng)
            end

            row = (
                policy_idx=p_idx,
                scenario_idx=s_idx,
                _flatten_to_namedtuple(policy, :policy)...,
                _flatten_to_namedtuple(scenario, :scenario)...,
                _flatten_to_namedtuple(outcome, :outcome)...,
            )

            record!(sink, row)
            !isnothing(prog) && next!(prog)
        end
    end

    return finalize(sink, n_policies, n_scenarios)
end

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
