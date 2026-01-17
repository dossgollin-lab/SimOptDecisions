# Test types for "Callbacks" -> "Interface function errors"
struct TSTestConfig <: AbstractConfig end
struct TSTestScenario <: AbstractScenario end
struct TSTestPolicy <: AbstractPolicy end
struct TSTestAction <: AbstractAction end
struct TSTestState <: AbstractState end

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

struct TSCounterScenario <: AbstractScenario end

struct TSIncrementPolicy <: AbstractPolicy
    increment::Int
end

function SimOptDecisions.initialize(::TSCounterConfig, ::TSCounterScenario, ::AbstractRNG)
    return TSCounterState(0)
end

function SimOptDecisions.get_action(
    policy::TSIncrementPolicy,
    state::TSCounterState,
    t::TimeStep,
    scenario::TSCounterScenario,
)
    return TSCounterAction(policy.increment)
end

function SimOptDecisions.run_timestep(
    state::TSCounterState,
    action::TSCounterAction,
    t::TimeStep,
    config::TSCounterConfig,
    scenario::TSCounterScenario,
    ::AbstractRNG,
)
    new_state = TSCounterState(state.value + action.increment)
    return (new_state, (increment=action.increment, final_value=new_state.value))
end

function SimOptDecisions.time_axis(config::TSCounterConfig, ::TSCounterScenario)
    return 1:config.n_steps
end

function SimOptDecisions.compute_outcome(
    step_records::Vector, config::TSCounterConfig, scenario::TSCounterScenario
)
    # Access final state from last step_record
    return (
        final_value=step_records[end].final_value,
        total_increments=sum(r.increment for r in step_records),
    )
end

# Test types for "Callbacks" -> "Minimal state model"
# (Demonstrates that every model needs explicit state, even if minimal)
struct TSMinimalAction <: AbstractAction
    multiplied_value::Float64
end

struct TSMinimalState <: AbstractState end  # Minimal state - just a marker

struct TSMinimalConfig <: AbstractConfig
    horizon::Int
end

struct TSMinimalScenario <: AbstractScenario
    multiplier::Float64
end

struct TSMinimalPolicy <: AbstractPolicy
    base::Float64
end

function SimOptDecisions.initialize(::TSMinimalConfig, ::TSMinimalScenario, ::AbstractRNG)
    return TSMinimalState()
end

function SimOptDecisions.get_action(
    policy::TSMinimalPolicy, state::TSMinimalState, t::TimeStep, scenario::TSMinimalScenario
)
    return TSMinimalAction(policy.base * scenario.multiplier * t.t)
end

function SimOptDecisions.run_timestep(
    state::TSMinimalState,
    action::TSMinimalAction,
    t::TimeStep,
    config::TSMinimalConfig,
    scenario::TSMinimalScenario,
    ::AbstractRNG,
)
    return (state, action.multiplied_value)
end

function SimOptDecisions.time_axis(config::TSMinimalConfig, ::TSMinimalScenario)
    return 1:config.horizon
end

function SimOptDecisions.compute_outcome(
    step_records::Vector, config::TSMinimalConfig, scenario::TSMinimalScenario
)
    return (total=sum(step_records),)
end

# Test types for "Callbacks" -> "NamedTuple step record"
struct TSNTAction <: AbstractAction end
struct TSNTState <: AbstractState end

struct TSNTConfig <: AbstractConfig
    horizon::Int
end

struct TSNTScenario <: AbstractScenario
    damage_rate::Float64
    cost_rate::Float64
end

struct TSNTPolicy <: AbstractPolicy end

function SimOptDecisions.initialize(::TSNTConfig, ::TSNTScenario, ::AbstractRNG)
    return TSNTState()
end

function SimOptDecisions.get_action(::TSNTPolicy, ::TSNTState, ::TimeStep, ::TSNTScenario)
    return TSNTAction()
end

function SimOptDecisions.run_timestep(
    state::TSNTState,
    action::TSNTAction,
    t::TimeStep,
    config::TSNTConfig,
    scenario::TSNTScenario,
    ::AbstractRNG,
)
    damage = scenario.damage_rate * t.t
    cost = scenario.cost_rate * t.t
    return (state, (damage=damage, cost=cost))
end

function SimOptDecisions.time_axis(config::TSNTConfig, ::TSNTScenario)
    return 1:config.horizon
end

function SimOptDecisions.compute_outcome(
    step_records::Vector, config::TSNTConfig, scenario::TSNTScenario
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

struct TSActionScenario <: AbstractScenario
    growth_rate::Float64
end

struct TSActionPolicy <: AbstractPolicy
    invest_fraction::Float64
end

function SimOptDecisions.get_action(
    policy::TSActionPolicy, state::TSActionState, t::TimeStep, scenario::TSActionScenario
)
    return TSActionAction(state.level * policy.invest_fraction)
end

function SimOptDecisions.initialize(::TSActionConfig, ::TSActionScenario, ::AbstractRNG)
    return TSActionState(100.0)  # Start with 100
end

function SimOptDecisions.run_timestep(
    state::TSActionState,
    action::TSActionAction,
    t::TimeStep,
    config::TSActionConfig,
    scenario::TSActionScenario,
    ::AbstractRNG,
)
    growth = state.level * scenario.growth_rate + action.invest
    new_level = state.level + growth
    new_state = TSActionState(new_level)
    return (new_state, (growth=growth, final_level=new_level))
end

function SimOptDecisions.time_axis(config::TSActionConfig, ::TSActionScenario)
    return 1:config.horizon
end

function SimOptDecisions.compute_outcome(
    step_records::Vector, config::TSActionConfig, scenario::TSActionScenario
)
    return (
        final_level=step_records[end].final_level,
        total_growth=sum(r.growth for r in step_records),
    )
end

# Test types for "Callbacks" -> "Recording support"
struct TSRecordAction <: AbstractAction end

struct TSRecordState <: AbstractState
    value::Float64
end

struct TSRecordConfig <: AbstractConfig
    horizon::Int
end

struct TSRecordScenario <: AbstractScenario end
struct TSRecordPolicy <: AbstractPolicy end

function SimOptDecisions.initialize(::TSRecordConfig, ::TSRecordScenario, ::AbstractRNG)
    return TSRecordState(0.0)
end

function SimOptDecisions.get_action(
    ::TSRecordPolicy, ::TSRecordState, ::TimeStep, ::TSRecordScenario
)
    return TSRecordAction()
end

function SimOptDecisions.run_timestep(
    state::TSRecordState,
    action::TSRecordAction,
    t::TimeStep,
    config::TSRecordConfig,
    scenario::TSRecordScenario,
    ::AbstractRNG,
)
    new_state = TSRecordState(state.value + 1.0)
    # Include final_value in step_record
    return (new_state, (prev_value=state.value, final_value=new_state.value))
end

function SimOptDecisions.time_axis(config::TSRecordConfig, ::TSRecordScenario)
    return 1:config.horizon
end

function SimOptDecisions.compute_outcome(
    step_records::Vector, config::TSRecordConfig, scenario::TSRecordScenario
)
    return (final_value=step_records[end].final_value,)
end

# Test types for "Callbacks" -> "Type stability"
struct TSTypeAction <: AbstractAction end

struct TSTypeState{T<:AbstractFloat} <: AbstractState
    value::T
end

struct TSTypeConfig <: AbstractConfig end
struct TSTypeScenario <: AbstractScenario end
struct TSTypePolicy <: AbstractPolicy end

function SimOptDecisions.initialize(::TSTypeConfig, ::TSTypeScenario, ::AbstractRNG)
    return TSTypeState(0.0)
end

function SimOptDecisions.get_action(
    ::TSTypePolicy, ::TSTypeState, ::TimeStep, ::TSTypeScenario
)
    return TSTypeAction()
end

function SimOptDecisions.run_timestep(
    state::TSTypeState,
    action::TSTypeAction,
    t::TimeStep,
    config::TSTypeConfig,
    scenario::TSTypeScenario,
    ::AbstractRNG,
)
    new_state = TSTypeState(state.value + 1.0)
    return (new_state, (prev_value=state.value, final_value=new_state.value))
end

function SimOptDecisions.time_axis(::TSTypeConfig, ::TSTypeScenario)
    return 1:5
end

function SimOptDecisions.compute_outcome(
    step_records::Vector, ::TSTypeConfig, ::TSTypeScenario
)
    return (
        final=step_records[end].final_value, sum=sum(r.prev_value for r in step_records)
    )
end

# Test types for "Callbacks" -> "Scenario-dependent compute_outcome"
struct TSDiscountAction <: AbstractAction end
struct TSDiscountState <: AbstractState end

struct TSDiscountConfig <: AbstractConfig
    horizon::Int
end

struct TSDiscountScenario <: AbstractScenario
    discount_rate::Float64
end

struct TSDiscountPolicy <: AbstractPolicy end

function SimOptDecisions.initialize(::TSDiscountConfig, ::TSDiscountScenario, ::AbstractRNG)
    return TSDiscountState()
end

function SimOptDecisions.get_action(
    ::TSDiscountPolicy, ::TSDiscountState, ::TimeStep, ::TSDiscountScenario
)
    return TSDiscountAction()
end

function SimOptDecisions.run_timestep(
    state::TSDiscountState,
    action::TSDiscountAction,
    t::TimeStep,
    config::TSDiscountConfig,
    scenario::TSDiscountScenario,
    ::AbstractRNG,
)
    damage = 100.0  # Constant damage each year
    return (state, damage)
end

function SimOptDecisions.time_axis(config::TSDiscountConfig, ::TSDiscountScenario)
    return 1:config.horizon
end

function SimOptDecisions.compute_outcome(
    damages::Vector, config::TSDiscountConfig, scenario::TSDiscountScenario
)
    # Discount using scenario's discount rate
    npv = sum(
        damages[t] * discount_factor(scenario.discount_rate, t) for t in eachindex(damages)
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

struct TSConnectScenario <: AbstractScenario end
struct TSConnectPolicy <: AbstractPolicy end

function SimOptDecisions.initialize(::TSConnectConfig, ::TSConnectScenario, ::AbstractRNG)
    return TSConnectState(0)
end

function SimOptDecisions.get_action(
    ::TSConnectPolicy, ::TSConnectState, ::TimeStep, ::TSConnectScenario
)
    return TSConnectAction()
end

function SimOptDecisions.run_timestep(
    state::TSConnectState,
    action::TSConnectAction,
    t::TimeStep,
    config::TSConnectConfig,
    scenario::TSConnectScenario,
    ::AbstractRNG,
)
    new_state = TSConnectState(state.count + 1)
    return (new_state, (prev_count=state.count, final_count=new_state.count))
end

function SimOptDecisions.time_axis(config::TSConnectConfig, ::TSConnectScenario)
    return 1:config.steps
end

function SimOptDecisions.compute_outcome(
    step_records::Vector, config::TSConnectConfig, scenario::TSConnectScenario
)
    return (final_count=step_records[end].final_count,)
end

# ============================================================================
# Tests
# ============================================================================

@testset "Callbacks" begin
    @testset "Interface function errors" begin
        config = TSTestConfig()
        scenario = TSTestScenario()
        policy = TSTestPolicy()
        rng = Random.Xoshiro(42)
        ts = TimeStep(1, 1)
        action = TSTestAction()
        state = TSTestState()

        # run_timestep should throw ArgumentError if not implemented (via interface_not_implemented)
        @test_throws ArgumentError SimOptDecisions.run_timestep(
            state, action, ts, config, scenario, rng
        )

        # time_axis should throw ArgumentError if not implemented (via interface_not_implemented)
        @test_throws ArgumentError SimOptDecisions.time_axis(config, scenario)

        # initialize should throw ArgumentError if not implemented
        @test_throws ArgumentError SimOptDecisions.initialize(config, scenario, rng)

        # compute_outcome should throw ArgumentError if not implemented
        @test_throws ArgumentError SimOptDecisions.compute_outcome([], config, scenario)
    end

    @testset "Stateful counter model" begin
        config = TSCounterConfig(10)
        scenario = TSCounterScenario()
        policy = TSIncrementPolicy(5)
        rng = Random.Xoshiro(42)

        result = SimOptDecisions.run_simulation(config, scenario, policy, rng)

        @test result.final_value == 50  # 10 steps * 5 increment
        @test result.total_increments == 50
    end

    @testset "Minimal state model" begin
        config = TSMinimalConfig(5)
        scenario = TSMinimalScenario(2.0)
        policy = TSMinimalPolicy(10.0)
        rng = Random.Xoshiro(42)

        result = SimOptDecisions.run_simulation(config, scenario, policy, rng)

        # 10 * 2 * (1+2+3+4+5) = 20 * 15 = 300
        @test result.total == 300.0
    end

    @testset "NamedTuple step record" begin
        config = TSNTConfig(4)
        scenario = TSNTScenario(10.0, 2.0)
        policy = TSNTPolicy()
        rng = Random.Xoshiro(42)

        result = SimOptDecisions.run_simulation(config, scenario, policy, rng)

        # damage: 10*(1+2+3+4) = 100, cost: 2*(1+2+3+4) = 20
        @test result.total_damage == 100.0
        @test result.total_cost == 20.0
    end

    @testset "Framework calls get_action" begin
        config = TSActionConfig(3)
        scenario = TSActionScenario(0.05)  # 5% growth rate
        policy = TSActionPolicy(0.10)  # 10% investment
        rng = Random.Xoshiro(42)

        result = SimOptDecisions.run_simulation(config, scenario, policy, rng)

        # Starting at 100, each step: growth = level * 0.05 + level * 0.10 = level * 0.15
        # Step 1: level=100, growth=15, new_level=115
        # Step 2: level=115, growth=17.25, new_level=132.25
        # Step 3: level=132.25, growth=19.8375, new_level=152.0875
        @test result.final_level ≈ 100 * 1.15^3 atol = 1e-10
        @test result.total_growth ≈ result.final_level - 100 atol = 1e-10
    end

    @testset "Recording support" begin
        config = TSRecordConfig(5)
        scenario = TSRecordScenario()
        policy = TSRecordPolicy()
        rng = Random.Xoshiro(42)

        # Test with TraceRecorderBuilder (using method overload, not kwargs)
        builder = TraceRecorderBuilder()
        result = SimOptDecisions.run_simulation(config, scenario, policy, builder, rng)

        # Should have recorded 5 timesteps (excluding initial state)
        trace = build_trace(builder)
        @test length(trace.states) == 5
        @test trace.times == [1, 2, 3, 4, 5]
        @test trace.states[end].value == 5.0
        @test all(a -> a isa TSRecordAction, trace.actions)

        # Test with NoRecorder (should work without error)
        result2 = SimOptDecisions.run_simulation(config, scenario, policy, rng)
        @test result2 == result  # Same result with or without recorder
    end

    @testset "Type stability" begin
        config = TSTypeConfig()
        scenario = TSTypeScenario()
        policy = TSTypePolicy()
        rng = Random.Xoshiro(42)

        # Test type inference
        result = @inferred SimOptDecisions.run_simulation(config, scenario, policy, rng)
        @test result.final == 5.0
        @test result.sum == 10.0  # 0+1+2+3+4
    end

    @testset "Scenario-dependent compute_outcome (discounting)" begin
        config = TSDiscountConfig(3)
        scenario = TSDiscountScenario(0.10)  # 10% discount rate
        policy = TSDiscountPolicy()
        rng = Random.Xoshiro(42)

        result = SimOptDecisions.run_simulation(config, scenario, policy, rng)

        # NPV = 100/1.10 + 100/1.10^2 + 100/1.10^3
        expected_npv = 100 / 1.10 + 100 / 1.10^2 + 100 / 1.10^3
        @test result.npv_damages ≈ expected_npv atol = 1e-10
        @test result.annual_damages == [100.0, 100.0, 100.0]
    end

    @testset "Auto-connection to simulate" begin
        # No need to implement simulate() - it auto-calls run_simulation!
        # Just test via the main simulate interface
        config = TSConnectConfig(7)
        scenario = TSConnectScenario()
        policy = TSConnectPolicy()

        result = simulate(config, scenario, policy, Random.Xoshiro(42))
        @test result.final_count == 7
    end
end
