@testset "Definition Macros" begin
    @testset "@scenariodef" begin
        # Basic scenario definition
        TestScenario1 = @scenariodef begin
            @continuous temperature
            @continuous precipitation 0.0 100.0
        end

        @test TestScenario1 <: AbstractScenario
        # Parametric types: check concrete instantiation
        @test fieldtype(TestScenario1{Float64}, :temperature) == ContinuousParameter{Float64}
        @test fieldtype(TestScenario1{Float64}, :precipitation) == ContinuousParameter{Float64}

        # Can construct instances with auto-wrapping
        s = TestScenario1(temperature=25.0, precipitation=50.0)
        @test value(s.temperature) == 25.0
        @test value(s.precipitation) == 50.0
        @test s.precipitation.bounds == (0.0, 100.0)

        # Can also construct with explicit ContinuousParameter
        s2 = TestScenario1(
            temperature=ContinuousParameter(25.0),
            precipitation=ContinuousParameter(50.0, (0.0, 100.0)),
        )
        @test value(s2.temperature) == 25.0
    end

    @testset "@policydef" begin
        TestPolicy1 = @policydef begin
            @continuous threshold 0.0 1.0
            @continuous capacity 0.0 100.0
        end

        @test TestPolicy1 <: AbstractPolicy
        @test fieldtype(TestPolicy1{Float64}, :threshold) == ContinuousParameter{Float64}

        # Auto-wrapping constructor
        p = TestPolicy1(threshold=0.5, capacity=50.0)
        @test value(p.threshold) == 0.5
        @test p.threshold.bounds == (0.0, 1.0)
    end

    @testset "@configdef" begin
        TestConfig1 = @configdef begin
            @discrete horizon
            @discrete num_samples [100, 500, 1000]
        end

        @test TestConfig1 <: AbstractConfig
        @test fieldtype(TestConfig1, :horizon) == DiscreteParameter{Int}

        # Auto-wrapping constructor
        c = TestConfig1(horizon=50, num_samples=500)
        @test value(c.horizon) == 50
    end

    @testset "@statedef" begin
        TestState1 = @statedef begin
            @continuous storage 0.0 1000.0
            @discrete count
        end

        @test TestState1 <: AbstractState
        @test fieldtype(TestState1{Float64}, :storage) == ContinuousParameter{Float64}
        @test fieldtype(TestState1, :count) == DiscreteParameter{Int}

        # Auto-wrapping constructor
        st = TestState1(storage=500.0, count=10)
        @test value(st.storage) == 500.0
        @test value(st.count) == 10
    end

    @testset "@outcomedef" begin
        TestOutcome1 = @outcomedef begin
            @continuous total_cost 0.0 Inf
            @continuous reliability 0.0 1.0
            @discrete failures
        end

        @test TestOutcome1 <: AbstractOutcome
        @test fieldtype(TestOutcome1{Float64}, :total_cost) == ContinuousParameter{Float64}
        @test fieldtype(TestOutcome1{Float64}, :reliability) == ContinuousParameter{Float64}
        @test fieldtype(TestOutcome1, :failures) == DiscreteParameter{Int}

        # Auto-wrapping constructor
        o = TestOutcome1(total_cost=1000.0, reliability=0.95, failures=2)
        @test value(o.total_cost) == 1000.0
        @test value(o.reliability) == 0.95
    end

    @testset "Mixed field types" begin
        TestScenario2 = @scenariodef begin
            @continuous x
            @discrete n
            @categorical mode [:a, :b, :c]
            @timeseries demand
        end

        @test fieldtype(TestScenario2{Float64}, :x) == ContinuousParameter{Float64}
        @test fieldtype(TestScenario2, :n) == DiscreteParameter{Int}
        @test fieldtype(TestScenario2, :mode) == CategoricalParameter{Symbol}
        @test fieldtype(TestScenario2{Float64}, :demand) == TimeSeriesParameter{Float64,Int}

        # Auto-wrapping constructor
        s = TestScenario2(x=1.5, n=10, mode=:a, demand=[1.0, 2.0, 3.0])
        @test value(s.x) == 1.5
        @test value(s.n) == 10
        @test value(s.mode) == :a
        @test value(s.demand) == [1.0, 2.0, 3.0]
    end

    @testset "GenericParameter" begin
        TestScenario3 = @scenariodef begin
            @continuous x
            @generic model
        end

        @test fieldtype(TestScenario3{Float64}, :x) == ContinuousParameter{Float64}
        @test fieldtype(TestScenario3, :model) == GenericParameter{Any}

        # Auto-wrapping constructor
        s = TestScenario3(x=1.0, model="test_model")
        @test value(s.model) == "test_model"
    end

    @testset "Explicit type annotation" begin
        # Allow mixing macro fields with explicit type annotations
        TestPolicy2 = @policydef begin
            @continuous x
            special::ContinuousParameter{Float32}
        end

        @test fieldtype(TestPolicy2{Float64}, :x) == ContinuousParameter{Float64}
        @test fieldtype(TestPolicy2, :special) == ContinuousParameter{Float32}
    end
end
