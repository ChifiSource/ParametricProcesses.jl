using ParametricProcesses
using ParametricProcesses: ProcessJob
using Test
nthrds = Threads.nthreads()

if nthrds < 3
    throw("To test a threaded process manager, you need to run the tests with greater than 2 threeads.")
    @info "run julia with threads set to 3: `julia --threads 3`"
end

@testset "Type System" verbose = true begin
    w = nothing
    @testset "jobs and workers" begin
        @test typeof(ProcessJob(s -> println(s), "example")) == ParametricProcesses.ProcessJob
        w = Worker{ParametricProcesses.Async}("1", 1)
        @test typeof(w) == Worker{Async}
    end
    @testset "process manager" begin
        pm = ProcessManager(w)
        @test pm["1"] == w
        @test pm[1] == w
        @test_throws KeyError pm["3"]
        @test_throws KeyError pm[3]
        delete!(pm, w.pid)
        @test length(pm.workers) == 0
        push!(pm, w)
        @test length(pm.workers) == 1
        delete!(pm, w.name)
        @test length(pm.workers) == 0
    end
end

@testset "Worker API" begin
    aworker = ParametricProcesses.create_workers(2, Async)
    w = aworker[1]
    @test typeof(w) == Worker{ParametricProcesses.Async}
    procs = processes(1)
    @test typeof(procs.workers) == Vector{Worker{<:Any}}
    @test worker_pids(procs) == [2]
    add_workers!(procs, 1, Threaded, "example")
    @test worker_pids(procs) == [2, 3]
    w = nothing
    try
        w = procs["example"]
    catch
        w = nothing
    end
    @test typeof(w) == Worker{Threaded}
    close(procs)
    @test length(worker_pids(procs)) == 0
end

@testset "ProcessJob API" begin
    procs = processes(2)
    jb = new_job(2000) do count::Int64
        count + 5
    end
    assign!(procs, 4, jb)
    @test procs[4].active == true
    sleep(1)
    ret = waitfor(procs, 4)
    @test procs[4].active == false
    @test ret[1] == 2005
    val = "hello "
    job = new_job() do 
        5
    end
    pid = distribute!(procs, job)
    sleep(1)
    waitfor(procs, pid ...) do ret
        @test ret[1] == 5
    end
    pid = pid[1]
    put!(procs, [pid], val)
    job = new_job() do 
        val * "world"
    end
    assign!(procs, pid, job, sync = true)
    hellw = waitfor(procs, pid) 
    @test hellw[1] == "hello world"
end
