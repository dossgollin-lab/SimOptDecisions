# Tests for SimOptMakieExt
# These tests require CairoMakie to be loaded

using CairoMakie

@testset "MakieExt" begin
    @testset "to_scalars interface" begin
        # Define a test state with to_scalars implementation
        struct PlotTestState <: AbstractState
            x::Float64
            y::Float64
        end

        SimOptDecisions.to_scalars(s::PlotTestState) = (x=s.x, y=s.y)

        state = PlotTestState(1.0, 2.0)
        scalars = to_scalars(state)

        @test scalars isa NamedTuple
        @test scalars.x == 1.0
        @test scalars.y == 2.0
    end

    @testset "to_scalars error for unimplemented" begin
        struct NoScalarsState <: AbstractState
            value::Float64
        end

        state = NoScalarsState(1.0)
        @test_throws ErrorException to_scalars(state)
    end

    @testset "plot_trace" begin
        # Define state type with to_scalars
        struct TraceTestState <: AbstractState
            position::Float64
            velocity::Float64
        end

        SimOptDecisions.to_scalars(s::TraceTestState) = (position=s.position, velocity=s.velocity)

        # Create a simple trace
        states = [
            TraceTestState(0.0, 1.0),
            TraceTestState(1.0, 1.0),
            TraceTestState(2.0, 0.5),
            TraceTestState(2.5, 0.0),
        ]
        times = [1, 2, 3, 4]

        recorder = TraceRecorder(states, times)

        # Test plotting
        fig, axes = plot_trace(recorder)

        @test fig isa Figure
        @test axes isa Vector{<:Axis}
        @test length(axes) == 2  # One per scalar field (position, velocity)
    end

    @testset "plot_trace with kwargs" begin
        struct KwargsTestState <: AbstractState
            value::Float64
        end

        SimOptDecisions.to_scalars(s::KwargsTestState) = (value=s.value,)

        states = [KwargsTestState(Float64(i)) for i in 1:5]
        times = 1:5

        recorder = TraceRecorder(states, collect(times))

        # Test with custom kwargs
        fig, axes = plot_trace(
            recorder; figure_kwargs=(; size=(800, 600)), line_kwargs=(; color=:red)
        )

        @test fig isa Figure
        @test length(axes) == 1
    end

    @testset "plot_trace empty error" begin
        struct EmptyTestState <: AbstractState
            value::Float64
        end

        SimOptDecisions.to_scalars(s::EmptyTestState) = (value=s.value,)

        # Create empty recorder and test that plot_trace throws an error
        recorder = TraceRecorder(EmptyTestState[], Int[])
        @test_throws ErrorException plot_trace(recorder)
    end

    @testset "plot_pareto 2-objective" begin
        # Create mock policy type
        struct ParetoTestPolicy <: AbstractPolicy
            x::Float64
        end

        # Create a result with Pareto front data
        pareto_params = [[0.1], [0.3], [0.5], [0.7], [0.9]]
        pareto_objectives = [[1.0, 9.0], [2.0, 7.0], [4.0, 4.0], [7.0, 2.0], [9.0, 1.0]]

        result = OptimizationResult{ParetoTestPolicy}(
            [0.5],
            [4.0, 4.0],
            ParetoTestPolicy(0.5),
            Dict{Symbol,Any}(:iterations => 100, :n_pareto => 5),
            pareto_params,
            pareto_objectives,
        )

        fig, ax = plot_pareto(result)

        @test fig isa Figure
        @test ax isa Axis
    end

    @testset "plot_pareto with objective names" begin
        struct NamedParetoPolicy <: AbstractPolicy
            x::Float64
        end

        pareto_params = [[0.2], [0.5], [0.8]]
        pareto_objectives = [[1.0, 5.0], [2.5, 2.5], [5.0, 1.0]]

        result = OptimizationResult{NamedParetoPolicy}(
            [0.5],
            [2.5, 2.5],
            NamedParetoPolicy(0.5),
            Dict{Symbol,Any}(:iterations => 50),
            pareto_params,
            pareto_objectives,
        )

        fig, ax = plot_pareto(
            result;
            objective_names=["Cost", "Risk"],
            highlight_best=true,
        )

        @test fig isa Figure
        @test ax isa Axis
    end

    @testset "plot_pareto without highlight" begin
        struct NoHighlightPolicy <: AbstractPolicy
            x::Float64
        end

        pareto_params = [[0.3], [0.6]]
        pareto_objectives = [[1.0, 3.0], [3.0, 1.0]]

        result = OptimizationResult{NoHighlightPolicy}(
            [0.3],
            [1.0, 3.0],
            NoHighlightPolicy(0.3),
            Dict{Symbol,Any}(),
            pareto_params,
            pareto_objectives,
        )

        fig, ax = plot_pareto(result; highlight_best=false)

        @test fig isa Figure
        @test ax isa Axis
    end

    @testset "plot_pareto empty error" begin
        struct EmptyParetoPolicy <: AbstractPolicy
            x::Float64
        end

        result = OptimizationResult{EmptyParetoPolicy}(
            [0.5],
            [1.0],
            EmptyParetoPolicy(0.5),
            Dict{Symbol,Any}(),
            Vector{Vector{Float64}}(),  # Empty Pareto front
            Vector{Vector{Float64}}(),
        )

        @test_throws ErrorException plot_pareto(result)
    end

    @testset "plot_pareto single objective error" begin
        struct SingleObjPolicy <: AbstractPolicy
            x::Float64
        end

        # Pareto front with single objective (invalid for plot_pareto)
        pareto_params = [[0.5]]
        pareto_objectives = [[1.0]]  # Only 1 objective

        result = OptimizationResult{SingleObjPolicy}(
            [0.5],
            [1.0],
            SingleObjPolicy(0.5),
            Dict{Symbol,Any}(),
            pareto_params,
            pareto_objectives,
        )

        @test_throws ErrorException plot_pareto(result)
    end
end
