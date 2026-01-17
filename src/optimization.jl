# ============================================================================
# Policy Interface Functions
# ============================================================================

"""Extract parameters from a policy as a vector."""
function params end

"""Return bounds for each parameter as Vector of (lower, upper) tuples."""
function param_bounds end

function param_bounds(::Type{T}) where {T<:AbstractPolicy}
    interface_not_implemented(:param_bounds, T, "::Type")
end

# ============================================================================
# Auto-derive param_bounds and params from ContinuousParameter fields
# ============================================================================

"""Extract parameter bounds from a policy's ContinuousParameter fields."""
function param_bounds(policy::AbstractPolicy)
    bounds = Tuple{Float64,Float64}[]
    for fname in fieldnames(typeof(policy))
        field = getfield(policy, fname)
        if field isa ContinuousParameter
            push!(bounds, (Float64(field.bounds[1]), Float64(field.bounds[2])))
        elseif field isa DiscreteParameter
            throw(
                ArgumentError(
                    "Field :$fname is DiscreteParameter. " *
                    "Optimization backends like Metaheuristics only support continuous parameters.",
                ),
            )
        elseif field isa CategoricalParameter
            throw(
                ArgumentError(
                    "Field :$fname is CategoricalParameter. " *
                    "Optimization backends like Metaheuristics only support continuous parameters.",
                ),
            )
        end
    end

    isempty(bounds) && return param_bounds(typeof(policy))
    return bounds
end

function _auto_params(policy::AbstractPolicy)
    vals = Float64[]
    for fname in fieldnames(typeof(policy))
        field = getfield(policy, fname)
        if field isa ContinuousParameter
            push!(vals, Float64(value(field)))
        end
    end
    return vals
end

function params(policy::AbstractPolicy)
    vals = _auto_params(policy)
    isempty(vals) && interface_not_implemented(:params, typeof(policy))
    return vals
end

# ============================================================================
# Optimization Result
# ============================================================================

"""Result of optimization. Pareto front contains non-dominated solutions."""
struct OptimizationResult{T<:AbstractFloat}
    convergence_info::Dict{Symbol,Any}
    pareto_params::Vector{Vector{T}}
    pareto_objectives::Vector{Vector{T}}
end

"""Iterate over the Pareto front (params, objectives) pairs."""
function pareto_front(result::OptimizationResult)
    zip(result.pareto_params, result.pareto_objectives)
end

"""Return true if solution `a` dominates solution `b` (minimization assumed)."""
function dominates(a::AbstractVector, b::AbstractVector)
    dominated = false
    for (ai, bi) in zip(a, b)
        ai > bi && return false
        ai < bi && (dominated = true)
    end
    return dominated
end

# ============================================================================
# Optimization Problem
# ============================================================================

"""Defines a simulation-optimization problem."""
struct OptimizationProblem{C<:AbstractConfig,S<:AbstractScenario,P<:AbstractPolicy,F}
    config::C
    scenarios::Vector{S}
    policy_type::Type{P}
    metric_calculator::F
    objectives::Vector{Objective}
    batch_size::AbstractBatchSize
    constraints::Vector{AbstractConstraint}
    bounds::Union{Nothing,Vector{Tuple{Float64,Float64}}}
end

"""Get parameter bounds for the problem."""
function get_bounds(prob::OptimizationProblem)
    prob.bounds !== nothing && return prob.bounds
    return [(Float64(lo), Float64(hi)) for (lo, hi) in param_bounds(prob.policy_type)]
end

function OptimizationProblem(
    config::AbstractConfig,
    scenarios::AbstractVector{<:AbstractScenario},
    policy_type::Type{P},
    metric_calculator::F,
    objectives::AbstractVector{<:Objective};
    batch_size::AbstractBatchSize=FullBatch(),
    constraints::AbstractVector{<:AbstractConstraint}=AbstractConstraint[],
    bounds::Union{Nothing,AbstractVector{<:Tuple}}=nothing,
) where {P<:AbstractPolicy,F}
    _validate_scenarios(scenarios)
    _validate_policy_interface(policy_type)
    _validate_objectives(objectives)

    scenarios_vec = collect(scenarios)
    obj_vec = collect(objectives)
    const_vec = collect(constraints)
    bounds_vec =
        bounds === nothing ? nothing : [(Float64(lo), Float64(hi)) for (lo, hi) in bounds]

    return OptimizationProblem(
        config,
        scenarios_vec,
        policy_type,
        metric_calculator,
        obj_vec,
        batch_size,
        const_vec,
        bounds_vec,
    )
end

function OptimizationProblem(
    config::AbstractConfig,
    scenarios::AbstractVector{<:AbstractScenario},
    policy_type::Type{P},
    metrics::AbstractVector{<:AbstractMetric},
    objectives::AbstractVector{<:Objective};
    batch_size::AbstractBatchSize=FullBatch(),
    constraints::AbstractVector{<:AbstractConstraint}=AbstractConstraint[],
    bounds::Union{Nothing,AbstractVector{<:Tuple}}=nothing,
) where {P<:AbstractPolicy}
    metric_names = Set(_all_metric_names(metrics))
    for obj in objectives
        if obj.name ∉ metric_names
            available = join(sort(collect(metric_names)), ", ")
            throw(
                ArgumentError(
                    "Objective references :$(obj.name) but no metric produces it. Available: $available",
                ),
            )
        end
    end

    metric_func = outcomes -> compute_metrics(metrics, outcomes)
    return OptimizationProblem(
        config,
        scenarios,
        policy_type,
        metric_func,
        objectives;
        batch_size,
        constraints,
        bounds,
    )
end

# ============================================================================
# Batch Selection
# ============================================================================

_select_batch(scenarios::Vector{S}, ::FullBatch, ::AbstractRNG) where {S} = scenarios

function _select_batch(
    scenarios::Vector{S}, batch_size::FixedBatch, rng::AbstractRNG
) where {S}
    indices = randperm(rng, length(scenarios))[1:(batch_size.n)]
    return scenarios[indices]
end

function _select_batch(
    scenarios::Vector{S}, batch_size::FractionBatch, rng::AbstractRNG
) where {S}
    n = max(1, round(Int, length(scenarios) * batch_size.fraction))
    indices = randperm(rng, length(scenarios))[1:n]
    return scenarios[indices]
end

# ============================================================================
# Policy Evaluation
# ============================================================================

"""Evaluate a policy across all (or a batch of) scenarios and return aggregated metrics."""
function evaluate_policy(
    prob::OptimizationProblem, policy::AbstractPolicy, rng::AbstractRNG
)
    batch_scenarios = _select_batch(prob.scenarios, prob.batch_size, rng)
    outcomes = map(s -> simulate(prob.config, s, policy, rng), batch_scenarios)
    return prob.metric_calculator(outcomes)
end

function evaluate_policy(prob::OptimizationProblem, policy::AbstractPolicy; seed::Int=1234)
    evaluate_policy(prob, policy, Random.Xoshiro(seed))
end

# ============================================================================
# Objective Extraction
# ============================================================================

"""Extract objective values from metrics, applying direction (negate for maximize)."""
function _extract_objectives(metrics::NamedTuple, objectives::Vector{Objective})
    return map(objectives) do obj
        haskey(metrics, obj.name) || throw(
            ArgumentError(
                "Metric calculator did not return :$(obj.name). Available: $(keys(metrics))",
            ),
        )
        val = Float64(metrics[obj.name])
        obj.direction == Maximize ? -val : val
    end
end

# ============================================================================
# Pareto Front Merging
# ============================================================================

"""Evaluate a policy and merge it into the result's Pareto front if non-dominated."""
function merge_into_pareto!(
    result::OptimizationResult{T},
    prob::OptimizationProblem,
    policy::AbstractPolicy;
    seed::Int=42,
) where {T}
    metrics = evaluate_policy(prob, policy; seed=seed)

    objectives = Vector{T}(undef, length(prob.objectives))
    for (i, obj) in enumerate(prob.objectives)
        objectives[i] = T(metrics[obj.name])
    end

    function to_min_space(objs)
        return [
            prob.objectives[i].direction == Maximize ? -objs[i] : objs[i] for
            i in eachindex(objs)
        ]
    end

    new_min = to_min_space(objectives)

    for existing_obj in result.pareto_objectives
        existing_min = to_min_space(existing_obj)
        dominates(existing_min, new_min) && return result
    end

    keep_indices = Int[]
    for (i, existing_obj) in enumerate(result.pareto_objectives)
        existing_min = to_min_space(existing_obj)
        dominates(new_min, existing_min) || push!(keep_indices, i)
    end

    new_pareto_params = result.pareto_params[keep_indices]
    new_pareto_objectives = result.pareto_objectives[keep_indices]

    push!(new_pareto_params, collect(T, params(policy)))
    push!(new_pareto_objectives, objectives)

    empty!(result.pareto_params)
    empty!(result.pareto_objectives)
    append!(result.pareto_params, new_pareto_params)
    append!(result.pareto_objectives, new_pareto_objectives)

    return result
end

# ============================================================================
# Optimization Entry Point
# ============================================================================

"""Run optimization on the problem using the specified backend."""
function optimize(prob::OptimizationProblem, backend::AbstractOptimizationBackend)
    _validate_problem(prob)
    return optimize_backend(prob, backend)
end

"""Backend-specific optimization. Extensions add methods to this function."""
function optimize_backend end

function optimize_backend(::OptimizationProblem, backend::AbstractOptimizationBackend)
    error(
        "No optimize_backend method for $(typeof(backend)). Run `using Metaheuristics` first.",
    )
end
