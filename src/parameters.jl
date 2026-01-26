# ============================================================================
# Parameter Types for Exploratory Modeling
# ============================================================================

using Random: AbstractRNG

"""Base type for typed parameters. Subtypes enable automatic flattening for `explore()`."""
abstract type AbstractParameter{T} end

# ============================================================================
# Simple Parameter Types
# ============================================================================

"""Continuous real-valued parameter with optional bounds."""
struct ContinuousParameter{T<:AbstractFloat} <: AbstractParameter{T}
    value::T
    bounds::Tuple{T,T}
end

function ContinuousParameter(value::T) where {T<:AbstractFloat}
    ContinuousParameter(value, (T(-Inf), T(Inf)))
end

"""Integer parameter with optional valid values constraint."""
struct DiscreteParameter{T<:Integer} <: AbstractParameter{T}
    value::T
    valid_values::Union{Nothing,Vector{T}}
end

DiscreteParameter(value::T) where {T<:Integer} = DiscreteParameter(value, nothing)

"""Categorical parameter with defined levels."""
struct CategoricalParameter{T} <: AbstractParameter{T}
    value::T
    levels::Vector{T}

    function CategoricalParameter(value::T, levels::Vector{T}) where {T}
        value ∈ levels || throw(ArgumentError("Value `$value` not in levels $levels"))
        new{T}(value, levels)
    end
end

"""Generic parameter for complex objects. Skipped in explore/flatten."""
struct GenericParameter{T} <: AbstractParameter{T}
    value::T
end

# ============================================================================
# TimeSeriesParameter
# ============================================================================

"""Error thrown when accessing TimeSeriesParameter with invalid time value."""
struct TimeSeriesParameterBoundsError <: Exception
    requested::Any
    available::Vector
end

function Base.showerror(io::IO, e::TimeSeriesParameterBoundsError)
    print(
        io, "TimeSeriesParameterBoundsError: time value $(e.requested) not in time_axis. "
    )
    if length(e.available) <= 10
        print(io, "Available: $(e.available)")
    else
        print(io, "Available range: $(first(e.available)) to $(last(e.available))")
    end
end

"""Time-indexed data. Index via `ts[t]` using TimeStep or integer position."""
struct TimeSeriesParameter{T<:AbstractFloat,I}
    time_axis::Vector{I}
    values::Vector{T}

    function TimeSeriesParameter(
        time_axis::Vector{I}, values::Vector{T}
    ) where {T<:AbstractFloat,I}
        isempty(values) && throw(ArgumentError("TimeSeriesParameter cannot be empty"))
        length(time_axis) != length(values) && throw(
            ArgumentError(
                "time_axis length ($(length(time_axis))) must match values length ($(length(values)))",
            ),
        )
        new{T,I}(time_axis, values)
    end
end

function TimeSeriesParameter(time_axis, values::Vector{T}) where {T<:AbstractFloat}
    TimeSeriesParameter(collect(time_axis), values)
end

function TimeSeriesParameter(time_axis, values)
    TimeSeriesParameter(collect(time_axis), collect(Float64, values))
end

function TimeSeriesParameter(values::Vector{T}) where {T<:AbstractFloat}
    TimeSeriesParameter(collect(1:length(values)), values)
end

TimeSeriesParameter(values) = TimeSeriesParameter(collect(Float64, values))

function Base.getindex(ts::TimeSeriesParameter{T,I}, t::TimeStep) where {T,I}
    idx = findfirst(==(t.val), ts.time_axis)
    isnothing(idx) && throw(TimeSeriesParameterBoundsError(t.val, ts.time_axis))
    ts.values[idx]
end

function Base.getindex(ts::TimeSeriesParameter{T,I}, i::Integer) where {T,I}
    (i < 1 || i > length(ts.values)) && throw(BoundsError(ts, i))
    ts.values[i]
end

Base.length(ts::TimeSeriesParameter) = length(ts.values)
Base.iterate(ts::TimeSeriesParameter) = iterate(ts.values)
Base.iterate(ts::TimeSeriesParameter, state) = iterate(ts.values, state)

# ============================================================================
# Value Extraction
# ============================================================================

"""Extract the value from a parameter."""
@inline value(p::AbstractParameter) = p.value
@inline value(ts::TimeSeriesParameter) = ts.values

"""Extract the time axis from a TimeSeriesParameter."""
@inline time_axis(ts::TimeSeriesParameter) = ts.time_axis

Base.getindex(p::AbstractParameter) = p.value

# ============================================================================
# Type Checking
# ============================================================================

"""Infer float type T from constructor arguments. Used by macro-generated constructors."""
function _infer_float_type(args...)
    for arg in args
        arg === nothing && continue
        if arg isa ContinuousParameter
            return typeof(arg.value)
        elseif arg isa TimeSeriesParameter
            return eltype(arg.values)
        elseif arg isa AbstractFloat
            return typeof(arg)
        end
    end
    return Float64
end

"""Check if a type is a valid parameter type for explore()."""
function _is_parameter_type(ftype)
    ftype <: AbstractParameter && return true
    ftype <: TimeSeriesParameter && return true
    if ftype isa UnionAll
        ftype <: AbstractParameter && return true
        ftype <: TimeSeriesParameter && return true
    end
    return false
end

"""Align a TimeSeriesParameter to a simulation time axis, returning a new parameter with positional (1:N) indexing."""
function align(ts::TimeSeriesParameter{T,I}, sim_times) where {T,I}
    sim_vals = collect(sim_times)
    indices = [findfirst(==(v), ts.time_axis) for v in sim_vals]
    missing_mask = isnothing.(indices)
    if any(missing_mask)
        throw(
            ArgumentError(
                "Cannot align: simulation time axis contains values not in TimeSeriesParameter. " *
                "Missing: $(sim_vals[missing_mask])",
            ),
        )
    end
    TimeSeriesParameter(collect(1:length(sim_vals)), ts.values[indices])
end

"""Get the value from an outcome field (used by exploration and backends)."""
function _get_outcome_value(field)
    if field isa AbstractParameter
        return field.value
    elseif field isa TimeSeriesParameter
        return field.values
    else
        return field
    end
end
