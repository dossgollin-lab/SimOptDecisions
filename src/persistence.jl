# ============================================================================
# Shared Parameters
# ============================================================================

"""
Parameters that are constant across all SOWs and not subject to optimization.
Examples: discount rate, planning horizon, physical constants.

Wrap your parameters in a NamedTuple for type stability and easy access.

# Example
```julia
sp = SharedParameters(discount_rate=0.03, horizon=50)
sp.discount_rate  # 0.03
sp.horizon        # 50
```
"""
struct SharedParameters{T<:NamedTuple}
    params::T
end

# Convenience constructor from keyword arguments
SharedParameters(; kwargs...) = SharedParameters(NamedTuple(kwargs))

# Allow direct field access
function Base.getproperty(sp::SharedParameters, name::Symbol)
    return name === :params ? getfield(sp, :params) : getfield(sp, :params)[name]
end

Base.propertynames(sp::SharedParameters) = propertynames(getfield(sp, :params))

# ============================================================================
# Experiment Configuration
# ============================================================================

"""
Complete configuration for a reproducible experiment.

# Fields
- `seed::Int`: Random seed for reproducibility
- `timestamp::DateTime`: When the experiment was created
- `git_commit::String`: Optional git commit hash (user-provided)
- `package_versions::String`: Optional package version info (user-provided)
- `sows::Vector{S}`: The SOWs used in this experiment
- `sow_source::String`: Description of how SOWs were generated
- `shared::SharedParameters`: SharedParameters for the experiment
- `backend::B`: Optimization backend configuration
"""
struct ExperimentConfig{S<:AbstractSOW,B<:AbstractOptimizationBackend}
    seed::Int
    timestamp::DateTime
    git_commit::String
    package_versions::String
    sows::Vector{S}
    sow_source::String
    shared::SharedParameters
    backend::B
end

# Convenience constructor with defaults
function ExperimentConfig(
    seed::Int,
    sows::AbstractVector{<:AbstractSOW},
    shared::SharedParameters,
    backend::AbstractOptimizationBackend;
    timestamp::DateTime=Dates.now(),
    git_commit::String="",
    package_versions::String="",
    sow_source::String="unspecified",
)
    _validate_sows(sows)
    return ExperimentConfig(
        seed,
        timestamp,
        git_commit,
        package_versions,
        collect(sows),
        sow_source,
        shared,
        backend,
    )
end

# ============================================================================
# Checkpoint Saving/Loading
# ============================================================================

"""
    save_checkpoint(filename, prob, optimizer_state; metadata="")

Save optimization state for crash recovery or later analysis.
"""
function save_checkpoint(
    filename::AbstractString, prob::OptimizationProblem, optimizer_state; metadata::String=""
)
    JLD2.jldsave(
        filename;
        problem=prob,
        optimizer_state=optimizer_state,
        metadata=metadata,
        timestamp=Dates.now(),
        version="0.1.0",
    )
    return nothing
end

"""
    load_checkpoint(filename) -> NamedTuple

Load a previously saved checkpoint.
Returns a NamedTuple with :problem, :optimizer_state, :metadata, :timestamp, :version
"""
function load_checkpoint(filename::AbstractString)
    data = JLD2.jldopen(filename, "r") do file
        (;
            problem=file["problem"],
            optimizer_state=file["optimizer_state"],
            metadata=file["metadata"],
            timestamp=file["timestamp"],
            version=file["version"],
        )
    end
    return data
end

# ============================================================================
# Experiment Saving/Loading
# ============================================================================

"""
    save_experiment(filename, config, result)

Save complete experiment configuration and results.
"""
function save_experiment(
    filename::AbstractString, config::ExperimentConfig, result::OptimizationResult
)
    JLD2.jldsave(filename; config=config, result=result, timestamp=Dates.now(), version="0.1.0")
    return nothing
end

"""
    load_experiment(filename) -> NamedTuple

Load a saved experiment.
"""
function load_experiment(filename::AbstractString)
    data = JLD2.jldopen(filename, "r") do file
        (; config=file["config"], result=file["result"], timestamp=file["timestamp"], version=file["version"])
    end
    return data
end
