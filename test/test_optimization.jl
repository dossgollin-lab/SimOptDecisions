@testset "Optimization" begin
    @testset "OptimizationProblem construction" begin
        # Set up MWE types for optimization
        struct OptCounterState <: AbstractState
            value::Float64
        end

        struct OptCounterPolicy <: AbstractPolicy
            increment::Float64
        end

        struct OptCounterParams <: AbstractConfig
            n_steps::Int
        end

        struct OptEmptySOW <: AbstractSOW end

        # Simple for-loop implementation (override full 5-arg simulate signature)
        function SimOptDecisions.simulate(
            params::OptCounterParams,
            sow::OptEmptySOW,
            policy::OptCounterPolicy,
            recorder::AbstractRecorder,
            rng::AbstractRNG,
        )
            value = 0.0
            for ts in SimOptDecisions.Utils.timeindex(1:params.n_steps)
                value += policy.increment
            end
            return (final_value=value,)
        end

        # Implement policy interface for optimization
        SimOptDecisions.param_bounds(::Type{OptCounterPolicy}) = [(0.0, 10.0)]
        OptCounterPolicy(x::AbstractVector) = OptCounterPolicy(x[1])
        SimOptDecisions.params(p::OptCounterPolicy) = [p.increment]

        # Create optimization problem
        params = OptCounterParams(10)
        sows = [OptEmptySOW() for _ in 1:5]

        function metric_calculator(outcomes)
            return (mean_value=sum(o.final_value for o in outcomes) / length(outcomes),)
        end

        prob = OptimizationProblem(
            params, sows, OptCounterPolicy, metric_calculator, [minimize(:mean_value)]
        )

        @test prob.config === params
        @test length(prob.sows) == 5
        @test prob.policy_type === OptCounterPolicy
        @test length(prob.objectives) == 1
        @test prob.batch_size isa FullBatch
        @test isempty(prob.constraints)

        # Test with options
        prob2 = OptimizationProblem(
            params,
            sows,
            OptCounterPolicy,
            metric_calculator,
            [minimize(:mean_value)];
            batch_size=FixedBatch(3),
        )
        @test prob2.batch_size isa FixedBatch
        @test prob2.batch_size.n == 3
    end

    @testset "evaluate_policy" begin
        # Reuse MWE types (defined in previous testset but need to redefine here)
        struct EvalCounterState <: AbstractState
            value::Float64
        end

        struct EvalCounterPolicy <: AbstractPolicy
            increment::Float64
        end

        struct EvalCounterParams <: AbstractConfig
            n_steps::Int
        end

        struct EvalEmptySOW <: AbstractSOW end

        # Simple for-loop implementation (override full 5-arg simulate signature)
        function SimOptDecisions.simulate(
            params::EvalCounterParams,
            sow::EvalEmptySOW,
            policy::EvalCounterPolicy,
            recorder::AbstractRecorder,
            rng::AbstractRNG,
        )
            value = 0.0
            for ts in SimOptDecisions.Utils.timeindex(1:params.n_steps)
                value += policy.increment
            end
            return (final_value=value,)
        end

        SimOptDecisions.param_bounds(::Type{EvalCounterPolicy}) = [(0.0, 10.0)]
        EvalCounterPolicy(x::AbstractVector) = EvalCounterPolicy(x[1])

        params = EvalCounterParams(10)
        sows = [EvalEmptySOW() for _ in 1:5]

        function eval_metric_calculator(outcomes)
            return (mean_value=sum(o.final_value for o in outcomes) / length(outcomes),)
        end

        prob = OptimizationProblem(
            params, sows, EvalCounterPolicy, eval_metric_calculator, [minimize(:mean_value)]
        )

        policy = EvalCounterPolicy(5.0)
        metrics = evaluate_policy(prob, policy; seed=42)

        @test haskey(metrics, :mean_value)
        @test metrics.mean_value == 50.0  # 10 steps * 5.0 increment
    end

    @testset "Objective extraction" begin
        metrics = (cost=100.0, reliability=0.95, efficiency=0.8)

        objectives_min = [minimize(:cost)]
        vals_min = SimOptDecisions._extract_objectives(metrics, objectives_min)
        @test vals_min == [100.0]  # Minimize: no change

        objectives_max = [maximize(:reliability)]
        vals_max = SimOptDecisions._extract_objectives(metrics, objectives_max)
        @test vals_max == [-0.95]  # Maximize: negated

        objectives_multi = [minimize(:cost), maximize(:reliability)]
        vals_multi = SimOptDecisions._extract_objectives(metrics, objectives_multi)
        @test vals_multi == [100.0, -0.95]

        # Missing metric should throw
        @test_throws ArgumentError SimOptDecisions._extract_objectives(
            metrics, [minimize(:missing)]
        )
    end

    @testset "Batch selection" begin
        struct BatchTestSOW <: AbstractSOW
            id::Int
        end

        sows = [BatchTestSOW(i) for i in 1:100]
        rng = Random.Xoshiro(42)

        # FullBatch returns all
        full_batch = SimOptDecisions._select_batch(sows, FullBatch(), rng)
        @test length(full_batch) == 100
        @test full_batch === sows

        # FixedBatch returns n
        fixed_batch = SimOptDecisions._select_batch(sows, FixedBatch(10), rng)
        @test length(fixed_batch) == 10
        @test all(s -> s in sows, fixed_batch)

        # FractionBatch returns fraction
        frac_batch = SimOptDecisions._select_batch(sows, FractionBatch(0.2), rng)
        @test length(frac_batch) == 20
        @test all(s -> s in sows, frac_batch)

        # FractionBatch minimum is 1
        tiny_sows = [BatchTestSOW(1)]
        tiny_batch = SimOptDecisions._select_batch(tiny_sows, FractionBatch(0.1), rng)
        @test length(tiny_batch) >= 1
    end

    @testset "OptimizationResult and pareto_front" begin
        struct ResultPolicy <: AbstractPolicy
            x::Float64
        end

        result = OptimizationResult{ResultPolicy,Float64}(
            [0.5],
            [10.0],
            ResultPolicy(0.5),
            Dict{Symbol,Any}(:iterations => 100),
            [[0.3], [0.5], [0.7]],
            [[12.0], [10.0], [8.0]],
        )

        @test result.best_params == [0.5]
        @test result.best_objectives == [10.0]
        @test result.best_policy.x == 0.5
        @test result.convergence_info[:iterations] == 100

        # Test pareto_front iteration
        front = collect(SimOptDecisions.pareto_front(result))
        @test length(front) == 3
        @test front[1] == ([0.3], [12.0])
        @test front[2] == ([0.5], [10.0])
        @test front[3] == ([0.7], [8.0])
    end
end
