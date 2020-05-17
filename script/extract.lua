local target = arg[1]
table.remove(arg, 1)

local existing_dirs = {}
local function accept(f, dir, num, type)
    if not existing_dirs[dir] then
        os.execute(('rm -r "%s/%s"'):format(target, dir))
        os.execute(('mkdir -p "%s/%s"'):format(target, dir))
        existing_dirs[dir] = true
    end

    os.execute(('cp "%s" "%s/%s/%s.%s"'):format(f, target, dir, num, type))
end

local files, rejected, rejected_total = 0, setmetatable({}, { __index = function() return 0 end }), 0
local function find_lines(f, lines)
    files = files + 1
    for l in io.lines(f) do
        for _, pat in ipairs(lines) do
            if l:find(pat) then
                rejected_total = rejected_total + 1
                rejected[pat] = rejected[pat] + 1
                return true
            end
        end
    end

    return false
end

local dirs = {
    binarytrees   = "trees",
    fannkuchredux = "fannkuch",
    -- fasta,
    -- knucleotide,
    -- mandelbrot,
    -- nbody,
    pidigits      = "pi",
    regexredux    = "regex",
    -- revcomp,
    spectralnorm  = "spectral",
}

local c_exclude = {
    "#include%s*<immintrin.h>",
    "#include%s*<emmintrin.h>",
    "#include%s*<xmmintrin.h>",
    "__builtin",
    "pcre_jit_exec", -- not available on hifive unleashed
    "#include%s*<omp.h>", -- TODO
    "#include%s*<apr_pools.h>", -- TODO
}

local rs_exclude = {
    "use%s+std::arch",
    "extern%s+crate%s+tokio_sync",
    "extern%s+crate%s+tokio_threadpool",
    "extern%s+crate%s+futures",
    "use%s+std::os::raw",
    "use%s+libc",
}

local types = setmetatable({}, {
    __index = function(tbl, key)
        local val = { accepted = 0, total = 0 }
        tbl[key] = val
        return val
    end
})
for _, f in ipairs(arg) do
    local dir, type = f:match(".*/([^/]+)/[^.]+%.(.+)")

    if dir then
        local num = 1
        if type:find("%.") then
            num, type = type:match("[^-]%-([^.]+)%.(.+)")
        end

        dir = dirs[dir] or dir

        local exclude
        if type == "gcc" then
            exclude, type = c_exclude, "c"
        elseif type == "gpp" then
            exclude, type = c_exclude, "cpp"
        elseif type == "rust" then
            exclude, type = rs_exclude, "rs"
        end

        types[dir].total = types[dir].total + (exclude and 1 or 0)
        if exclude and not find_lines(f, exclude) then
            types[dir].accepted = types[dir].accepted + 1
            accept(f, dir, num, type)
        end
    end
end

-- process blacklist stats
local blacklist = {}
for i,v in pairs(rejected) do
    table.insert(blacklist, {name = i, num = v})
end
table.sort(blacklist, function(a, b) return a.num > b.num end)

print(("Accepted %d of %d files."):format(files - rejected_total, files))
for i,v in pairs(types) do
    print(("  %2d/%2d %s"):format(v.accepted, v.total, i))
end

print ""
print "Blacklist stats"
for _,v in ipairs(blacklist) do
    print(("  %2d %s"):format(v.num, v.name))
end

print ""
os.execute("./script/update_cargo.sh")
