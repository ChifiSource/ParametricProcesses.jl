"""
#### ParametricProcesses -- versatile process managers for julia
Created in February, 2023 by
[chifi - an open source software dynasty.](https://github.com/orgs/ChifiSource)
- This software is MIT-licensed.

`ParametricProcesses` provides a high-level parametric worker interface for managing different types of parallel computing 
platforms. The results are process tracking and load/worker distribution for multi-threaded and asynchronous use-cases.
With extensions, this management framework could be used further with other forms of parallel computing.
---
###### contents
 - AbstractWorker
 - Process
 - WorkerProcess
 - Threaded
 - Async
 - AbstractJob
 - AbstractProcessManager
 - ProcessJob
 - new_job
 - Worker{T <: Process}
 - Workers{T}
 - ProcessManager
 - create_workers
 - add_workers!
 - delete!(pm::ProcessManager, name::String)
 - delete!(pm::ProcessManager, pid::Int64)
 - processes
 - assign!
 - distribute!
 - waitfor
 - get_return
 - worker_pids
"""
module ParametricProcesses
import Base: show, getindex, push!, delete!
using Distributed

abstract type AbstractWorker end
abstract type Process end
abstract type WorkerProcess <: Process end
abstract type Threaded <: Process end
abstract type Async <: Process end
abstract type AbstractJob end
abstract type AbstractProcessManager end

mutable struct ProcessJob <: AbstractJob
    f::Function
    args
    kwargs
    function ProcessJob(f::Function, args ...; keyargs ...)
        new(f, args, keyargs)
    end
end

const new_job = ProcessJob

mutable struct Worker{T <: Process} <: AbstractWorker
    name::String
    pid::Int64
    ret::Any
    active::Bool
    task::Any
    Worker{T}(name::String, pid::Int64) where {T <: Process} = begin
        new{T}(name, pid, nothing, false, nothing)
    end
end

const Workers{T} = Vector{T} where {T <: AbstractWorker}

function show(io::IO, worker::Worker{<:Any})
    T = typeof(worker).parameters[1]
    activemessage = "inactive"
    if worker.active
        activemessage = "active"
    end
    println("$(worker.pid) |$T process: $(worker.name) ($(activemessage))")
end

mutable struct ProcessManager <: AbstractProcessManager
    workers::Workers{<:Any}
    function ProcessManager(workers::Worker{<:Any} ...)
        workers::Vector{Worker} = Vector{Worker{<:Any}}([w for w in workers])
        new(workers)
    end
    function ProcessManager(workers::Vector{<:AbstractWorker})
        new(workers)
    end
end

function show(io::IO, pm::AbstractProcessManager)
    [show(worker) for worker in pm.workers]
end

function getindex(pm::ProcessManager, name::String)
    pos = findfirst(worker::Worker{<:Any} -> worker.name == name, pm.workers)
    if isnothing(pos)
        # throw
    end
    pm.workers[pos]
end

function getindex(pm::ProcessManager, pid::Int64)
    pos = findfirst(worker::Worker{<:Any} -> worker.pid == pid, pm.workers)
    if isnothing(pos)
        # throw
    end
    pm.workers[pos]
end

function create_workers(n::Int64, of::Type{Threaded}, 
    names::Vector{String} = ["$e" for e in 1:n])
    pids = addprocs(n)
    Vector{Worker{<:Any}}([Worker{of}(names[e], pid) for (e, pid) in enumerate(pids)])
end

function add_workers!(pm::ProcessManager, n::Int64, of::Type{<:Process} = Threaded, names::String ...)
    workers = Vector{Worker{<:Any}}()
    name_n = length(names)
    if name_n == 0
        workers = create_workers(n, of)
    elseif name_n != n
        # throw
    else
        workers = create_workers(n, of, [name for name in names])
    end
    pm.workers = vcat(pm.workers, workers)
end

function delete!(pm::ProcessManager, pid::Int64)
    pos = findfirst(worker::Worker{<:Any} -> worker.pid == pid, pm.workers)
    if isnothing(pos)
        # throw
    end
    deleteat!(pm.workers, pos)
end

function delete!(pm::ProcessManager, name::String)
    pos = findfirst(worker::Worker{<:Any} -> worker.pid == pid, pm.workers)
    if isnothing(pos)
        # throw
    end
    deleteat!(pm.workers, pos)
end

function processes(n::Int64, of::Type{<:Process} = Threaded, names::String ...)
    workers = Vector{Worker{<:Any}}()
    name_n = length(names)
    if name_n == 0
        workers = create_workers(n, of)
    elseif name_n != n
        # throw
    else
        workers = create_workers(n, of, [name for name in names])
    end
    ProcessManager(workers)
end

function assign!(assigned_worker::Worker{Threaded}, job::AbstractJob)
    if ~(assigned_worker.active)
        assigned_task = remotecall(job.f, assigned_worker.pid, job.args ...; job.kwargs ...)
        assigned_worker.task = assigned_task
        assigned_worker.active = true
        @async begin
            wait(assigned_task)
            assigned_worker.active = false
            assigned_worker.ret = fetch(assigned_task)
        end
        return assigned_worker.pid
    end
    @async begin
        wait(assigned_worker.task)
        sleep(1)
        assign!(assigned_worker, job)
    end
    assigned_worker.pid
end

function assign!(f::Function, assigned_worker::Worker{Threaded}, job::AbstractJob)
    if ~(assigned_worker.active)
        assigned_task = remotecall(job.f, assigned_worker.pid, job.args ...; job.kwargs ...)
        assigned_worker.task = assigned_task
        assigned_worker.active = true
        @async begin
            wait(worker.assigned_task)
            assigned_worker.active = false
        end
        return assigned_worker.pid
    end
    @async begin
        wait(assigned_worker.task)
        sleep(1)
        assign!(f, assigned_worker, job)
    end
    assigned_worker.pid
end

function assign!(f::Function, pm::ProcessManager, pid::Any, jobs::AbstractJob ...)
   [assign!(f, pm[pid], job) for job in jobs]::Vector{Int64}
end

function assign!(pm::ProcessManager, pid::Any, jobs::AbstractJob ...)
    [assign!(pm[pid], job) for job in jobs]::Vector{Int64}
 end

worker_pids(pm::ProcessManager) = [w.pid for w in pm.workers]

function waitfor(pm::ProcessManager, pids::Any ...)
    workers = [pm[pid] for pid in pids]
    while true
        next = findfirst(w -> w.active == true, workers)
        if isnothing(next)
            break
        end
        wait(workers[next].task)
    end
    [pm[pid].ret for pid in pids]
end

function get_return!(pm::ProcessManager, pids::Any ...)
    [pm[pid].ret for pid in pids]
end

function use_with!(pm::ProcessManager, pid::Any, mod::String)
    imprtjob = new_job() do 
        eval(Meta.parse("using $(name)"))
    end
    assign!(pm.workers[pid], imprtjob)
end

function distribute!(pm::ProcessManager, jobs::AbstractJob ...)
    jobs = [job for job in jobs]
    n_jobs = length(jobs)
    open = filter(w::AbstractWorker -> ~(w.active), pm.workers)
    at = 1
    n_open = length(open)
    [begin
        assign!(worker, job)
    end for job in jobs]
    [w.pid for w in open]
end

function distribute!(pm::ProcessManager, worker_pids::Vector{Int64}, jobs::AbstractJob ...)
    workers = [pm.workers[id] for id in worker_pids]
    return worker_pids
end

function distribute!(pm::ProcessManager, percentage::Float64, jobs::AbstractJob ...)
    total_workers = length(pm.workers)
    num_workers_to_use = round(Int, percentage * total_workers)
    
    open = filter(w -> ~w.active, pm.workers)
    num_open = length(open)
    
    if num_open < num_workers_to_use
        # If there aren't enough open workers, assign jobs asynchronously
        async_workers = filter(w -> w.active, pm.workers)
        for job in jobs
            if isempty(async_workers)
                error("Not enough open and active workers to distribute the jobs.")
            end
            worker = popfirst!(async_workers)
            assign!(worker, job)
        end
        return [w.pid for w in async_workers]
    end
    # Assign jobs to open workers
    for job in jobs
        worker = popfirst!(open)
        assign!(worker, job)
    end
    return [w.pid for w in open]
end

export processes, add_workers!, assign!, distribute!, Worker, ProcessManager, worker_pids
export Threaded, new_job, @everywhere, get_return!, waitfor, use_with!, Async, RemoteChannel

end # module BasicProcesses
