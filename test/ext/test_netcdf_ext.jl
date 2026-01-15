# Test NetCDF extension for exploration results
# This test catches the critical bug where the extension used sow_idx instead of scenario_idx

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
    SimOptDecisions.time_axis(config::NCTestConfig, scenario::NCTestScenario) = 1:config.n_steps

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

    @testset "netcdf_sink with explore()" begin
        config = NCTestConfig(3)
        scenarios = [
            NCTestScenario(ContinuousParameter(1.0)),
            NCTestScenario(ContinuousParameter(2.0)),
        ]
        policies = [NCTestPolicy(ContinuousParameter(0.5))]

        # Create temp file for NetCDF output
        filepath = tempname() * ".nc"

        try
            # This test catches the bug: extension must use scenario_idx not sow_idx
            sink = netcdf_sink(filepath; flush_every=1)
            result = explore(config, scenarios, policies; sink=sink, progress=false)

            # Verify file was created
            @test isfile(filepath)
            @test result == filepath

            # Verify contents using NCDatasets
            NCDataset(filepath, "r") do ds
                # Check dimensions use "scenario" not "sow"
                @test haskey(ds.dim, "scenario")
                @test haskey(ds.dim, "policy")
                @test !haskey(ds.dim, "sow")

                # Check attribute names
                @test haskey(ds.attrib, "n_scenarios")
                @test haskey(ds.attrib, "n_policies")
                @test !haskey(ds.attrib, "n_sows")

                # Check data was written correctly
                @test ds.attrib["n_scenarios"] == 2
                @test ds.attrib["n_policies"] == 1

                # Verify outcome values
                @test haskey(ds, "outcome_total")
            end
        finally
            # Cleanup
            isfile(filepath) && rm(filepath)
        end
    end
end
