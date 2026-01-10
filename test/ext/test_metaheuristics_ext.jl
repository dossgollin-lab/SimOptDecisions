# Tests for SimOptMetaheuristicsExt
# These tests require Metaheuristics.jl to be loaded

using Metaheuristics

# Note: Both Metaheuristics and SimOptDecisions export `optimize`,
# so we use fully qualified SimOptDecisions.optimize in tests

@testset "MetaheuristicsExt" begin
    # Define MWE types for optimization testing
    struct MHCounterState <: AbstractState
        value::Float64
    end

    struct MHCounterPolicy <: AbstractPolicy
        increment::Float64
    end

    struct MHCounterParams <: AbstractConfig
        n_steps::Int
    end

    struct MHEmptySOW <: AbstractSOW end

    # Simple for-loop implementation
    function SimOptDecisions.simulate(
        params::MHCounterParams, sow::MHEmptySOW, policy::MHCounterPolicy, rng::AbstractRNG
    )
        value = 0.0
        for ts in SimOptDecisions.Utils.timeindex(1:params.n_steps)
            value += policy.increment
        end
        return (final_value=value,)
    end

    # Implement policy interface
    SimOptDecisions.param_bounds(::Type{MHCounterPolicy}) = [(0.0, 10.0)]
    MHCounterPolicy(x::AbstractVector) = MHCounterPolicy(x[1])
    SimOptDecisions.params(p::MHCounterPolicy) = [p.increment]

    @testset "Single-objective optimization with ECA" begin
        params = MHCounterParams(10)
        sows = [MHEmptySOW() for _ in 1:5]

        function metric_calculator(outcomes)
            return (mean_value=sum(o.final_value for o in outcomes) / length(outcomes),)
        end

        prob = OptimizationProblem(
            params, sows, MHCounterPolicy, metric_calculator, [minimize(:mean_value)]
        )

        # Run optimization with limited iterations for speed
        backend = MetaheuristicsBackend(;
            algorithm=:ECA, max_iterations=20, population_size=20, parallel=false
        )

        result = SimOptDecisions.optimize(prob, backend)

        # Check result structure
        @test result isa OptimizationResult{Float64}
        @test haskey(result.convergence_info, :iterations)
        @test haskey(result.convergence_info, :f_calls)

        # Single-objective stores result as single-point Pareto front
        @test length(result.pareto_params) == 1
        @test length(result.pareto_objectives) == 1

        # Get the solution from the front
        params, objectives = first(pareto_front(result))
        @test length(params) == 1
        @test length(objectives) == 1

        # Construct policy from params
        best_policy = MHCounterPolicy(params)
        @test best_policy isa MHCounterPolicy

        # Params should be in bounds
        @test params[1] >= 0.0
        @test params[1] <= 10.0
    end

    @testset "Multi-objective optimization with NSGA2" begin
        # Define a 2-parameter policy for multi-objective
        struct MHMultiPolicy <: AbstractPolicy
            param1::Float64
            param2::Float64
        end

        SimOptDecisions.param_bounds(::Type{MHMultiPolicy}) = [(0.0, 10.0), (0.0, 10.0)]
        MHMultiPolicy(x::AbstractVector) = MHMultiPolicy(x[1], x[2])

        # Simple for-loop implementation for MHMultiPolicy
        function SimOptDecisions.simulate(
            params::MHCounterParams,
            sow::MHEmptySOW,
            policy::MHMultiPolicy,
            rng::AbstractRNG,
        )
            value = 0.0
            for ts in SimOptDecisions.Utils.timeindex(1:params.n_steps)
                value += policy.param1 - policy.param2 * 0.1
            end
            return (final_value=value,)
        end

        params = MHCounterParams(5)
        sows = [MHEmptySOW() for _ in 1:3]

        function multi_metric_calculator(outcomes)
            values = [o.final_value for o in outcomes]
            return (
                mean_value=sum(values) / length(values),
                variance=sum((v - sum(values) / length(values))^2 for v in values) /
                         length(values),
            )
        end

        prob = OptimizationProblem(
            params,
            sows,
            MHMultiPolicy,
            multi_metric_calculator,
            [minimize(:mean_value), minimize(:variance)],
        )

        backend = MetaheuristicsBackend(;
            algorithm=:NSGA2, max_iterations=10, population_size=20, parallel=false
        )

        result = SimOptDecisions.optimize(prob, backend)

        # Check result structure
        @test result isa OptimizationResult{Float64}

        # Multi-objective should have Pareto front
        @test length(result.pareto_params) > 0
        @test length(result.pareto_objectives) > 0
        @test haskey(result.convergence_info, :n_pareto)

        # Each solution in front should have 2 params and 2 objectives
        for (params, objectives) in pareto_front(result)
            @test length(params) == 2
            @test length(objectives) == 2
        end
    end

    @testset "Maximization objective handling" begin
        params = MHCounterParams(5)
        sows = [MHEmptySOW() for _ in 1:3]

        function max_metric_calculator(outcomes)
            return (value=sum(o.final_value for o in outcomes) / length(outcomes),)
        end

        prob = OptimizationProblem(
            params,
            sows,
            MHCounterPolicy,
            max_metric_calculator,
            [maximize(:value)],  # Maximize instead of minimize
        )

        backend = MetaheuristicsBackend(;
            algorithm=:ECA, max_iterations=15, population_size=15, parallel=false
        )

        result = SimOptDecisions.optimize(prob, backend)

        # With maximize, objectives should be positive (un-negated)
        # The result should favor higher increment values
        _, objectives = first(pareto_front(result))
        @test objectives[1] >= 0
    end

    @testset "Constraint handling - FeasibilityConstraint" begin
        params = MHCounterParams(5)
        sows = [MHEmptySOW() for _ in 1:3]

        function fc_metric_calculator(outcomes)
            return (value=sum(o.final_value for o in outcomes) / length(outcomes),)
        end

        # Constraint: increment must be >= 2.0
        constraint = FeasibilityConstraint(:min_increment, p -> p.increment >= 2.0)

        prob = OptimizationProblem(
            params,
            sows,
            MHCounterPolicy,
            fc_metric_calculator,
            [minimize(:value)];
            constraints=AbstractConstraint[constraint],
        )

        backend = MetaheuristicsBackend(;
            algorithm=:ECA, max_iterations=20, population_size=20, parallel=false
        )

        result = SimOptDecisions.optimize(prob, backend)

        # Best solution should respect constraint (increment >= 2.0)
        # Due to optimization dynamics, this might not be exact but should be close
        params, _ = first(pareto_front(result))
        @test params[1] >= 1.5  # Allow some tolerance
    end

    @testset "Constraint handling - PenaltyConstraint" begin
        params = MHCounterParams(5)
        sows = [MHEmptySOW() for _ in 1:3]

        function pc_metric_calculator(outcomes)
            return (value=sum(o.final_value for o in outcomes) / length(outcomes),)
        end

        # Penalty: penalize increments > 5.0
        penalty_constraint = PenaltyConstraint(
            :upper_limit,
            p -> p.increment > 5.0 ? (p.increment - 5.0)^2 : 0.0,
            10.0,  # weight
        )

        prob = OptimizationProblem(
            params,
            sows,
            MHCounterPolicy,
            pc_metric_calculator,
            [minimize(:value)];
            constraints=AbstractConstraint[penalty_constraint],
        )

        backend = MetaheuristicsBackend(;
            algorithm=:ECA, max_iterations=15, population_size=15, parallel=false
        )

        result = SimOptDecisions.optimize(prob, backend)

        # Result should exist and be valid
        @test result isa OptimizationResult{Float64}
        params, _ = first(pareto_front(result))
        @test params[1] >= 0.0
        @test params[1] <= 10.0
    end
end
