# ============================================================================
# Declarative Metrics System
# ============================================================================

using Statistics: mean, var, quantile

"""Abstract base type for declarative metric specifications."""
abstract type AbstractMetric end

"""Compute the mean of `field` across all outcomes."""
struct ExpectedValue <: AbstractMetric
    name::Symbol
    field::Symbol
end

"""Compute the fraction of outcomes satisfying `predicate`."""
struct Probability{F} <: AbstractMetric
    name::Symbol
    predicate::F
end

"""Compute both mean and variance of `field` across all outcomes."""
struct MeanAndVariance <: AbstractMetric
    mean_name::Symbol
    var_name::Symbol
    field::Symbol
end

"""Compute the variance of `field` across all outcomes."""
struct Variance <: AbstractMetric
    name::Symbol
    field::Symbol
end

"""Compute the `q`-th quantile of `field` across all outcomes."""
struct Quantile{T<:AbstractFloat} <: AbstractMetric
    name::Symbol
    field::Symbol
    q::T

    function Quantile(name::Symbol, field::Symbol, q::T) where {T<:AbstractFloat}
        0 < q < 1 || throw(ArgumentError("Quantile q must be in (0, 1), got $q"))
        new{T}(name, field, q)
    end
end

Quantile(name::Symbol, field::Symbol, q::Real) = Quantile(name, field, Float64(q))

"""Compute a custom metric using an arbitrary function."""
struct CustomMetric{F} <: AbstractMetric
    name::Symbol
    func::F
end

# ============================================================================
# Metric Computation
# ============================================================================

function compute_metric(m::ExpectedValue, outcomes)
    m.name => mean(getfield(o, m.field) for o in outcomes)
end
compute_metric(m::Probability, outcomes) = m.name => mean(m.predicate(o) for o in outcomes)
function compute_metric(m::Variance, outcomes)
    m.name => var([getfield(o, m.field) for o in outcomes])
end

function compute_metric(m::MeanAndVariance, outcomes)
    values = [getfield(o, m.field) for o in outcomes]
    return [m.mean_name => mean(values), m.var_name => var(values)]
end

function compute_metric(m::Quantile, outcomes)
    m.name => quantile([getfield(o, m.field) for o in outcomes], m.q)
end
compute_metric(m::CustomMetric, outcomes) = m.name => m.func(outcomes)

"""Compute all metrics and return as a NamedTuple."""
function compute_metrics(metrics::AbstractVector{<:AbstractMetric}, outcomes)
    pairs = Pair{Symbol,Real}[]
    for m in metrics
        result = compute_metric(m, outcomes)
        if result isa Vector
            append!(pairs, result)
        else
            push!(pairs, result)
        end
    end
    return NamedTuple(pairs)
end

# ============================================================================
# Metric Name Extraction
# ============================================================================

_metric_names(m::AbstractMetric) = [m.name]
_metric_names(m::MeanAndVariance) = [m.mean_name, m.var_name]

"""Get all metric names from a collection of metrics."""
function _all_metric_names(metrics::AbstractVector{<:AbstractMetric})
    names = Symbol[]
    for m in metrics
        append!(names, _metric_names(m))
    end
    return names
end
