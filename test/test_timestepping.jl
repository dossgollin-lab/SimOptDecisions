# Test types for "Callbacks" -> "Interface function errors"
struct TSTestConfig <: AbstractConfig end
struct TSTestSOW <: AbstractSOW end
struct TSTestPolicy <: AbstractPolicy end
struct TSTestAction <: AbstractAction end

# Test types for "Callbacks" -> "Stateful counter model"
struct TSCounterAction <: AbstractAction
    increment::Int
end

struct TSCounterState <: AbstractState
    value::Int
end

struct TSCounterConfig <: AbstractConfig
    n_steps::Int
end

struct TSCounterSOW <: AbstractSOW end

struct TSIncrementPolicy <: AbstractPolicy
    increment::Int
end

function SimOptDecisions.initialize(::TSCounterConfig, ::TSCounterSOW, ::AbstractRNG)
    return TSCounterState(0)
end

function SimOptDecisions.get_action(
    policy::TSIncrementPolicy, state::TSCounterState, sow::TSCounterSOW, t::TimeStep
)
    return TSCounterAction(policy.increment)
end

function SimOptDecisions.run_timestep(
    state::TSCounterState,
    action::TSCounterAction,
    sow::TSCounterSOW,
    config::TSCounterConfig,
    t::TimeStep,
    ::AbstractRNG,
)
    new_state = TSCounterState(state.value + action.increment)
    return (new_state, action.increment)  # step_record is the increment
end

function SimOptDecisions.time_axis(config::TSCounterConfig, ::TSCounterSOW)
    return 1:config.n_steps
end

function SimOptDecisions.finalize(
    final_state::TSCounterState,
    step_records::Vector,
    config::TSCounterConfig,
    sow::TSCounterSOW,
)
    return (final_value=final_state.value, total_increments=sum(step_records))
end

# Test types for "Callbacks" -> "Stateless model"
struct TSStatelessAction <: AbstractAction
    multiplied_value::Float64
end

struct TSStatelessConfig <: AbstractConfig
    horizon::Int
end

struct TSStatelessSOW <: AbstractSOW
    multiplier::Float64
end

struct TSStatelessPolicy <: AbstractPolicy
    base::Float64
end

function SimOptDecisions.initialize(::TSStatelessConfig, ::TSStatelessSOW, ::AbstractRNG)
    return nothing
end

function SimOptDecisions.get_action(
    policy::TSStatelessPolicy, state::Nothing, sow::TSStatelessSOW, t::TimeStep
)
    return TSStatelessAction(policy.base * sow.multiplier * t.t)
end

function SimOptDecisions.run_timestep(
    state::Nothing,
    action::TSStatelessAction,
    sow::TSStatelessSOW,
    config::TSStatelessConfig,
    t::TimeStep,
    ::AbstractRNG,
)
    return (nothing, action.multiplied_value)
end

function SimOptDecisions.time_axis(config::TSStatelessConfig, ::TSStatelessSOW)
    return 1:config.horizon
end

function SimOptDecisions.finalize(
    ::Nothing, step_records::Vector, config::TSStatelessConfig, sow::TSStatelessSOW
)
    return (total=sum(step_records),)
end

# Test types for "Callbacks" -> "NamedTuple step record"
struct TSNTAction <: AbstractAction end

struct TSNTConfig <: AbstractConfig
    horizon::Int
end

struct TSNTsow <: AbstractSOW
    damage_rate::Float64
    cost_rate::Float64
end

struct TSNTPolicy <: AbstractPolicy end

function SimOptDecisions.initialize(::TSNTConfig, ::TSNTsow, ::AbstractRNG)
    return nothing
end

function SimOptDecisions.get_action(::TSNTPolicy, ::Nothing, ::TSNTsow, ::TimeStep)
    return TSNTAction()
end

function SimOptDecisions.run_timestep(
    state::Nothing,
    action::TSNTAction,
    sow::TSNTsow,
    config::TSNTConfig,
    t::TimeStep,
    ::AbstractRNG,
)
    damage = sow.damage_rate * t.t
    cost = sow.cost_rate * t.t
    return (nothing, (damage=damage, cost=cost))
end

function SimOptDecisions.time_axis(config::TSNTConfig, ::TSNTsow)
    return 1:config.horizon
end

function SimOptDecisions.finalize(
    ::Nothing, step_records::Vector, config::TSNTConfig, sow::TSNTsow
)
    total_damage = sum(o.damage for o in step_records)
    total_cost = sum(o.cost for o in step_records)
    return (total_damage=total_damage, total_cost=total_cost)
end

# Test types for "Callbacks" -> "Framework calls get_action"
struct TSActionAction <: AbstractAction
    invest::Float64
end

struct TSActionState <: AbstractState
    level::Float64
end

struct TSActionConfig <: AbstractConfig
    horizon::Int
end

struct TSActionSOW <: AbstractSOW
    growth_rate::Float64
end

struct TSActionPolicy <: AbstractPolicy
    invest_fraction::Float64
end

function SimOptDecisions.get_action(
    policy::TSActionPolicy, state::TSActionState, sow::TSActionSOW, t::TimeStep
)
    return TSActionAction(state.level * policy.invest_fraction)
end

function SimOptDecisions.initialize(::TSActionConfig, ::TSActionSOW, ::AbstractRNG)
    return TSActionState(100.0)  # Start with 100
end

function SimOptDecisions.run_timestep(
    state::TSActionState,
    action::TSActionAction,
    sow::TSActionSOW,
    config::TSActionConfig,
    t::TimeStep,
    ::AbstractRNG,
)
    # Action is passed by framework, not computed here
    # Transition: growth from rate + investment
    growth = state.level * sow.growth_rate + action.invest
    new_level = state.level + growth
    new_state = TSActionState(new_level)

    return (new_state, growth)  # step_record is growth this step
end

function SimOptDecisions.time_axis(config::TSActionConfig, ::TSActionSOW)
    return 1:config.horizon
end

function SimOptDecisions.finalize(
    final_state::TSActionState,
    step_records::Vector,
    config::TSActionConfig,
    sow::TSActionSOW,
)
    return (final_level=final_state.level, total_growth=sum(step_records))
end

# Test types for "Callbacks" -> "Recording support"
struct TSRecordAction <: AbstractAction end

struct TSRecordState <: AbstractState
    value::Float64
end

struct TSRecordConfig <: AbstractConfig
    horizon::Int
end

struct TSRecordSOW <: AbstractSOW end
struct TSRecordPolicy <: AbstractPolicy end

function SimOptDecisions.initialize(::TSRecordConfig, ::TSRecordSOW, ::AbstractRNG)
    return TSRecordState(0.0)
end

function SimOptDecisions.get_action(
    ::TSRecordPolicy, ::TSRecordState, ::TSRecordSOW, ::TimeStep
)
    return TSRecordAction()
end

function SimOptDecisions.run_timestep(
    state::TSRecordState,
    action::TSRecordAction,
    sow::TSRecordSOW,
    config::TSRecordConfig,
    t::TimeStep,
    ::AbstractRNG,
)
    new_state = TSRecordState(state.value + 1.0)
    return (new_state, state.value)
end

function SimOptDecisions.time_axis(config::TSRecordConfig, ::TSRecordSOW)
    return 1:config.horizon
end

function SimOptDecisions.finalize(
    final_state::TSRecordState,
    step_records::Vector,
    config::TSRecordConfig,
    sow::TSRecordSOW,
)
    return (final_value=final_state.value,)
end

# Test types for "Callbacks" -> "Type stability"
struct TSTypeAction <: AbstractAction end

struct TSTypeConfig <: AbstractConfig end
struct TSTypeSOW <: AbstractSOW end
struct TSTypePolicy <: AbstractPolicy end

function SimOptDecisions.initialize(::TSTypeConfig, ::TSTypeSOW, ::AbstractRNG)
    return 0.0
end

function SimOptDecisions.get_action(::TSTypePolicy, ::Float64, ::TSTypeSOW, ::TimeStep)
    return TSTypeAction()
end

function SimOptDecisions.run_timestep(
    state::Float64,
    action::TSTypeAction,
    sow::TSTypeSOW,
    config::TSTypeConfig,
    t::TimeStep,
    ::AbstractRNG,
)
    return (state + 1.0, state)
end

function SimOptDecisions.time_axis(::TSTypeConfig, ::TSTypeSOW)
    return 1:5
end

function SimOptDecisions.finalize(
    final_state::Float64, step_records::Vector{Float64}, ::TSTypeConfig, ::TSTypeSOW
)
    return (final=final_state, sum=sum(step_records))
end

# Test types for "Callbacks" -> "SOW-dependent finalize"
struct TSDiscountAction <: AbstractAction end

struct TSDiscountConfig <: AbstractConfig
    horizon::Int
end

struct TSDiscountSOW <: AbstractSOW
    discount_rate::Float64
end

struct TSDiscountPolicy <: AbstractPolicy end

function SimOptDecisions.initialize(::TSDiscountConfig, ::TSDiscountSOW, ::AbstractRNG)
    return nothing
end

function SimOptDecisions.get_action(
    ::TSDiscountPolicy, ::Nothing, ::TSDiscountSOW, ::TimeStep
)
    return TSDiscountAction()
end

function SimOptDecisions.run_timestep(
    state::Nothing,
    action::TSDiscountAction,
    sow::TSDiscountSOW,
    config::TSDiscountConfig,
    t::TimeStep,
    ::AbstractRNG,
)
    damage = 100.0  # Constant damage each year
    return (nothing, damage)
end

function SimOptDecisions.time_axis(config::TSDiscountConfig, ::TSDiscountSOW)
    return 1:config.horizon
end

function SimOptDecisions.finalize(
    ::Nothing, damages::Vector, config::TSDiscountConfig, sow::TSDiscountSOW
)
    # Discount using SOW's discount rate
    npv = sum(
        damages[t] * SimOptDecisions.Utils.discount_factor(sow.discount_rate, t) for
        t in eachindex(damages)
    )
    return (npv_damages=npv, annual_damages=damages)
end

# Test types for "Callbacks" -> "Auto-connection to simulate"
struct TSConnectAction <: AbstractAction end

struct TSConnectState <: AbstractState
    count::Int
end

struct TSConnectConfig <: AbstractConfig
    steps::Int
end

struct TSConnectSOW <: AbstractSOW end
struct TSConnectPolicy <: AbstractPolicy end

function SimOptDecisions.initialize(::TSConnectConfig, ::TSConnectSOW, ::AbstractRNG)
    return TSConnectState(0)
end

function SimOptDecisions.get_action(
    ::TSConnectPolicy, ::TSConnectState, ::TSConnectSOW, ::TimeStep
)
    return TSConnectAction()
end

function SimOptDecisions.run_timestep(
    state::TSConnectState,
    action::TSConnectAction,
    sow::TSConnectSOW,
    config::TSConnectConfig,
    t::TimeStep,
    ::AbstractRNG,
)
    return (TSConnectState(state.count + 1), state.count)
end

function SimOptDecisions.time_axis(config::TSConnectConfig, ::TSConnectSOW)
    return 1:config.steps
end

function SimOptDecisions.finalize(
    final_state::TSConnectState,
    step_records::Vector,
    config::TSConnectConfig,
    sow::TSConnectSOW,
)
    return (final_count=final_state.count,)
end

# ============================================================================
# Tests
# ============================================================================

@testset "Callbacks" begin
    @testset "Interface function errors" begin
        config = TSTestConfig()
        sow = TSTestSOW()
        policy = TSTestPolicy()
        rng = Random.Xoshiro(42)
        ts = TimeStep(1, 1)
        action = TSTestAction()

        # run_timestep should throw MethodError if not implemented
        @test_throws MethodError SimOptDecisions.run_timestep(
            nothing, action, sow, config, ts, rng
        )

        # time_axis should throw MethodError if not implemented
        @test_throws MethodError SimOptDecisions.time_axis(config, sow)

        # initialize should throw ArgumentError if not implemented
        @test_throws ArgumentError SimOptDecisions.initialize(config, sow, rng)

        # finalize should throw ArgumentError if not implemented
        @test_throws ArgumentError SimOptDecisions.finalize(nothing, [], config, sow)
    end

    @testset "Stateful counter model" begin
        config = TSCounterConfig(10)
        sow = TSCounterSOW()
        policy = TSIncrementPolicy(5)
        rng = Random.Xoshiro(42)

        result = SimOptDecisions.run_simulation(config, sow, policy, rng)

        @test result.final_value == 50  # 10 steps * 5 increment
        @test result.total_increments == 50
    end

    @testset "Stateless model (nothing state)" begin
        config = TSStatelessConfig(5)
        sow = TSStatelessSOW(2.0)
        policy = TSStatelessPolicy(10.0)
        rng = Random.Xoshiro(42)

        result = SimOptDecisions.run_simulation(config, sow, policy, rng)

        # 10 * 2 * (1+2+3+4+5) = 20 * 15 = 300
        @test result.total == 300.0
    end

    @testset "NamedTuple step record" begin
        config = TSNTConfig(4)
        sow = TSNTsow(10.0, 2.0)
        policy = TSNTPolicy()
        rng = Random.Xoshiro(42)

        result = SimOptDecisions.run_simulation(config, sow, policy, rng)

        # damage: 10*(1+2+3+4) = 100, cost: 2*(1+2+3+4) = 20
        @test result.total_damage == 100.0
        @test result.total_cost == 20.0
    end

    @testset "Framework calls get_action" begin
        config = TSActionConfig(3)
        sow = TSActionSOW(0.05)  # 5% growth rate
        policy = TSActionPolicy(0.10)  # 10% investment
        rng = Random.Xoshiro(42)

        result = SimOptDecisions.run_simulation(config, sow, policy, rng)

        # Starting at 100, each step: growth = level * 0.05 + level * 0.10 = level * 0.15
        # Step 1: level=100, growth=15, new_level=115
        # Step 2: level=115, growth=17.25, new_level=132.25
        # Step 3: level=132.25, growth=19.8375, new_level=152.0875
        @test result.final_level ≈ 100 * 1.15^3 atol = 1e-10
        @test result.total_growth ≈ result.final_level - 100 atol = 1e-10
    end

    @testset "Recording support" begin
        config = TSRecordConfig(5)
        sow = TSRecordSOW()
        policy = TSRecordPolicy()
        rng = Random.Xoshiro(42)

        # Test with TraceRecorderBuilder (using method overload, not kwargs)
        builder = TraceRecorderBuilder()
        result = SimOptDecisions.run_simulation(config, sow, policy, builder, rng)

        # Should have recorded 5 timesteps (excluding initial state)
        trace = build_trace(builder)
        @test length(trace.states) == 5
        @test trace.times == [1, 2, 3, 4, 5]
        @test trace.states[end].value == 5.0
        @test all(a -> a isa TSRecordAction, trace.actions)

        # Test with NoRecorder (should work without error)
        result2 = SimOptDecisions.run_simulation(config, sow, policy, rng)
        @test result2 == result  # Same result with or without recorder
    end

    @testset "Type stability" begin
        config = TSTypeConfig()
        sow = TSTypeSOW()
        policy = TSTypePolicy()
        rng = Random.Xoshiro(42)

        # Test type inference
        result = @inferred SimOptDecisions.run_simulation(config, sow, policy, rng)
        @test result.final == 5.0
        @test result.sum == 10.0  # 0+1+2+3+4
    end

    @testset "SOW-dependent finalize (discounting)" begin
        config = TSDiscountConfig(3)
        sow = TSDiscountSOW(0.10)  # 10% discount rate
        policy = TSDiscountPolicy()
        rng = Random.Xoshiro(42)

        result = SimOptDecisions.run_simulation(config, sow, policy, rng)

        # NPV = 100/1.10 + 100/1.10^2 + 100/1.10^3
        expected_npv = 100 / 1.10 + 100 / 1.10^2 + 100 / 1.10^3
        @test result.npv_damages ≈ expected_npv atol = 1e-10
        @test result.annual_damages == [100.0, 100.0, 100.0]
    end

    @testset "Auto-connection to simulate" begin
        # No need to implement simulate() - it auto-calls run_simulation!
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

        # Integer indexing
        @test ts[1] == 1.0
        @test ts[2] == 2.0
        @test ts[3] == 3.0

        # TimeStep indexing
        @test ts[TimeStep(1, 2020)] == 1.0
        @test ts[TimeStep(2, 2021)] == 2.0
        @test ts[TimeStep(3, 2022)] == 3.0

        # Bounds errors
        @test_throws TimeSeriesParameterBoundsError ts[0]
        @test_throws TimeSeriesParameterBoundsError ts[4]

        # Iteration
        @test collect(ts) == [1.0, 2.0, 3.0]

        # Empty not allowed
        @test_throws ArgumentError TimeSeriesParameter(Float64[])

        # Construction from range
        ts2 = TimeSeriesParameter(1.0:3.0)
        @test length(ts2) == 3
        @test ts2[2] == 2.0
    end
end
