# Test types for "Interface function errors"
struct TestState <: AbstractState end
struct TestPolicy <: AbstractPolicy end
struct TestConfig <: AbstractConfig end
struct TestSOW <: AbstractSOW end

# Test types for "get_action interface" -> "custom get_action (state-dependent)"
struct InventoryAction <: AbstractAction
    order::Float64
end

struct InventoryPolicy <: AbstractPolicy
    reorder_point::Float64
    order_size::Float64
end

struct InventoryState <: AbstractState
    level::Float64
end

struct DemandSOW <: AbstractSOW
    demand::Float64
end

function SimOptDecisions.get_action(
    policy::InventoryPolicy, state::InventoryState, sow::DemandSOW, t::TimeStep
)
    if state.level < policy.reorder_point
        return InventoryAction(policy.order_size)
    else
        return InventoryAction(0.0)
    end
end

# Test types for "get_action interface" -> "get_action with nothing state"
struct StatelessAction <: AbstractAction
    action_value::Float64
end

struct StatelessPolicy <: AbstractPolicy
    multiplier::Float64
end

struct InfoSOW <: AbstractSOW
    base_value::Float64
end

function SimOptDecisions.get_action(
    policy::StatelessPolicy, state::Nothing, sow::InfoSOW, t::TimeStep
)
    return StatelessAction(sow.base_value * policy.multiplier * t.t)
end

# Test types for "get_action interface" -> "get_action for static policy"
struct ElevationAction <: AbstractAction
    elevation::Float64
end

struct StaticElevationPolicy <: AbstractPolicy
    elevation_ft::Float64
end

struct FloodSOW <: AbstractSOW end

function SimOptDecisions.get_action(
    policy::StaticElevationPolicy, state, sow::FloodSOW, t::TimeStep
)
    return ElevationAction(policy.elevation_ft)
end

# Test types for "Direct simulate (non-time-stepped)"
struct AnalyticalConfig <: AbstractConfig
    multiplier::Float64
end

struct AnalyticalSOW <: AbstractSOW
    value::Float64
end

struct AnalyticalPolicy <: AbstractPolicy
    factor::Float64
end

function SimOptDecisions.simulate(
    config::AnalyticalConfig,
    sow::AnalyticalSOW,
    policy::AnalyticalPolicy,
    recorder::AbstractRecorder,
    rng::AbstractRNG,
)
    return (result=(config.multiplier * sow.value * policy.factor),)
end

# Test types for "Time-stepped simulation (simple for loop)"
struct CounterAction <: AbstractAction
    increment::Int
end

struct CounterState <: AbstractState
    value::Int
end

struct IncrementPolicy <: AbstractPolicy
    increment::Int
end

struct CounterConfig <: AbstractConfig
    n_steps::Int
end

struct EmptySOW <: AbstractSOW end

function SimOptDecisions.simulate(
    config::CounterConfig,
    sow::EmptySOW,
    policy::IncrementPolicy,
    recorder::AbstractRecorder,
    rng::AbstractRNG,
)
    state = CounterState(0)
    action = CounterAction(policy.increment)
    record!(recorder, state, nothing, nothing, nothing)

    for ts in SimOptDecisions.Utils.timeindex(1:config.n_steps)
        state = CounterState(state.value + policy.increment)
        record!(recorder, state, (increment=policy.increment,), ts.val, action)
    end

    return (final_value=state.value,)
end

# Test types for "Type stability"
struct SimTSCounterAction <: AbstractAction
    increment::Float64
end

struct SimTSCounterState <: AbstractState
    value::Float64
end

struct SimTSIncrementPolicy <: AbstractPolicy
    increment::Float64
end

struct SimTSCounterConfig <: AbstractConfig end
struct SimTSEmptySOW <: AbstractSOW end

function SimOptDecisions.simulate(
    config::SimTSCounterConfig,
    sow::SimTSEmptySOW,
    policy::SimTSIncrementPolicy,
    recorder::AbstractRecorder,
    rng::AbstractRNG,
)
    state = SimTSCounterState(0.0)
    action = SimTSCounterAction(policy.increment)
    record!(recorder, state, nothing, nothing, nothing)

    for ts in SimOptDecisions.Utils.timeindex(1:10)
        state = SimTSCounterState(state.value + policy.increment)
        record!(recorder, state, (increment=policy.increment,), ts.val, action)
    end

    return (final_value=state.value,)
end

# Test types for "Early termination"
struct TermState <: AbstractState
    value::Int
end

struct TermPolicy <: AbstractPolicy end
struct TermConfig <: AbstractConfig end
struct TermSOW <: AbstractSOW end

function SimOptDecisions.simulate(
    config::TermConfig,
    sow::TermSOW,
    policy::TermPolicy,
    recorder::AbstractRecorder,
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

# ============================================================================
# Tests
# ============================================================================

@testset "Simulation" begin
    @testset "Interface function errors" begin
        config = TestConfig()
        sow = TestSOW()
        policy = TestPolicy()
        rng = Random.Xoshiro(42)

        # simulate calls run_simulation by default,
        # which throws MethodError for time_axis (no fallback implementation)
        @test_throws MethodError simulate(config, sow, policy, rng)

        # get_action should throw helpful error if not implemented
        ts = TimeStep(1, 1, false)
        @test_throws ArgumentError get_action(policy, TestState(), sow, ts)
    end

    @testset "get_action interface" begin
        @testset "custom get_action (state-dependent)" begin
            policy = InventoryPolicy(10.0, 50.0)
            sow = DemandSOW(5.0)
            ts = TimeStep(1, 1, false)

            # Low inventory -> order
            low_state = InventoryState(5.0)
            action_low = get_action(policy, low_state, sow, ts)
            @test action_low isa AbstractAction
            @test action_low.order == 50.0

            # High inventory -> no order
            high_state = InventoryState(15.0)
            action_high = get_action(policy, high_state, sow, ts)
            @test action_high.order == 0.0
        end

        @testset "get_action with nothing state" begin
            policy = StatelessPolicy(2.0)
            sow = InfoSOW(10.0)
            ts = TimeStep(3, 3, false)

            action = get_action(policy, nothing, sow, ts)
            @test action isa AbstractAction
            @test action.action_value == 60.0  # 10 * 2 * 3
        end

        @testset "get_action for static policy" begin
            policy = StaticElevationPolicy(8.0)
            sow = FloodSOW()
            ts = TimeStep(1, 1, false)

            action = get_action(policy, nothing, sow, ts)
            @test action isa AbstractAction
            @test action.elevation == 8.0
        end
    end

    @testset "Direct simulate (non-time-stepped)" begin
        config = AnalyticalConfig(2.0)
        sow = AnalyticalSOW(3.0)
        policy = AnalyticalPolicy(4.0)

        result = simulate(config, sow, policy, Random.Xoshiro(42))
        @test result.result == 24.0  # 2.0 * 3.0 * 4.0
    end

    @testset "Time-stepped simulation (simple for loop)" begin
        # Run simulation
        config = CounterConfig(10)
        sow = EmptySOW()
        policy = IncrementPolicy(5)

        result = simulate(config, sow, policy, Random.Xoshiro(42))
        @test result.final_value == 50  # 10 steps * 5 increment

        # With recorder
        builder = TraceRecorderBuilder()
        result2 = simulate(config, sow, policy, builder, Random.Xoshiro(42))
        trace = build_trace(builder)

        @test result2.final_value == 50
        @test length(trace.states) == 10
        @test trace.states[end].value == 50
        @test trace.times == collect(1:10)

        # With explicit RNG
        rng = Random.Xoshiro(42)
        result3 = simulate(config, sow, policy, rng)
        @test result3.final_value == 50
    end

    @testset "Type stability" begin
        config = SimTSCounterConfig()
        sow = SimTSEmptySOW()
        policy = SimTSIncrementPolicy(1.0)
        rng = Random.Xoshiro(42)

        # Test type inference for simulate
        @test @inferred(simulate(config, sow, policy, NoRecorder(), rng)) isa NamedTuple

        # Test basic functionality
        result = simulate(config, sow, policy, rng)
        @test result.final_value == 10.0
    end

    @testset "Early termination" begin
        config = TermConfig()
        sow = TermSOW()
        policy = TermPolicy()

        result = simulate(config, sow, policy, Random.Xoshiro(42))
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
        @test SimOptDecisions.Utils.discount_factor(0.10, 1) ≈ 1 / 1.10
        @test SimOptDecisions.Utils.discount_factor(0.10, 2) ≈ 1 / 1.10^2
        @test SimOptDecisions.Utils.discount_factor(0.10, 10) ≈ 1 / 1.10^10

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
end
