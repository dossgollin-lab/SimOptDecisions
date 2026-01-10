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

params(p::AbstractPolicy) = interface_not_implemented(:params, typeof(p))

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
# Optimization Result
# ============================================================================

"""
Result of an optimization run.

# Fields
- `best_params::Vector{T}`: Best parameter vector found
- `best_objectives::Vector{T}`: Objective values at best solution
- `best_policy::P`: The best policy constructed from best_params
- `convergence_info::Dict{Symbol,Any}`: Backend-specific convergence information
- `pareto_params::Vector{Vector{T}}`: Pareto front parameter vectors (multi-objective)
- `pareto_objectives::Vector{Vector{T}}`: Pareto front objective values (multi-objective)
"""
struct OptimizationResult{P<:AbstractPolicy,T<:AbstractFloat}
    best_params::Vector{T}
    best_objectives::Vector{T}
    best_policy::P
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

"""
    merge_into_pareto!(result::OptimizationResult, prob::OptimizationProblem, policy::AbstractPolicy; seed=42)

Evaluate a policy and merge it into the optimization result's Pareto front.
The policy is evaluated using the problem's config, SOWs, and metric calculator.
Dominance is checked: the policy is added only if not dominated, and any
existing solutions dominated by it are removed.

Updates `best_policy` and `best_objectives` if the new policy becomes the best
(using normalized equal weighting).

# Example
```julia
result = optimize(prob, backend)
merge_into_pareto!(result, prob, ElevationPolicy(0.0))  # add "no elevation" baseline
```
"""
function merge_into_pareto!(
    result::OptimizationResult{P,T},
    prob::OptimizationProblem,
    policy::AbstractPolicy;
    seed::Int=42,
) where {P,T}
    # Evaluate the policy
    metrics = evaluate_policy(prob, policy; seed=seed)

    # Extract objectives (applying direction: negate for Maximize since we store un-negated)
    objectives = Vector{T}(undef, length(prob.objectives))
    for (i, obj) in enumerate(prob.objectives)
        val = T(metrics[obj.name])
        objectives[i] = val  # Store un-negated (original scale)
    end

    # For dominance checking, we need to compare in minimization space
    # (negate maximized objectives for comparison)
    function to_min_space(objs)
        return [prob.objectives[i].direction == Maximize ? -objs[i] : objs[i]
                for i in eachindex(objs)]
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

    # Recompute best using normalized weighting
    if !isempty(result.pareto_objectives)
        best_idx = _select_best_pareto_idx(result.pareto_objectives, prob.objectives)

        # Update best fields (these are mutable vectors, so we can modify in place)
        empty!(result.best_params)
        append!(result.best_params, result.pareto_params[best_idx])
        empty!(result.best_objectives)
        append!(result.best_objectives, result.pareto_objectives[best_idx])

        # Note: best_policy is immutable, can't update it in-place
        # Users should reconstruct: policy_type(result.best_params)
    end

    return result
end

"""
Select best solution from Pareto front using normalized equal weighting.
Works with un-negated objectives, respecting direction.
"""
function _select_best_pareto_idx(pareto_objectives::Vector{Vector{T}}, objectives) where {T}
    if length(pareto_objectives) <= 1
        return 1
    end

    n_obj = length(pareto_objectives[1])
    n_sol = length(pareto_objectives)

    # Convert to minimization space for comparison
    min_space = [[objectives[j].direction == Maximize ? -pareto_objectives[i][j] : pareto_objectives[i][j]
                  for j in 1:n_obj] for i in 1:n_sol]

    # Find min/max for each objective
    mins = [minimum(min_space[i][j] for i in 1:n_sol) for j in 1:n_obj]
    maxs = [maximum(min_space[i][j] for i in 1:n_sol) for j in 1:n_obj]

    # Compute normalized sum (lower is better)
    best_idx = 1
    best_score = Inf
    for i in 1:n_sol
        score = 0.0
        for j in 1:n_obj
            range = maxs[j] - mins[j]
            if range > 0
                score += (min_space[i][j] - mins[j]) / range
            else
                score += 0.5
            end
        end
        if score < best_score
            best_score = score
            best_idx = i
        end
    end

    return best_idx
end

# ============================================================================
# Optimization Problem
# ============================================================================

"""Defines a simulation-optimization problem. See examples for usage."""
struct OptimizationProblem{C<:AbstractConfig,S<:AbstractSOW,P<:AbstractPolicy,F}
    config::C
    sows::Vector{S}
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
    sows::AbstractVector{<:AbstractSOW},
    policy_type::Type{P},
    metric_calculator::F,
    objectives::AbstractVector{<:Objective};
    batch_size::AbstractBatchSize=FullBatch(),
    constraints::AbstractVector{<:AbstractConstraint}=AbstractConstraint[],
    bounds::Union{Nothing,AbstractVector{<:Tuple}}=nothing,
) where {P<:AbstractPolicy,F}
    # Validate inputs
    _validate_sows(sows)
    _validate_policy_interface(policy_type)
    _validate_objectives(objectives)

    # Convert to concrete vector types
    sows_vec = collect(sows)
    obj_vec = collect(objectives)
    const_vec = collect(constraints)
    bounds_vec = bounds === nothing ? nothing : [(Float64(lo), Float64(hi)) for (lo, hi) in bounds]

    return OptimizationProblem(
        config, sows_vec, policy_type, metric_calculator, obj_vec, batch_size, const_vec, bounds_vec
    )
end

# ============================================================================
# Batch Selection
# ============================================================================

"""
Select SOWs for a batch evaluation.
"""
function _select_batch(sows::Vector{S}, batch_size::FullBatch, rng::AbstractRNG) where {S}
    return sows
end

function _select_batch(sows::Vector{S}, batch_size::FixedBatch, rng::AbstractRNG) where {S}
    indices = randperm(rng, length(sows))[1:(batch_size.n)]
    return sows[indices]
end

function _select_batch(
    sows::Vector{S}, batch_size::FractionBatch, rng::AbstractRNG
) where {S}
    n = max(1, round(Int, length(sows) * batch_size.fraction))
    indices = randperm(rng, length(sows))[1:n]
    return sows[indices]
end

# ============================================================================
# Policy Evaluation
# ============================================================================

"""
    evaluate_policy(prob::OptimizationProblem, policy, rng::AbstractRNG)

Evaluate a policy across all (or a batch of) SOWs and return aggregated metrics.
"""
function evaluate_policy(
    prob::OptimizationProblem, policy::AbstractPolicy, rng::AbstractRNG
)
    # Select SOWs for this evaluation
    batch_sows = _select_batch(prob.sows, prob.batch_size, rng)

    # Run simulations
    outcomes = map(batch_sows) do sow
        simulate(prob.config, sow, policy, rng)
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
