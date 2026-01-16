@testset "Definition Macros" begin
    @testset "@scenariodef" begin
        # Basic scenario definition
        TestScenario1 = @scenariodef begin
            @continuous temperature
            @continuous precipitation 0.0 100.0
        end

        @test TestScenario1 <: AbstractScenario
        @test fieldtype(TestScenario1, :temperature) == ContinuousParameter{Float64}
        @test fieldtype(TestScenario1, :precipitation) == ContinuousParameter{Float64}

        # Can construct instances
        s = TestScenario1(
            temperature=ContinuousParameter(25.0),
            precipitation=ContinuousParameter(50.0, (0.0, 100.0)),
        )
        @test value(s.temperature) == 25.0
        @test value(s.precipitation) == 50.0
    end

    @testset "@policydef" begin
        TestPolicy1 = @policydef begin
            @continuous threshold 0.0 1.0
            @continuous capacity 0.0 100.0
        end

        @test TestPolicy1 <: AbstractPolicy
        @test fieldtype(TestPolicy1, :threshold) == ContinuousParameter{Float64}

        p = TestPolicy1(
            threshold=ContinuousParameter(0.5, (0.0, 1.0)),
            capacity=ContinuousParameter(50.0, (0.0, 100.0)),
        )
        @test value(p.threshold) == 0.5
    end

    @testset "@configdef" begin
        TestConfig1 = @configdef begin
            @discrete horizon
            @discrete num_samples [100, 500, 1000]
        end

        @test TestConfig1 <: AbstractConfig
        @test fieldtype(TestConfig1, :horizon) == DiscreteParameter{Int}

        c = TestConfig1(
            horizon=DiscreteParameter(50), num_samples=DiscreteParameter(500, [100, 500, 1000])
        )
        @test value(c.horizon) == 50
    end

    @testset "@statedef" begin
        TestState1 = @statedef begin
            @continuous storage 0.0 1000.0
            @discrete count
        end

        @test TestState1 <: AbstractState
        @test fieldtype(TestState1, :storage) == ContinuousParameter{Float64}
        @test fieldtype(TestState1, :count) == DiscreteParameter{Int}
    end

    @testset "Mixed field types" begin
        TestScenario2 = @scenariodef begin
            @continuous x
            @discrete n
            @categorical mode [:a, :b, :c]
            @timeseries demand
        end

        @test fieldtype(TestScenario2, :x) == ContinuousParameter{Float64}
        @test fieldtype(TestScenario2, :n) == DiscreteParameter{Int}
        @test fieldtype(TestScenario2, :mode) == CategoricalParameter{Symbol}
        @test fieldtype(TestScenario2, :demand) == TimeSeriesParameter{Float64,Int}
    end

    @testset "GenericParameter with warning" begin
        # This should emit a warning about GenericParameter
        TestScenario3 = @scenariodef begin
            @continuous x
            @generic model
        end

        @test fieldtype(TestScenario3, :x) == ContinuousParameter{Float64}
        @test fieldtype(TestScenario3, :model) == GenericParameter{Any}
    end

    @testset "Explicit type annotation" begin
        # Allow mixing macro fields with explicit type annotations
        TestPolicy2 = @policydef begin
            @continuous x
            special::ContinuousParameter{Float32}
        end

        @test fieldtype(TestPolicy2, :x) == ContinuousParameter{Float64}
        @test fieldtype(TestPolicy2, :special) == ContinuousParameter{Float32}
    end
end
