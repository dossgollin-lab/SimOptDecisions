using Tables

# ============================================================================
# Test Types with Parameter Fields
# ============================================================================

struct ExploreTestConfig <: AbstractConfig
    n_steps::Int
end

struct ExploreTestSOW{T<:AbstractFloat} <: AbstractSOW
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
SimOptDecisions.time_axis(config::ExploreTestConfig, sow::ExploreTestSOW) = 1:config.n_steps

SimOptDecisions.initialize(config::ExploreTestConfig, sow::ExploreTestSOW, rng::AbstractRNG) =
    ExploreTestState(0.0)

SimOptDecisions.get_action(
    policy::ExploreTestPolicy, state::ExploreTestState,
    sow::ExploreTestSOW, t::TimeStep
) = ExploreTestAction()

function SimOptDecisions.run_timestep(
    state::ExploreTestState, action::ExploreTestAction,
    sow::ExploreTestSOW, config::ExploreTestConfig,
    t::TimeStep, rng::AbstractRNG
)
    new_val = state.value + sow.x.value
    return ExploreTestState(new_val), (step_value=new_val,)
end

function SimOptDecisions.finalize(
    state::ExploreTestState, step_records,
    config::ExploreTestConfig, sow::ExploreTestSOW
)
    ExploreTestOutcome(
        ContinuousParameter(state.value),
        DiscreteParameter(length(step_records))
    )
end

# ============================================================================
# Tests
# ============================================================================

@testset "Exploration" begin
    @testset "Flattening" begin
        sow = ExploreTestSOW(
            ContinuousParameter(1.5),
            CategoricalParameter(:high, [:low, :high])
        )

        nt = SimOptDecisions._flatten_to_namedtuple(sow, :sow)
        @test nt.sow_x == 1.5
        @test nt.sow_scenario == :high
    end

    @testset "TimeSeriesParameter flattening" begin
        struct TSSow <: AbstractSOW
            demand::TimeSeriesParameter{Float64}
        end

        sow = TSSow(TimeSeriesParameter([1.0, 2.0, 3.0]))
        nt = SimOptDecisions._flatten_to_namedtuple(sow, :sow)

        @test nt[Symbol("sow_demand[1]")] == 1.0
        @test nt[Symbol("sow_demand[2]")] == 2.0
        @test nt[Symbol("sow_demand[3]")] == 3.0
    end

    @testset "Validation errors" begin
        struct BadSOW <: AbstractSOW
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
                BadSOW, GoodPolicy{Float64}, GoodOutcome{Float64}
            )
        end
    end

    @testset "explore() basic" begin
        config = ExploreTestConfig(3)
        sows = [
            ExploreTestSOW(ContinuousParameter(1.0), CategoricalParameter(:low, [:low, :high])),
            ExploreTestSOW(ContinuousParameter(2.0), CategoricalParameter(:high, [:low, :high])),
        ]
        policies = [
            ExploreTestPolicy(ContinuousParameter(0.5)),
            ExploreTestPolicy(ContinuousParameter(0.8)),
        ]

        result = explore(config, sows, policies; progress=false)

        @test size(result) == (2, 2)  # 2 policies × 2 sows
        @test length(result) == 4

        # Check indexing
        @test result[1, 1].policy_idx == 1
        @test result[1, 1].sow_idx == 1
        @test result[2, 2].policy_idx == 2
        @test result[2, 2].sow_idx == 2

        # Check flattened columns exist
        @test :policy_threshold in keys(result[1, 1])
        @test :sow_x in keys(result[1, 1])
        @test :outcome_total in keys(result[1, 1])

        # Check outcome values make sense
        # policy 1 (threshold=0.5), sow 1 (x=1.0): 3 steps → total = 3.0
        @test result[1, 1].outcome_total == 3.0
        @test result[1, 1].outcome_count == 3

        # policy 1 (threshold=0.5), sow 2 (x=2.0): 3 steps → total = 6.0
        @test result[1, 2].outcome_total == 6.0
    end

    @testset "Tables.jl compatibility" begin
        config = ExploreTestConfig(3)
        sows = [ExploreTestSOW(ContinuousParameter(1.0), CategoricalParameter(:low, [:low, :high]))]
        policies = [ExploreTestPolicy(ContinuousParameter(0.5))]

        result = explore(config, sows, policies; progress=false)

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
        sows = [
            ExploreTestSOW(ContinuousParameter(1.0), CategoricalParameter(:low, [:low, :high])),
            ExploreTestSOW(ContinuousParameter(2.0), CategoricalParameter(:high, [:low, :high])),
        ]
        policies = [
            ExploreTestPolicy(ContinuousParameter(0.5)),
            ExploreTestPolicy(ContinuousParameter(0.8)),
        ]

        result = explore(config, sows, policies; progress=false)

        # outcomes_for_policy
        pol1_outcomes = outcomes_for_policy(result, 1)
        @test length(pol1_outcomes) == 2
        @test all(r.policy_idx == 1 for r in pol1_outcomes)

        # outcomes_for_sow
        sow1_outcomes = outcomes_for_sow(result, 1)
        @test length(sow1_outcomes) == 2
        @test all(r.sow_idx == 1 for r in sow1_outcomes)

        # filter
        filtered = filter(r -> r.policy_idx == 1, result)
        @test length(filtered) == 2

        # Column categorization
        @test :policy_threshold in result.policy_columns
        @test :sow_x in result.sow_columns
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
        sows = [ExploreTestSOW(ContinuousParameter(1.0), CategoricalParameter(:low, [:low, :high]))]
        policy = ExploreTestPolicy(ContinuousParameter(0.5))

        result = explore(config, sows, policy; progress=false)
        @test size(result) == (1, 1)
    end

    @testset "Empty inputs throw" begin
        config = ExploreTestConfig(3)
        sows = ExploreTestSOW{Float64}[]
        policies = [ExploreTestPolicy(ContinuousParameter(0.5))]

        @test_throws ArgumentError explore(config, sows, policies; progress=false)
        @test_throws ArgumentError explore(config, [ExploreTestSOW(ContinuousParameter(1.0), CategoricalParameter(:low, [:low, :high]))], AbstractPolicy[]; progress=false)
    end

    @testset "Bounds checking" begin
        config = ExploreTestConfig(3)
        sows = [ExploreTestSOW(ContinuousParameter(1.0), CategoricalParameter(:low, [:low, :high]))]
        policies = [ExploreTestPolicy(ContinuousParameter(0.5))]

        result = explore(config, sows, policies; progress=false)

        @test_throws BoundsError result[0, 1]
        @test_throws BoundsError result[1, 0]
        @test_throws BoundsError result[2, 1]
        @test_throws BoundsError result[1, 2]
    end
end
