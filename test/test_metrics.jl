# ============================================================================
# Test Declarative Metrics System
# ============================================================================

@testset "Metrics" begin
    # Sample outcomes for testing
    outcomes = [
        (cost=100.0, loss=10.0, success=true),
        (cost=200.0, loss=20.0, success=false),
        (cost=150.0, loss=15.0, success=true),
        (cost=250.0, loss=25.0, success=false),
    ]

    @testset "ExpectedValue" begin
        metric = ExpectedValue(:mean_cost, :cost)
        result = compute_metric(metric, outcomes)
        @test result == (:mean_cost => 175.0)
    end

    @testset "Probability" begin
        metric = Probability(:prob_success, o -> o.success)
        result = compute_metric(metric, outcomes)
        @test result == (:prob_success => 0.5)
    end

    @testset "Variance" begin
        metric = Variance(:var_cost, :cost)
        result = compute_metric(metric, outcomes)
        @test result.first == :var_cost
        @test result.second ≈ 4166.666666666667 atol=0.01
    end

    @testset "MeanAndVariance" begin
        metric = MeanAndVariance(:mean_loss, :var_loss, :loss)
        result = compute_metric(metric, outcomes)
        @test length(result) == 2
        @test result[1] == (:mean_loss => 17.5)
        @test result[2].first == :var_loss
        @test result[2].second ≈ 41.666666666667 atol=0.01
    end

    @testset "Quantile" begin
        metric = Quantile(:cost_75, :cost, 0.75)
        result = compute_metric(metric, outcomes)
        @test result.first == :cost_75
        @test result.second ≈ 212.5 atol=0.1

        # Test validation
        @test_throws ArgumentError Quantile(:bad, :cost, 0.0)
        @test_throws ArgumentError Quantile(:bad, :cost, 1.0)
        @test_throws ArgumentError Quantile(:bad, :cost, -0.5)
        @test_throws ArgumentError Quantile(:bad, :cost, 1.5)
    end

    @testset "CustomMetric" begin
        metric = CustomMetric(:max_cost, outcomes -> maximum(o.cost for o in outcomes))
        result = compute_metric(metric, outcomes)
        @test result == (:max_cost => 250.0)
    end

    @testset "compute_metrics" begin
        metrics = [
            ExpectedValue(:mean_cost, :cost),
            Probability(:prob_success, o -> o.success),
            MeanAndVariance(:mean_loss, :var_loss, :loss),
        ]

        result = compute_metrics(metrics, outcomes)

        @test result isa NamedTuple
        @test result.mean_cost == 175.0
        @test result.prob_success == 0.5
        @test result.mean_loss == 17.5
        @test haskey(result, :var_loss)
    end

    @testset "_all_metric_names" begin
        metrics = [
            ExpectedValue(:mean_cost, :cost),
            MeanAndVariance(:mean_loss, :var_loss, :loss),
            Probability(:prob_ok, o -> true),
        ]

        names = SimOptDecisions._all_metric_names(metrics)
        @test :mean_cost in names
        @test :mean_loss in names
        @test :var_loss in names
        @test :prob_ok in names
        @test length(names) == 4
    end
end
