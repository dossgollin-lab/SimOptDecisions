# ============================================================================
# Declarative Metrics System
# ============================================================================

using Statistics: mean, var, quantile

"""Abstract base type for declarative metric specifications."""
abstract type AbstractMetric end

"""
    ExpectedValue(name::Symbol, field::Symbol)

Compute the mean of `field` across all outcomes.

# Example
```julia
ExpectedValue(:expected_cost, :total_cost)
# Computes: mean(o.total_cost for o in outcomes)
```
"""
struct ExpectedValue <: AbstractMetric
    name::Symbol
    field::Symbol
end

"""
    Probability(name::Symbol, predicate)

Compute the fraction of outcomes satisfying `predicate`.

# Example
```julia
Probability(:prob_no_flood, o -> o.n_floods == 0)
# Computes: mean(o.n_floods == 0 for o in outcomes)
```
"""
struct Probability{F} <: AbstractMetric
    name::Symbol
    predicate::F
end

"""
    MeanAndVariance(mean_name::Symbol, var_name::Symbol, field::Symbol)

Compute both mean and variance of `field` across all outcomes.

# Example
```julia
MeanAndVariance(:mean_loss, :var_loss, :flood_loss)
```
"""
struct MeanAndVariance <: AbstractMetric
    mean_name::Symbol
    var_name::Symbol
    field::Symbol
end

"""
    Variance(name::Symbol, field::Symbol)

Compute the variance of `field` across all outcomes.
"""
struct Variance <: AbstractMetric
    name::Symbol
    field::Symbol
end

"""
    Quantile(name::Symbol, field::Symbol, q)

Compute the `q`-th quantile of `field` across all outcomes.

# Example
```julia
Quantile(:cost_95, :total_cost, 0.95)
# Computes: quantile([o.total_cost for o in outcomes], 0.95)
```
"""
struct Quantile{T<:AbstractFloat} <: AbstractMetric
    name::Symbol
    field::Symbol
    q::T

    function Quantile(name::Symbol, field::Symbol, q::T) where {T<:AbstractFloat}
        0 < q < 1 || throw(ArgumentError("Quantile q must be in (0, 1), got $q"))
        new{T}(name, field, q)
    end
end

# Convenience constructor for literal floats
Quantile(name::Symbol, field::Symbol, q::Real) = Quantile(name, field, Float64(q))

"""
    CustomMetric(name::Symbol, func)

Compute a custom metric using an arbitrary function.

# Example
```julia
CustomMetric(:sharpe_ratio, outcomes -> mean_return(outcomes) / std_return(outcomes))
```
"""
struct CustomMetric{F} <: AbstractMetric
    name::Symbol
    func::F
end

# ============================================================================
# Metric Computation
# ============================================================================

"""
    compute_metric(metric::AbstractMetric, outcomes) -> Pair or Vector{Pair}

Compute a single metric from outcomes.
"""
function compute_metric(m::ExpectedValue, outcomes)
    return m.name => mean(getfield(o, m.field) for o in outcomes)
end

function compute_metric(m::Probability, outcomes)
    return m.name => mean(m.predicate(o) for o in outcomes)
end

function compute_metric(m::Variance, outcomes)
    values = [getfield(o, m.field) for o in outcomes]
    return m.name => var(values)
end

function compute_metric(m::MeanAndVariance, outcomes)
    values = [getfield(o, m.field) for o in outcomes]
    return [m.mean_name => mean(values), m.var_name => var(values)]
end

function compute_metric(m::Quantile, outcomes)
    values = [getfield(o, m.field) for o in outcomes]
    return m.name => quantile(values, m.q)
end

function compute_metric(m::CustomMetric, outcomes)
    return m.name => m.func(outcomes)
end

"""
    compute_metrics(metrics::Vector{<:AbstractMetric}, outcomes) -> NamedTuple

Compute all metrics and return as a NamedTuple.
"""
function compute_metrics(metrics::AbstractVector{<:AbstractMetric}, outcomes)
    pairs = Pair{Symbol,Float64}[]
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
# Metric Name Extraction (for validation)
# ============================================================================

"""Extract all metric names produced by a metric."""
function _metric_names(m::AbstractMetric)
    return [m.name]
end

function _metric_names(m::MeanAndVariance)
    return [m.mean_name, m.var_name]
end

"""Get all metric names from a collection of metrics."""
function _all_metric_names(metrics::AbstractVector{<:AbstractMetric})
    names = Symbol[]
    for m in metrics
        append!(names, _metric_names(m))
    end
    return names
end
