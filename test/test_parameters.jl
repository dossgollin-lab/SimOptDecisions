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

        # With valid values (vector)
        p2 = DiscreteParameter(2, [1, 2, 3])
        @test p2.valid_values == [1, 2, 3]

        # With range (collected to vector)
        p3 = DiscreteParameter(3, 1:5)
        @test p3.valid_values == [1, 2, 3, 4, 5]
        @test p3.value == 3

        # With tuple (collected to vector)
        p4 = DiscreteParameter(10, (5, 10, 15))
        @test p4.valid_values == [5, 10, 15]

        # Invalid value throws
        @test_throws ArgumentError DiscreteParameter(99, [1, 2, 3])
        @test_throws ArgumentError DiscreteParameter(0, 1:5)
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

        # Tuple levels (collected to vector)
        p3 = CategoricalParameter(:x, (:x, :y, :z))
        @test p3.levels == [:x, :y, :z]
    end

    @testset "GenericParameter" begin
        # Basic construction
        # Note: warning may or may not appear depending on test order (maxlog=1)
        struct TestComplexType
            data::Vector{Int}
        end

        obj = TestComplexType([1, 2, 3])
        p = GenericParameter(obj)
        @test p.value === obj
        @test value(p) === obj
        @test p[] === obj

        # Second construction should not warn (maxlog=1 already triggered)
        p2 = GenericParameter(TestComplexType([4, 5]))
        @test p2.value.data == [4, 5]
    end

    @testset "TimeSeriesParameter value() and time_axis()" begin
        ts = TimeSeriesParameter(2020:2022, [1.0, 2.0, 3.0])
        @test value(ts) == [1.0, 2.0, 3.0]
        @test value(ts) === ts.values  # same reference
        @test time_axis(ts) == [2020, 2021, 2022]
        @test time_axis(ts) === ts.time_axis  # same reference
    end
end
