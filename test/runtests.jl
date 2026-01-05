using SimOptDecisions
using Test
using Random
using Tables
using Dates

# Import specific functions to avoid conflicts with Base
import SimOptDecisions: finalize, step

@testset "SimOptDecisions.jl" begin
    @testset "Types" begin
        # TimeStep construction with Int
        ts = TimeStep(1, 2020, false)
        @test ts.t == 1
        @test ts.val == 2020
        @test ts.is_last == false

        # TimeStep with Date
        ts_date = TimeStep(5, Date(2025, 1, 1), true)
        @test ts_date.val == Date(2025, 1, 1)
        @test ts_date.is_last == true

        # TimeStep with Float64
        ts_float = TimeStep(10, 0.5, false)
        @test ts_float.val == 0.5
    end

    @testset "Time Axis Validation" begin
        # Valid time axes
        @test SimOptDecisions._validate_time_axis(1:100) === nothing
        @test SimOptDecisions._validate_time_axis([1, 2, 3]) === nothing
        @test SimOptDecisions._validate_time_axis(1.0:0.1:10.0) === nothing
        @test SimOptDecisions._validate_time_axis(
            Date(2020):Year(1):Date(2030)
        ) === nothing

        # Invalid: Vector{Any}
        @test_throws ArgumentError SimOptDecisions._validate_time_axis(Any[1, 2, 3])
    end

    @testset "NoRecorder" begin
        r = NoRecorder()
        # Should not error and return nothing
        @test record!(r, "state", 1) === nothing
        @test record!(r, nothing, nothing) === nothing
        @test record!(r, 42, Date(2020)) === nothing
    end

    @testset "TraceRecorderBuilder and finalize" begin
        builder = TraceRecorderBuilder()
        record!(builder, nothing, nothing)  # Initial state
        record!(builder, 1.0, 1)
        record!(builder, 2.0, 2)
        record!(builder, 3.0, 3)

        recorder = finalize(builder)

        @test recorder isa TraceRecorder{Float64,Int}
        @test length(recorder.states) == 3
        @test length(recorder.times) == 3
        @test recorder.states == [1.0, 2.0, 3.0]
        @test recorder.times == [1, 2, 3]
    end

    @testset "TraceRecorder pre-allocation" begin
        recorder = TraceRecorder{Float64,Int}(10)
        @test length(recorder.states) == 10
        @test length(recorder.times) == 10
    end

    @testset "TraceRecorder Tables.jl interface" begin
        recorder = TraceRecorder([1.0, 2.0, 3.0], [10, 20, 30])

        @test Tables.istable(typeof(recorder))
        @test Tables.columnaccess(typeof(recorder))
        @test Tables.columnnames(recorder) == (:state, :time)
        @test Tables.getcolumn(recorder, :state) == [1.0, 2.0, 3.0]
        @test Tables.getcolumn(recorder, :time) == [10, 20, 30]
        @test Tables.getcolumn(recorder, 1) == [1.0, 2.0, 3.0]
        @test Tables.getcolumn(recorder, 2) == [10, 20, 30]

        # Invalid column access
        @test_throws ArgumentError Tables.getcolumn(recorder, :invalid)
        @test_throws BoundsError Tables.getcolumn(recorder, 3)

        schema = Tables.schema(recorder)
        @test schema.names == (:state, :time)
        @test schema.types == (Float64, Int)
    end

    @testset "Interface function errors" begin
        # Define minimal concrete types for testing
        struct TestState <: AbstractState end
        struct TestPolicy <: AbstractPolicy end
        struct TestModel <: AbstractSystemModel end
        struct TestSOW <: AbstractSOW end

        model = TestModel()
        sow = TestSOW()
        policy = TestPolicy()
        state = TestState()
        rng = Random.Xoshiro(42)
        ts = TimeStep(1, 1, false)

        # Should throw helpful errors
        @test_throws ErrorException initialize(model, sow, rng)
        @test_throws ErrorException step(state, model, sow, policy, ts, rng)
        @test_throws ErrorException time_axis(model, sow)

        # Default implementations should work
        @test aggregate_outcome(state, model) === state
        @test is_terminal(state, model, ts) == false
    end

    @testset "Full simulation (MWE)" begin
        # Minimal Working Example: Counter that increments each step

        struct CounterState <: AbstractState
            value::Int
        end

        struct IncrementPolicy <: AbstractPolicy
            increment::Int
        end

        struct CounterModel <: AbstractSystemModel
            n_steps::Int
        end

        struct EmptySOW <: AbstractSOW end

        # Implement interface
        function SimOptDecisions.initialize(::CounterModel, ::EmptySOW, rng::AbstractRNG)
            return CounterState(0)
        end

        function SimOptDecisions.step(
            state::CounterState,
            model::CounterModel,
            ::EmptySOW,
            policy::IncrementPolicy,
            t::TimeStep,
            rng::AbstractRNG,
        )
            return CounterState(state.value + policy.increment)
        end

        function SimOptDecisions.time_axis(model::CounterModel, ::EmptySOW)
            return 1:(model.n_steps)
        end

        function SimOptDecisions.aggregate_outcome(state::CounterState, ::CounterModel)
            return (final_value=state.value,)
        end

        # Run simulation
        model = CounterModel(10)
        sow = EmptySOW()
        policy = IncrementPolicy(5)

        result = simulate(model, sow, policy)
        @test result.final_value == 50  # 10 steps * 5 increment

        # With recorder
        builder = TraceRecorderBuilder()
        result2 = simulate(model, sow, policy, builder)
        recorder = finalize(builder)

        @test result2.final_value == 50
        @test length(recorder.states) == 10
        @test recorder.states[end].value == 50
        @test recorder.times == collect(1:10)

        # With explicit RNG
        rng = Random.Xoshiro(42)
        result3 = simulate(model, sow, policy; rng=rng)
        @test result3.final_value == 50
    end

    @testset "Type stability" begin
        struct TSCounterState <: AbstractState
            value::Float64
        end

        struct TSIncrementPolicy <: AbstractPolicy
            increment::Float64
        end

        struct TSCounterModel <: AbstractSystemModel end
        struct TSEmptySOW <: AbstractSOW end

        function SimOptDecisions.initialize(::TSCounterModel, ::TSEmptySOW, rng::AbstractRNG)
            return TSCounterState(0.0)
        end

        function SimOptDecisions.step(
            state::TSCounterState,
            ::TSCounterModel,
            ::TSEmptySOW,
            policy::TSIncrementPolicy,
            t::TimeStep,
            rng::AbstractRNG,
        )
            return TSCounterState(state.value + policy.increment)
        end

        function SimOptDecisions.time_axis(::TSCounterModel, ::TSEmptySOW)
            return 1:10
        end

        function SimOptDecisions.aggregate_outcome(state::TSCounterState, ::TSCounterModel)
            return (final_value=state.value,)
        end

        model = TSCounterModel()
        sow = TSEmptySOW()
        policy = TSIncrementPolicy(1.0)
        rng = Random.Xoshiro(42)

        # Test type inference
        @test @inferred(simulate(model, sow, policy, NoRecorder(), rng)) isa NamedTuple
    end

    @testset "Early termination" begin
        struct TermState <: AbstractState
            value::Int
        end

        struct TermPolicy <: AbstractPolicy end
        struct TermModel <: AbstractSystemModel end
        struct TermSOW <: AbstractSOW end

        function SimOptDecisions.initialize(::TermModel, ::TermSOW, rng::AbstractRNG)
            return TermState(0)
        end

        function SimOptDecisions.step(
            state::TermState,
            ::TermModel,
            ::TermSOW,
            ::TermPolicy,
            t::TimeStep,
            rng::AbstractRNG,
        )
            return TermState(state.value + 1)
        end

        function SimOptDecisions.time_axis(::TermModel, ::TermSOW)
            return 1:100
        end

        # Terminate when value reaches 5
        function SimOptDecisions.is_terminal(state::TermState, ::TermModel, t::TimeStep)
            return state.value >= 5
        end

        function SimOptDecisions.aggregate_outcome(state::TermState, ::TermModel)
            return (final_value=state.value,)
        end

        model = TermModel()
        sow = TermSOW()
        policy = TermPolicy()

        result = simulate(model, sow, policy)
        # Should terminate early at value 5, not 100
        @test result.final_value == 5
    end

    # ========================================================================
    # Phase 2: Optimization Infrastructure
    # ========================================================================

    @testset "Objective construction" begin
        obj1 = minimize(:cost)
        @test obj1.name == :cost
        @test obj1.direction == Minimize

        obj2 = maximize(:reliability)
        @test obj2.name == :reliability
        @test obj2.direction == Maximize

        obj3 = Objective(:custom, Minimize)
        @test obj3.name == :custom
        @test obj3.direction == Minimize
    end

    @testset "Batch size types" begin
        @test FullBatch() isa AbstractBatchSize

        fb = FixedBatch(50)
        @test fb.n == 50
        @test_throws ArgumentError FixedBatch(0)
        @test_throws ArgumentError FixedBatch(-1)

        frac = FractionBatch(0.5)
        @test frac.fraction == 0.5
        @test FractionBatch(1.0).fraction == 1.0  # Edge case: 1.0 is valid
        @test_throws ArgumentError FractionBatch(0.0)
        @test_throws ArgumentError FractionBatch(1.5)
        @test_throws ArgumentError FractionBatch(-0.1)
    end

    @testset "SOW validation" begin
        struct OptTestSOW1 <: AbstractSOW end
        struct OptTestSOW2 <: AbstractSOW end

        @test SimOptDecisions._validate_sows([OptTestSOW1(), OptTestSOW1()]) === nothing
        @test_throws ArgumentError SimOptDecisions._validate_sows([])
        @test_throws ArgumentError SimOptDecisions._validate_sows(
            [OptTestSOW1(), OptTestSOW2()]
        )
    end

    @testset "Objectives validation" begin
        @test SimOptDecisions._validate_objectives([minimize(:cost)]) === nothing
        @test SimOptDecisions._validate_objectives(
            [minimize(:cost), maximize(:reliability)]
        ) === nothing

        @test_throws ArgumentError SimOptDecisions._validate_objectives([])
        @test_throws ArgumentError SimOptDecisions._validate_objectives(
            [minimize(:cost), minimize(:cost)]
        )  # Duplicate
    end

    @testset "Policy interface validation" begin
        # Policy without interface
        struct BadOptPolicy <: AbstractPolicy end
        @test_throws ArgumentError SimOptDecisions._validate_policy_interface(BadOptPolicy)

        # Policy with interface
        struct GoodOptPolicy <: AbstractPolicy
            x::Float64
        end
        SimOptDecisions.param_bounds(::Type{GoodOptPolicy}) = [(0.0, 1.0)]
        GoodOptPolicy(x::AbstractVector) = GoodOptPolicy(x[1])

        @test SimOptDecisions._validate_policy_interface(GoodOptPolicy) === nothing

        # Test bounds validation
        struct BadBoundsPolicy <: AbstractPolicy
            x::Float64
        end
        SimOptDecisions.param_bounds(::Type{BadBoundsPolicy}) = [(1.0, 0.0)]  # lower > upper
        BadBoundsPolicy(x::AbstractVector) = BadBoundsPolicy(x[1])

        @test_throws ArgumentError SimOptDecisions._validate_policy_interface(BadBoundsPolicy)
    end

    @testset "Constraint types" begin
        fc = FeasibilityConstraint(:bounds, p -> true)
        @test fc.name == :bounds
        @test fc.func(nothing) == true

        pc = PenaltyConstraint(:soft_limit, p -> 0.0, 10.0)
        @test pc.name == :soft_limit
        @test pc.weight == 10.0
        @test pc.func(nothing) == 0.0
        @test_throws ArgumentError PenaltyConstraint(:bad, p -> 0.0, -1.0)
    end

    @testset "SharedParameters" begin
        sp = SharedParameters(; discount_rate=0.03, horizon=50)
        @test sp.discount_rate == 0.03
        @test sp.horizon == 50
        @test sp.params == (discount_rate=0.03, horizon=50)
        @test :discount_rate in propertynames(sp)
        @test :horizon in propertynames(sp)
    end

    @testset "MetaheuristicsBackend construction" begin
        backend = MetaheuristicsBackend()
        @test backend.algorithm == :ECA
        @test backend.max_iterations == 1000
        @test backend.population_size == 100
        @test backend.parallel == true
        @test backend.options == Dict{Symbol,Any}()

        backend2 = MetaheuristicsBackend(;
            algorithm=:DE, max_iterations=500, population_size=50, parallel=false
        )
        @test backend2.algorithm == :DE
        @test backend2.max_iterations == 500
        @test backend2.population_size == 50
        @test backend2.parallel == false
    end

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

        prob = OptimizationProblem(
            ExtTestModel(),
            [ExtTestSOW()],
            ExtTestPolicy,
            outcomes -> (mean=sum(o.final_value for o in outcomes) / length(outcomes),),
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

    @testset "Validation hooks" begin
        struct ValidatableModel <: AbstractSystemModel end
        struct ValidatablePolicy <: AbstractPolicy end

        # Default implementations return true
        @test validate(ValidatableModel()) == true
        @test validate(ValidatablePolicy(), ValidatableModel()) == true
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
