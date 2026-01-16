# ============================================================================
# Definition Macros for Parameter Types
# ============================================================================

"""
    @scenariodef name begin ... end

Define a scenario type with parameter fields.

# Field Macros
- `@continuous name` - ContinuousParameter{Float64}, unbounded
- `@continuous name lo hi` - ContinuousParameter{Float64} with bounds
- `@discrete name` - DiscreteParameter{Int}, unconstrained
- `@discrete name [v1, v2, ...]` or `@discrete name range` - constrained values
- `@categorical name [:a, :b, ...]` - CategoricalParameter with levels
- `@timeseries name` - TimeSeriesParameter{Float64,Int}
- `@generic name` - GenericParameter{Any} (warns about limitations)

# Example
```julia
MyScenario = @scenariodef begin
    @continuous temperature
    @continuous precipitation 0.0 100.0
    @discrete num_events
    @categorical climate [:wet, :dry]
    @timeseries streamflow
end
```
"""
macro scenariodef(body)
    _defmacro_impl(:AbstractScenario, body, __module__)
end

macro scenariodef(name, body)
    _defmacro_impl(:AbstractScenario, body, __module__; name=name)
end

"""
    @policydef name begin ... end

Define a policy type with parameter fields.

See `@scenariodef` for field macro syntax.
"""
macro policydef(body)
    _defmacro_impl(:AbstractPolicy, body, __module__)
end

macro policydef(name, body)
    _defmacro_impl(:AbstractPolicy, body, __module__; name=name)
end

"""
    @configdef name begin ... end

Define a config type with parameter fields.

See `@scenariodef` for field macro syntax.
"""
macro configdef(body)
    _defmacro_impl(:AbstractConfig, body, __module__)
end

macro configdef(name, body)
    _defmacro_impl(:AbstractConfig, body, __module__; name=name)
end

"""
    @statedef name begin ... end

Define a state type with parameter fields.

See `@scenariodef` for field macro syntax.
"""
macro statedef(body)
    _defmacro_impl(:AbstractState, body, __module__)
end

macro statedef(name, body)
    _defmacro_impl(:AbstractState, body, __module__; name=name)
end

# ============================================================================
# Implementation
# ============================================================================

function _defmacro_impl(supertype::Symbol, body::Expr, mod::Module; name=nothing)
    if body.head !== :block
        throw(ArgumentError("Expected begin...end block"))
    end

    fields = Expr[]
    defaults = Dict{Symbol,Any}()
    has_generic = false
    generic_fields = Symbol[]

    for expr in body.args
        expr isa LineNumberNode && continue

        if expr isa Expr && expr.head === :macrocall
            field_expr, field_default, is_generic = _parse_field_macro(expr, mod)
            if field_expr !== nothing
                push!(fields, field_expr)
                if field_default !== nothing
                    defaults[field_expr.args[1]] = field_default
                end
                if is_generic
                    has_generic = true
                    push!(generic_fields, field_expr.args[1])
                end
            end
        elseif expr isa Expr && expr.head === :(::)
            # Allow explicit type annotations like `myfield::ContinuousParameter{Float32}`
            push!(fields, expr)
        end
    end

    if isempty(fields)
        throw(ArgumentError("No fields defined in block"))
    end

    # Generate warning for generic parameters
    warning_expr = if has_generic
        field_names = join(generic_fields, ", ")
        quote
            @warn """
            GenericParameter fields: $($field_names)
            These fields will be:
              - Skipped in explore() (not varied)
              - Excluded from to_table / file export
              - Not visualized
            Consider using CategoricalParameter to select from predefined options.
            """
        end
    else
        :()
    end

    # Build struct
    struct_expr = if name === nothing
        # Anonymous struct - return the type
        gensym_name = gensym("DefType")
        quote
            $warning_expr
            Base.@kwdef struct $gensym_name <: SimOptDecisions.$supertype
                $(fields...)
            end
            $gensym_name
        end
    else
        # Named struct
        quote
            $warning_expr
            Base.@kwdef struct $name <: SimOptDecisions.$supertype
                $(fields...)
            end
        end
    end

    return esc(struct_expr)
end

function _parse_field_macro(expr::Expr, mod::Module)
    macro_name = expr.args[1]
    args = filter(x -> !(x isa LineNumberNode), expr.args[2:end])

    if macro_name === Symbol("@continuous")
        return _parse_continuous(args), nothing, false
    elseif macro_name === Symbol("@discrete")
        return _parse_discrete(args), nothing, false
    elseif macro_name === Symbol("@categorical")
        return _parse_categorical(args), nothing, false
    elseif macro_name === Symbol("@timeseries")
        return _parse_timeseries(args), nothing, false
    elseif macro_name === Symbol("@generic")
        return _parse_generic(args), nothing, true
    else
        return nothing, nothing, false
    end
end

function _parse_continuous(args)
    if length(args) == 1
        # @continuous name - unbounded
        name = args[1]
        return :($name::ContinuousParameter{Float64})
    elseif length(args) == 3
        # @continuous name lo hi - bounded
        name, lo, hi = args
        return :($name::ContinuousParameter{Float64})
    else
        throw(ArgumentError("@continuous expects 1 or 3 arguments: name or name lo hi"))
    end
end

function _parse_discrete(args)
    if length(args) == 1
        name = args[1]
        return :($name::DiscreteParameter{Int})
    elseif length(args) == 2
        name = args[1]
        # Second arg is valid_values (vector or range)
        return :($name::DiscreteParameter{Int})
    else
        throw(ArgumentError("@discrete expects 1 or 2 arguments: name or name [values]"))
    end
end

function _parse_categorical(args)
    if length(args) == 2
        name, levels = args
        return :($name::CategoricalParameter{Symbol})
    else
        throw(ArgumentError("@categorical expects 2 arguments: name [:level1, :level2, ...]"))
    end
end

function _parse_timeseries(args)
    if length(args) == 1
        name = args[1]
        return :($name::TimeSeriesParameter{Float64,Int})
    elseif length(args) == 2
        name = args[1]
        # Second arg is value type
        return :($name::TimeSeriesParameter{Float64,Int})
    else
        throw(ArgumentError("@timeseries expects 1 or 2 arguments: name or name T"))
    end
end

function _parse_generic(args)
    if length(args) == 1
        name = args[1]
        return :($name::GenericParameter{Any})
    elseif length(args) == 2
        name, T = args
        return :($name::GenericParameter{$T})
    else
        throw(ArgumentError("@generic expects 1 or 2 arguments: name or name T"))
    end
end
