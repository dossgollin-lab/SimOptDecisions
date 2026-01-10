@testset "Recorders" begin
    @testset "NoRecorder" begin
        r = NoRecorder()
        @test record!(r, "state", "record", 1, "action") === nothing
    end

    @testset "TraceRecorderBuilder and SimulationTrace" begin
        # Define a test action type
        struct TestAction <: AbstractAction
            value::Float64
        end

        builder = TraceRecorderBuilder()
        record!(builder, 0.0, nothing, nothing, nothing)  # Initial state (t=0)
        record!(builder, 1.0, (value=10,), 1, TestAction(0.1))
        record!(builder, 2.0, (value=20,), 2, TestAction(0.2))
        record!(builder, 3.0, (value=30,), 3, TestAction(0.3))

        trace = build_trace(builder)

        # Type includes initial_state type as first parameter
        @test trace isa SimulationTrace{Float64,Float64,@NamedTuple{value::Int},Int,TestAction}
        @test trace.initial_state == 0.0
        @test length(trace.states) == 3
        @test length(trace.step_records) == 3
        @test length(trace.times) == 3
        @test length(trace.actions) == 3
        @test trace.states == [1.0, 2.0, 3.0]
        @test trace.step_records == [(value=10,), (value=20,), (value=30,)]
        @test trace.times == [1, 2, 3]
        @test trace.actions == [TestAction(0.1), TestAction(0.2), TestAction(0.3)]
    end

    @testset "SimulationTrace Tables.jl interface" begin
        struct TableTestAction <: AbstractAction
            x::Int
        end

        trace = SimulationTrace(
            0.0,  # initial_state
            [1.0, 2.0, 3.0],
            [(v=10,), (v=20,), (v=30,)],
            [100, 200, 300],
            [TableTestAction(1), TableTestAction(2), TableTestAction(3)],
        )

        @test trace.initial_state == 0.0

        @test Tables.istable(typeof(trace))
        @test Tables.columnaccess(typeof(trace))
        @test Tables.columnnames(trace) == (:state, :step_record, :time, :action)
        @test Tables.getcolumn(trace, :state) == [1.0, 2.0, 3.0]
        @test Tables.getcolumn(trace, :step_record) == [(v=10,), (v=20,), (v=30,)]
        @test Tables.getcolumn(trace, :time) == [100, 200, 300]
        @test Tables.getcolumn(trace, :action) ==
            [TableTestAction(1), TableTestAction(2), TableTestAction(3)]
        @test Tables.getcolumn(trace, 1) == [1.0, 2.0, 3.0]
        @test Tables.getcolumn(trace, 2) == [(v=10,), (v=20,), (v=30,)]
        @test Tables.getcolumn(trace, 3) == [100, 200, 300]
        @test Tables.getcolumn(trace, 4) ==
            [TableTestAction(1), TableTestAction(2), TableTestAction(3)]

        # Invalid column access
        @test_throws ArgumentError Tables.getcolumn(trace, :invalid)
        @test_throws BoundsError Tables.getcolumn(trace, 5)

        schema = Tables.schema(trace)
        @test schema.names == (:state, :step_record, :time, :action)
    end
end
