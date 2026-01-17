@testset "Parameter Types" begin
    @testset "ContinuousParameter" begin
        # Default bounds
        p = ContinuousParameter(1.5)
        @test p.value == 1.5
        @test p.bounds == (-Inf, Inf)
        @test p[] == 1.5
        @test value(p) == 1.5

        # Custom bounds
        p2 = ContinuousParameter(0.5, (0.0, 1.0))
        @test p2.bounds == (0.0, 1.0)

        # Type stability with Float32
        p3 = ContinuousParameter(1.0f0)
        @test p3.value isa Float32
        @test p3.bounds == (-Inf32, Inf32)
    end

    @testset "DiscreteParameter" begin
        # Default (no valid_values)
        p = DiscreteParameter(5)
        @test p.value == 5
        @test p.valid_values === nothing
        @test value(p) == 5
        @test p[] == 5

        # With valid values
        p2 = DiscreteParameter(2, [1, 2, 3])
        @test p2.valid_values == [1, 2, 3]
    end

    @testset "CategoricalParameter" begin
        # Symbol categories
        p = CategoricalParameter(:high, [:low, :medium, :high])
        @test p.value == :high
        @test p.levels == [:low, :medium, :high]
        @test value(p) == :high
        @test p[] == :high

        # Invalid value throws
        @test_throws ArgumentError CategoricalParameter(:invalid, [:low, :high])

        # String categories
        p2 = CategoricalParameter("a", ["a", "b", "c"])
        @test p2.value == "a"
        @test p2.levels == ["a", "b", "c"]
    end

    @testset "TimeSeriesParameter" begin
        # Construction with explicit time_axis
        ts = TimeSeriesParameter(2020:2022, [1.0, 2.0, 3.0])
        @test length(ts) == 3
        @test time_axis(ts) == [2020, 2021, 2022]
        @test time_axis(ts) === ts.time_axis
        @test value(ts) == [1.0, 2.0, 3.0]
        @test value(ts) === ts.values

        # Integer indexing (by position)
        @test ts[1] == 1.0
        @test ts[2] == 2.0
        @test ts[3] == 3.0

        # TimeStep indexing (looks up t.val in time_axis)
        @test ts[TimeStep(1, 2020)] == 1.0
        @test ts[TimeStep(2, 2021)] == 2.0
        @test ts[TimeStep(3, 2022)] == 3.0

        # Bounds errors
        @test_throws BoundsError ts[0]
        @test_throws BoundsError ts[4]
        @test_throws TimeSeriesParameterBoundsError ts[TimeStep(1, 2025)]

        # Iteration
        @test collect(ts) == [1.0, 2.0, 3.0]

        # Empty not allowed
        @test_throws ArgumentError TimeSeriesParameter(1:0, Float64[])

        # Mismatched lengths not allowed
        @test_throws ArgumentError TimeSeriesParameter(1:3, [1.0, 2.0])

        # Values-only constructor (auto-generates 1:n time axis)
        ts_auto = TimeSeriesParameter([10.0, 20.0, 30.0])
        @test length(ts_auto) == 3
        @test time_axis(ts_auto) == [1, 2, 3]
        @test ts_auto[TimeStep(1, 1)] == 10.0
        @test ts_auto[TimeStep(2, 2)] == 20.0

        # Construction from range values
        ts2 = TimeSeriesParameter(1:3, 1.0:3.0)
        @test length(ts2) == 3
        @test ts2[2] == 2.0
    end

    @testset "GenericParameter" begin
        # Basic usage
        p = GenericParameter("a string")
        @test p.value == "a string"
        @test value(p) == "a string"
        @test p[] == "a string"

        # With complex type
        data = Dict(:a => 1, :b => 2)
        p2 = GenericParameter(data)
        @test value(p2) === data

        # Type-parameterized
        p3 = GenericParameter{Vector{Int}}([1, 2, 3])
        @test p3.value == [1, 2, 3]
    end
end
