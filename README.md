<div align="center">
  <img src="https://github.com/ChifiSource/image_dump/blob/main/parametricprocesses/parproc.png" width="375"></img>

  [![version](https://juliahub.com/docs/General/ParametricProcesses/stable/version.svg)](https://juliahub.com/ui/Packages/General/ParametricProcesses)
  
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
  - [adding workers](#adding-extensions)
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
julia> add_workers!(pm, 1, Threaded, "emma the worker <3")
2 |Threaded process: emma the worker <3 (inactive)

julia> w = Worker{Async}("steve the worker", 20)
20 |Async process: steve the worker (inactive)


julia> push!(pm, w)
2 |Threaded process: emma the worker <3 (inactive)
20 |Async process: steve the worker (inactive)


join("$(w.name)\n" for w in pm.workers)
"emma the worker <3
steve the worker
"

```
`Workers` can be indexed by their name or their pid.
```julia
julia> pm["steve the worker"]
20 |Async process: steve the worker (inactive)


julia> pm[2]
2 |Threaded process: emma the worker <3 (inactive)


```
Here is a list of other functions used to manage workers.
- `close(pm::ProcessManager)` - closes **all** active `Workers` in `pm`.
- `delete!(pm::ProcessManager, pid::Int64)` - closes `Worker` by `pid`
- `delete!(pm::ProcessManager, name::String)` - closes `Worker` by `name`.
- `worker_pids(pm::ProcessManager)`  - returns worker process identifiers for all `Workers` in `pm.workers`
- `waitfor(pm::ProcessManager, pids::Any ...)` - waits for `pids` to finish, then returns their returns in a `Vector{Any}`
- `put!(pm::ProcessManager, pids::Vector{Int64}, vals ...)` - serializes data and defines in in the `Main` of each process in `pids`.

There is also `@everywhere` used to define functions and modules across all workers, as well as `@distribute` to use all available workers for iteration.
```julia
@time @distribute for x in 1:5
    sleep(3)
end
@time for x in 1:5
    sleep(3)
end
```
`@everywhere` is the more important of the two. `put!` can be used to transmit data, but this will not work for functions or modules -- **`@everywhere` must be used for this, after the workers are open.**
```julia
using ParametricProcesses

# make workers first
pm = processes(2)

# using a `Module`
@everywhere using JSON

# using a `Function`
@everywhere function sample()
    println("sample")
end

jbs = (new_job(JSON.parse, "{\"x\":5}"), new_job(sample))


pids = distribute!(pm, jbs ...)
# -- v output
From worker 3:	sample
2-element Vector{Int64}:
 2
 3
# --

rets = waitfor(pm, pids ...)
println("x is $(rets[1]["x"])")
# - v output
x is 5
```
- For a **full** list of exports, try `?ParametricProcesses`
##### jobs
In order to use our threads to complete tasks, we will need to construct a sub-type of `AbstractJob`. The running type for this is `ProcessJob`, which may be called from the `new_job` binding. We provide this with a `Function` that takes arguments, as well as the arguments we seek to provide to that `Function` (if any).
```julia
new_job(f::Function, args ...; keyargs ...)
```
```julia
myjob = new_job(readdir, ".")
```
From here, we have access to the following functions to distribute our jobs amongst our `Workers`.
```julia
distribute!
assign!
assign_open!
distribute_open!
```
`waitfor` is used to wait for certain workers to finish their tasks, getting their returns as they complete.  
Consider the following `waitfor` example:
```julia
pm = processes(4)

jb = new_job() do 
    sleep(10)
    @info "hello world!"
    return 55
end

assign!(pm, 2, jb)

ret = waitfor(pm, 2); println("worker 2 completed, it returned: ", ret[1])

# From worker 2:	[ Info: hello world!
# worker 2 completed, it returned: 55
```
Feasibly, you can pass the `ProcessManager` to all workers and manage processes from different workers by using `@everywhere`.
### examples
###### css property parsing
This simple example shows how jobs (which ideally would be more CPU intensive and less memory-intensive than this,) can easily be distributed amongst dependencies -- especially for simple `Function` calls like `parse_props` below:
```julia
using ParametricProcesses
using Test
procs = processes(2)

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
- In the above example, `distribute!` is used to perform the tasks on 5 threads instead of one. While this does not necessarily offer a huge benefit to performance as parsing CSS is pretty simple and it is more CPU work to serialize the data for the thread, this examples does show pretty well how to easily replicate tasks across several workers.

 ---
### contributing
There are several ways to contribute to the `ParametricProcesses` package.
- submitting [issues](https://github.com/ChifiSource/ParametricProcesses.jl/issues) ([guidelines](#guidelines))
- [creating `Worker` extensions](#adding-workers).
- forking and pull-requestion ([guildelines](#guidelines))
- trying other [chifi](https://github.com/ChifiSource) projects.
- contributing to other [chifi](https://github.com/ChifiSource) projects (gives more attention here).
##### adding workers
Adding your own `Workers` is pretty straightforward. We can create new functionality by creating a new <: `Process` or a new <: `AbstractWorker`. A `Process` is used to change the functionality of a `Worker`, an `AbstractWorker` extension usually means we need to facilitate different types of `Worker` data or `ProcessManager` functionality. Creating a `Process` is very simple, as a `Process` is simply an `abstract` type.
```julia
abstract type CUDA <: Process end
```
From here, we have a few bindings which will need to be defined:
```julia
close(w::Worker{Process})
create_workers(n::Int64, of::Type{Process}, 
    names::Vector{String} = ["$e" for e in 1:n])
assign!(assigned_worker::Worker{Process}, job::AbstractJob)
```
Pretty simple; these are the main functionality that changes when we are using different hardware -- allocating jobs, creating workers to do the jobs, and closing the workers will all be different depending on what `Process` we are using. Fortunately, a `Worker` will fit entirely into the API by simply extending these three, so with these simple functions we can easily create high-level bindings to distribute our jobs over a myriad of different worker types. If we wanted to create our own `Worker`, things would get a little more complicated. It is also possible to make your own sub-type of `AbstractProcessManager` or `AbstractJob` and extend that way. All of the information needed to follow consistencies for these super-types are available in the documentation.
##### guidelines
We are not super picky on contributions, as the goal of [chifi](https://github.com/ChifiSource) is to get more people involved in computing. However, if you want your code merged there are definitely a few things to be aware of before contributing to this package.
- If there is no issue for what you want to do, [create an issue](https://github.com/ChifiSource/ParametricProcesses.jl)
- If you have multiple issues, **submit multiple issues** rather than typing each issue into one issue.
- Make sure the issue you are solving or feature you want to implement is still feasible on `Unstable` -- this is the top-level development branch which represents the latest unstable changes.
- Please format your documentation using the technique presented in the rest of the file.
- Make sure `Pkg.test("ParametricProcesses")` works with your version of `ParametricProcesses` before making a pull-request.
