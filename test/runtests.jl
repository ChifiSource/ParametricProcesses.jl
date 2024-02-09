using ParametricProcesses
using Test
nthrds = Base.n_threads()

if nthrds < 3
    throw("To test a threaded process manager, you need to run the tests with greater than 2 threeads.")
    @info "run julia with threads set to 3: `julia --threads 3`"
end

@testset "types" do 
    @test typeof(ProcessJob(s -> println(s), "example")) == ProcessJob
    w = Worker{ParametricProcesses.Async}("1", 1))
    @test typeof(w) == Worker{Async}
    pm = ProcessManager(w)
    @test pm["1"] == w
    @test pm[1] == w
    delete!(pm, w.pid)
    @test length(pm.workers) == 0
    push!(pm, w)
    @test length(pm.workers) == 1
    delete!(pm, w.name)
    @test length(pm.workers) == 0
end

@testset "Worker API" do
    aworker = create_workers(2, Async)
    @test typeof(aworker[1]) = Worker{ParametricProcesses.Async}
    procs = processes(2)
    @test typeof(procs.workers) == Workers{<:Any}
    @test worker_pids(procs) == [2, 3]
    
end

@testset "ProcessJob API" do

end