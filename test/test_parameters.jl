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

    @testset "TimeSeriesParameter value() and time_axis()" begin
        ts = TimeSeriesParameter(2020:2022, [1.0, 2.0, 3.0])
        @test value(ts) == [1.0, 2.0, 3.0]
        @test value(ts) === ts.values  # same reference
        @test time_axis(ts) == [2020, 2021, 2022]
        @test time_axis(ts) === ts.time_axis  # same reference
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
