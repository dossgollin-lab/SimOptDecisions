# ============================================================================
# Policy Interface Functions
# ============================================================================

"""
    params(policy::AbstractPolicy) -> AbstractVector{<:AbstractFloat}

Extract parameters from a policy as a vector.
Optional: useful for inspection/logging, but not required for optimization.
The optimizer uses `param_bounds` and the vector constructor instead.
"""
function params end

"""
    param_bounds(::Type{P}) -> Vector{Tuple{T,T}}

Return the bounds for each parameter as a Vector of (lower, upper) tuples.
Override for your policy type.
"""
function param_bounds end

function param_bounds(::Type{T}) where {T<:AbstractPolicy}
    interface_not_implemented(:param_bounds, T, "::Type")
end

# ============================================================================
# Auto-derive param_bounds and params from ContinuousParameter fields
# ============================================================================

"""
    param_bounds(policy::AbstractPolicy) -> Vector{Tuple{Float64,Float64}}

Extract parameter bounds from a policy's ContinuousParameter fields.
Falls back to `param_bounds(typeof(policy))` if no ContinuousParameter fields found.
"""
function param_bounds(policy::AbstractPolicy)
    bounds = Tuple{Float64,Float64}[]
    for fname in fieldnames(typeof(policy))
        field = getfield(policy, fname)
        if field isa ContinuousParameter
            push!(bounds, (Float64(field.bounds[1]), Float64(field.bounds[2])))
        elseif field isa DiscreteParameter
            throw(ArgumentError(
                "Field :$fname is DiscreteParameter. " *
                "Optimization backends like Metaheuristics only support continuous parameters. " *
                "Use ContinuousParameter or implement a custom optimizer."
            ))
        elseif field isa CategoricalParameter
            throw(ArgumentError(
                "Field :$fname is CategoricalParameter. " *
                "Optimization backends like Metaheuristics only support continuous parameters. " *
                "Use ContinuousParameter or implement a custom optimizer."
            ))
        end
    end

    if isempty(bounds)
        # No ContinuousParameter fields found, fall back to type-based method
        return param_bounds(typeof(policy))
    end

    return bounds
end

"""
    params(policy::AbstractPolicy) -> Vector{Float64}

Extract parameter values from a policy's ContinuousParameter fields.
Auto-derives from ContinuousParameter fields if not explicitly implemented.
"""
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

# Override the fallback to use auto-derive when possible
function params(policy::AbstractPolicy)
    vals = _auto_params(policy)
    if isempty(vals)
        interface_not_implemented(:params, typeof(policy))
    end
    return vals
end

# ============================================================================
# Optimization Result
# ============================================================================

"""
Result of an optimization run.

The Pareto front contains all non-dominated solutions. For single-objective problems,
this is a single point. For multi-objective problems, users iterate over the front
and select based on their preferences.

To construct a policy: `PolicyType(params)` where `params` comes from iterating `pareto_front(result)`.

# Fields
- `convergence_info::Dict{Symbol,Any}`: Backend-specific convergence information
- `pareto_params::Vector{Vector{T}}`: Pareto front parameter vectors
- `pareto_objectives::Vector{Vector{T}}`: Pareto front objective values
"""
struct OptimizationResult{T<:AbstractFloat}
    convergence_info::Dict{Symbol,Any}
    pareto_params::Vector{Vector{T}}
    pareto_objectives::Vector{Vector{T}}
end

"""
    pareto_front(result::OptimizationResult)

Iterate over the Pareto front (params, objectives) pairs.
"""
function pareto_front(result::OptimizationResult)
    return zip(result.pareto_params, result.pareto_objectives)
end

"""
    dominates(a::Vector, b::Vector) -> Bool

Return true if solution `a` dominates solution `b` (all objectives ≤ and at least one <).
Assumes minimization for all objectives.
"""
function dominates(a::AbstractVector, b::AbstractVector)
    dominated = false
    for (ai, bi) in zip(a, b)
        if ai > bi
            return false  # a is worse in at least one objective
        elseif ai < bi
            dominated = true  # a is strictly better in at least one
        end
    end
    return dominated
end

# ============================================================================
# Optimization Problem
# ============================================================================

"""Defines a simulation-optimization problem. See examples for usage."""
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

"""
    get_bounds(prob::OptimizationProblem)

Get the parameter bounds for the problem. Uses custom bounds if specified,
otherwise falls back to `param_bounds(prob.policy_type)`.
"""
function get_bounds(prob::OptimizationProblem)
    if prob.bounds !== nothing
        return prob.bounds
    else
        return [(Float64(lo), Float64(hi)) for (lo, hi) in param_bounds(prob.policy_type)]
    end
end

# Primary constructor with validation
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
    # Validate inputs
    _validate_scenarios(scenarios)
    _validate_policy_interface(policy_type)
    _validate_objectives(objectives)

    # Convert to concrete vector types
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

# Constructor accepting Vector{AbstractMetric} for declarative metrics
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
    # Validate that all objectives reference metrics that will be computed
    metric_names = Set(_all_metric_names(metrics))
    for obj in objectives
        if obj.name ∉ metric_names
            available = join(sort(collect(metric_names)), ", ")
            throw(ArgumentError(
                "Objective references :$(obj.name) but no metric produces it. " *
                "Available metrics: $available"
            ))
        end
    end

    # Convert to function for internal use
    metric_func = outcomes -> compute_metrics(metrics, outcomes)

    return OptimizationProblem(
        config, scenarios, policy_type, metric_func, objectives;
        batch_size=batch_size, constraints=constraints, bounds=bounds
    )
end

# ============================================================================
# Batch Selection
# ============================================================================

"""
Select scenarios for a batch evaluation.
"""
function _select_batch(scenarios::Vector{S}, batch_size::FullBatch, rng::AbstractRNG) where {S}
    return scenarios
end

function _select_batch(scenarios::Vector{S}, batch_size::FixedBatch, rng::AbstractRNG) where {S}
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

"""
    evaluate_policy(prob::OptimizationProblem, policy, rng::AbstractRNG)

Evaluate a policy across all (or a batch of) scenarios and return aggregated metrics.
"""
function evaluate_policy(
    prob::OptimizationProblem, policy::AbstractPolicy, rng::AbstractRNG
)
    # Select scenarios for this evaluation
    batch_scenarios = _select_batch(prob.scenarios, prob.batch_size, rng)

    # Run simulations
    outcomes = map(batch_scenarios) do scenario
        simulate(prob.config, scenario, policy, rng)
    end

    # Aggregate to metrics
    return prob.metric_calculator(outcomes)
end

# Convenience overload with seed
function evaluate_policy(prob::OptimizationProblem, policy::AbstractPolicy; seed::Int=1234)
    return evaluate_policy(prob, policy, Random.Xoshiro(seed))
end

# ============================================================================
# Objective Extraction
# ============================================================================

"""
Extract objective values from metrics, applying direction (negate for maximize).
"""
function _extract_objectives(metrics::NamedTuple, objectives::Vector{Objective})
    return map(objectives) do obj
        if !haskey(metrics, obj.name)
            throw(
                ArgumentError(
                    "Metric calculator did not return :$(obj.name). " *
                    "Available metrics: $(keys(metrics))",
                ),
            )
        end
        val = Float64(metrics[obj.name])
        # Metaheuristics minimizes, so negate for maximize
        obj.direction == Maximize ? -val : val
    end
end

# ============================================================================
# Pareto Front Merging
# ============================================================================

"""
    merge_into_pareto!(result::OptimizationResult, prob::OptimizationProblem, policy::AbstractPolicy; seed=42)

Evaluate a policy and merge it into the optimization result's Pareto front.
The policy is evaluated using the problem's config, scenarios, and metric calculator.
Dominance is checked: the policy is added only if not dominated, and any
existing solutions dominated by it are removed.

# Example
```julia
result = optimize(prob, backend)
merge_into_pareto!(result, prob, ElevationPolicy(0.0))  # add "no elevation" baseline
```
"""
function merge_into_pareto!(
    result::OptimizationResult{T},
    prob::OptimizationProblem,
    policy::AbstractPolicy;
    seed::Int=42,
) where {T}
    # Evaluate the policy
    metrics = evaluate_policy(prob, policy; seed=seed)

    # Extract objectives (store un-negated, original scale)
    objectives = Vector{T}(undef, length(prob.objectives))
    for (i, obj) in enumerate(prob.objectives)
        objectives[i] = T(metrics[obj.name])
    end

    # For dominance checking, convert to minimization space
    function to_min_space(objs)
        return [
            prob.objectives[i].direction == Maximize ? -objs[i] : objs[i] for
            i in eachindex(objs)
        ]
    end

    new_min = to_min_space(objectives)

    # Check if new solution is dominated by any existing solution
    for existing_obj in result.pareto_objectives
        existing_min = to_min_space(existing_obj)
        if dominates(existing_min, new_min)
            return result  # New solution is dominated, don't add
        end
    end

    # Remove existing solutions dominated by new solution
    keep_indices = Int[]
    for (i, existing_obj) in enumerate(result.pareto_objectives)
        existing_min = to_min_space(existing_obj)
        if !dominates(new_min, existing_min)
            push!(keep_indices, i)
        end
    end

    # Filter to non-dominated solutions
    new_pareto_params = result.pareto_params[keep_indices]
    new_pareto_objectives = result.pareto_objectives[keep_indices]

    # Add new solution
    push!(new_pareto_params, collect(T, params(policy)))
    push!(new_pareto_objectives, objectives)

    # Update result's Pareto front (modify in place via the vectors)
    empty!(result.pareto_params)
    empty!(result.pareto_objectives)
    append!(result.pareto_params, new_pareto_params)
    append!(result.pareto_objectives, new_pareto_objectives)

    return result
end

# ============================================================================
# Optimization Entry Point
# ============================================================================

"""
    optimize(prob::OptimizationProblem, backend::AbstractOptimizationBackend)

Run optimization on the problem using the specified backend.
Returns an OptimizationResult.

Requires loading the appropriate extension (e.g., `using Metaheuristics`).
"""
function optimize(prob::OptimizationProblem, backend::AbstractOptimizationBackend)
    # Full validation before expensive computation
    _validate_problem(prob)

    # Dispatch to backend-specific implementation
    return optimize_backend(prob, backend)
end

"""
    optimize_backend(prob, backend)

Backend-specific optimization implementation.
Extensions add methods to this function.

Requires loading the appropriate extension package (e.g., `using Metaheuristics`).
"""
function optimize_backend end

# Generic fallback with helpful error message
function optimize_backend(::OptimizationProblem, backend::AbstractOptimizationBackend)
    backend_type = typeof(backend)
    return error(
        "No optimize_backend method defined for $(backend_type). " *
        "If using MetaheuristicsBackend, run `using Metaheuristics` before calling optimize().",
    )
end
