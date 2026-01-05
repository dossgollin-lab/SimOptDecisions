module SimOptMetaheuristicsExt

using SimOptDecisions
using Metaheuristics
using Random

# Import internal functions we need to extend/use
import SimOptDecisions:
    optimize_backend,
    _extract_objectives,
    OptimizationProblem,
    OptimizationResult,
    MetaheuristicsBackend,
    AbstractPolicy,
    AbstractConstraint,
    FeasibilityConstraint,
    PenaltyConstraint,
    Maximize,
    evaluate_policy,
    param_bounds

# ============================================================================
# Algorithm Selection
# ============================================================================

"""
Select the appropriate Metaheuristics algorithm based on the symbol and number of objectives.
Metaheuristics.jl v3 uses the algorithm's internal iteration handling.
"""
function _get_algorithm(
    sym::Symbol, n_objectives::Int, pop_size::Int, max_iters::Int, user_options::Dict{Symbol,Any}
)
    if n_objectives == 1
        # Single-objective algorithms
        if sym == :ECA
            alg = Metaheuristics.ECA(; N=pop_size, user_options...)
        elseif sym == :DE
            alg = Metaheuristics.DE(; N=pop_size, user_options...)
        elseif sym == :PSO
            alg = Metaheuristics.PSO(; N=pop_size, user_options...)
        elseif sym == :ABC
            alg = Metaheuristics.ABC(; N=pop_size, user_options...)
        elseif sym == :SA
            alg = Metaheuristics.SA(; user_options...)
        else
            error(
                "Unknown single-objective algorithm: $sym. " *
                "Supported: :ECA, :DE, :PSO, :ABC, :SA",
            )
        end
    else
        # Multi-objective algorithms
        if sym == :NSGA2
            alg = Metaheuristics.NSGA2(; N=pop_size, user_options...)
        elseif sym == :NSGA3
            alg = Metaheuristics.NSGA3(; N=pop_size, user_options...)
        elseif sym == :SPEA2
            alg = Metaheuristics.SPEA2(; N=pop_size, user_options...)
        elseif sym == :MOEAD
            alg = Metaheuristics.MOEA_DE(; N=pop_size, user_options...)
        else
            error(
                "Unknown multi-objective algorithm: $sym. " *
                "Supported: :NSGA2, :NSGA3, :SPEA2, :MOEAD",
            )
        end
    end

    # Set iteration limit via the algorithm's options
    alg.options.iterations = max_iters

    return alg
end

# ============================================================================
# Constraint Application
# ============================================================================

"""
Apply constraints to objective values. Returns modified objectives.
For feasibility constraints, returns Inf if infeasible.
For penalty constraints, adds weighted penalty to objectives.
"""
function _apply_constraints(
    objectives::Vector{Float64},
    policy::AbstractPolicy,
    constraints::Vector{<:AbstractConstraint},
)
    for c in constraints
        if c isa FeasibilityConstraint
            if !c.func(policy)
                return fill(Inf, length(objectives))
            end
        elseif c isa PenaltyConstraint
            penalty = c.func(policy)
            if penalty > 0
                objectives = objectives .+ (c.weight * penalty)
            end
        end
    end
    return objectives
end

# ============================================================================
# Result Wrapping
# ============================================================================

"""
Convert Metaheuristics result to SimOptDecisions OptimizationResult.
Handles both single and multi-objective cases.
"""
function _wrap_result(
    mh_result,
    ::Type{P},
    prob::OptimizationProblem,
) where {P<:AbstractPolicy}
    n_objectives = length(prob.objectives)

    if n_objectives == 1
        # Single-objective: extract best solution
        best_x = Metaheuristics.minimizer(mh_result)
        best_f_raw = [Metaheuristics.minimum(mh_result)]

        # Un-negate maximized objectives
        best_f = _unnegate_objectives(best_f_raw, prob.objectives)

        return OptimizationResult{P}(
            best_x,
            best_f,
            P(best_x),
            Dict{Symbol,Any}(
                :iterations => mh_result.iteration,
                :f_calls => mh_result.f_calls,
                :converged => Metaheuristics.termination_status_message(mh_result),
            ),
            Vector{Vector{Float64}}(),  # No Pareto front for single-objective
            Vector{Vector{Float64}}(),
        )
    else
        # Multi-objective: extract Pareto front using non-dominated solutions
        nds = Metaheuristics.get_non_dominated_solutions(mh_result.population)

        # Extract parameters and objectives from Pareto front
        pareto_params = Vector{Vector{Float64}}()
        pareto_objectives = Vector{Vector{Float64}}()

        for sol in nds
            push!(pareto_params, Vector{Float64}(Metaheuristics.get_position(sol)))
            raw_obj = Vector{Float64}(Metaheuristics.fval(sol))
            push!(pareto_objectives, _unnegate_objectives(raw_obj, prob.objectives))
        end

        # Select best as first Pareto solution (or could use hypervolume)
        best_x = isempty(pareto_params) ? zeros(length(param_bounds(P))) : pareto_params[1]
        best_f = isempty(pareto_objectives) ? zeros(n_objectives) : pareto_objectives[1]

        return OptimizationResult{P}(
            best_x,
            best_f,
            P(best_x),
            Dict{Symbol,Any}(
                :iterations => mh_result.iteration,
                :f_calls => mh_result.f_calls,
                :converged => Metaheuristics.termination_status_message(mh_result),
                :n_pareto => length(pareto_params),
            ),
            pareto_params,
            pareto_objectives,
        )
    end
end

"""
Un-negate objectives that were maximized (since Metaheuristics minimizes).
"""
function _unnegate_objectives(raw_objectives::Vector{Float64}, objectives)
    result = copy(raw_objectives)
    for (i, obj) in enumerate(objectives)
        if obj.direction == Maximize
            result[i] = -result[i]
        end
    end
    return result
end

# ============================================================================
# Main Optimization Backend
# ============================================================================

function SimOptDecisions.optimize_backend(
    prob::OptimizationProblem, backend::MetaheuristicsBackend
)
    P = prob.policy_type
    n_objectives = length(prob.objectives)

    # Build bounds matrix for Metaheuristics: 2 x n_params matrix
    # Row 1 = lower bounds, Row 2 = upper bounds
    bounds_vec = param_bounds(P)
    n_params = length(bounds_vec)
    bounds = zeros(2, n_params)
    for (i, b) in enumerate(bounds_vec)
        bounds[1, i] = b[1]  # lower bound
        bounds[2, i] = b[2]  # upper bound
    end

    # Build fitness function
    function fitness(x::AbstractVector{T}) where {T<:AbstractFloat}
        # Create policy from parameters
        policy = P(x)

        # Use deterministic RNG based on parameter hash for reproducibility
        rng = Random.Xoshiro(hash(x))

        # Evaluate policy across SOWs
        metrics = evaluate_policy(prob, policy, rng)

        # Extract objectives (negates maximization objectives)
        objectives = _extract_objectives(metrics, prob.objectives)

        # Apply constraints
        objectives = _apply_constraints(objectives, policy, prob.constraints)

        # Return single value for single-objective, (f, g, h) Tuple for multi-objective
        # Metaheuristics.jl requires Tuple{Vector, Vector, Vector} for multi-objective:
        # (objectives, inequality_constraints, equality_constraints)
        if n_objectives == 1
            return objectives[1]
        else
            # Return (f, g, h) tuple with empty constraint vectors
            return (objectives, Float64[], Float64[])
        end
    end

    # Select algorithm with iteration limit
    algorithm = _get_algorithm(
        backend.algorithm, n_objectives, backend.population_size, backend.max_iterations, backend.options
    )

    # Run optimization
    mh_result = Metaheuristics.optimize(fitness, bounds, algorithm)

    # Wrap result
    return _wrap_result(mh_result, P, prob)
end

end # module SimOptMetaheuristicsExt
