<div align="center">
  <img src="https://github.com/ChifiSource/image_dump/blob/main/parametricprocesses/parproc.png" width="375"></img>
</div>

`ParametricProcesses` offers a parametric `Worker` type and a `ProcessManager` API capable of facilitating multiple forms of parallel processing and high-level declarative `Distributed` worker management.
```julia
using Pkg; Pkg.add("ParametricProcesses")
# Unstable:
using Pkg; Pkg.add("ParametricProcesses", rev = "Unstable")
```
---
- [usage](#usage)
  -  [workers](#workers)
  -  [jobs](#jobs)
-  [examples](#examples)
- [contributing](#contributing)
  - [adding workers](#extensions)
  - [contributing guidelines](#guidelines)
### usage
Before trying to use threaded `Workers` (`Workers{Threaded}`), make sure to start **julia with multiple threads**!
```julia
julia --threads 6
```
- For a **full** list of exports, try `?ParametricProcesses`
```julia
using ParametricProcesses
procs = processes(5)
x = 5
firstjob = new_job(x) do x::Int64
   for n in 1:x
       println("hello")
       sleep(2)
   end 
end
secondjob = new_job(x) do x::Int64
   sleep(1)
   for n in 1:x
       println("world")
       sleep(2)
   end 
end

distribute!(procs, firstjob, secondjob)
```
```julia
julia> distribute!(procs, firstjob, secondjob)
2-element Vector{Int64}:
 7
 8

julia>       From worker 7:	hello
      From worker 8:	world
      From worker 7:	hello
      From worker 8:	world
      From worker 7:	hello
      From worker 8:	world
      From worker 7:	hello
      From worker 8:	world
      From worker 7:	hello
      From worker 8:	world

```
##### workers
The *typical* `ParametricProcesses` workflow involves creating a process manager with workers, then creating jobs and distributing them amongst those workers using `assign!` and `distribute!`.  To get started, we can create a `ProcessManager` by using the `processes` Function. This `Function` will take an `Int64` and optionally, a `Process` type. The default process type will be `Threaded`, so ensure you have multiple threads for the following example:
```julia
procs = processes(5)
```
We can create a process manager with workers of any type using this same `Function`, `processes`.
```julia
async_procs = processes(2, Async)
```
`Workers` are held in the `ProcessManager.workers` field, we can also add workers directly with the `add_workers!` function, or create workers manually and `push!` them.
```julia

```
`Workers` can be indexed by their name or their pid.
```julia

```
Here is a list of other functions used to manage workers.
- `close(pm::ProcessManager)` - closes **all** active `Workers` in `pm`.
- `delete!(pm::ProcessManager, pid::Int64)` - closes `Worker` by `pid`
- `delete!(pm::ProcessManager, name::String)` - closes `Worker` by `name`.
- `worker_pids(pm::ProcessManager)`  - returns worker process identifiers for all `Workers` in `pm.workers`
- `waitfor(pm::ProcessManager, pids::Any ...)` - waits for `pids` to finish, then returns their returns in a `Vector{Any}`
- `put!(pm::ProcessManager, pids::Vector{Int64}, vals ...)` - serializes data and defines in in the `Main` of each process in `pids`.

There is also `@everywhere` used to define functions and modules across all workers, as well as `@distribute` to use all available workers for iteration.

- For a **full** list of exports, try `?ParametricProcesses`
##### jobs
In order to use our threads to complete tasks, we will need to construct a sub-type of `AbstractJob`. The running type for this is `ProcessJob`, which may be called from the `new_job` binding. We provide this with a `Function` that takes arguments, as well as the arguments we seek to provide to that `Function` (if any).
```julia

```
From here, we have access to the following functions to distribute our jobs amongst our `Workers`.
```julia

```
Consider the following `waitfor` example:
```julia
```
### examples
###### css property parsing
```julia
procs = processes(5)

@everywhere function parse_props(s::String)
    propkeys = split(s, ";")
    filter!(t -> ~(isnothing(t)), [begin 
        splts = split(kp, ":")
        if length(splts) < 2
            nothing
        else
            splts[1] => splts[2]
        end
    end for kp in propkeys])
end

firstset = join("$(rand(500:5000)):$(rand(500:5000));" for n in 1:5000)
secondset = join("$(rand(500:5000)):$(rand(500:5000));" for n in 1:50000)
thirdset = join("$(rand(500:5000)):$(rand(500:5000));" for n in 1:5000)
fourthset = join("$(rand(500:5000)):$(rand(500:5000));" for n in 1:100000)
fifthset = join("$(rand(500:5000)):$(rand(500:5000));" for n in 1:50000)
sets = (firstset, secondset, thirdset, fourthset, fifthset)
ret = vcat([parse_props(set) for set in sets] ...)
jbs = (new_job(parse_props, set) for set in sets)
ids = distribute!(procs, worker_pids(procs), jbs ...)
mret = vcat(waitfor(procs, ids ...) ...)
@test length(ret) == length(mret)
```
In the above example, `distribute!` is used to perform the tasks on 5 threads instead of one. While this does not necessarily offer a huge benefit to performance as parsing CSS is pretty simple and it is more CPU work to serialize the data for the thread, this examples does show pretty well how to easily replicate tasks across several workers.

 ---
### contributing
There are several ways to contribute to the `ParametricProcesses` package.
- submitting [issues](https://github.com/ChifiSource/ParametricProcesses.jl/issues) ([guidelines](#guidelines))
- [creating `Worker` extensions](#adding-workers).
- forking and pull-requestion ([guildelines](#guidelines))
- trying other [chifi](https://github.com/ChifiSource) projects.
- contributing to other [chifi](https://github.com/ChifiSource) projects (gives more attention here).
##### adding workers
##### guidelines
