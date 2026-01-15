# ============================================================================
# Exploratory Modeling Infrastructure
# ============================================================================

using OrderedCollections: OrderedDict
using ProgressMeter: Progress, next!

# ============================================================================
# Error Types
# ============================================================================

"""
    ExploratoryInterfaceError

Thrown when types don't meet requirements for exploratory modeling.
"""
struct ExploratoryInterfaceError <: Exception
    msg::String
end

Base.showerror(io::IO, e::ExploratoryInterfaceError) = print(io, e.msg)

# ============================================================================
# Flattening Infrastructure
# ============================================================================

# Single-value parameters -> single column
function _flatten_parameter(name::Symbol, p::ContinuousParameter, prefix::Symbol)
    OrderedDict{Symbol,Any}(Symbol(prefix, :_, name) => p.value)
end

function _flatten_parameter(name::Symbol, p::DiscreteParameter, prefix::Symbol)
    OrderedDict{Symbol,Any}(Symbol(prefix, :_, name) => p.value)
end

function _flatten_parameter(name::Symbol, p::CategoricalParameter, prefix::Symbol)
    OrderedDict{Symbol,Any}(Symbol(prefix, :_, name) => p.value)
end

# Time series -> multiple columns with [i] notation
function _flatten_parameter(name::Symbol, p::TimeSeriesParameter, prefix::Symbol)
    result = OrderedDict{Symbol,Any}()
    for (i, val) in enumerate(p.data)
        result[Symbol(prefix, :_, name, "[", i, "]")] = val
    end
    return result
end

"""
    _flatten_to_namedtuple(obj, prefix::Symbol) -> NamedTuple

Flatten a struct with parameter fields to a NamedTuple with prefixed column names.
"""
function _flatten_to_namedtuple(obj, prefix::Symbol)
    T = typeof(obj)
    result = OrderedDict{Symbol,Any}()

    for fname in fieldnames(T)
        field = getfield(obj, fname)

        if field isa AbstractParameter
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
    """
Cannot flatten `$T` for exploratory analysis.

Problem: Field `$fname` has type `$ftype`, which is not a parameter type.

All fields must be one of:
  - ContinuousParameter{T}  -- continuous real values
  - DiscreteParameter{T}    -- integer values
  - CategoricalParameter{T} -- categorical/enum values
  - TimeSeriesParameter{T}  -- time series data

Example fix:

    # Before
    struct $T
        $fname::$ftype
    end

    # After
    struct $T
        $fname::ContinuousParameter{Float64}
    end

Note: `simulate()` and `evaluate_policy()` work without this requirement.
Only `explore()` requires parameter types for structured output.
"""
end

# ============================================================================
# Validation
# ============================================================================

function _validate_exploratory_interface(::Type{S}, ::Type{P}, ::Type{O}) where {S,P,O}
    errors = String[]

    _collect_field_errors!(errors, S, "SOW")
    _collect_field_errors!(errors, P, "Policy")
    _collect_field_errors!(errors, O, "Outcome")

    if !isempty(errors)
        throw(
            ExploratoryInterfaceError(
                "Cannot use `explore()` with current types:\n\n" *
                join(errors, "\n") *
                "\n\n" *
                "All fields must be: ContinuousParameter, DiscreteParameter, " *
                "CategoricalParameter, or TimeSeriesParameter.\n\n" *
                "Note: `simulate()` and `evaluate_policy()` still work without this.",
            ),
        )
    end
end

function _collect_field_errors!(errors, T, label)
    for (fname, ftype) in zip(fieldnames(T), fieldtypes(T))
        is_param = ftype <: AbstractParameter || ftype <: TimeSeriesParameter
        # Handle parametric types (UnionAll)
        if !is_param && ftype isa UnionAll
            is_param = ftype <: AbstractParameter || ftype <: TimeSeriesParameter
        end
        if !is_param
            push!(errors, "  - $label.$fname :: $ftype")
        end
    end
end

# ============================================================================
# ExplorationResult
# ============================================================================

"""
    ExplorationResult

Results from `explore()`, containing outcomes for all (policy, sow) combinations.

# Indexing
- `result[p, s]` -- outcome for policy p, sow s
- `outcomes_for_policy(result, p)` -- all outcomes for policy p
- `outcomes_for_sow(result, s)` -- all outcomes for sow s

# Tables.jl Integration
Convert to DataFrame: `DataFrame(result)`

# Fields
- `rows::Vector{NamedTuple}` -- all result rows
- `n_policies::Int` -- number of policies
- `n_sows::Int` -- number of SOWs
- `policy_columns::Vector{Symbol}` -- column names for policy parameters
- `sow_columns::Vector{Symbol}` -- column names for SOW parameters
- `outcome_columns::Vector{Symbol}` -- column names for outcome fields
"""
struct ExplorationResult
    rows::Vector{NamedTuple}
    n_policies::Int
    n_sows::Int
    policy_columns::Vector{Symbol}
    sow_columns::Vector{Symbol}
    outcome_columns::Vector{Symbol}
end

function ExplorationResult(rows::Vector{NamedTuple}, n_policies::Int, n_sows::Int)
    if isempty(rows)
        return ExplorationResult(rows, n_policies, n_sows, Symbol[], Symbol[], Symbol[])
    end

    all_cols = collect(keys(first(rows)))

    policy_cols = filter(all_cols) do c
        s = String(c)
        startswith(s, "policy_") && c != :policy_idx
    end

    sow_cols = filter(all_cols) do c
        s = String(c)
        startswith(s, "sow_") && c != :sow_idx
    end

    outcome_cols = filter(c -> startswith(String(c), "outcome_"), all_cols)

    ExplorationResult(rows, n_policies, n_sows, policy_cols, sow_cols, outcome_cols)
end

# Indexing
function Base.getindex(r::ExplorationResult, p::Int, s::Int)
    @boundscheck begin
        1 <= p <= r.n_policies || throw(BoundsError(r, (p, s)))
        1 <= s <= r.n_sows || throw(BoundsError(r, (p, s)))
    end
    idx = (p - 1) * r.n_sows + s
    return r.rows[idx]
end

Base.size(r::ExplorationResult) = (r.n_policies, r.n_sows)
Base.length(r::ExplorationResult) = length(r.rows)

# Iteration
Base.iterate(r::ExplorationResult) = iterate(r.rows)
Base.iterate(r::ExplorationResult, state) = iterate(r.rows, state)
Base.eltype(::Type{ExplorationResult}) = NamedTuple

# Tables.jl interface
Tables.istable(::Type{<:ExplorationResult}) = true
Tables.rowaccess(::Type{<:ExplorationResult}) = true
Tables.rows(r::ExplorationResult) = r.rows

function Tables.schema(r::ExplorationResult)
    isempty(r.rows) && return nothing
    row = first(r.rows)
    Tables.Schema(keys(row), typeof.(values(row)))
end

"""
    outcomes_for_policy(result::ExplorationResult, p::Int) -> Vector{NamedTuple}

Get all outcomes for a specific policy across all SOWs.
"""
outcomes_for_policy(r::ExplorationResult, p::Int) = [r[p, s] for s in 1:r.n_sows]

"""
    outcomes_for_sow(result::ExplorationResult, s::Int) -> Vector{NamedTuple}

Get all outcomes for a specific SOW across all policies.
"""
outcomes_for_sow(r::ExplorationResult, s::Int) = [r[p, s] for p in 1:r.n_policies]

# Filtering
function Base.filter(f, r::ExplorationResult)
    filtered = filter(f, r.rows)
    ExplorationResult(
        filtered, r.n_policies, r.n_sows, r.policy_columns, r.sow_columns, r.outcome_columns
    )
end

# Finalize InMemorySink -> ExplorationResult
function finalize(sink::InMemorySink, n_policies::Int, n_sows::Int)
    ExplorationResult(sink.results, n_policies, n_sows)
end

# ============================================================================
# Main explore() Function
# ============================================================================

"""
    explore(config, sows, policies; sink, rng, progress) -> ExplorationResult

Run simulations for all combinations of policies and SOWs, collecting structured results.

# Arguments
- `config::AbstractConfig`: Simulation configuration
- `sows::AbstractVector{<:AbstractSOW}`: States of the world to explore
- `policies::AbstractVector{<:AbstractPolicy}`: Policies to evaluate

# Keyword Arguments
- `sink::AbstractResultSink = InMemorySink()`: Where to store results
- `rng::AbstractRNG = Random.default_rng()`: Random number generator
- `progress::Bool = true`: Show progress bar

# Returns
- `ExplorationResult` (for InMemorySink) or filepath (for file sinks)

# Requirements
All fields in SOW, Policy, and Outcome types must be parameter types:
`ContinuousParameter`, `DiscreteParameter`, `CategoricalParameter`, or `TimeSeriesParameter`.

# Example
```julia
result = explore(config, sows, policies)

# Access results
result[1, 2]  # policy 1, sow 2
outcomes_for_policy(result, 1)  # all sows for policy 1

# Convert to DataFrame
using DataFrames
df = DataFrame(result)
```
"""
function explore(
    config::AbstractConfig,
    sows::AbstractVector{<:AbstractSOW},
    policies::AbstractVector{<:AbstractPolicy};
    sink::AbstractResultSink=InMemorySink(),
    rng::AbstractRNG=Random.default_rng(),
    progress::Bool=true,
)
    isempty(sows) && throw(ArgumentError("sows cannot be empty"))
    isempty(policies) && throw(ArgumentError("policies cannot be empty"))

    # Run one simulation to get outcome type for validation
    first_outcome = simulate(config, first(sows), first(policies), rng)

    # Validate all types have parameter fields
    _validate_exploratory_interface(eltype(sows), eltype(policies), typeof(first_outcome))

    n_policies = length(policies)
    n_sows = length(sows)
    n_total = n_policies * n_sows

    prog = progress ? Progress(n_total; desc="Exploring: ", showspeed=true) : nothing

    for (p_idx, policy) in enumerate(policies)
        for (s_idx, sow) in enumerate(sows)
            # Skip first simulation (already done for validation)
            outcome = if p_idx == 1 && s_idx == 1
                first_outcome
            else
                simulate(config, sow, policy, rng)
            end

            row = (
                policy_idx=p_idx,
                sow_idx=s_idx,
                _flatten_to_namedtuple(policy, :policy)...,
                _flatten_to_namedtuple(sow, :sow)...,
                _flatten_to_namedtuple(outcome, :outcome)...,
            )

            record!(sink, row)
            !isnothing(prog) && next!(prog)
        end
    end

    return finalize(sink, n_policies, n_sows)
end

# Convenience: single policy
function explore(
    config::AbstractConfig,
    sows::AbstractVector{<:AbstractSOW},
    policy::AbstractPolicy;
    kwargs...,
)
    explore(config, sows, [policy]; kwargs...)
end

# Convenience: from OptimizationProblem
function explore(
    prob::OptimizationProblem, policies::AbstractVector{<:AbstractPolicy}; kwargs...
)
    explore(prob.config, prob.sows, policies; kwargs...)
end

function explore(prob::OptimizationProblem, policy::AbstractPolicy; kwargs...)
    explore(prob.config, prob.sows, [policy]; kwargs...)
end
