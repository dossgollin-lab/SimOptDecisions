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

# ============================================================================
# Optimization Problem
# ============================================================================

"""Defines a simulation-optimization problem. See examples for usage."""
struct OptimizationProblem{P<:AbstractConfig,S<:AbstractSOW,T<:AbstractPolicy}
    config::P
    sows::Vector{S}
    policy_type::Type{T}
    metric_calculator::Function
    objectives::Vector{Objective}
    batch_size::AbstractBatchSize
    constraints::Vector{AbstractConstraint}
end

# Primary constructor with validation
function OptimizationProblem(
    config::AbstractConfig,
    sows::AbstractVector{<:AbstractSOW},
    policy_type::Type{T},
    metric_calculator::Function,
    objectives::AbstractVector{<:Objective};
    batch_size::AbstractBatchSize=FullBatch(),
    constraints::AbstractVector{<:AbstractConstraint}=AbstractConstraint[],
) where {T<:AbstractPolicy}
    # Validate inputs
    _validate_sows(sows)
    _validate_policy_interface(policy_type)
    _validate_objectives(objectives)

    # Convert to concrete vector types
    sows_vec = collect(sows)
    obj_vec = collect(objectives)
    const_vec = collect(constraints)

    return OptimizationProblem(
        config, sows_vec, policy_type, metric_calculator, obj_vec, batch_size, const_vec
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
