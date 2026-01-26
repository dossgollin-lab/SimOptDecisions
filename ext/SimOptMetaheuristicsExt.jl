module SimOptMetaheuristicsExt

using SimOptDecisions
using Metaheuristics
using Random

# Import internal functions we need to extend/use
import SimOptDecisions:
    optimize_backend,
    _extract_objectives,
    OptimizationResult,
    MetaheuristicsBackend,
    AbstractPolicy,
    AbstractConfig,
    AbstractScenario,
    AbstractBatchSize,
    FullBatch,
    AbstractConstraint,
    FeasibilityConstraint,
    PenaltyConstraint,
    Objective,
    Maximize,
    evaluate_policy,
    param_bounds

# ============================================================================
# Algorithm Selection
# ============================================================================

"""Select Metaheuristics algorithm based on symbol and number of objectives."""
function _get_algorithm(
    sym::Symbol,
    n_objectives::Int,
    pop_size::Int,
    max_iters::Int,
    parallel::Bool,
    user_options::Dict{Symbol,Any},
)
    options = Metaheuristics.Options(; iterations=max_iters, parallel_evaluation=parallel)

    if n_objectives == 1
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

"""Denormalize parameters from [0,1] space to actual bounds."""
function _denormalize(
    x_normalized::AbstractVector, bounds_vec::Vector{Tuple{Float64,Float64}}
)
    return [lo + x * (hi - lo) for (x, (lo, hi)) in zip(x_normalized, bounds_vec)]
end

"""Denormalize a matrix of parameters (each row is a solution)."""
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

"""Apply constraints to objective values."""
function _apply_constraints(
    objectives::Vector{Float64}, policy::AbstractPolicy, constraints
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

"""Convert Metaheuristics result to OptimizationResult."""
function _wrap_result(
    mh_result, objectives::Vector{Objective}, bounds_vec::Vector{Tuple{Float64,Float64}}
)
    n_objectives = length(objectives)

    if n_objectives == 1
        best_x_norm = Vector{Float64}(Metaheuristics.minimizer(mh_result))
        best_x = _denormalize(best_x_norm, bounds_vec)
        best_f_raw = [Metaheuristics.minimum(mh_result)]
        best_f = _unnegate_objectives(best_f_raw, objectives)

        return OptimizationResult{Float64}(
            Dict{Symbol,Any}(
                :iterations => mh_result.iteration,
                :f_calls => mh_result.f_calls,
                :converged => Metaheuristics.termination_status_message(mh_result),
            ),
            [best_x],
            [best_f],
        )
    else
        nds = Metaheuristics.get_non_dominated_solutions(mh_result.population)

        pareto_params = Vector{Vector{Float64}}()
        pareto_objectives = Vector{Vector{Float64}}()

        for sol in nds
            x_norm = Vector{Float64}(Metaheuristics.get_position(sol))
            push!(pareto_params, _denormalize(x_norm, bounds_vec))
            raw_obj = Vector{Float64}(Metaheuristics.fval(sol))
            push!(pareto_objectives, _unnegate_objectives(raw_obj, objectives))
        end

        return OptimizationResult{Float64}(
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

"""Un-negate objectives that were maximized."""
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
# Main Optimization Backend (flat args)
# ============================================================================

function SimOptDecisions.optimize_backend(
    backend::MetaheuristicsBackend,
    config::AbstractConfig,
    scenarios::Vector{<:AbstractScenario},
    policy_type::Type{P},
    metric_calculator,
    objectives::Vector{Objective};
    batch_size=FullBatch(),
    constraints=AbstractConstraint[],
    bounds=nothing,
) where {P<:AbstractPolicy}
    # Metaheuristics only supports continuous parameters
    for (fname, ftype) in zip(fieldnames(P), fieldtypes(P))
        if ftype <: SimOptDecisions.DiscreteParameter
            throw(
                ArgumentError(
                    "Field :$fname is DiscreteParameter. " *
                    "Metaheuristics backend only supports continuous parameters.",
                ),
            )
        elseif ftype <: SimOptDecisions.CategoricalParameter
            throw(
                ArgumentError(
                    "Field :$fname is CategoricalParameter. " *
                    "Metaheuristics backend only supports continuous parameters.",
                ),
            )
        end
    end

    n_objectives = length(objectives)

    # Get bounds (custom or from policy type)
    bounds_vec = if bounds !== nothing
        bounds
    else
        [(Float64(lo), Float64(hi)) for (lo, hi) in param_bounds(policy_type)]
    end
    n_params = length(bounds_vec)

    # Optimizer works in normalized [0,1] space
    normalized_bounds = zeros(2, n_params)
    normalized_bounds[2, :] .= 1.0

    # Get seed from backend options
    sim_seed = get(backend.options, :seed, 42)::Int

    # Evaluate a single solution vector (in normalized space)
    function _evaluate_one(x_normalized)
        x_real = _denormalize(x_normalized, bounds_vec)
        policy = P(x_real)
        rng = Random.Xoshiro(sim_seed)
        metrics = evaluate_policy(
            config, scenarios, policy, metric_calculator, rng; batch_size
        )
        obj_values = _extract_objectives(metrics, objectives)
        return _apply_constraints(obj_values, policy, constraints)
    end

    # Fitness function for Metaheuristics
    function fitness(X)
        if X isa AbstractVector
            obj_values = _evaluate_one(X)
            if n_objectives == 1
                return obj_values[1]
            else
                return (obj_values, Float64[], Float64[])
            end
        else
            n_solutions = size(X, 1)

            if n_objectives == 1
                fx = zeros(n_solutions)
                Threads.@threads for i in 1:n_solutions
                    fx[i] = _evaluate_one(view(X, i, :))[1]
                end
                return fx
            else
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

    algorithm = _get_algorithm(
        backend.algorithm,
        n_objectives,
        backend.population_size,
        backend.max_iterations,
        backend.parallel,
        backend.options,
    )

    mh_result = Metaheuristics.optimize(fitness, normalized_bounds, algorithm)

    return _wrap_result(mh_result, objectives, bounds_vec)
end

end # module SimOptMetaheuristicsExt
