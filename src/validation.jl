# ============================================================================
# Parameter Type Validation
# ============================================================================

"""Thrown when types don't use required parameter types."""
struct ParameterTypeError <: Exception
    msg::String
end

Base.showerror(io::IO, e::ParameterTypeError) = print(io, e.msg)

const _VALIDATED_TYPES = Set{Type}()

"""Validate that all fields in type T are parameter types."""
function _validate_parameter_fields(::Type{T}, label::String) where {T}
    T in _VALIDATED_TYPES && return nothing

    errors = String[]

    for (fname, ftype) in zip(fieldnames(T), fieldtypes(T))
        _is_parameter_type(ftype) || push!(errors, "  - $fname :: $ftype")
    end

    if !isempty(errors)
        throw(
            ParameterTypeError(
                "$label type `$T` has non-parameter fields:\n" *
                join(errors, "\n") *
                "\n\nAll fields must be one of:\n" *
                "  - ContinuousParameter{T}\n" *
                "  - DiscreteParameter{T}\n" *
                "  - CategoricalParameter{T}\n" *
                "  - TimeSeriesParameter{T,I}\n" *
                "  - GenericParameter{T}",
            ),
        )
    end

    push!(_VALIDATED_TYPES, T)
    return nothing
end

const _STRICT_VALIDATION = Ref{Union{Nothing,Bool}}(nothing)

function _is_strict_validation()::Bool
    if isnothing(_STRICT_VALIDATION[])
        _STRICT_VALIDATION[] =
            lowercase(get(ENV, "SIMOPT_STRICT_VALIDATION", "false")) in ("true", "1", "yes")
    end
    return _STRICT_VALIDATION[]
end

"""Validate Scenario and Policy types (only when SIMOPT_STRICT_VALIDATION=true)."""
function _validate_simulation_types(scenario::AbstractScenario, policy::AbstractPolicy)
    _is_strict_validation() || return nothing
    _validate_parameter_fields(typeof(scenario), "Scenario")
    _validate_parameter_fields(typeof(policy), "Policy")
    return nothing
end

"""Validate Outcome type (only when SIMOPT_STRICT_VALIDATION=true)."""
function _validate_outcome_type(outcome)
    _is_strict_validation() || return nothing
    _validate_parameter_fields(typeof(outcome), "Outcome")
    return nothing
end

# ============================================================================
# Policy Interface Validation
# ============================================================================

"""Validate that a policy type implements param_bounds and vector constructor."""
function _validate_policy_interface(::Type{P}) where {P<:AbstractPolicy}
    bounds = try
        param_bounds(P)
    catch e
        if e isa ArgumentError && contains(e.msg, "not implemented")
            throw(ArgumentError("Policy type $P must implement `param_bounds(::Type{$P})`"))
        end
        rethrow(e)
    end

    isa(bounds, AbstractVector) || throw(
        ArgumentError(
            "param_bounds(::Type{$P}) must return an AbstractVector, got $(typeof(bounds))",
        ),
    )

    isempty(bounds) &&
        throw(ArgumentError("param_bounds(::Type{$P}) returned empty bounds"))

    for (i, b) in enumerate(bounds)
        (isa(b, Tuple) && length(b) == 2) ||
            throw(ArgumentError("param_bounds(::Type{$P})[$i] must be a 2-tuple, got $b"))
        b[1] > b[2] && throw(
            ArgumentError(
                "param_bounds(::Type{$P})[$i] has lower > upper: $(b[1]) > $(b[2])"
            ),
        )
    end

    sample_x = [(b[1] + b[2]) / 2 for b in bounds]
    test_policy = try
        P(sample_x)
    catch e
        throw(
            ArgumentError("$P must have a constructor accepting AbstractVector. Error: $e"),
        )
    end

    test_policy isa AbstractPolicy ||
        throw(ArgumentError("$P(x) must return an AbstractPolicy"))

    return nothing
end

# ============================================================================
# Scenario Validation
# ============================================================================

"""Validate that scenarios are a homogeneous collection of AbstractScenario."""
function _validate_scenarios(scenarios)
    isempty(scenarios) && throw(ArgumentError("Scenarios collection cannot be empty"))

    first_type = typeof(first(scenarios))
    first(scenarios) isa AbstractScenario || throw(
        ArgumentError("Scenarios must be subtypes of AbstractScenario, got $first_type")
    )

    for (i, scenario) in enumerate(scenarios)
        typeof(scenario) === first_type || throw(
            ArgumentError(
                "All scenarios must be the same type. Scenario 1 is $first_type, scenario $i is $(typeof(scenario))",
            ),
        )
    end

    return nothing
end

# ============================================================================
# Objectives Validation
# ============================================================================

"""Validate that objectives are well-formed."""
function _validate_objectives(objectives)
    isempty(objectives) && throw(ArgumentError("At least one objective is required"))

    names = Set{Symbol}()
    for obj in objectives
        obj isa Objective || throw(
            ArgumentError(
                "Objectives must be Objective structs. Use `minimize(:name)` or `maximize(:name)`.",
            ),
        )
        obj.name in names && throw(ArgumentError("Duplicate objective name: $(obj.name)"))
        push!(names, obj.name)
    end

    return nothing
end

# ============================================================================
# Config Validation Hooks
# ============================================================================

"""Override for domain-specific config validation. Default returns true."""
validate(config::AbstractConfig) = true

"""Override for domain-specific policy/config validation. Default returns true."""
validate(policy::AbstractPolicy, config::AbstractConfig) = true

# ============================================================================
# Constraint Types
# ============================================================================

abstract type AbstractConstraint end

"""A constraint that must be satisfied for feasibility. Function returns true if feasible."""
struct FeasibilityConstraint{F} <: AbstractConstraint
    name::Symbol
    func::F
end

"""A constraint that adds a penalty when violated. Function returns 0.0 for no violation."""
struct PenaltyConstraint{T<:AbstractFloat,F} <: AbstractConstraint
    name::Symbol
    func::F
    weight::T

    function PenaltyConstraint(name::Symbol, func::F, weight::T) where {T<:AbstractFloat,F}
        weight >= 0 || throw(ArgumentError("Penalty weight must be non-negative"))
        new{T,F}(name, func, weight)
    end
end
