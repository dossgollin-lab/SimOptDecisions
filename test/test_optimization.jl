@testset "Optimization" begin
    @testset "OptimizationProblem construction" begin
        # Set up MWE types for optimization
        struct OptCounterState <: AbstractState
            value::Float64
        end

        struct OptCounterPolicy <: AbstractPolicy
            increment::Float64
        end

        struct OptCounterModel <: AbstractSystemModel
            n_steps::Int
        end

        struct OptEmptySOW <: AbstractSOW end

        # Implement interface for simulation
        function SimOptDecisions.initialize(::OptCounterModel, ::OptEmptySOW, rng::AbstractRNG)
            return OptCounterState(0.0)
        end

        function SimOptDecisions.step(
            state::OptCounterState,
            ::OptCounterModel,
            ::OptEmptySOW,
            policy::OptCounterPolicy,
            t::TimeStep,
            rng::AbstractRNG,
        )
            return OptCounterState(state.value + policy.increment)
        end

        function SimOptDecisions.time_axis(model::OptCounterModel, ::OptEmptySOW)
            return 1:(model.n_steps)
        end

        function SimOptDecisions.aggregate_outcome(state::OptCounterState, ::OptCounterModel)
            return (final_value=state.value,)
        end

        # Implement policy interface for optimization
        SimOptDecisions.param_bounds(::Type{OptCounterPolicy}) = [(0.0, 10.0)]
        OptCounterPolicy(x::AbstractVector) = OptCounterPolicy(x[1])
        SimOptDecisions.params(p::OptCounterPolicy) = [p.increment]

        # Create optimization problem
        model = OptCounterModel(10)
        sows = [OptEmptySOW() for _ in 1:5]

        function metric_calculator(outcomes)
            return (mean_value=sum(o.final_value for o in outcomes) / length(outcomes),)
        end

        prob = OptimizationProblem(
            model, sows, OptCounterPolicy, metric_calculator, [minimize(:mean_value)]
        )

        @test prob.model === model
        @test length(prob.sows) == 5
        @test prob.policy_type === OptCounterPolicy
        @test length(prob.objectives) == 1
        @test prob.batch_size isa FullBatch
        @test isempty(prob.constraints)

        # Test with options
        prob2 = OptimizationProblem(
            model,
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

        struct EvalCounterModel <: AbstractSystemModel
            n_steps::Int
        end

        struct EvalEmptySOW <: AbstractSOW end

        function SimOptDecisions.initialize(::EvalCounterModel, ::EvalEmptySOW, rng::AbstractRNG)
            return EvalCounterState(0.0)
        end

        function SimOptDecisions.step(
            state::EvalCounterState,
            ::EvalCounterModel,
            ::EvalEmptySOW,
            policy::EvalCounterPolicy,
            t::TimeStep,
            rng::AbstractRNG,
        )
            return EvalCounterState(state.value + policy.increment)
        end

        function SimOptDecisions.time_axis(model::EvalCounterModel, ::EvalEmptySOW)
            return 1:(model.n_steps)
        end

        function SimOptDecisions.aggregate_outcome(state::EvalCounterState, ::EvalCounterModel)
            return (final_value=state.value,)
        end

        SimOptDecisions.param_bounds(::Type{EvalCounterPolicy}) = [(0.0, 10.0)]
        EvalCounterPolicy(x::AbstractVector) = EvalCounterPolicy(x[1])

        model = EvalCounterModel(10)
        sows = [EvalEmptySOW() for _ in 1:5]

        function eval_metric_calculator(outcomes)
            return (mean_value=sum(o.final_value for o in outcomes) / length(outcomes),)
        end

        prob = OptimizationProblem(
            model, sows, EvalCounterPolicy, eval_metric_calculator, [minimize(:mean_value)]
        )

        policy = EvalCounterPolicy(5.0)
        metrics = evaluate_policy(prob, policy; seed=42)

        @test haskey(metrics, :mean_value)
        @test metrics.mean_value == 50.0  # 10 steps * 5.0 increment
    end

    @testset "MetaheuristicsBackend requires extension" begin
        # Create minimal valid problem
        struct ExtTestState <: AbstractState
            value::Float64
        end

        struct ExtTestPolicy <: AbstractPolicy
            x::Float64
        end

        struct ExtTestModel <: AbstractSystemModel end
        struct ExtTestSOW <: AbstractSOW end

        function SimOptDecisions.initialize(::ExtTestModel, ::ExtTestSOW, rng::AbstractRNG)
            return ExtTestState(0.0)
        end

        function SimOptDecisions.step(
            state::ExtTestState,
            ::ExtTestModel,
            ::ExtTestSOW,
            policy::ExtTestPolicy,
            t::TimeStep,
            rng::AbstractRNG,
        )
            return ExtTestState(state.value + policy.x)
        end

        function SimOptDecisions.time_axis(::ExtTestModel, ::ExtTestSOW)
            return 1:10
        end

        function SimOptDecisions.aggregate_outcome(state::ExtTestState, ::ExtTestModel)
            return (final_value=state.value,)
        end

        SimOptDecisions.param_bounds(::Type{ExtTestPolicy}) = [(0.0, 1.0)]
        ExtTestPolicy(x::AbstractVector) = ExtTestPolicy(x[1])

        function ext_test_metric_calculator(outcomes)
            return (mean=sum(o.final_value for o in outcomes) / length(outcomes),)
        end

        prob = OptimizationProblem(
            ExtTestModel(),
            [ExtTestSOW()],
            ExtTestPolicy,
            ext_test_metric_calculator,
            [minimize(:mean)],
        )

        # Should throw helpful error
        @test_throws ErrorException optimize(prob, MetaheuristicsBackend())
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

        result = OptimizationResult{ResultPolicy}(
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
        front = collect(pareto_front(result))
        @test length(front) == 3
        @test front[1] == ([0.3], [12.0])
        @test front[2] == ([0.5], [10.0])
        @test front[3] == ([0.7], [8.0])
    end
end
