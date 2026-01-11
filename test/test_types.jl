@testset "Types" begin
    @testset "TimeStep" begin
        # TimeStep construction with Int
        ts = TimeStep(1, 2020)
        @test ts.t == 1
        @test ts.val == 2020

        # TimeStep with Date
        ts_date = TimeStep(5, Date(2025, 1, 1))
        @test ts_date.val == Date(2025, 1, 1)

        # TimeStep with Float64
        ts_float = TimeStep(10, 0.5)
        @test ts_float.val == 0.5

        # is_first and is_last helper methods
        @test SimOptDecisions.Utils.is_first(ts)
        @test !SimOptDecisions.Utils.is_first(ts_date)
        @test SimOptDecisions.Utils.is_last(ts, 1)
        @test !SimOptDecisions.Utils.is_last(ts, 10)
        @test SimOptDecisions.Utils.is_last(ts_date, 5)
    end

    @testset "Time Axis Validation" begin
        # Valid time axes
        @test SimOptDecisions._validate_time_axis(1:100) === nothing
        @test SimOptDecisions._validate_time_axis([1, 2, 3]) === nothing
        @test SimOptDecisions._validate_time_axis(1.0:0.1:10.0) === nothing
        @test SimOptDecisions._validate_time_axis(Date(2020):Year(1):Date(2030)) === nothing

        # Invalid: Vector{Any}
        @test_throws ArgumentError SimOptDecisions._validate_time_axis(Any[1, 2, 3])
    end

    @testset "Objective construction" begin
        obj1 = minimize(:cost)
        @test obj1.name == :cost
        @test obj1.direction == Minimize

        obj2 = maximize(:reliability)
        @test obj2.name == :reliability
        @test obj2.direction == Maximize

        obj3 = Objective(:custom, Minimize)
        @test obj3.name == :custom
        @test obj3.direction == Minimize
    end

    @testset "Batch size types" begin
        @test FullBatch() isa AbstractBatchSize

        fb = FixedBatch(50)
        @test fb.n == 50
        @test_throws ArgumentError FixedBatch(0)
        @test_throws ArgumentError FixedBatch(-1)

        frac = FractionBatch(0.5)
        @test frac.fraction == 0.5
        @test FractionBatch(1.0).fraction == 1.0  # Edge case: 1.0 is valid
        @test_throws ArgumentError FractionBatch(0.0)
        @test_throws ArgumentError FractionBatch(1.5)
        @test_throws ArgumentError FractionBatch(-0.1)
    end

    @testset "MetaheuristicsBackend construction" begin
        backend = MetaheuristicsBackend()
        @test backend.algorithm == :ECA
        @test backend.max_iterations == 1000
        @test backend.population_size == 100
        @test backend.parallel == true
        @test backend.options == Dict{Symbol,Any}()

        backend2 = MetaheuristicsBackend(;
            algorithm=:DE, max_iterations=500, population_size=50, parallel=false
        )
        @test backend2.algorithm == :DE
        @test backend2.max_iterations == 500
        @test backend2.population_size == 50
        @test backend2.parallel == false
    end
end
