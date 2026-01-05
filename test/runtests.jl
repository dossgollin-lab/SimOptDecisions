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
end
