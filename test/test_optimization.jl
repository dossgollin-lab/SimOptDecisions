# Test types for "OptimizationProblem construction"
struct OptCounterAction <: AbstractAction end

struct OptCounterPolicy <: AbstractPolicy
    increment::Float64
end

struct OptCounterConfig <: AbstractConfig
    n_steps::Int
end

struct OptEmptySOW <: AbstractScenario end

function SimOptDecisions.initialize(::OptCounterConfig, ::OptEmptySOW, ::AbstractRNG)
    return 0.0  # state is just a Float64 counter
end

function SimOptDecisions.get_action(
    ::OptCounterPolicy, ::Float64, ::OptEmptySOW, ::TimeStep
)
    return OptCounterAction()
end

function SimOptDecisions.run_timestep(
    state::Float64,
    ::OptCounterAction,
    ::OptEmptySOW,
    ::OptCounterConfig,
    ::TimeStep,
    ::AbstractRNG,
)
    return (state + 1.0, state)  # increment state, record old value
end

function SimOptDecisions.time_axis(config::OptCounterConfig, ::OptEmptySOW)
    return 1:config.n_steps
end

function SimOptDecisions.compute_outcome(
    final_state::Float64, ::Vector, config::OptCounterConfig, ::OptEmptySOW
)
    return (final_value=final_state,)
end

SimOptDecisions.param_bounds(::Type{OptCounterPolicy}) = [(0.0, 10.0)]
OptCounterPolicy(x::AbstractVector) = OptCounterPolicy(x[1])
SimOptDecisions.params(p::OptCounterPolicy) = [p.increment]

# Test types for "evaluate_policy"
struct EvalCounterAction <: AbstractAction end

struct EvalCounterPolicy <: AbstractPolicy
    increment::Float64
end

struct EvalCounterConfig <: AbstractConfig
    n_steps::Int
end

struct EvalEmptySOW <: AbstractScenario end

function SimOptDecisions.initialize(::EvalCounterConfig, ::EvalEmptySOW, ::AbstractRNG)
    return 0.0
end

function SimOptDecisions.get_action(
    policy::EvalCounterPolicy, ::Float64, ::EvalEmptySOW, ::TimeStep
)
    return EvalCounterAction()
end

function SimOptDecisions.run_timestep(
    state::Float64,
    ::EvalCounterAction,
    ::EvalEmptySOW,
    ::EvalCounterConfig,
    ::TimeStep,
    ::AbstractRNG,
)
    return (state + 5.0, state)  # Fixed increment of 5.0 for this test
end

function SimOptDecisions.time_axis(config::EvalCounterConfig, ::EvalEmptySOW)
    return 1:config.n_steps
end

function SimOptDecisions.compute_outcome(
    final_state::Float64, ::Vector, config::EvalCounterConfig, ::EvalEmptySOW
)
    return (final_value=final_state,)
end

SimOptDecisions.param_bounds(::Type{EvalCounterPolicy}) = [(0.0, 10.0)]
EvalCounterPolicy(x::AbstractVector) = EvalCounterPolicy(x[1])

# Test types for "Batch selection"
struct BatchTestSOW <: AbstractScenario
    id::Int
end

# Test types for "OptimizationResult and pareto_front"
struct ResultPolicy <: AbstractPolicy
    x::Float64
end

# ============================================================================
# Tests
# ============================================================================

@testset "Optimization" begin
    @testset "OptimizationProblem construction" begin
        # Create optimization problem
        config = OptCounterConfig(10)
        scenarios = [OptEmptySOW() for _ in 1:5]

        function metric_calculator(outcomes)
            return (mean_value=sum(o.final_value for o in outcomes) / length(outcomes),)
        end

        prob = OptimizationProblem(
            config, scenarios, OptCounterPolicy, metric_calculator, [minimize(:mean_value)]
        )

        @test prob.config === config
        @test length(prob.scenarios) == 5
        @test prob.policy_type === OptCounterPolicy
        @test length(prob.objectives) == 1
        @test prob.batch_size isa FullBatch
        @test isempty(prob.constraints)

        # Test with options
        prob2 = OptimizationProblem(
            config,
            scenarios,
            OptCounterPolicy,
            metric_calculator,
            [minimize(:mean_value)];
            batch_size=FixedBatch(3),
        )
        @test prob2.batch_size isa FixedBatch
        @test prob2.batch_size.n == 3

        # Test with custom bounds
        prob3 = OptimizationProblem(
            config,
            scenarios,
            OptCounterPolicy,
            metric_calculator,
            [minimize(:mean_value)];
            bounds=[(3.0, 7.0)],
        )
        @test prob3.bounds == [(3.0, 7.0)]
        @test get_bounds(prob3) == [(3.0, 7.0)]

        # Default bounds come from param_bounds
        @test prob.bounds === nothing
        @test get_bounds(prob) == [(0.0, 10.0)]
    end

    @testset "dominates" begin
        # a dominates b: all <= and at least one <
        @test dominates([1.0, 1.0], [2.0, 2.0])
        @test dominates([1.0, 2.0], [2.0, 2.0])
        @test dominates([2.0, 1.0], [2.0, 2.0])

        # Neither dominates
        @test !dominates([1.0, 3.0], [2.0, 2.0])  # a better on 1, b better on 2
        @test !dominates([2.0, 2.0], [1.0, 3.0])

        # Equal: not dominated
        @test !dominates([1.0, 1.0], [1.0, 1.0])

        # b dominates a
        @test !dominates([2.0, 2.0], [1.0, 1.0])
    end

    @testset "evaluate_policy" begin
        config = EvalCounterConfig(10)
        scenarios = [EvalEmptySOW() for _ in 1:5]

        function eval_metric_calculator(outcomes)
            return (mean_value=sum(o.final_value for o in outcomes) / length(outcomes),)
        end

        prob = OptimizationProblem(
            config, scenarios, EvalCounterPolicy, eval_metric_calculator, [minimize(:mean_value)]
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
        scenarios = [BatchTestSOW(i) for i in 1:100]
        rng = Random.Xoshiro(42)

        # FullBatch returns all
        full_batch = SimOptDecisions._select_batch(scenarios, FullBatch(), rng)
        @test length(full_batch) == 100
        @test full_batch === scenarios

        # FixedBatch returns n
        fixed_batch = SimOptDecisions._select_batch(scenarios, FixedBatch(10), rng)
        @test length(fixed_batch) == 10
        @test all(s -> s in scenarios, fixed_batch)

        # FractionBatch returns fraction
        frac_batch = SimOptDecisions._select_batch(scenarios, FractionBatch(0.2), rng)
        @test length(frac_batch) == 20
        @test all(s -> s in scenarios, frac_batch)

        # FractionBatch minimum is 1
        tiny_scenarios = [BatchTestSOW(1)]
        tiny_batch = SimOptDecisions._select_batch(tiny_scenarios, FractionBatch(0.1), rng)
        @test length(tiny_batch) >= 1
    end

    @testset "OptimizationResult and pareto_front" begin
        result = OptimizationResult{Float64}(
            Dict{Symbol,Any}(:iterations => 100),
            [[0.3], [0.5], [0.7]],
            [[12.0], [10.0], [8.0]],
        )

        @test result.convergence_info[:iterations] == 100

        # Test pareto_front iteration
        front = collect(SimOptDecisions.pareto_front(result))
        @test length(front) == 3
        @test front[1] == ([0.3], [12.0])
        @test front[2] == ([0.5], [10.0])
        @test front[3] == ([0.7], [8.0])

        # Construct policy from params in the front
        @test ResultPolicy(front[1][1][1]).x == 0.3
    end
end
