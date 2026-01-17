using TOML: TOML

# ============================================================================
# Package Version
# ============================================================================

const _PROJECT_TOML = joinpath(@__DIR__, "..", "Project.toml")
const PACKAGE_VERSION = let
    isfile(_PROJECT_TOML) ? TOML.parsefile(_PROJECT_TOML)["version"] : "unknown"
end

# ============================================================================
# Shared Parameters
# ============================================================================

"""Parameters constant across scenarios, not subject to optimization (e.g., discount rate)."""
struct SharedParameters{T<:NamedTuple}
    params::T
end

SharedParameters(; kwargs...) = SharedParameters(NamedTuple(kwargs))

function Base.getproperty(sp::SharedParameters, name::Symbol)
    return name === :params ? getfield(sp, :params) : getfield(sp, :params)[name]
end

Base.propertynames(sp::SharedParameters) = propertynames(getfield(sp, :params))

# ============================================================================
# Experiment Configuration
# ============================================================================

"""Complete configuration for a reproducible experiment."""
struct ExperimentConfig{S<:AbstractScenario,B<:AbstractOptimizationBackend}
    seed::Int
    timestamp::DateTime
    git_commit::String
    package_versions::String
    scenarios::Vector{S}
    scenario_source::String
    shared::SharedParameters
    backend::B
end

function ExperimentConfig(
    seed::Int,
    scenarios::AbstractVector{<:AbstractScenario},
    shared::SharedParameters,
    backend::AbstractOptimizationBackend;
    timestamp::DateTime=Dates.now(),
    git_commit::String="",
    package_versions::String="",
    scenario_source::String="unspecified",
)
    _validate_scenarios(scenarios)
    return ExperimentConfig(seed, timestamp, git_commit, package_versions, collect(scenarios), scenario_source, shared, backend)
end

# ============================================================================
# Checkpoint Saving/Loading
# ============================================================================

"""Save optimization state for crash recovery."""
function save_checkpoint(filename::AbstractString, prob::OptimizationProblem, optimizer_state; metadata::String="")
    JLD2.jldsave(filename; problem=prob, optimizer_state=optimizer_state, metadata=metadata, timestamp=Dates.now(), version=PACKAGE_VERSION)
    return nothing
end

"""Load a previously saved checkpoint."""
function load_checkpoint(filename::AbstractString)
    JLD2.jldopen(filename, "r") do file
        (; problem=file["problem"], optimizer_state=file["optimizer_state"], metadata=file["metadata"], timestamp=file["timestamp"], version=file["version"])
    end
end

# ============================================================================
# Experiment Saving/Loading
# ============================================================================

"""Save complete experiment configuration and results."""
function save_experiment(filename::AbstractString, config::ExperimentConfig, result::OptimizationResult)
    JLD2.jldsave(filename; config=config, result=result, timestamp=Dates.now(), version=PACKAGE_VERSION)
    return nothing
end

"""Load a saved experiment."""
function load_experiment(filename::AbstractString)
    JLD2.jldopen(filename, "r") do file
        (; config=file["config"], result=file["result"], timestamp=file["timestamp"], version=file["version"])
    end
end
