# ============================================================================
# Interface Functions - Users must implement these for their models
# ============================================================================

"""
Create initial state for a simulation.
Must be implemented by user.
"""
function initialize end

function initialize(model::AbstractSystemModel, sow::AbstractSOW, rng::AbstractRNG)
    return error(
        "Implement `SimOptDecisions.initialize(::$(typeof(model)), ::$(typeof(sow)), ::AbstractRNG)` " *
        "to return initial state",
    )
end

"""
Advance simulation by one time step.
Must be implemented by user.
"""
function step end

function step(
    state::AbstractState,
    model::AbstractSystemModel,
    sow::AbstractSOW,
    policy::AbstractPolicy,
    t::TimeStep,
    rng::AbstractRNG,
)
    return error(
        "Implement `SimOptDecisions.step(::$(typeof(state)), ::$(typeof(model)), " *
        "::$(typeof(sow)), ::$(typeof(policy)), ::TimeStep, ::AbstractRNG)` to return new state",
    )
end

"""
Return the time points for simulation.
Must be implemented by user.
"""
function time_axis end

function time_axis(model::AbstractSystemModel, sow::AbstractSOW)
    return error(
        "Implement `SimOptDecisions.time_axis(::$(typeof(model)), ::$(typeof(sow)))` " *
        "to return iterable of time points (e.g., 1:100, Date(2020):Year(1):Date(2050))",
    )
end

"""
Extract final metrics from terminal state.
Default returns state unchanged. Override for custom outcome extraction.
"""
function aggregate_outcome end

aggregate_outcome(state::AbstractState, model::AbstractSystemModel) = state

"""
Check for early termination.
Default is false. Override for custom termination conditions.
"""
function is_terminal end

is_terminal(state::AbstractState, model::AbstractSystemModel, t::TimeStep) = false

# ============================================================================
# Main Simulation Function
# ============================================================================

"""
    simulate(model, sow, policy, recorder, rng)

Run a simulation of the model with given SOW and policy.

Returns the outcome from `aggregate_outcome(final_state, model)`.
"""
function simulate(
    model::AbstractSystemModel,
    sow::AbstractSOW,
    policy::AbstractPolicy,
    recorder::AbstractRecorder,
    rng::AbstractRNG,
)
    # Get and validate time axis
    times = time_axis(model, sow)
    _validate_time_axis(times)
    n_steps = length(times)

    # Initialize
    state = initialize(model, sow, rng)
    record!(recorder, state, nothing)

    # Simulation loop
    for (i, t_val) in enumerate(times)
        t = TimeStep(i, t_val, i == n_steps)

        # Check early termination
        if is_terminal(state, model, t)
            break
        end

        # Advance state
        state = step(state, model, sow, policy, t, rng)
        record!(recorder, state, t_val)
    end

    return aggregate_outcome(state, model)
end

# Convenience overload with keyword arguments
function simulate(
    model::AbstractSystemModel,
    sow::AbstractSOW,
    policy::AbstractPolicy;
    recorder::AbstractRecorder=NoRecorder(),
    rng::AbstractRNG=Random.default_rng(),
)
    return simulate(model, sow, policy, recorder, rng)
end

# Convenience overload: positional recorder, default rng
function simulate(
    model::AbstractSystemModel,
    sow::AbstractSOW,
    policy::AbstractPolicy,
    recorder::AbstractRecorder,
)
    return simulate(model, sow, policy, recorder, Random.default_rng())
end
