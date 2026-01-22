using Tables
using YAXArrays

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
function SimOptDecisions.time_axis(config::ExploreTestConfig, scenario::ExploreTestScenario)
    1:config.n_steps
end

function SimOptDecisions.initialize(
    config::ExploreTestConfig, scenario::ExploreTestScenario, rng::AbstractRNG
)
    ExploreTestState(0.0)
end

function SimOptDecisions.get_action(
    policy::ExploreTestPolicy,
    state::ExploreTestState,
    t::TimeStep,
    scenario::ExploreTestScenario,
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
        ContinuousParameter(step_records[end].step_value),
        DiscreteParameter(length(step_records)),
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

    @testset "GenericParameter flattening (skipped)" begin
        struct GenericScenario <: AbstractScenario
            x::ContinuousParameter{Float64}
            model::GenericParameter{Dict{Symbol,Int}}
        end

        scenario = GenericScenario(
            ContinuousParameter(1.5), GenericParameter(Dict(:a => 1, :b => 2))
        )
        nt = SimOptDecisions._flatten_to_namedtuple(scenario, :scenario)

        # x should be flattened
        @test nt.scenario_x == 1.5
        # model should be skipped (not in keys)
        @test !haskey(nt, :scenario_model)
        @test length(keys(nt)) == 1
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

    @testset "explore() basic - YAXArray Dataset" begin
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

        # Result should be a Dataset
        @test result isa YAXArrays.Dataset

        # Check dimensions of outcome arrays
        @test :total in keys(result.cubes)
        @test :count in keys(result.cubes)

        total_arr = result[:total]
        @test size(total_arr) == (2, 2)  # 2 policies × 2 scenarios

        # Check outcome values make sense
        # policy 1, scenario 1 (x=1.0): 3 steps → total = 3.0
        # YAXArrays returns 0-dim arrays for single-element selection
        @test only(total_arr[policy=1, scenario=1]) == 3.0

        # policy 1, scenario 2 (x=2.0): 3 steps → total = 6.0
        @test only(total_arr[policy=1, scenario=2]) == 6.0

        # Check count values
        count_arr = result[:count]
        @test all(count_arr .== 3)

        # Check parameter metadata is stored
        @test :policy_threshold in keys(result.cubes)
        @test :scenario_x in keys(result.cubes)
    end

    @testset "Executors" begin
        @testset "SequentialExecutor" begin
            config = ExploreTestConfig(3)
            scenarios = [
                ExploreTestScenario(
                    ContinuousParameter(1.0), CategoricalParameter(:low, [:low, :high])
                ),
            ]
            policies = [ExploreTestPolicy(ContinuousParameter(0.5))]

            executor = SequentialExecutor(; crn=true, seed=42)
            result = explore(config, scenarios, policies; executor, progress=false)

            @test result isa YAXArrays.Dataset
            @test result[:total][1, 1] == 3.0
        end

        @testset "ThreadedExecutor" begin
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

            executor = ThreadedExecutor(; crn=true, seed=42)
            result = explore(config, scenarios, policies; executor, progress=false)

            @test result isa YAXArrays.Dataset
            @test size(result[:total]) == (2, 2)
        end

        @testset "CRN reproducibility" begin
            config = ExploreTestConfig(3)
            scenarios = [
                ExploreTestScenario(
                    ContinuousParameter(1.0), CategoricalParameter(:low, [:low, :high])
                ),
            ]
            policies = [ExploreTestPolicy(ContinuousParameter(0.5))]

            # Same seed should give same results
            executor1 = SequentialExecutor(; crn=true, seed=12345)
            executor2 = SequentialExecutor(; crn=true, seed=12345)

            result1 = explore(config, scenarios, policies; executor=executor1, progress=false)
            result2 = explore(config, scenarios, policies; executor=executor2, progress=false)

            @test result1[:total][1, 1] == result2[:total][1, 1]
        end
    end

    @testset "Storage Backends" begin
        @testset "InMemoryBackend" begin
            config = ExploreTestConfig(3)
            scenarios = [
                ExploreTestScenario(
                    ContinuousParameter(1.0), CategoricalParameter(:low, [:low, :high])
                ),
            ]
            policies = [ExploreTestPolicy(ContinuousParameter(0.5))]

            result = explore(
                config, scenarios, policies;
                backend=InMemoryBackend(),
                progress=false
            )
            @test result isa YAXArrays.Dataset
        end

        @testset "ZarrBackend" begin
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
            ]

            zarr_path = mktempdir()
            result = explore(
                config, scenarios, policies;
                backend=ZarrBackend(joinpath(zarr_path, "results.zarr")),
                progress=false
            )

            @test result isa YAXArrays.Dataset
            @test isdir(joinpath(zarr_path, "results.zarr"))
            @test result[:total][1, 1] == 3.0
            @test result[:total][1, 2] == 6.0
        end
    end

    @testset "Result accessors" begin
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
        @test :total in keys(pol1_outcomes)
        @test size(pol1_outcomes[:total]) == (2,)  # 2 scenarios

        # outcomes_for_scenario
        scenario1_outcomes = outcomes_for_scenario(result, 1)
        @test :total in keys(scenario1_outcomes)
        @test size(scenario1_outcomes[:total]) == (2,)  # 2 policies
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
        @test size(result[:total]) == (1, 1)
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

    @testset "explore_traced" begin
        config = ExploreTestConfig(3)
        scenarios = [
            ExploreTestScenario(
                ContinuousParameter(1.0), CategoricalParameter(:low, [:low, :high])
            ),
        ]
        policies = [ExploreTestPolicy(ContinuousParameter(0.5))]

        result, traces = explore_traced(config, scenarios, policies; progress=false)

        @test result isa YAXArrays.Dataset
        @test size(traces) == (1, 1)
        @test traces[1, 1] isa SimulationTrace
    end

    @testset "DistributedExecutor traced throws" begin
        config = ExploreTestConfig(3)
        scenarios = [
            ExploreTestScenario(
                ContinuousParameter(1.0), CategoricalParameter(:low, [:low, :high])
            ),
        ]
        policies = [ExploreTestPolicy(ContinuousParameter(0.5))]

        @test_throws ArgumentError explore_traced(
            config, scenarios, policies;
            executor=DistributedExecutor(),
            progress=false
        )
    end
end
