sleep(2)
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

@testset "- example: CSS property parsing" verbose = true begin
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
end