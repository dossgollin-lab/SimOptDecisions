# ============================================================================
# Executor Abstraction for Simulation Execution
# ============================================================================

"""Base type for execution strategies."""
abstract type AbstractExecutor end

"""Configuration for Common Random Numbers (CRN) variance reduction."""
struct CRNConfig
    enabled::Bool
    base_seed::UInt64
end

CRNConfig(; enabled::Bool=true, seed::Integer=1234) = CRNConfig(enabled, UInt64(seed))

"""Create a deterministic RNG stream for a specific scenario index."""
function create_scenario_rng(config::CRNConfig, scenario_idx::Int)
    seed = config.base_seed + UInt64(scenario_idx - 1) * UInt64(0x9E3779B97F4A7C15)
    Random.Xoshiro(seed)
end

# ============================================================================
# Sequential Executor
# ============================================================================

"""Execute simulations sequentially on a single thread."""
struct SequentialExecutor <: AbstractExecutor
    crn::CRNConfig
end

SequentialExecutor(; crn::Bool=true, seed::Integer=1234) =
    SequentialExecutor(CRNConfig(; enabled=crn, seed))

function execute_exploration(
    executor::SequentialExecutor,
    config::AbstractConfig,
    scenarios::AbstractVector{<:AbstractScenario},
    policies::AbstractVector{<:AbstractPolicy},
    callback::Function;
    progress::Bool=true,
)
    n_policies = length(policies)
    n_scenarios = length(scenarios)
    n_total = n_policies * n_scenarios

    prog = progress ? Progress(n_total; desc="Exploring: ", showspeed=true) : nothing

    for (p_idx, policy) in enumerate(policies)
        for (s_idx, scenario) in enumerate(scenarios)
            rng = if executor.crn.enabled
                create_scenario_rng(executor.crn, s_idx)
            else
                Random.default_rng()
            end

            outcome = simulate(config, scenario, policy, rng)
            callback(p_idx, s_idx, outcome)

            !isnothing(prog) && next!(prog)
        end
    end
end

function execute_traced_exploration(
    executor::SequentialExecutor,
    config::AbstractConfig,
    scenarios::AbstractVector{<:AbstractScenario},
    policies::AbstractVector{<:AbstractPolicy},
    callback::Function;
    progress::Bool=true,
)
    n_policies = length(policies)
    n_scenarios = length(scenarios)
    n_total = n_policies * n_scenarios

    prog = progress ? Progress(n_total; desc="Exploring (traced): ", showspeed=true) : nothing

    for (p_idx, policy) in enumerate(policies)
        for (s_idx, scenario) in enumerate(scenarios)
            rng = if executor.crn.enabled
                create_scenario_rng(executor.crn, s_idx)
            else
                Random.default_rng()
            end

            outcome, trace = simulate_traced(config, scenario, policy, rng)
            callback(p_idx, s_idx, outcome, trace)

            !isnothing(prog) && next!(prog)
        end
    end
end

# ============================================================================
# Threaded Executor
# ============================================================================

"""Execute simulations in parallel using Julia threads."""
struct ThreadedExecutor <: AbstractExecutor
    crn::CRNConfig
    ntasks::Int
end

function ThreadedExecutor(; crn::Bool=true, seed::Integer=1234, ntasks::Int=Threads.nthreads())
    ThreadedExecutor(CRNConfig(; enabled=crn, seed), ntasks)
end

function execute_exploration(
    executor::ThreadedExecutor,
    config::AbstractConfig,
    scenarios::AbstractVector{<:AbstractScenario},
    policies::AbstractVector{<:AbstractPolicy},
    callback::Function;
    progress::Bool=true,
)
    n_policies = length(policies)
    n_scenarios = length(scenarios)
    n_total = n_policies * n_scenarios

    prog = progress ? Progress(n_total; desc="Exploring (threaded): ", showspeed=true) : nothing
    lock = ReentrantLock()

    work_items = [(p_idx, s_idx) for p_idx in 1:n_policies for s_idx in 1:n_scenarios]

    Threads.@threads for (p_idx, s_idx) in work_items
        policy = policies[p_idx]
        scenario = scenarios[s_idx]

        rng = if executor.crn.enabled
            create_scenario_rng(executor.crn, s_idx)
        else
            Random.Xoshiro()
        end

        outcome = simulate(config, scenario, policy, rng)

        Base.@lock lock begin
            callback(p_idx, s_idx, outcome)
            !isnothing(prog) && next!(prog)
        end
    end
end

function execute_traced_exploration(
    executor::ThreadedExecutor,
    config::AbstractConfig,
    scenarios::AbstractVector{<:AbstractScenario},
    policies::AbstractVector{<:AbstractPolicy},
    callback::Function;
    progress::Bool=true,
)
    n_policies = length(policies)
    n_scenarios = length(scenarios)
    n_total = n_policies * n_scenarios

    prog = progress ? Progress(n_total; desc="Exploring (threaded, traced): ", showspeed=true) : nothing
    lock = ReentrantLock()

    work_items = [(p_idx, s_idx) for p_idx in 1:n_policies for s_idx in 1:n_scenarios]

    Threads.@threads for (p_idx, s_idx) in work_items
        policy = policies[p_idx]
        scenario = scenarios[s_idx]

        rng = if executor.crn.enabled
            create_scenario_rng(executor.crn, s_idx)
        else
            Random.Xoshiro()
        end

        outcome, trace = simulate_traced(config, scenario, policy, rng)

        Base.@lock lock begin
            callback(p_idx, s_idx, outcome, trace)
            !isnothing(prog) && next!(prog)
        end
    end
end

# ============================================================================
# Distributed Executor
# ============================================================================

"""Execute simulations across distributed workers using Distributed.jl."""
struct DistributedExecutor <: AbstractExecutor
    crn::CRNConfig
end

DistributedExecutor(; crn::Bool=true, seed::Integer=1234) =
    DistributedExecutor(CRNConfig(; enabled=crn, seed))

function execute_exploration(
    executor::DistributedExecutor,
    config::AbstractConfig,
    scenarios::AbstractVector{<:AbstractScenario},
    policies::AbstractVector{<:AbstractPolicy},
    callback::Function;
    progress::Bool=true,
)
    n_policies = length(policies)
    n_scenarios = length(scenarios)
    n_total = n_policies * n_scenarios

    prog = progress ? Progress(n_total; desc="Exploring (distributed): ", showspeed=true) : nothing

    work_items = [(p_idx, s_idx, policies[p_idx], scenarios[s_idx])
                  for p_idx in 1:n_policies for s_idx in 1:n_scenarios]

    crn_config = executor.crn
    results = asyncmap(work_items; ntasks=n_total) do (p_idx, s_idx, policy, scenario)
        rng = if crn_config.enabled
            create_scenario_rng(crn_config, s_idx)
        else
            Random.Xoshiro()
        end
        outcome = simulate(config, scenario, policy, rng)
        (p_idx, s_idx, outcome)
    end

    for (p_idx, s_idx, outcome) in results
        callback(p_idx, s_idx, outcome)
        !isnothing(prog) && next!(prog)
    end
end

function execute_traced_exploration(
    ::DistributedExecutor,
    ::AbstractConfig,
    ::AbstractVector{<:AbstractScenario},
    ::AbstractVector{<:AbstractPolicy},
    ::Function;
    progress::Bool=true,
)
    throw(ArgumentError(
        "DistributedExecutor does not support traced exploration. " *
        "Traces contain complex state that cannot be efficiently serialized across workers. " *
        "Use SequentialExecutor or ThreadedExecutor for traced exploration."
    ))
end
