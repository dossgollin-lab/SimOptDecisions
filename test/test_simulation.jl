@testset "Simulation" begin
    @testset "Interface function errors" begin
        # Define minimal concrete types for testing
        struct TestState <: AbstractState end
        struct TestPolicy <: AbstractPolicy end
        struct TestParams <: AbstractFixedParams end
        struct TestSOW <: AbstractSOW end

        params = TestParams()
        sow = TestSOW()
        policy = TestPolicy()
        rng = Random.Xoshiro(42)

        # simulate should throw helpful error if not implemented
        @test_throws ErrorException simulate(params, sow, policy, rng)
    end

    @testset "Direct simulate (non-time-stepped)" begin
        # Test analytical/direct computation without time-stepping

        struct AnalyticalParams <: AbstractFixedParams
            multiplier::Float64
        end

        struct AnalyticalSOW <: AbstractSOW
            value::Float64
        end

        struct AnalyticalPolicy <: AbstractPolicy
            factor::Float64
        end

        function SimOptDecisions.simulate(
            params::AnalyticalParams,
            sow::AnalyticalSOW,
            policy::AnalyticalPolicy,
            rng::AbstractRNG,
        )
            return (result=params.multiplier * sow.value * policy.factor,)
        end

        params = AnalyticalParams(2.0)
        sow = AnalyticalSOW(3.0)
        policy = AnalyticalPolicy(4.0)

        result = simulate(params, sow, policy)
        @test result.result == 24.0  # 2.0 * 3.0 * 4.0
    end

    @testset "Time-stepped simulation (simple for loop)" begin
        # Counter that increments each step - using simple for loop

        struct CounterState <: AbstractState
            value::Int
        end

        struct IncrementPolicy <: AbstractPolicy
            increment::Int
        end

        struct CounterParams <: AbstractFixedParams
            n_steps::Int
        end

        struct EmptySOW <: AbstractSOW end

        # Simple for-loop implementation
        function SimOptDecisions.simulate(
            params::CounterParams,
            sow::EmptySOW,
            policy::IncrementPolicy,
            rng::AbstractRNG,
        )
            value = 0
            for ts in SimOptDecisions.Utils.timeindex(1:params.n_steps)
                value += policy.increment
            end
            return (final_value=value,)
        end

        # With recorder support
        function SimOptDecisions.simulate(
            params::CounterParams,
            sow::EmptySOW,
            policy::IncrementPolicy,
            recorder::AbstractRecorder,
            rng::AbstractRNG,
        )
            state = CounterState(0)
            record!(recorder, state, nothing)

            for ts in SimOptDecisions.Utils.timeindex(1:params.n_steps)
                state = CounterState(state.value + policy.increment)
                record!(recorder, state, ts.val)
            end

            return (final_value=state.value,)
        end

        # Run simulation
        params = CounterParams(10)
        sow = EmptySOW()
        policy = IncrementPolicy(5)

        result = simulate(params, sow, policy)
        @test result.final_value == 50  # 10 steps * 5 increment

        # With recorder
        builder = TraceRecorderBuilder()
        result2 = simulate(params, sow, policy, builder)
        recorder = finalize(builder)

        @test result2.final_value == 50
        @test length(recorder.states) == 10
        @test recorder.states[end].value == 50
        @test recorder.times == collect(1:10)

        # With explicit RNG
        rng = Random.Xoshiro(42)
        result3 = simulate(params, sow, policy; rng=rng)
        @test result3.final_value == 50
    end

    @testset "Type stability" begin
        struct TSCounterState <: AbstractState
            value::Float64
        end

        struct TSIncrementPolicy <: AbstractPolicy
            increment::Float64
        end

        struct TSCounterParams <: AbstractFixedParams end
        struct TSEmptySOW <: AbstractSOW end

        # Simple for-loop implementation
        function SimOptDecisions.simulate(
            params::TSCounterParams,
            sow::TSEmptySOW,
            policy::TSIncrementPolicy,
            rng::AbstractRNG,
        )
            value = 0.0
            for ts in SimOptDecisions.Utils.timeindex(1:10)
                value += policy.increment
            end
            return (final_value=value,)
        end

        function SimOptDecisions.simulate(
            params::TSCounterParams,
            sow::TSEmptySOW,
            policy::TSIncrementPolicy,
            recorder::AbstractRecorder,
            rng::AbstractRNG,
        )
            state = TSCounterState(0.0)
            record!(recorder, state, nothing)

            for ts in SimOptDecisions.Utils.timeindex(1:10)
                state = TSCounterState(state.value + policy.increment)
                record!(recorder, state, ts.val)
            end

            return (final_value=state.value,)
        end

        params = TSCounterParams()
        sow = TSEmptySOW()
        policy = TSIncrementPolicy(1.0)
        rng = Random.Xoshiro(42)

        # Test type inference for simulate
        @test @inferred(simulate(params, sow, policy, NoRecorder(), rng)) isa NamedTuple

        # Test basic functionality
        result = simulate(params, sow, policy, rng)
        @test result.final_value == 10.0
    end

    @testset "Early termination" begin
        struct TermState <: AbstractState
            value::Int
        end

        struct TermPolicy <: AbstractPolicy end
        struct TermParams <: AbstractFixedParams end
        struct TermSOW <: AbstractSOW end

        # Simple for-loop with early termination
        function SimOptDecisions.simulate(
            params::TermParams,
            sow::TermSOW,
            policy::TermPolicy,
            rng::AbstractRNG,
        )
            value = 0
            for ts in SimOptDecisions.Utils.timeindex(1:100)
                value += 1
                # Early termination condition
                if value >= 5
                    break
                end
            end
            return (final_value=value,)
        end

        params = TermParams()
        sow = TermSOW()
        policy = TermPolicy()

        result = simulate(params, sow, policy)
        # Should terminate early at value 5, not 100
        @test result.final_value == 5
    end
end

@testset "Utils" begin
    @testset "discount_factor" begin
        # Basic functionality
        @test SimOptDecisions.Utils.discount_factor(0.0, 1) == 1.0
        @test SimOptDecisions.Utils.discount_factor(0.0, 10) == 1.0

        # 10% discount rate
        @test SimOptDecisions.Utils.discount_factor(0.10, 1) ≈ 1/1.10
        @test SimOptDecisions.Utils.discount_factor(0.10, 2) ≈ 1/1.10^2
        @test SimOptDecisions.Utils.discount_factor(0.10, 10) ≈ 1/1.10^10

        # 5% discount rate, year 0 should be 1.0
        @test SimOptDecisions.Utils.discount_factor(0.05, 0) == 1.0
    end

    @testset "timeindex" begin
        # Integer range
        times = collect(SimOptDecisions.Utils.timeindex(1:5))
        @test length(times) == 5
        @test times[1] == TimeStep(1, 1, false)
        @test times[5] == TimeStep(5, 5, true)
        @test all(ts -> ts.t == ts.val, times)

        # Check is_last
        @test all(ts -> !ts.is_last, times[1:4])
        @test times[5].is_last

        # Non-1-based range
        times2 = collect(SimOptDecisions.Utils.timeindex(2020:2025))
        @test length(times2) == 6
        @test times2[1] == TimeStep(1, 2020, false)
        @test times2[6] == TimeStep(6, 2025, true)

        # Single element
        times3 = collect(SimOptDecisions.Utils.timeindex(1:1))
        @test length(times3) == 1
        @test times3[1] == TimeStep(1, 1, true)
    end

    @testset "run_timesteps" begin
        @testset "scalar output" begin
            # Simple accumulator - state is cumulative sum, output is step value
            final_state, outputs = SimOptDecisions.Utils.run_timesteps(0.0, 1:5) do state, ts
                new_state = state + ts.val
                return (new_state, Float64(ts.val))
            end

            @test final_state == 15.0  # 1+2+3+4+5
            @test length(outputs) == 5
            @test outputs == [1.0, 2.0, 3.0, 4.0, 5.0]
        end

        @testset "stateless model (nothing state)" begin
            # No state, just collecting outputs
            final_state, outputs = SimOptDecisions.Utils.run_timesteps(nothing, 1:3) do state, ts
                return (state, ts.val^2)
            end

            @test final_state === nothing
            @test outputs == [1, 4, 9]
        end

        @testset "NamedTuple output" begin
            # Multiple outputs per step
            final_state, results = SimOptDecisions.Utils.run_timesteps(0.0, 1:4) do state, ts
                damage = Float64(ts.val * 10)
                cost = Float64(ts.val * 2)
                new_state = state + damage
                return (new_state, (damage=damage, cost=cost))
            end

            @test final_state == 100.0  # 10+20+30+40
            @test length(results) == 4
            @test results[1] == (damage=10.0, cost=2.0)
            @test results[4] == (damage=40.0, cost=8.0)
            @test [r.damage for r in results] == [10.0, 20.0, 30.0, 40.0]
            @test [r.cost for r in results] == [2.0, 4.0, 6.0, 8.0]
        end

        @testset "custom struct output" begin
            struct StepResult
                value::Float64
                is_last::Bool
            end

            final_state, results = SimOptDecisions.Utils.run_timesteps(1, 1:3) do state, ts
                return (state + 1, StepResult(Float64(state * ts.val), ts.is_last))
            end

            @test final_state == 4  # 1 + 3 increments
            @test length(results) == 3
            @test results[1].value == 1.0  # state=1, ts.val=1
            @test results[2].value == 4.0  # state=2, ts.val=2
            @test results[3].value == 9.0  # state=3, ts.val=3
            @test !results[1].is_last
            @test !results[2].is_last
            @test results[3].is_last
        end

        @testset "non-1-based time axis" begin
            # Date-like range (using years 2020-2022)
            final_state, outputs = SimOptDecisions.Utils.run_timesteps(0, 2020:2022) do state, ts
                return (state + 1, ts.val)  # output is the year value
            end

            @test final_state == 3
            @test outputs == [2020, 2021, 2022]
        end

        @testset "single timestep" begin
            final_state, outputs = SimOptDecisions.Utils.run_timesteps(10, 1:1) do state, ts
                @test ts.is_last  # should be true for single step
                return (state * 2, state + ts.val)
            end

            @test final_state == 20
            @test outputs == [11]
        end

        @testset "type inference" begin
            # Test that output type is properly inferred
            _, outputs = SimOptDecisions.Utils.run_timesteps(0.0, 1:3) do state, ts
                return (state, Float64(ts.val))
            end
            @test eltype(outputs) === Float64

            _, outputs2 = SimOptDecisions.Utils.run_timesteps(0, 1:3) do state, ts
                return (state, (a=ts.val, b=ts.val * 2))
            end
            @test eltype(outputs2) <: NamedTuple
        end
    end
end
