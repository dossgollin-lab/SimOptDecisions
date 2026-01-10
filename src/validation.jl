# ============================================================================
# Policy Interface Validation
# ============================================================================

"""
Validate that a policy type implements the required optimization interface:
- `param_bounds(::Type{P})` returns vector of (lower, upper) tuples
- `P(x::AbstractVector)` constructor exists
"""
function _validate_policy_interface(::Type{P}) where {P<:AbstractPolicy}
    # Check param_bounds is implemented and returns correct type
    bounds = try
        param_bounds(P)
    catch e
        if e isa ArgumentError && contains(e.msg, "not implemented")
            throw(
                ArgumentError(
                    "Policy type $P must implement `param_bounds(::Type{$P})` " *
                    "returning a Vector of (lower, upper) tuples",
                ),
            )
        end
        rethrow(e)
    end

    if !isa(bounds, AbstractVector)
        throw(
            ArgumentError(
                "param_bounds(::Type{$P}) must return an AbstractVector of tuples, " *
                "got $(typeof(bounds))",
            ),
        )
    end

    if isempty(bounds)
        throw(
            ArgumentError(
                "param_bounds(::Type{$P}) returned empty bounds. " *
                "Policies must have at least one parameter.",
            ),
        )
    end

    # Validate each bound is a 2-tuple with lower <= upper
    for (i, b) in enumerate(bounds)
        if !isa(b, Tuple) || length(b) != 2
            throw(
                ArgumentError(
                    "param_bounds(::Type{$P})[$i] must be a 2-tuple (lower, upper), got $b"
                ),
            )
        end
        if b[1] > b[2]
            throw(
                ArgumentError(
                    "param_bounds(::Type{$P})[$i] has lower > upper: $(b[1]) > $(b[2])"
                ),
            )
        end
    end

    # Check constructor works with sample parameters
    sample_x = [(b[1] + b[2]) / 2 for b in bounds]
    test_policy = try
        P(sample_x)
    catch e
        throw(
            ArgumentError(
                "$P must have a constructor accepting AbstractVector. " *
                "Add: $P(x::AbstractVector{T}) where T<:AbstractFloat = ...\n" *
                "Original error: $e",
            ),
        )
    end

    if !(test_policy isa AbstractPolicy)
        throw(
            ArgumentError("$P(x) must return an AbstractPolicy, got $(typeof(test_policy))")
        )
    end

    return nothing
end

# ============================================================================
# SOW Validation
# ============================================================================

"""
Validate that SOWs are a homogeneous collection of AbstractSOW.
"""
function _validate_sows(sows)
    if isempty(sows)
        throw(ArgumentError("SOWs collection cannot be empty"))
    end

    # Check all are AbstractSOW
    first_type = typeof(first(sows))
    if !(first(sows) isa AbstractSOW)
        throw(ArgumentError("SOWs must be subtypes of AbstractSOW, got $(first_type)"))
    end

    # Check homogeneity
    for (i, sow) in enumerate(sows)
        if typeof(sow) !== first_type
            throw(
                ArgumentError(
                    "All SOWs must be the same concrete type. " *
                    "SOW 1 is $(first_type), but SOW $i is $(typeof(sow))",
                ),
            )
        end
    end

    return nothing
end

# ============================================================================
# Objectives Validation
# ============================================================================

"""
Validate that objectives are well-formed.
"""
function _validate_objectives(objectives)
    if isempty(objectives)
        throw(ArgumentError("At least one objective is required"))
    end

    names = Set{Symbol}()
    for obj in objectives
        if !(obj isa Objective)
            throw(
                ArgumentError(
                    "Objectives must be Objective structs, got $(typeof(obj)). " *
                    "Use `minimize(:name)` or `maximize(:name)`.",
                ),
            )
        end
        if obj.name in names
            throw(ArgumentError("Duplicate objective name: $(obj.name)"))
        end
        push!(names, obj.name)
    end

    return nothing
end

# ============================================================================
# Config Validation Hooks
# ============================================================================

"""
    validate(config::AbstractConfig) -> Bool

Override this to add domain-specific validation for your config.
Default returns true (valid).
"""
validate(config::AbstractConfig) = true

"""
    validate(policy::AbstractPolicy, config::AbstractConfig) -> Bool

Override this to add domain-specific validation for policy/config compatibility.
Default returns true (valid).
"""
validate(policy::AbstractPolicy, config::AbstractConfig) = true

# ============================================================================
# Constraint Types
# ============================================================================

abstract type AbstractConstraint end

"""
A constraint that must be satisfied for a solution to be feasible.
The function should return true if the policy is feasible.
"""
struct FeasibilityConstraint{F} <: AbstractConstraint
    name::Symbol
    func::F  # policy -> Bool (true = feasible)
end

"""
A constraint that adds a penalty to the objective(s) when violated.
The function should return 0.0 for no violation, positive for violation.
"""
struct PenaltyConstraint{T<:AbstractFloat,F} <: AbstractConstraint
    name::Symbol
    func::F  # policy -> Float64 (0.0 = no violation)
    weight::T

    function PenaltyConstraint(name::Symbol, func::F, weight::T) where {T<:AbstractFloat,F}
        weight >= 0 || throw(ArgumentError("Penalty weight must be non-negative"))
        new{T,F}(name, func, weight)
    end
end

# ============================================================================
# Full Problem Validation
# ============================================================================

"""
Validate an OptimizationProblem before running optimization.
Called automatically by `optimize()`.
"""
function _validate_problem(prob)
    # Re-validate components (in case user modified after construction)
    _validate_sows(prob.sows)
    _validate_policy_interface(prob.policy_type)
    _validate_objectives(prob.objectives)

    # Validate config
    if !validate(prob.config)
        throw(ArgumentError("Config validation failed"))
    end

    # Validate batch size against SOW count
    n_sows = length(prob.sows)
    batch = prob.batch_size
    if batch isa FixedBatch && batch.n > n_sows
        throw(ArgumentError("FixedBatch size $(batch.n) exceeds number of SOWs ($n_sows)"))
    end

    return nothing
end
