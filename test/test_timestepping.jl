@testset "TimeStepping" begin
    @testset "Interface function errors" begin
        # Minimal types for testing error messages
        struct TSTestParams <: AbstractConfig end
        struct TSTestSOW <: AbstractSOW end
        struct TSTestPolicy <: AbstractPolicy end

        params = TSTestParams()
        sow = TSTestSOW()
        policy = TSTestPolicy()
        rng = Random.Xoshiro(42)
        ts = TimeStep(1, 1, false)

        # run_timestep should throw MethodError if not implemented
        @test_throws MethodError SimOptDecisions.TimeStepping.run_timestep(
            nothing, params, sow, policy, ts, rng
        )

        # time_axis should throw MethodError if not implemented
        @test_throws MethodError SimOptDecisions.TimeStepping.time_axis(params, sow)
    end

    @testset "Default implementations" begin
        struct DefaultTSParams <: AbstractConfig end
        struct DefaultTSSOW <: AbstractSOW end

        params = DefaultTSParams()
        sow = DefaultTSSOW()
        rng = Random.Xoshiro(42)

        # initialize defaults to nothing (stateless models)
        @test SimOptDecisions.TimeStepping.initialize(params, sow, rng) === nothing

        # finalize defaults to returning final_state
        @test SimOptDecisions.TimeStepping.finalize(:final_state, [1, 2, 3], params, sow) === :final_state
        @test SimOptDecisions.TimeStepping.finalize(42.0, Float64[], params, sow) === 42.0
    end

    @testset "Stateful counter model" begin
        # A simple counter that increments each step
        struct TSCounterState <: AbstractState
            value::Int
        end

        struct TSCounterParams <: AbstractConfig
            n_steps::Int
        end

        struct TSCounterSOW <: AbstractSOW end

        struct TSIncrementPolicy <: AbstractPolicy
            increment::Int
        end

        # Implement TimeStepping callbacks
        function SimOptDecisions.TimeStepping.initialize(::TSCounterParams, ::TSCounterSOW, ::AbstractRNG)
            return TSCounterState(0)
        end

        function SimOptDecisions.TimeStepping.run_timestep(
            state::TSCounterState, params::TSCounterParams, sow::TSCounterSOW,
            policy::TSIncrementPolicy, t::TimeStep, ::AbstractRNG
        )
            new_state = TSCounterState(state.value + policy.increment)
            return (new_state, policy.increment)  # output is the increment
        end

        function SimOptDecisions.TimeStepping.time_axis(params::TSCounterParams, ::TSCounterSOW)
            return 1:params.n_steps
        end

        function SimOptDecisions.TimeStepping.finalize(
            final_state::TSCounterState, outputs::Vector, params::TSCounterParams, sow::TSCounterSOW
        )
            return (final_value=final_state.value, total_increments=sum(outputs))
        end

        params = TSCounterParams(10)
        sow = TSCounterSOW()
        policy = TSIncrementPolicy(5)
        rng = Random.Xoshiro(42)

        result = SimOptDecisions.TimeStepping.run_simulation(params, sow, policy, rng)

        @test result.final_value == 50  # 10 steps * 5 increment
        @test result.total_increments == 50
    end

    @testset "Stateless model (nothing state)" begin
        # Model that computes something each step, no state tracking
        struct TSStatelessParams <: AbstractConfig
            horizon::Int
        end

        struct TSStatelessSOW <: AbstractSOW
            multiplier::Float64
        end

        struct TSStatelessPolicy <: AbstractPolicy
            base::Float64
        end

        # initialize returns nothing by default, no need to implement

        function SimOptDecisions.TimeStepping.run_timestep(
            state::Nothing, params::TSStatelessParams, sow::TSStatelessSOW,
            policy::TSStatelessPolicy, t::TimeStep, ::AbstractRNG
        )
            output = policy.base * sow.multiplier * t.t
            return (nothing, output)
        end

        function SimOptDecisions.TimeStepping.time_axis(params::TSStatelessParams, ::TSStatelessSOW)
            return 1:params.horizon
        end

        function SimOptDecisions.TimeStepping.finalize(
            ::Nothing, outputs::Vector, params::TSStatelessParams, sow::TSStatelessSOW
        )
            return (total=sum(outputs),)
        end

        params = TSStatelessParams(5)
        sow = TSStatelessSOW(2.0)
        policy = TSStatelessPolicy(10.0)
        rng = Random.Xoshiro(42)

        result = SimOptDecisions.TimeStepping.run_simulation(params, sow, policy, rng)

        # 10 * 2 * (1+2+3+4+5) = 20 * 15 = 300
        @test result.total == 300.0
    end

    @testset "NamedTuple step output" begin
        # Test collecting NamedTuple outputs per step
        struct TSNTParams <: AbstractConfig
            horizon::Int
        end

        struct TSNTsow <: AbstractSOW
            damage_rate::Float64
            cost_rate::Float64
        end

        struct TSNTPolicy <: AbstractPolicy end

        function SimOptDecisions.TimeStepping.run_timestep(
            state::Nothing, params::TSNTParams, sow::TSNTsow,
            policy::TSNTPolicy, t::TimeStep, ::AbstractRNG
        )
            damage = sow.damage_rate * t.t
            cost = sow.cost_rate * t.t
            return (nothing, (damage=damage, cost=cost))
        end

        function SimOptDecisions.TimeStepping.time_axis(params::TSNTParams, ::TSNTsow)
            return 1:params.horizon
        end

        function SimOptDecisions.TimeStepping.finalize(
            ::Nothing, outputs::Vector, params::TSNTParams, sow::TSNTsow
        )
            total_damage = sum(o.damage for o in outputs)
            total_cost = sum(o.cost for o in outputs)
            return (total_damage=total_damage, total_cost=total_cost)
        end

        params = TSNTParams(4)
        sow = TSNTsow(10.0, 2.0)
        policy = TSNTPolicy()
        rng = Random.Xoshiro(42)

        result = SimOptDecisions.TimeStepping.run_simulation(params, sow, policy, rng)

        # damage: 10*(1+2+3+4) = 100, cost: 2*(1+2+3+4) = 20
        @test result.total_damage == 100.0
        @test result.total_cost == 20.0
    end

    @testset "Integration with get_action" begin
        # Test that users can call get_action inside run_timestep
        struct TSActionState <: AbstractState
            level::Float64
        end

        struct TSActionParams <: AbstractConfig
            horizon::Int
        end

        struct TSActionSOW <: AbstractSOW
            growth_rate::Float64
        end

        struct TSActionPolicy <: AbstractPolicy
            invest_fraction::Float64
        end

        # Implement get_action
        function SimOptDecisions.get_action(
            policy::TSActionPolicy,
            state::TSActionState,
            sow::TSActionSOW,
            t::TimeStep,
        )
            return (invest=state.level * policy.invest_fraction,)
        end

        # Implement TimeStepping callbacks
        function SimOptDecisions.TimeStepping.initialize(::TSActionParams, ::TSActionSOW, ::AbstractRNG)
            return TSActionState(100.0)  # Start with 100
        end

        function SimOptDecisions.TimeStepping.run_timestep(
            state::TSActionState, params::TSActionParams, sow::TSActionSOW,
            policy::TSActionPolicy, t::TimeStep, ::AbstractRNG
        )
            # Call get_action to get the investment decision
            action = get_action(policy, state, sow, t)

            # Transition: growth from rate + investment
            growth = state.level * sow.growth_rate + action.invest
            new_level = state.level + growth
            new_state = TSActionState(new_level)

            return (new_state, growth)  # output is growth this step
        end

        function SimOptDecisions.TimeStepping.time_axis(params::TSActionParams, ::TSActionSOW)
            return 1:params.horizon
        end

        function SimOptDecisions.TimeStepping.finalize(
            final_state::TSActionState, outputs::Vector, params::TSActionParams, sow::TSActionSOW
        )
            return (final_level=final_state.level, total_growth=sum(outputs))
        end

        params = TSActionParams(3)
        sow = TSActionSOW(0.05)  # 5% growth rate
        policy = TSActionPolicy(0.10)  # 10% investment
        rng = Random.Xoshiro(42)

        result = SimOptDecisions.TimeStepping.run_simulation(params, sow, policy, rng)

        # Starting at 100, each step: growth = level * 0.05 + level * 0.10 = level * 0.15
        # Step 1: level=100, growth=15, new_level=115
        # Step 2: level=115, growth=17.25, new_level=132.25
        # Step 3: level=132.25, growth=19.8375, new_level=152.0875
        @test result.final_level ≈ 100 * 1.15^3 atol=1e-10
        @test result.total_growth ≈ result.final_level - 100 atol=1e-10
    end

    @testset "Recording support" begin
        struct TSRecordState <: AbstractState
            value::Float64
        end

        struct TSRecordParams <: AbstractConfig
            horizon::Int
        end

        struct TSRecordSOW <: AbstractSOW end
        struct TSRecordPolicy <: AbstractPolicy end

        function SimOptDecisions.TimeStepping.initialize(::TSRecordParams, ::TSRecordSOW, ::AbstractRNG)
            return TSRecordState(0.0)
        end

        function SimOptDecisions.TimeStepping.run_timestep(
            state::TSRecordState, params::TSRecordParams, sow::TSRecordSOW,
            policy::TSRecordPolicy, t::TimeStep, ::AbstractRNG
        )
            new_state = TSRecordState(state.value + 1.0)
            return (new_state, state.value)
        end

        function SimOptDecisions.TimeStepping.time_axis(params::TSRecordParams, ::TSRecordSOW)
            return 1:params.horizon
        end

        params = TSRecordParams(5)
        sow = TSRecordSOW()
        policy = TSRecordPolicy()
        rng = Random.Xoshiro(42)

        # Test with TraceRecorderBuilder
        builder = TraceRecorderBuilder()
        result = SimOptDecisions.TimeStepping.run_simulation(
            params, sow, policy, rng; recorder=builder
        )

        # Should have recorded initial state + 5 timesteps = 6 entries (but finalize skips first)
        recorder = finalize(builder)
        @test length(recorder.states) == 5  # Excluding initial state (time=nothing)
        @test recorder.times == [1, 2, 3, 4, 5]
        @test recorder.states[end].value == 5.0

        # Test with NoRecorder (should work without error)
        result2 = SimOptDecisions.TimeStepping.run_simulation(params, sow, policy, rng)
        @test result2 == result  # Same result with or without recorder
    end

    @testset "Positional recorder argument" begin
        # Test the convenience overload with positional recorder
        struct TSPosParams <: AbstractConfig end
        struct TSPosSOW <: AbstractSOW end
        struct TSPosPolicy <: AbstractPolicy end

        function SimOptDecisions.TimeStepping.run_timestep(
            state::Nothing, params::TSPosParams, sow::TSPosSOW,
            policy::TSPosPolicy, t::TimeStep, ::AbstractRNG
        )
            return (nothing, t.t)
        end

        function SimOptDecisions.TimeStepping.time_axis(::TSPosParams, ::TSPosSOW)
            return 1:3
        end

        function SimOptDecisions.TimeStepping.finalize(::Nothing, outputs::Vector, ::TSPosParams, ::TSPosSOW)
            return (total=sum(outputs),)
        end

        params = TSPosParams()
        sow = TSPosSOW()
        policy = TSPosPolicy()
        rng = Random.Xoshiro(42)

        # Test positional recorder argument
        builder = TraceRecorderBuilder()
        result = SimOptDecisions.TimeStepping.run_simulation(params, sow, policy, builder, rng)
        @test result.total == 6  # 1+2+3
    end

    @testset "Type stability" begin
        struct TSTypeParams <: AbstractConfig end
        struct TSTypeSOW <: AbstractSOW end
        struct TSTypePolicy <: AbstractPolicy end

        function SimOptDecisions.TimeStepping.run_timestep(
            state::Float64, params::TSTypeParams, sow::TSTypeSOW,
            policy::TSTypePolicy, t::TimeStep, ::AbstractRNG
        )
            return (state + 1.0, state)
        end

        function SimOptDecisions.TimeStepping.time_axis(::TSTypeParams, ::TSTypeSOW)
            return 1:5
        end

        function SimOptDecisions.TimeStepping.initialize(::TSTypeParams, ::TSTypeSOW, ::AbstractRNG)
            return 0.0
        end

        function SimOptDecisions.TimeStepping.finalize(
            final_state::Float64, outputs::Vector{Float64}, ::TSTypeParams, ::TSTypeSOW
        )
            return (final=final_state, sum=sum(outputs))
        end

        params = TSTypeParams()
        sow = TSTypeSOW()
        policy = TSTypePolicy()
        rng = Random.Xoshiro(42)

        # Test type inference
        result = @inferred SimOptDecisions.TimeStepping.run_simulation(
            params, sow, policy, rng
        )
        @test result.final == 5.0
        @test result.sum == 10.0  # 0+1+2+3+4
    end

    @testset "SOW-dependent finalize (discounting)" begin
        # Test that finalize can use SOW parameters (like discount_rate)
        struct TSDiscountParams <: AbstractConfig
            horizon::Int
        end

        struct TSDiscountSOW <: AbstractSOW
            discount_rate::Float64
        end

        struct TSDiscountPolicy <: AbstractPolicy end

        function SimOptDecisions.TimeStepping.run_timestep(
            state::Nothing, params::TSDiscountParams, sow::TSDiscountSOW,
            policy::TSDiscountPolicy, t::TimeStep, ::AbstractRNG
        )
            damage = 100.0  # Constant damage each year
            return (nothing, damage)
        end

        function SimOptDecisions.TimeStepping.time_axis(params::TSDiscountParams, ::TSDiscountSOW)
            return 1:params.horizon
        end

        function SimOptDecisions.TimeStepping.finalize(
            ::Nothing, damages::Vector, params::TSDiscountParams, sow::TSDiscountSOW
        )
            # Discount using SOW's discount rate
            npv = sum(
                damages[t] * SimOptDecisions.Utils.discount_factor(sow.discount_rate, t)
                for t in eachindex(damages)
            )
            return (npv_damages=npv, annual_damages=damages)
        end

        params = TSDiscountParams(3)
        sow = TSDiscountSOW(0.10)  # 10% discount rate
        policy = TSDiscountPolicy()
        rng = Random.Xoshiro(42)

        result = SimOptDecisions.TimeStepping.run_simulation(params, sow, policy, rng)

        # NPV = 100/1.10 + 100/1.10^2 + 100/1.10^3
        expected_npv = 100/1.10 + 100/1.10^2 + 100/1.10^3
        @test result.npv_damages ≈ expected_npv atol=1e-10
        @test result.annual_damages == [100.0, 100.0, 100.0]
    end

    @testset "Auto-connection to simulate" begin
        # Test that simulate() automatically calls TimeStepping.run_simulation
        # (no boilerplate needed - just implement the callbacks)
        struct TSConnectState <: AbstractState
            count::Int
        end

        struct TSConnectConfig <: AbstractConfig
            steps::Int
        end

        struct TSConnectSOW <: AbstractSOW end
        struct TSConnectPolicy <: AbstractPolicy end

        function SimOptDecisions.TimeStepping.initialize(::TSConnectConfig, ::TSConnectSOW, ::AbstractRNG)
            return TSConnectState(0)
        end

        function SimOptDecisions.TimeStepping.run_timestep(
            state::TSConnectState, config::TSConnectConfig, sow::TSConnectSOW,
            policy::TSConnectPolicy, t::TimeStep, ::AbstractRNG
        )
            return (TSConnectState(state.count + 1), state.count)
        end

        function SimOptDecisions.TimeStepping.time_axis(config::TSConnectConfig, ::TSConnectSOW)
            return 1:config.steps
        end

        function SimOptDecisions.TimeStepping.finalize(
            final_state::TSConnectState, outputs::Vector, config::TSConnectConfig, sow::TSConnectSOW
        )
            return (final_count=final_state.count,)
        end

        # No need to implement simulate() - it auto-calls TimeStepping.run_simulation!
        # Just test via the main simulate interface
        config = TSConnectConfig(7)
        sow = TSConnectSOW()
        policy = TSConnectPolicy()

        result = simulate(config, sow, policy, Random.Xoshiro(42))
        @test result.final_count == 7
    end

    @testset "TimeSeriesParameter" begin
        # Construction
        ts = TimeSeriesParameter([1.0, 2.0, 3.0])
        @test length(ts) == 3
        @test eltype(ts) == Float64

        # Integer indexing
        @test ts[1] == 1.0
        @test ts[2] == 2.0
        @test ts[3] == 3.0

        # TimeStep indexing
        @test ts[TimeStep(1, 2020, false)] == 1.0
        @test ts[TimeStep(2, 2021, false)] == 2.0
        @test ts[TimeStep(3, 2022, true)] == 3.0

        # Bounds errors
        @test_throws TimeSeriesParameterBoundsError ts[0]
        @test_throws TimeSeriesParameterBoundsError ts[4]

        # Iteration
        @test collect(ts) == [1.0, 2.0, 3.0]
        @test first(ts) == 1.0
        @test last(ts) == 3.0

        # Indexing helpers
        @test firstindex(ts) == 1
        @test lastindex(ts) == 3
        @test collect(eachindex(ts)) == [1, 2, 3]

        # Empty not allowed
        @test_throws ArgumentError TimeSeriesParameter(Float64[])

        # Construction from range
        ts2 = TimeSeriesParameter(1.0:3.0)
        @test length(ts2) == 3
        @test ts2[2] == 2.0
    end
end
