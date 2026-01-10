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
    sym::Symbol,
    n_objectives::Int,
    pop_size::Int,
    max_iters::Int,
    parallel::Bool,
    user_options::Dict{Symbol,Any},
)
    # Create options with parallel evaluation setting
    options = Metaheuristics.Options(; iterations=max_iters, parallel_evaluation=parallel)

    if n_objectives == 1
        # Single-objective algorithms
        if sym == :ECA
            alg = Metaheuristics.ECA(; N=pop_size, options=options, user_options...)
        elseif sym == :DE
            alg = Metaheuristics.DE(; N=pop_size, options=options, user_options...)
        elseif sym == :PSO
            alg = Metaheuristics.PSO(; N=pop_size, options=options, user_options...)
        elseif sym == :ABC
            alg = Metaheuristics.ABC(; N=pop_size, options=options, user_options...)
        elseif sym == :SA
            alg = Metaheuristics.SA(; options=options, user_options...)
        else
            error(
                "Unknown single-objective algorithm: $sym. " *
                "Supported: :ECA, :DE, :PSO, :ABC, :SA",
            )
        end
    else
        # Multi-objective algorithms
        if sym == :NSGA2
            alg = Metaheuristics.NSGA2(; N=pop_size, options=options, user_options...)
        elseif sym == :NSGA3
            alg = Metaheuristics.NSGA3(; N=pop_size, options=options, user_options...)
        elseif sym == :SPEA2
            alg = Metaheuristics.SPEA2(; N=pop_size, options=options, user_options...)
        elseif sym == :MOEAD
            alg = Metaheuristics.MOEA_DE(; N=pop_size, options=options, user_options...)
        else
            error(
                "Unknown multi-objective algorithm: $sym. " *
                "Supported: :NSGA2, :NSGA3, :SPEA2, :MOEAD",
            )
        end
    end

    return alg
end

# ============================================================================
# Parameter Normalization
# ============================================================================

"""
Denormalize parameters from [0,1] space to actual bounds.
"""
function _denormalize(
    x_normalized::AbstractVector, bounds_vec::Vector{Tuple{Float64,Float64}}
)
    return [lo + x * (hi - lo) for (x, (lo, hi)) in zip(x_normalized, bounds_vec)]
end

"""
Denormalize a matrix of parameters (each row is a solution).
"""
function _denormalize(
    X_normalized::AbstractMatrix, bounds_vec::Vector{Tuple{Float64,Float64}}
)
    X_denorm = similar(X_normalized)
    for j in eachindex(bounds_vec)
        lo, hi = bounds_vec[j]
        @views X_denorm[:, j] .= lo .+ X_normalized[:, j] .* (hi - lo)
    end
    return X_denorm
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
# Pareto Best Selection
# ============================================================================

"""
Select best solution from Pareto front using normalized equal weighting.
Normalizes each objective to [0,1] range and picks the solution with lowest sum
(equivalent to picking the point closest to origin in normalized space).
"""
function _select_best_pareto(pareto_objectives::Vector{Vector{Float64}})
    if isempty(pareto_objectives)
        return 1
    end
    if length(pareto_objectives) == 1
        return 1
    end

    n_obj = length(pareto_objectives[1])
    n_sol = length(pareto_objectives)

    # Find min/max for each objective
    mins = [minimum(pareto_objectives[i][j] for i in 1:n_sol) for j in 1:n_obj]
    maxs = [maximum(pareto_objectives[i][j] for i in 1:n_sol) for j in 1:n_obj]

    # Compute normalized sum for each solution (lower is better)
    best_idx = 1
    best_score = Inf
    for i in 1:n_sol
        score = 0.0
        for j in 1:n_obj
            range = maxs[j] - mins[j]
            if range > 0
                score += (pareto_objectives[i][j] - mins[j]) / range
            else
                score += 0.5  # All same value
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
# Result Wrapping
# ============================================================================

"""
Convert Metaheuristics result to SimOptDecisions OptimizationResult.
Handles both single and multi-objective cases.
Denormalizes parameters from [0,1] space back to actual bounds.
"""
function _wrap_result(
    mh_result,
    ::Type{P},
    prob::OptimizationProblem,
    bounds_vec::Vector{Tuple{Float64,Float64}},
) where {P<:AbstractPolicy}
    n_objectives = length(prob.objectives)

    if n_objectives == 1
        # Single-objective: extract best solution (in normalized space)
        best_x_norm = Vector{Float64}(Metaheuristics.minimizer(mh_result))
        best_x = _denormalize(best_x_norm, bounds_vec)
        best_f_raw = [Metaheuristics.minimum(mh_result)]

        # Un-negate maximized objectives
        best_f = _unnegate_objectives(best_f_raw, prob.objectives)

        return OptimizationResult{P,Float64}(
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
            x_norm = Vector{Float64}(Metaheuristics.get_position(sol))
            push!(pareto_params, _denormalize(x_norm, bounds_vec))
            raw_obj = Vector{Float64}(Metaheuristics.fval(sol))
            push!(pareto_objectives, _unnegate_objectives(raw_obj, prob.objectives))
        end

        # Select best using normalized objective weighting (equal importance in [0,1] space)
        best_idx = _select_best_pareto(pareto_objectives)
        best_x = isempty(pareto_params) ? zeros(length(bounds_vec)) : pareto_params[best_idx]
        best_f = isempty(pareto_objectives) ? zeros(n_objectives) : pareto_objectives[best_idx]

        return OptimizationResult{P,Float64}(
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

    # Get actual bounds for denormalization
    bounds_vec = [(Float64(lo), Float64(hi)) for (lo, hi) in param_bounds(P)]
    n_params = length(bounds_vec)

    # Optimizer works in normalized [0,1] space
    normalized_bounds = zeros(2, n_params)
    normalized_bounds[2, :] .= 1.0  # All upper bounds are 1.0

    # Get seed from backend options, defaulting to 42
    sim_seed = get(backend.options, :seed, 42)::Int

    # Evaluate a single solution vector (in normalized space) and return objectives
    # Uses fixed seed for consistent policy comparison across optimization
    function _evaluate_one(x_normalized)
        x_real = _denormalize(x_normalized, bounds_vec)
        policy = P(x_real)
        rng = Random.Xoshiro(sim_seed)
        metrics = evaluate_policy(prob, policy, rng)
        objectives = _extract_objectives(metrics, prob.objectives)
        return _apply_constraints(objectives, policy, prob.constraints)
    end

    # Fitness function that handles both single (Vector) and batch (Matrix) evaluation
    # When parallel_evaluation=true, Metaheuristics passes a Matrix where each row is a solution
    # When parallel_evaluation=false, it passes a Vector
    function fitness(X)
        if X isa AbstractVector
            # Single solution evaluation
            objectives = _evaluate_one(X)
            if n_objectives == 1
                return objectives[1]
            else
                return (objectives, Float64[], Float64[])
            end
        else
            # Batch evaluation: X is N × D matrix, each row is a solution
            n_solutions = size(X, 1)

            if n_objectives == 1
                # Single objective: return vector of fitness values
                fx = zeros(n_solutions)
                Threads.@threads for i in 1:n_solutions
                    fx[i] = _evaluate_one(view(X, i, :))[1]
                end
                return fx
            else
                # Multi-objective: return (F, G, H)
                fx = zeros(n_solutions, n_objectives)
                gx = zeros(n_solutions, 0)
                hx = zeros(n_solutions, 0)
                Threads.@threads for i in 1:n_solutions
                    fx[i, :] = _evaluate_one(view(X, i, :))
                end
                return (fx, gx, hx)
            end
        end
    end

    # Select algorithm with iteration limit and parallel evaluation setting
    algorithm = _get_algorithm(
        backend.algorithm,
        n_objectives,
        backend.population_size,
        backend.max_iterations,
        backend.parallel,
        backend.options,
    )

    # Run optimization in normalized space
    mh_result = Metaheuristics.optimize(fitness, normalized_bounds, algorithm)

    # Wrap result (denormalizing parameters back to real space)
    return _wrap_result(mh_result, P, prob, bounds_vec)
end

end # module SimOptMetaheuristicsExt
