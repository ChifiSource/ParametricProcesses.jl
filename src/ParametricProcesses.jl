module ParametricProcesses
import Base: show, getindex, push!, delete!
using Distributed

abstract type AbstractWorker end
abstract type Process end
abstract type WorkerProcess <: Process end
abstract type Threaded <: Process end
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
        workers::Vector{Worker} = [w for w in workers]
        new(workers)
    end
    function ProcessManager(workers::Vector{<:AbstractWorker})
        new(workers)
    end
end

function show(io::IO, pm::ProcessManager)
    println("pid | process type | name | active")
    [show(io, worker) for worker in pm.workers]
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
    [Worker{of}(names[e], pid) for (e, pid) in enumerate(pids)]
end

function add_workers!(pm::ProcessManager, n::Int64, of::Type{<:Process} = Threaded, names::String ...)
    workers = Vector{Worker{<:Any}}()
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
        return assigned_worker::Worker{Threaded}
    end
    @async begin
        wait(assigned_worker.task)
        sleep(1)
        assign!(assigned_worker, job)
    end
end

function assign!(f::Function, assigned_worker::Worker{Threaded}, job::AbstractJob)
    if ~(assigned_worker.active)
        assigned_task = remotecall(job.f, assigned_worker.pid, job.args ...; job.kwargs ...)
        assigned_worker.task = assigned_task
        assigned_worker.active = true
        @async begin
            wait(assigned_task)
            f(fetch(assigned_task) ...)
            assigned_worker.active = false
        end
        return assigned_worker::Worker{Threaded}
    end
    @async begin
        wait(assigned_worker.task)
        sleep(1)
        assign!(f, assigned_worker, job)
    end
end

function assign!(f::Function, pm::ProcessManager, pid::Any, jobs::AbstractJob ...)
   [assign!(f, pm[pid], job) for job in jobs]::Vector{AbstractWorker}
end


function waitfor(pm::ProcessManager, pids::Any ...)
    workers = [pm[pid] for pid in pids]
    while true
        next = findfirst(w -> w.active == true, workers)
        if isnothing(next)
            break
        end
        wait(workers[next].task)
    end
    return
end

function get_return!(pm::ProcessManager, pids::Any ...)
    [pm[pid].ret for pid in pids]
end

function distribute!(pm::ProcessManager, jobs::AbstractJob ...)
    jobs = [job for job in jobs]
    n_jobs = length(jobs)
    open = filter(w::AbstractWorker -> ~(w.active), pm.workers)
    at = 1
    n_open = length(open)
    while n_jobs > 0
        jb = assign!(open[at], jobs[n_jobs])
        at += 1
        if at > n_open
            at = 1
        end
        deleteat!(jobs, n_jobs)
        n_jobs = length(jobs)
    end
end

function distribute!(pm::ProcessManager, jobs::Pair{Float64, <:AbstractJob} ...)

end

export processes, add_workers!, assign!, distribute!, Worker, ProcessManager
export Threaded, new_job

end # module BasicProcesses
