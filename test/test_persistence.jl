# Module-level metric calculator to avoid JLD2 serialization warnings
# (functions defined inside @testset are closures that JLD2 can't serialize properly)
_checkpoint_metric_calc(outcomes) = (mean=sum(o.final for o in outcomes) / length(outcomes),)

@testset "Persistence" begin
    @testset "SharedParameters" begin
        sp = SharedParameters(; discount_rate=0.03, horizon=50)
        @test sp.discount_rate == 0.03
        @test sp.horizon == 50
        @test sp.params == (discount_rate=0.03, horizon=50)
        @test :discount_rate in propertynames(sp)
        @test :horizon in propertynames(sp)
    end

    @testset "ExperimentConfig construction" begin
        struct PersistTestSOW <: AbstractSOW
            id::Int
        end

        sows = [PersistTestSOW(i) for i in 1:10]
        shared = SharedParameters(; rate=0.05)
        backend = MetaheuristicsBackend()

        config = ExperimentConfig(42, sows, shared, backend; sow_source="test data")

        @test config.seed == 42
        @test length(config.sows) == 10
        @test config.shared.rate == 0.05
        @test config.backend === backend
        @test config.sow_source == "test data"
        @test config.git_commit == ""
        @test config.package_versions == ""
    end

    @testset "Checkpoint save/load" begin
        # Create a minimal problem for testing
        struct CheckpointState <: AbstractState
            v::Float64
        end

        struct CheckpointPolicy <: AbstractPolicy
            x::Float64
        end

        struct CheckpointParams <: AbstractConfig end
        struct CheckpointSOW <: AbstractSOW end

        # Simple for-loop implementation
        function SimOptDecisions.simulate(
            params::CheckpointParams,
            sow::CheckpointSOW,
            policy::CheckpointPolicy,
            rng::AbstractRNG,
        )
            value = 0.0
            for ts in SimOptDecisions.Utils.timeindex(1:5)
                value += policy.x
            end
            return (final=value,)
        end

        SimOptDecisions.param_bounds(::Type{CheckpointPolicy}) = [(0.0, 1.0)]
        CheckpointPolicy(x::AbstractVector) = CheckpointPolicy(x[1])

        prob = OptimizationProblem(
            CheckpointParams(),
            [CheckpointSOW()],
            CheckpointPolicy,
            _checkpoint_metric_calc,
            [minimize(:mean)],
        )

        # Test save and load
        tmpfile = tempname() * ".jld2"
        try
            optimizer_state = Dict(:iteration => 50, :best_x => [0.5])
            save_checkpoint(tmpfile, prob, optimizer_state; metadata="test checkpoint")

            loaded = load_checkpoint(tmpfile)
            @test loaded.optimizer_state[:iteration] == 50
            @test loaded.optimizer_state[:best_x] == [0.5]
            @test loaded.metadata == "test checkpoint"
            @test loaded.version == "0.1.0"
            @test loaded.problem isa OptimizationProblem
        finally
            rm(tmpfile; force=true)
        end
    end

    @testset "Experiment save/load" begin
        struct ExpTestSOW <: AbstractSOW end

        sows = [ExpTestSOW() for _ in 1:3]
        shared = SharedParameters(; param1=1.0)
        backend = MetaheuristicsBackend()
        config = ExperimentConfig(123, sows, shared, backend)

        struct ExpResultPolicy <: AbstractPolicy
            x::Float64
        end

        result = OptimizationResult{ExpResultPolicy,Float64}(
            [0.7],
            [5.0],
            ExpResultPolicy(0.7),
            Dict{Symbol,Any}(),
            Vector{Vector{Float64}}(),
            Vector{Vector{Float64}}(),
        )

        tmpfile = tempname() * ".jld2"
        try
            save_experiment(tmpfile, config, result)

            loaded = load_experiment(tmpfile)
            @test loaded.config.seed == 123
            @test loaded.result.best_params == [0.7]
            @test loaded.result.best_policy.x == 0.7
            @test loaded.version == "0.1.0"
        finally
            rm(tmpfile; force=true)
        end
    end
end
