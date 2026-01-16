using Tables

# ============================================================================
# Test Types with Parameter Fields
# ============================================================================

struct ExploreTestConfig <: AbstractConfig
    n_steps::Int
end

struct ExploreTestScenario{T<:AbstractFloat} <: AbstractScenario
    x::ContinuousParameter{T}
    scenario::CategoricalParameter{Symbol}
end

struct ExploreTestPolicy{T<:AbstractFloat} <: AbstractPolicy
    threshold::ContinuousParameter{T}
end

struct ExploreTestState{T<:AbstractFloat} <: AbstractState
    value::T
end

struct ExploreTestAction <: AbstractAction end

struct ExploreTestOutcome{T<:AbstractFloat}
    total::ContinuousParameter{T}
    count::DiscreteParameter{Int}
end

# Implement callbacks
SimOptDecisions.time_axis(config::ExploreTestConfig, scenario::ExploreTestScenario) = 1:config.n_steps

function SimOptDecisions.initialize(
    config::ExploreTestConfig, scenario::ExploreTestScenario, rng::AbstractRNG
)
    ExploreTestState(0.0)
end

function SimOptDecisions.get_action(
    policy::ExploreTestPolicy, state::ExploreTestState, t::TimeStep, scenario::ExploreTestScenario
)
    ExploreTestAction()
end

function SimOptDecisions.run_timestep(
    state::ExploreTestState,
    action::ExploreTestAction,
    t::TimeStep,
    config::ExploreTestConfig,
    scenario::ExploreTestScenario,
    rng::AbstractRNG,
)
    new_val = state.value + scenario.x.value
    return ExploreTestState(new_val), (step_value=new_val,)
end

function SimOptDecisions.compute_outcome(
    step_records, config::ExploreTestConfig, scenario::ExploreTestScenario
)
    ExploreTestOutcome(
        ContinuousParameter(step_records[end].step_value), DiscreteParameter(length(step_records))
    )
end

# ============================================================================
# Tests
# ============================================================================

@testset "Exploration" begin
    @testset "Flattening" begin
        scenario = ExploreTestScenario(
            ContinuousParameter(1.5), CategoricalParameter(:high, [:low, :high])
        )

        nt = SimOptDecisions._flatten_to_namedtuple(scenario, :scenario)
        @test nt.scenario_x == 1.5
        @test nt.scenario_scenario == :high
    end

    @testset "TimeSeriesParameter flattening" begin
        struct TSScenario <: AbstractScenario
            demand::TimeSeriesParameter{Float64,Int}
        end

        # With explicit time_axis, column names use the time values
        scenario = TSScenario(TimeSeriesParameter(2020:2022, [1.0, 2.0, 3.0]))
        nt = SimOptDecisions._flatten_to_namedtuple(scenario, :scenario)

        @test nt[Symbol("scenario_demand[2020]")] == 1.0
        @test nt[Symbol("scenario_demand[2021]")] == 2.0
        @test nt[Symbol("scenario_demand[2022]")] == 3.0
    end

    @testset "Validation errors" begin
        struct BadScenario <: AbstractScenario
            x::Float64  # not a parameter type!
        end

        struct GoodPolicy{T} <: AbstractPolicy
            p::ContinuousParameter{T}
        end

        struct GoodOutcome{T}
            v::ContinuousParameter{T}
        end

        @test_throws ExploratoryInterfaceError begin
            SimOptDecisions._validate_exploratory_interface(
                BadScenario, GoodPolicy{Float64}, GoodOutcome{Float64}
            )
        end
    end

    @testset "explore() basic" begin
        config = ExploreTestConfig(3)
        scenarios = [
            ExploreTestScenario(
                ContinuousParameter(1.0), CategoricalParameter(:low, [:low, :high])
            ),
            ExploreTestScenario(
                ContinuousParameter(2.0), CategoricalParameter(:high, [:low, :high])
            ),
        ]
        policies = [
            ExploreTestPolicy(ContinuousParameter(0.5)),
            ExploreTestPolicy(ContinuousParameter(0.8)),
        ]

        result = explore(config, scenarios, policies; progress=false)

        @test size(result) == (2, 2)  # 2 policies × 2 scenarios
        @test length(result) == 4

        # Check indexing
        @test result[1, 1].policy_idx == 1
        @test result[1, 1].scenario_idx == 1
        @test result[2, 2].policy_idx == 2
        @test result[2, 2].scenario_idx == 2

        # Check flattened columns exist
        @test :policy_threshold in keys(result[1, 1])
        @test :scenario_x in keys(result[1, 1])
        @test :outcome_total in keys(result[1, 1])

        # Check outcome values make sense
        # policy 1 (threshold=0.5), scenario 1 (x=1.0): 3 steps → total = 3.0
        @test result[1, 1].outcome_total == 3.0
        @test result[1, 1].outcome_count == 3

        # policy 1 (threshold=0.5), scenario 2 (x=2.0): 3 steps → total = 6.0
        @test result[1, 2].outcome_total == 6.0
    end

    @testset "Tables.jl compatibility" begin
        config = ExploreTestConfig(3)
        scenarios = [
            ExploreTestScenario(
                ContinuousParameter(1.0), CategoricalParameter(:low, [:low, :high])
            ),
        ]
        policies = [ExploreTestPolicy(ContinuousParameter(0.5))]

        result = explore(config, scenarios, policies; progress=false)

        @test Tables.istable(result)
        @test Tables.rowaccess(typeof(result))

        # Should be convertible to any Tables.jl sink
        rows = collect(Tables.rows(result))
        @test length(rows) == 1

        # Schema should be available
        schema = Tables.schema(result)
        @test schema !== nothing
    end

    @testset "ExplorationResult accessors" begin
        config = ExploreTestConfig(3)
        scenarios = [
            ExploreTestScenario(
                ContinuousParameter(1.0), CategoricalParameter(:low, [:low, :high])
            ),
            ExploreTestScenario(
                ContinuousParameter(2.0), CategoricalParameter(:high, [:low, :high])
            ),
        ]
        policies = [
            ExploreTestPolicy(ContinuousParameter(0.5)),
            ExploreTestPolicy(ContinuousParameter(0.8)),
        ]

        result = explore(config, scenarios, policies; progress=false)

        # outcomes_for_policy
        pol1_outcomes = outcomes_for_policy(result, 1)
        @test length(pol1_outcomes) == 2
        @test all(r.policy_idx == 1 for r in pol1_outcomes)

        # outcomes_for_scenario
        scenario1_outcomes = outcomes_for_scenario(result, 1)
        @test length(scenario1_outcomes) == 2
        @test all(r.scenario_idx == 1 for r in scenario1_outcomes)

        # filter
        filtered = filter(r -> r.policy_idx == 1, result)
        @test length(filtered) == 2

        # Column categorization
        @test :policy_threshold in result.policy_columns
        @test :scenario_x in result.scenario_columns
        @test :outcome_total in result.outcome_columns
    end

    @testset "Sinks" begin
        @testset "InMemorySink" begin
            sink = InMemorySink()
            record!(sink, (a=1, b=2))
            record!(sink, (a=3, b=4))
            @test length(sink.results) == 2
        end

        @testset "NoSink" begin
            sink = NoSink()
            record!(sink, (a=1,))
            @test finalize(sink, 1, 1) === nothing
        end
    end

    @testset "Single policy convenience" begin
        config = ExploreTestConfig(3)
        scenarios = [
            ExploreTestScenario(
                ContinuousParameter(1.0), CategoricalParameter(:low, [:low, :high])
            ),
        ]
        policy = ExploreTestPolicy(ContinuousParameter(0.5))

        result = explore(config, scenarios, policy; progress=false)
        @test size(result) == (1, 1)
    end

    @testset "Empty inputs throw" begin
        config = ExploreTestConfig(3)
        scenarios = ExploreTestScenario{Float64}[]
        policies = [ExploreTestPolicy(ContinuousParameter(0.5))]

        @test_throws ArgumentError explore(config, scenarios, policies; progress=false)
        @test_throws ArgumentError explore(
            config,
            [
                ExploreTestScenario(
                    ContinuousParameter(1.0), CategoricalParameter(:low, [:low, :high])
                ),
            ],
            AbstractPolicy[];
            progress=false,
        )
    end

    @testset "Bounds checking" begin
        config = ExploreTestConfig(3)
        scenarios = [
            ExploreTestScenario(
                ContinuousParameter(1.0), CategoricalParameter(:low, [:low, :high])
            ),
        ]
        policies = [ExploreTestPolicy(ContinuousParameter(0.5))]

        result = explore(config, scenarios, policies; progress=false)

        @test_throws BoundsError result[0, 1]
        @test_throws BoundsError result[1, 0]
        @test_throws BoundsError result[2, 1]
        @test_throws BoundsError result[1, 2]
    end
end
