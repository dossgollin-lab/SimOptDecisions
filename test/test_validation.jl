# Test types for "Scenario validation"
struct OptTestScenario1 <: AbstractScenario end
struct OptTestScenario2 <: AbstractScenario end

# Test types for "Policy interface validation"
struct BadOptPolicy <: AbstractPolicy end

struct GoodOptPolicy <: AbstractPolicy
    x::Float64
end

SimOptDecisions.param_bounds(::Type{GoodOptPolicy}) = [(0.0, 1.0)]
GoodOptPolicy(x::AbstractVector) = GoodOptPolicy(x[1])

struct BadBoundsPolicy <: AbstractPolicy
    x::Float64
end

SimOptDecisions.param_bounds(::Type{BadBoundsPolicy}) = [(1.0, 0.0)]  # lower > upper
BadBoundsPolicy(x::AbstractVector) = BadBoundsPolicy(x[1])

# Test types for "Validation hooks"
struct ValidatableParams <: AbstractConfig end
struct ValidatablePolicy <: AbstractPolicy end

# ============================================================================
# Tests
# ============================================================================

@testset "Validation" begin
    @testset "Scenario validation" begin
        @test SimOptDecisions._validate_scenarios([
            OptTestScenario1(), OptTestScenario1()
        ]) === nothing
        @test_throws ArgumentError SimOptDecisions._validate_scenarios([])
        @test_throws ArgumentError SimOptDecisions._validate_scenarios([
            OptTestScenario1(), OptTestScenario2()
        ])
    end

    @testset "Objectives validation" begin
        @test SimOptDecisions._validate_objectives([minimize(:cost)]) === nothing
        @test SimOptDecisions._validate_objectives([
            minimize(:cost), maximize(:reliability)
        ]) === nothing

        @test_throws ArgumentError SimOptDecisions._validate_objectives([])
        @test_throws ArgumentError SimOptDecisions._validate_objectives([
            minimize(:cost), minimize(:cost)
        ])  # Duplicate
    end

    @testset "Policy interface validation" begin
        # Policy without interface
        @test_throws ArgumentError SimOptDecisions._validate_policy_interface(BadOptPolicy)

        # Policy with interface
        @test SimOptDecisions._validate_policy_interface(GoodOptPolicy) === nothing

        # Test bounds validation
        @test_throws ArgumentError SimOptDecisions._validate_policy_interface(
            BadBoundsPolicy
        )
    end

    @testset "Constraint types" begin
        fc = FeasibilityConstraint(:bounds, p -> true)
        @test fc.name == :bounds
        @test fc.func(nothing) == true

        pc = PenaltyConstraint(:soft_limit, p -> 0.0, 10.0)
        @test pc.name == :soft_limit
        @test pc.weight == 10.0
        @test pc.func(nothing) == 0.0
        @test_throws ArgumentError PenaltyConstraint(:bad, p -> 0.0, -1.0)
    end

    @testset "Validation hooks" begin
        # Default implementations return true
        @test validate(ValidatableParams()) == true
        @test validate(ValidatablePolicy(), ValidatableParams()) == true
    end
end
