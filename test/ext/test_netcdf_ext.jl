# Test NetCDF export for exploration results

@testset "NetCDF Extension" begin
    # Define minimal types for testing
    struct NCTestConfig <: AbstractConfig
        n_steps::Int
    end

    struct NCTestScenario{T<:AbstractFloat} <: AbstractScenario
        x::ContinuousParameter{T}
    end

    struct NCTestPolicy{T<:AbstractFloat} <: AbstractPolicy
        threshold::ContinuousParameter{T}
    end

    struct NCTestState{T<:AbstractFloat} <: AbstractState
        value::T
    end

    struct NCTestOutcome{T<:AbstractFloat}
        total::ContinuousParameter{T}
    end

    # Implement callbacks
    SimOptDecisions.time_axis(config::NCTestConfig, scenario::NCTestScenario) =
        1:config.n_steps

    function SimOptDecisions.initialize(
        config::NCTestConfig, scenario::NCTestScenario, rng::AbstractRNG
    )
        NCTestState(0.0)
    end

    function SimOptDecisions.get_action(
        policy::NCTestPolicy, state::NCTestState, t::TimeStep, scenario::NCTestScenario
    )
        :noop
    end

    function SimOptDecisions.run_timestep(
        state::NCTestState,
        action,
        t::TimeStep,
        config::NCTestConfig,
        scenario::NCTestScenario,
        rng::AbstractRNG,
    )
        new_val = state.value + scenario.x.value
        return NCTestState(new_val), (step_value=new_val,)
    end

    function SimOptDecisions.compute_outcome(
        step_records, config::NCTestConfig, scenario::NCTestScenario
    )
        NCTestOutcome(ContinuousParameter(step_records[end].step_value))
    end

    @testset "save_netcdf and load_netcdf" begin
        config = NCTestConfig(3)
        scenarios = [
            NCTestScenario(ContinuousParameter(1.0)),
            NCTestScenario(ContinuousParameter(2.0)),
        ]
        policies = [
            NCTestPolicy(ContinuousParameter(0.5)),
            NCTestPolicy(ContinuousParameter(0.8)),
        ]

        # Run exploration
        result = explore(config, scenarios, policies; progress=false)

        # Save to NetCDF
        filepath = tempname() * ".nc"

        try
            save_netcdf(result, filepath)

            # Verify file was created
            @test isfile(filepath)

            # Load back and verify
            loaded = load_netcdf(filepath)

            @test loaded isa Dataset
            @test :total in keys(loaded.cubes)

            # Verify data matches
            @test loaded[:total][1, 1] == result[:total][1, 1]
            @test loaded[:total][2, 2] == result[:total][2, 2]
        finally
            # Cleanup
            isfile(filepath) && rm(filepath)
        end
    end
end
