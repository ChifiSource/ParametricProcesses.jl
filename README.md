<div align="center">
  <img src="https://github.com/ChifiSource/image_dump/blob/main/parametricprocesses/parproc.png" width="375"></img>
</div>

`ParametricProcesses` offers a parametric `Worker` type capable of facilitating multiple forms of parallel processing and high-level declarative `Distributed` worker management.
```julia
```
---
###### basic usage
```julia
using ParametricProcesses
procs = processes(5)
x = 5
firstjob = new_job(x) do num::Int64
    x += 5
end
secondjob = new_job(x) do num::Int64
    println(x)
end

distribute!(procs, firstjob, secondjob)
```
