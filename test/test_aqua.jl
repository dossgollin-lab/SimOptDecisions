@testset "Aqua.jl" begin
    using Aqua
    # Ignore stdlib compat (versions tied to Julia, not independently versioned)
    Aqua.test_all(
        SimOptDecisions; deps_compat=(ignore=[:Dates, :Random, :Statistics, :TOML, :Test],)
    )
end
