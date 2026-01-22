# Tests for SimOptMakieExt
# These tests require CairoMakie to be loaded

using CairoMakie
using YAXArrays

# Test types for "to_scalars interface"
struct PlotTestState <: AbstractState
    x::Float64
    y::Float64
end

SimOptDecisions.to_scalars(s::PlotTestState) = (x=s.x, y=s.y)

# Test types for "to_scalars error for unimplemented"
struct NoScalarsState <: AbstractState
    value::Float64
end

# ============================================================================
# Tests
# ============================================================================

@testset "MakieExt" begin
    @testset "to_scalars interface" begin
        state = PlotTestState(1.0, 2.0)
        scalars = to_scalars(state)

        @test scalars isa NamedTuple
        @test scalars.x == 1.0
        @test scalars.y == 2.0
    end

    @testset "to_scalars error for unimplemented" begin
        state = NoScalarsState(1.0)
        @test_throws ArgumentError to_scalars(state)
    end

    @testset "plot_trace" begin
        # Create a simple SimulationTrace with NamedTuple step_records
        initial_state = 0.0
        states = [1.0, 2.0, 2.5]
        step_records = [
            (position=1.0, velocity=1.0),
            (position=2.0, velocity=0.5),
            (position=2.5, velocity=0.0),
        ]
        times = [1, 2, 3]
        actions = [nothing, nothing, nothing]

        trace = SimulationTrace(initial_state, states, step_records, times, actions)

        # Test plotting
        fig, axes = plot_trace(trace)

        @test fig isa Figure
        @test axes isa Vector{<:Axis}
        @test length(axes) == 2  # One per field in step_record (position, velocity)
    end

    @testset "plot_trace empty error" begin
        # Create empty trace and test that plot_trace throws an error
        trace = SimulationTrace(0.0, Float64[], NamedTuple[], Int[], Nothing[])
        @test_throws ErrorException plot_trace(trace)
    end

    @testset "plot_pareto 2-objective" begin
        # Create a result with Pareto front data
        pareto_params = [[0.1], [0.3], [0.5], [0.7], [0.9]]
        pareto_objectives = [[1.0, 9.0], [2.0, 7.0], [4.0, 4.0], [7.0, 2.0], [9.0, 1.0]]

        result = OptimizationResult{Float64}(
            Dict{Symbol,Any}(:iterations => 100, :n_pareto => 5),
            pareto_params,
            pareto_objectives,
        )

        fig, ax = plot_pareto(result)

        @test fig isa Figure
        @test ax isa Axis
    end

    @testset "plot_pareto empty error" begin
        result = OptimizationResult{Float64}(
            Dict{Symbol,Any}(),
            Vector{Vector{Float64}}(),  # Empty Pareto front
            Vector{Vector{Float64}}(),
        )

        @test_throws ErrorException plot_pareto(result)
    end

    @testset "plot_pareto single objective error" begin
        # Pareto front with single objective (invalid for plot_pareto)
        pareto_params = [[0.5]]
        pareto_objectives = [[1.0]]  # Only 1 objective

        result = OptimizationResult{Float64}(
            Dict{Symbol,Any}(), pareto_params, pareto_objectives
        )

        @test_throws ErrorException plot_pareto(result)
    end

    @testset "plot_exploration with Dataset" begin
        # Create a simple YAXArray Dataset for testing
        policy_axis = Dim{:policy}(1:2)
        scenario_axis = Dim{:scenario}(1:3)

        total_data = [1.0 2.0 3.0; 4.0 5.0 6.0]
        total = YAXArray((policy_axis, scenario_axis), total_data)

        ds = YAXArrays.Dataset(; total)

        fig, ax = plot_exploration(ds; outcome_field=:total)

        @test fig isa Figure
        @test ax isa Axis
    end

    @testset "plot_exploration_scatter with Dataset" begin
        # Create a simple YAXArray Dataset for testing
        policy_axis = Dim{:policy}(1:3)
        scenario_axis = Dim{:scenario}(1:4)

        cost_data = rand(3, 4)
        benefit_data = rand(3, 4)

        ds = YAXArrays.Dataset(;
            cost=YAXArray((policy_axis, scenario_axis), cost_data),
            benefit=YAXArray((policy_axis, scenario_axis), benefit_data),
        )

        fig, ax = plot_exploration_scatter(ds; x=:cost, y=:benefit)

        @test fig isa Figure
        @test ax isa Axis
    end
end
