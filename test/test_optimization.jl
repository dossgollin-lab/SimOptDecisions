# Test types for "evaluate_policy"
struct EvalCounterAction <: AbstractAction end

struct EvalCounterPolicy <: AbstractPolicy
    increment::Float64
end

struct EvalCounterConfig <: AbstractConfig
    n_steps::Int
end

struct EvalEmptyScenario <: AbstractScenario end

function SimOptDecisions.initialize(::EvalCounterConfig, ::EvalEmptyScenario, ::AbstractRNG)
    return 0.0
end

function SimOptDecisions.get_action(
    policy::EvalCounterPolicy, ::Float64, ::TimeStep, ::EvalEmptyScenario
)
    return EvalCounterAction()
end

function SimOptDecisions.run_timestep(
    state::Float64,
    ::EvalCounterAction,
    ::TimeStep,
    ::EvalCounterConfig,
    ::EvalEmptyScenario,
    ::AbstractRNG,
)
    new_state = state + 5.0
    return (new_state, new_state)
end

function SimOptDecisions.time_axis(config::EvalCounterConfig, ::EvalEmptyScenario)
    return 1:config.n_steps
end

function SimOptDecisions.compute_outcome(
    step_records::Vector, config::EvalCounterConfig, ::EvalEmptyScenario
)
    return (final_value=step_records[end],)
end

SimOptDecisions.param_bounds(::Type{EvalCounterPolicy}) = [(0.0, 10.0)]
EvalCounterPolicy(x::AbstractVector) = EvalCounterPolicy(x[1])
SimOptDecisions.params(p::EvalCounterPolicy) = [p.increment]

# Test types for "Batch selection"
struct BatchTestScenario <: AbstractScenario
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
        scenarios = [EvalEmptyScenario() for _ in 1:5]

        function eval_metric_calculator(outcomes)
            return (mean_value=sum(o.final_value for o in outcomes) / length(outcomes),)
        end

        policy = EvalCounterPolicy(5.0)
        metrics = evaluate_policy(
            config, scenarios, policy, eval_metric_calculator; seed=42
        )

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
        scenarios = [BatchTestScenario(i) for i in 1:100]
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
        tiny_scenarios = [BatchTestScenario(1)]
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

    @testset "Auto-derive param_bounds and params" begin
        # Test policy with ContinuousParameter fields
        struct AutoDerivePolicy <: AbstractPolicy
            threshold::ContinuousParameter{Float64}
            rate::ContinuousParameter{Float64}
        end

        policy = AutoDerivePolicy(
            ContinuousParameter(0.5, (0.0, 1.0)), ContinuousParameter(0.02, (0.0, 0.1))
        )

        # param_bounds should auto-derive from instance
        bounds = param_bounds(policy)
        @test bounds == [(0.0, 1.0), (0.0, 0.1)]

        # params should auto-derive from instance
        p = params(policy)
        @test p == [0.5, 0.02]

        # Test policy with DiscreteParameter should error
        struct DiscretePolicy <: AbstractPolicy
            n::DiscreteParameter{Int}
        end

        discrete_policy = DiscretePolicy(DiscreteParameter(5))
        @test_throws ArgumentError param_bounds(discrete_policy)

        # Test policy with CategoricalParameter should error
        struct CategoricalPolicy <: AbstractPolicy
            mode::CategoricalParameter{Symbol}
        end

        cat_policy = CategoricalPolicy(CategoricalParameter(:high, [:low, :high]))
        @test_throws ArgumentError param_bounds(cat_policy)

        # Test policy with no ContinuousParameter fields falls back to type method
        struct PlainPolicy <: AbstractPolicy
            x::Float64
        end

        # Should fall back to param_bounds(::Type{PlainPolicy}) which throws
        plain_policy = PlainPolicy(1.0)
        @test_throws ArgumentError param_bounds(plain_policy)
        @test_throws ArgumentError params(plain_policy)
    end
end
