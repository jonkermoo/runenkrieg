--!strict
-- Lune test runner: finds every *.spec.luau under tests/ and runs it.
-- A spec returns a table of name -> function; a test fails by erroring.
local fs = require("@lune/fs")
local process = require("@lune/process")

local passed, failed = 0, 0

local function collect(dir: string, out: { string })
	for _, entry in fs.readDir(dir) do
		local path = dir .. "/" .. entry
		if fs.isDir(path) then
			collect(path, out)
		elseif string.match(entry, "%.spec%.luau$") then
			table.insert(out, path)
		end
	end
end

local specs = {}
collect("tests", specs)
table.sort(specs)

for _, path in specs do
	local spec = (require :: any)("./" .. string.gsub(string.sub(path, 7), "%.luau$", ""))
	for name, fn in spec do
		local ok, err = pcall(fn)
		if ok then
			passed += 1
		else
			failed += 1
			print(`FAIL {path} :: {name}\n  {err}`)
		end
	end
end

print(`{passed} passed, {failed} failed ({#specs} spec files)`)
process.exit(if failed > 0 then 1 else 0)
