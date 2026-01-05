# ============================================================================
# Policy Interface Functions
# ============================================================================

"""
    params(policy::AbstractPolicy) -> AbstractVector{<:AbstractFloat}

Extract parameters from a policy as a vector.
Override for your policy type.
"""
function params end

params(p::AbstractPolicy) =
    error("Implement `SimOptDecisions.params(::$(typeof(p)))` to return parameter vector")

"""
    param_bounds(::Type{P}) -> Vector{Tuple{T,T}}

Return the bounds for each parameter as a Vector of (lower, upper) tuples.
Override for your policy type.
"""
function param_bounds end

param_bounds(::Type{T}) where {T<:AbstractPolicy} =
    error("Implement `SimOptDecisions.param_bounds(::Type{$T})` to return bounds")

# ============================================================================
# Optimization Result
# ============================================================================

"""
Result of an optimization run.

# Fields
- `best_params::Vector{Float64}`: Best parameter vector found
- `best_objectives::Vector{Float64}`: Objective values at best solution
- `best_policy::P`: The best policy constructed from best_params
- `convergence_info::Dict{Symbol,Any}`: Backend-specific convergence information
- `pareto_params::Vector{Vector{Float64}}`: Pareto front parameter vectors (multi-objective)
- `pareto_objectives::Vector{Vector{Float64}}`: Pareto front objective values (multi-objective)
"""
struct OptimizationResult{P<:AbstractPolicy}
    best_params::Vector{Float64}
    best_objectives::Vector{Float64}
    best_policy::P
    convergence_info::Dict{Symbol,Any}
    pareto_params::Vector{Vector{Float64}}
    pareto_objectives::Vector{Vector{Float64}}
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

"""
Defines a simulation-optimization problem.

# Fields
- `model`: The system model to simulate
- `sows`: Vector of States of the World to evaluate policies against
- `policy_type`: The Type of policy to optimize (not an instance)
- `metric_calculator`: Function mapping Vector{Outcome} -> NamedTuple of metrics
- `objectives`: Vector of Objective specifying what to optimize
- `batch_size`: How many SOWs to use per evaluation (default: FullBatch)
- `constraints`: Optional vector of constraints
"""
struct OptimizationProblem{
    M<:AbstractSystemModel,
    S<:AbstractSOW,
    P<:AbstractPolicy,
    F<:Function,
    B<:AbstractBatchSize,
}
    model::M
    sows::Vector{S}
    policy_type::Type{P}
    metric_calculator::F
    objectives::Vector{Objective}
    batch_size::B
    constraints::Vector{AbstractConstraint}
end

# Primary constructor with validation
function OptimizationProblem(
    model::AbstractSystemModel,
    sows::AbstractVector{<:AbstractSOW},
    policy_type::Type{P},
    metric_calculator::Function,
    objectives::AbstractVector{<:Objective};
    batch_size::AbstractBatchSize=FullBatch(),
    constraints::AbstractVector{<:AbstractConstraint}=AbstractConstraint[],
) where {P<:AbstractPolicy}
    # Validate inputs
    _validate_sows(sows)
    _validate_policy_interface(policy_type)
    _validate_objectives(objectives)

    # Convert to concrete vector types
    sows_vec = collect(sows)
    obj_vec = collect(objectives)
    const_vec = collect(constraints)

    return OptimizationProblem(
        model, sows_vec, policy_type, metric_calculator, obj_vec, batch_size, const_vec
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

    # Run simulations (no recorder for performance)
    outcomes = map(batch_sows) do sow
        simulate(prob.model, sow, policy, NoRecorder(), rng)
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
    values = Float64[]
    for obj in objectives
        if !haskey(metrics, obj.name)
            throw(
                ArgumentError(
                    "Metric calculator did not return :$(obj.name). " *
                    "Available metrics: $(keys(metrics))",
                ),
            )
        end
        val = metrics[obj.name]
        # Metaheuristics minimizes, so negate for maximize
        push!(values, obj.direction == Maximize ? -val : val)
    end
    return values
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
