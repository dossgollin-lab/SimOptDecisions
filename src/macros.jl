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

"""Define an outcome type for exploration results. Same field syntax as @scenariodef."""
macro outcomedef(body)
    _defmacro_impl(:AbstractOutcome, body, __module__)
end

macro outcomedef(name, body)
    _defmacro_impl(:AbstractOutcome, body, __module__; name=name)
end

# ============================================================================
# Field Info for Macro Parsing
# ============================================================================

struct FieldInfo
    name::Symbol
    type_expr::Expr          # The field type expression (may use T)
    uses_T::Bool             # Whether this field uses the T type parameter
    wrap_kind::Symbol        # :continuous, :discrete, :categorical, :timeseries, :generic, :none
    bounds::Union{Nothing,Tuple{Any,Any}}  # For @continuous with bounds
    levels::Union{Nothing,Any}             # For @categorical
end

# ============================================================================
# Implementation
# ============================================================================

function _defmacro_impl(supertype::Symbol, body::Expr, mod::Module; name=nothing)
    body.head === :block || throw(ArgumentError("Expected begin...end block"))

    # Parse all fields
    field_infos = FieldInfo[]
    for expr in body.args
        expr isa LineNumberNode && continue
        if expr isa Expr && expr.head === :macrocall
            info = _parse_field_macro(expr, mod)
            info !== nothing && push!(field_infos, info)
        elseif expr isa Expr && expr.head === :(::)
            # Plain typed field - no wrapping
            fname = expr.args[1]
            ftype = expr.args[2]
            push!(
                field_infos,
                FieldInfo(fname, :($fname::$ftype), false, :none, nothing, nothing),
            )
        end
    end

    isempty(field_infos) && throw(ArgumentError("No fields defined in block"))

    # Check if we need a type parameter
    needs_T = any(f -> f.uses_T, field_infos)

    # Build field expressions for struct
    fields = [f.type_expr for f in field_infos]

    # Generate struct name
    struct_name = name === nothing ? gensym("DefType") : name

    # Generate the struct definition
    if needs_T
        T = :T
        struct_def = quote
            struct $struct_name{$T<:AbstractFloat} <: SimOptDecisions.$supertype
                $(fields...)
            end
        end
    else
        struct_def = quote
            struct $struct_name <: SimOptDecisions.$supertype
                $(fields...)
            end
        end
    end

    # Generate auto-wrapping constructor
    constructor_def = _generate_constructor(struct_name, field_infos, needs_T, supertype)

    # Generate vector constructor for policy types
    vector_constructor_def = _generate_vector_constructor(
        struct_name, field_infos, supertype
    )

    # Combine struct, constructor, and vector constructor
    result = if name === nothing
        quote
            $struct_def
            $constructor_def
            $vector_constructor_def
            $struct_name
        end
    else
        quote
            $struct_def
            $constructor_def
            $vector_constructor_def
        end
    end

    return esc(result)
end

function _generate_constructor(struct_name, field_infos, needs_T, supertype)
    # Build keyword arguments (all required, no defaults)
    kwargs = [Expr(:kw, f.name, :nothing) for f in field_infos]

    # Build field wrapping expressions
    wrap_exprs = []
    for f in field_infos
        wrapped = _wrap_field_expr(f)
        push!(wrap_exprs, wrapped)
    end

    # Add validation call for configs
    validate_call = if supertype === :AbstractConfig
        :(SimOptDecisions.validate_config(obj))
    else
        nothing
    end

    if needs_T
        # Collect names of continuous/timeseries fields for T inference
        t_fields = [
            f.name for f in field_infos if f.wrap_kind in (:continuous, :timeseries)
        ]

        quote
            function $struct_name(; $(kwargs...))
                T = SimOptDecisions._infer_float_type($(t_fields...))
                obj = $struct_name{T}($(wrap_exprs...))
                $validate_call
                return obj
            end
        end
    else
        quote
            function $struct_name(; $(kwargs...))
                obj = $struct_name($(wrap_exprs...))
                $validate_call
                return obj
            end
        end
    end
end

"""Generate vector constructor for @policydef types with only bounded @continuous fields."""
function _generate_vector_constructor(struct_name, field_infos, supertype)
    supertype === :AbstractPolicy || return nothing

    # Only auto-generate if ALL fields are bounded @continuous
    all(f -> f.wrap_kind === :continuous && f.bounds !== nothing, field_infos) ||
        return nothing

    kw_pairs = [Expr(:kw, f.name, :(x[$i])) for (i, f) in enumerate(field_infos)]
    return quote
        function $struct_name(x::AbstractVector)
            return $struct_name(; $(kw_pairs...))
        end
    end
end

function _wrap_field_expr(f::FieldInfo)
    name = f.name
    if f.wrap_kind === :continuous
        if f.bounds !== nothing
            lo, hi = f.bounds
            quote
                if $name isa ContinuousParameter
                    $name
                else
                    ContinuousParameter(T($name), (T($lo), T($hi)))
                end
            end
        else
            quote
                if $name isa ContinuousParameter
                    $name
                else
                    ContinuousParameter(T($name))
                end
            end
        end
    elseif f.wrap_kind === :discrete
        quote
            if $name isa DiscreteParameter
                $name
            else
                DiscreteParameter(Int($name))
            end
        end
    elseif f.wrap_kind === :categorical
        levels = f.levels
        quote
            if $name isa CategoricalParameter
                $name
            else
                CategoricalParameter($name, $levels)
            end
        end
    elseif f.wrap_kind === :timeseries
        quote
            if $name isa TimeSeriesParameter
                $name
            else
                TimeSeriesParameter($name)
            end
        end
    elseif f.wrap_kind === :generic
        quote
            if $name isa GenericParameter
                $name
            else
                GenericParameter{Any}($name)
            end
        end
    else
        # Plain field, no wrapping
        name
    end
end

function _parse_field_macro(expr::Expr, mod::Module)
    macro_name = expr.args[1]
    args = filter(x -> !(x isa LineNumberNode), expr.args[2:end])

    if macro_name === Symbol("@continuous")
        return _parse_continuous(args)
    elseif macro_name === Symbol("@discrete")
        return _parse_discrete(args)
    elseif macro_name === Symbol("@categorical")
        return _parse_categorical(args)
    elseif macro_name === Symbol("@timeseries")
        return _parse_timeseries(args)
    elseif macro_name === Symbol("@generic")
        return _parse_generic(args)
    else
        return nothing
    end
end

function _parse_continuous(args)
    length(args) in (1, 3) || throw(ArgumentError("@continuous expects 1 or 3 arguments"))
    name = args[1]
    if length(args) == 3
        lo, hi = args[2], args[3]
        FieldInfo(
            name, :($name::ContinuousParameter{T}), true, :continuous, (lo, hi), nothing
        )
    else
        FieldInfo(
            name, :($name::ContinuousParameter{T}), true, :continuous, nothing, nothing
        )
    end
end

function _parse_discrete(args)
    length(args) in (1, 2) || throw(ArgumentError("@discrete expects 1 or 2 arguments"))
    name = args[1]
    FieldInfo(name, :($name::DiscreteParameter{Int}), false, :discrete, nothing, nothing)
end

function _parse_categorical(args)
    length(args) == 2 || throw(ArgumentError("@categorical expects 2 arguments"))
    name, levels = args[1], args[2]
    FieldInfo(
        name, :($name::CategoricalParameter{Symbol}), false, :categorical, nothing, levels
    )
end

"""Parse @timeseries field. Index type is always Int (1-based position); actual time values
(e.g. dates, years) live in TimeStep.val and can be aligned via `align()`."""
function _parse_timeseries(args)
    length(args) in (1, 2) || throw(ArgumentError("@timeseries expects 1 or 2 arguments"))
    name = args[1]
    FieldInfo(
        name, :($name::TimeSeriesParameter{T,Int}), true, :timeseries, nothing, nothing
    )
end

function _parse_generic(args)
    if length(args) == 1
        name = args[1]
        FieldInfo(name, :($name::GenericParameter{Any}), false, :generic, nothing, nothing)
    elseif length(args) == 2
        name, T = args
        FieldInfo(name, :($name::GenericParameter{$T}), false, :generic, nothing, nothing)
    else
        throw(ArgumentError("@generic expects 1 or 2 arguments"))
    end
end
