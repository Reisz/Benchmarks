-- Utility
local autofill = {}
function autofill:__index(key)
    local result = setmetatable({}, autofill)
    self[key] = result
    return result
end

local function enumerate(f, s, var)
    return function(s, i)
        local vars = { f(s, var) }
        var = vars[1]
        return var and i + 1, table.unpack(vars)
    end, s, 0
end

local function frequencyToGhz(frequency, unit)
    if type(frequency) ~= "number" then frequency = tonumber(frequency) end

    unit = unit:lower()
    if unit == "mhz" then
        frequency = frequency / 1000
    elseif unit == "khz" then
        frequency = frequency / 1000000
    end

    return frequency
end

local function geom_mean(numbers)
    local count = #numbers
    if count == 0 then return 0, 0, 0 ,0 end

    local mean, power = 1, 1 / count
    for _,v in ipairs(numbers) do mean = mean * v^power end

    local variance = 0
    for _,v in ipairs(numbers) do variance = variance + (mean - v)^2 end
    variance = variance * power

    local std_dev = math.sqrt(variance)

    return mean, std_dev, math.min(table.unpack(numbers)), math.max(table.unpack(numbers))
end

local function sorted_pairs(tbl)
    local idx = {}
    for i in pairs(tbl) do table.insert(idx, i) end
    table.sort(idx)

    local i = 1
    return function()
        local var_1 = idx[i]
        local var_2 = var_1 and tbl[var_1]
        i = i + 1
        return var_1, var_2
    end
end

local function write_dat(filename, lines)
    local file = io.open(filename, "w")

    file:write(table.concat(lines.title, " "), "\n")
    lines.title = nil

    for i, line in sorted_pairs(lines) do
        file:write(string.format("%q ", i), table.concat(line, " "), "\n")
    end

    file:close()
end

-- Program Start
local data = setmetatable({}, autofill)
local iperf = {}

local plot = arg[1]
table.remove(arg, 1)

local all_numbers = setmetatable({}, autofill)
for _, filename in ipairs(arg) do
    if filename:match("iperf%-[^%.]+%.log$") then
        table.insert(iperf, filename)
    else
        local platform, bench, number = filename:match("([^/]+)/([^/]+)/(.+).bm")

        local lines = io.lines(filename)

        local title = lines()
        local header = title and lines()

        -- parse cpu frequency from title line
        local frequency_ghz
        if title then
            local number, unit = title:match("%(%d+%s+x%s+(%S+)%s+([^,]+)")
            frequency_ghz = number and frequencyToGhz(number, unit)
        end

        local ok = false
        if header then
            -- find index of requested column
            local to_plot = 1
            for column in header:gmatch("%S+") do
                if column == plot then
                    ok = true
                    break
                end

                to_plot = to_plot + 1
            end

            if ok then
                local normalized_values = {}

                -- collect values from requested column
                for line in lines do
                    for i, v in enumerate(line:gmatch("%S+")) do
                        if i == to_plot then
                            table.insert(normalized_values, tonumber(v) * frequency_ghz)
                            break
                        end
                    end
                end

                data[bench][platform][number] = { geom_mean(normalized_values) }
            else
                print(string.format("Could not find column %q in %s", plot, filename))
            end
        end

        if not ok then
            data[bench][platform][number] = { 0, 0 }
        elseif not rawget(all_numbers[bench], number) then
            all_numbers[bench][number] = true
        end
    end
end

local overall = setmetatable({}, autofill)

-- One file per bench
for bench, platforms in pairs(data) do
    local lines = setmetatable({ title = { "Benchmark" } }, autofill)

    for platform, numbers in sorted_pairs(platforms) do
        table.insert(lines.title, string.format("%q %q", platform, platform))

        local mean_values, min_values = {}, {}
        for number in pairs(all_numbers[bench]) do
            local data = rawget(numbers, number) or { 0, 0 }

            -- collect values for combined plot
            if data[1] > 0 then
                table.insert(mean_values, data[1])
                table.insert(min_values, data[3])
            end

            table.insert(lines[number], string.format("%f %f", data[1], data[2]))
        end

        local min = #min_values > 0 and math.min(unpack(min_values)) or 0
        overall[platform][bench] = { geom_mean(mean_values), min }
    end

    write_dat(("output/data/%s.dat"):format(bench), lines)
end

-- One combined file
local lines = setmetatable({ title = { "Benchmark" } }, autofill)

for platform, numbers in sorted_pairs(overall) do
    table.insert(lines.title, string.format("%q %q", platform, platform, platform))

    for number, data in pairs(numbers) do
        table.insert(lines[number], string.format("%f %f", data[1], data[2]))
    end
end


write_dat("output/data/combined.dat", lines)

local iperf_results = setmetatable({}, autofill)
for _,filename in ipairs(iperf) do
    local platform, target, offload = filename:match("([^/]+)/iperf%-([^%-]+)(%-?[^%.]*)%.log")
    offload = offload or ""

    local prog, mode
    for l in io.lines(filename) do
        if l:find("iperf ", 1, true) then
            if l:find("-s", 1, true) then
                -- iperf2 server measures ethox tcp client
                prog, mode = "ethox", "tcp"
            elseif not l:find("Done", 1, true) then
                error("Unexpected non-server iperf2 call.")
            end
        elseif l:find("iperf3 ", 1, true) then
            if l:find("-s", 1, true) then
                if l:find("--udp", 1, true) then
                    -- ethox udp server measures ethox udp client
                    prog, mode = "ethox", "udp"
                elseif l:find("--tcp", 1, true) then
                    error("Unexpected ethox-iperf tcp server call.")
                end
                -- regular iperf3 is measured at client side
            elseif l:find("-c", 1, true) then
                if l:find("-u") then
                    -- iperf3 udp client measurement
                    prog, mode = "iperf", "udp"
                elseif not l:find("--", 1, true) then -- exclude exthox calls
                    -- iperf3 tcp client measurement
                    prog, mode = "iperf", "tcp"
                end
                -- ethox is measured at client
            end
        else
            if prog == "ethox" and mode == "udp" then
                local ethox_bps = l:match("(%d+)%s+Byte/sec")
                if ethox_bps then
                    local ethox_mbitps = ethox_bps / 125000
                    iperf_results[target]["ethox-" .. mode .. offload] = ethox_mbitps
                end
            else
                local iperf_mbitps = l:match("(%d+%.?%d*)%s+Mbits/sec")
                if iperf_mbitps then
                    iperf_results[platform][prog .. "-" .. mode .. offload] = iperf_mbitps
                end
            end
        end

        -- if l:find(" -s ", 1, true) then
        --     mode = "server"
        --     get_prot(l)
        --     print(l)
        --     print(mode, prot)
        -- elseif l:find(" -c ", 1, true) then
        --     mode = "client"
        --     get_prot(l)
        --     print(l)
        --     print(mode, prot)
        -- else
        --     if mode == "server" then
        --     elseif mode == "client" then
        --         local iperf_mbitps, udp = l:match("(%d+%.?%d*)%s+Mbits/sec[^%%]*(%%?).*sender")
        --         if iperf_mbitps then
        --             local iperf = "iperf-" .. (#udp > 0 and "udp" or "tcp") .. offload
        --             iperf_results[platform][iperf] = iperf_mbitps
        --         end
        --     end
        -- end
    end
end

local lines = setmetatable({ title = { "iPerf" } }, autofill)
for platform, results in sorted_pairs(iperf_results) do
    table.insert(lines.title, string.format("%q", platform))
    for mode, value in pairs(results) do
        table.insert(lines[mode], string.format("%f", value))
    end
end
write_dat("output/data/iperf.dat", lines)
