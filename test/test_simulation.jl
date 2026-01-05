@testset "Simulation" begin
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

        # Test type inference for simulate
        @test @inferred(simulate(model, sow, policy, NoRecorder(), rng)) isa NamedTuple

        # Test type inference for interface functions
        @test @inferred(SimOptDecisions.initialize(model, sow, rng)) isa TSCounterState
        state = SimOptDecisions.initialize(model, sow, rng)
        ts = TimeStep(1, 1, false)
        @test @inferred(SimOptDecisions.step(state, model, sow, policy, ts, rng)) isa TSCounterState
        @test @inferred(SimOptDecisions.aggregate_outcome(state, model)) isa NamedTuple

        # Test zero allocations in hot path
        # Warm-up run
        simulate(model, sow, policy, NoRecorder(), rng)

        # Test allocations
        allocs = @allocated simulate(model, sow, policy, NoRecorder(), rng)
        @test allocs == 0
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
end
