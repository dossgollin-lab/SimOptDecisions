# ============================================================================
# Definition Macros for Parameter Types
# ============================================================================

"""Define a scenario type. Use @continuous, @discrete, @categorical, @timeseries, @generic for fields."""
macro scenariodef(body)
    _defmacro_impl(:AbstractScenario, body, __module__)
end

macro scenariodef(name, body)
    _defmacro_impl(:AbstractScenario, body, __module__; name=name)
end

"""Define a policy type. Same field syntax as @scenariodef."""
macro policydef(body)
    _defmacro_impl(:AbstractPolicy, body, __module__)
end

macro policydef(name, body)
    _defmacro_impl(:AbstractPolicy, body, __module__; name=name)
end

"""Define a config type. Same field syntax as @scenariodef."""
macro configdef(body)
    _defmacro_impl(:AbstractConfig, body, __module__)
end

macro configdef(name, body)
    _defmacro_impl(:AbstractConfig, body, __module__; name=name)
end

"""Define a state type. Same field syntax as @scenariodef."""
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
    body.head === :block || throw(ArgumentError("Expected begin...end block"))

    fields = Expr[]
    for expr in body.args
        expr isa LineNumberNode && continue
        if expr isa Expr && expr.head === :macrocall
            field_expr, _, _ = _parse_field_macro(expr, mod)
            field_expr !== nothing && push!(fields, field_expr)
        elseif expr isa Expr && expr.head === :(::)
            push!(fields, expr)
        end
    end

    isempty(fields) && throw(ArgumentError("No fields defined in block"))

    struct_expr = if name === nothing
        gensym_name = gensym("DefType")
        quote
            Base.@kwdef struct $gensym_name <: SimOptDecisions.$supertype
                $(fields...)
            end
            $gensym_name
        end
    else
        quote
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
    length(args) in (1, 3) || throw(ArgumentError("@continuous expects 1 or 3 arguments"))
    name = args[1]
    return :($name::ContinuousParameter{Float64})
end

function _parse_discrete(args)
    length(args) in (1, 2) || throw(ArgumentError("@discrete expects 1 or 2 arguments"))
    name = args[1]
    return :($name::DiscreteParameter{Int})
end

function _parse_categorical(args)
    length(args) == 2 || throw(ArgumentError("@categorical expects 2 arguments"))
    name = args[1]
    return :($name::CategoricalParameter{Symbol})
end

function _parse_timeseries(args)
    length(args) in (1, 2) || throw(ArgumentError("@timeseries expects 1 or 2 arguments"))
    name = args[1]
    return :($name::TimeSeriesParameter{Float64,Int})
end

function _parse_generic(args)
    if length(args) == 1
        name = args[1]
        return :($name::GenericParameter{Any})
    elseif length(args) == 2
        name, T = args
        return :($name::GenericParameter{$T})
    else
        throw(ArgumentError("@generic expects 1 or 2 arguments"))
    end
end
