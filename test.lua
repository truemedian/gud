local buffer = require("libs/buffer")

local function test_ffi(chunks)
	local buf = buffer.new()

	local j = 1
	for i = 1, #chunks do
		buf:write(chunks[i])

		local str = buf:peek()
		local idx = str:find("\r\n\r\n", j)
		if idx then
			local a = buf:read(idx - 1)
			return a:tostring()
		end

		j = #str - 3
	end
end

local function test_naive(chunks)
	local buf = ""

	local j = 1
	for i = 1, #chunks do
		buf = buf .. chunks[i]

		local idx = buf:find("\r\n\r\n", j, true)
		if idx then
			return buf:sub(1, idx - 1)
		end

		j = #buf - 3
	end
end

local function test_tbl(chunks)
	local buf = {}

	for i = 1, #chunks do
		buf[i] = chunks[i]

		if buf[2] ~= nil then
			local suffix = buf[#buf - 1]:sub(-3)
			if #suffix < 3 and buf[#buf - 2] ~= nil then
				suffix = buf[#buf - 2]:sub(-3 + #suffix) .. suffix
			end

			local prefix = buf[#buf]:sub(1, 3)
			local together = suffix .. prefix
			local idx = together:find("\r\n\r\n", 1, true)

			if idx then
				local res = table.concat(buf, "", 1, #buf - 1) .. together:sub(1, idx - 1)
				buf[1] = buf[#buf]:sub(idx)

				for k = 2, #buf do
					buf[k] = nil
				end

				return res
			end

			idx = buf[#buf]:find("\r\n\r\n", 1, true)
			if idx then
				local res = table.concat(buf, "", 1, #buf - 1) .. buf[#buf]:sub(1, idx - 1)
				buf[1] = buf[#buf]:sub(idx)

				for k = 2, #buf do
					buf[k] = nil
				end

				return res
			end
		end
	end
end

local function f(x)
	return string.format("%.6f", x)
end

print("bytes", "ffi (s)", "ffi (MB/s)", "ffi len", "naive (s)", "naive (MB/s)", "naive len", "tbl (s)", "tbl (MB/s)", "tbl len")
for j = 1, 100 do
	local chunks = {}

	math.randomseed(12345 * j)
	for i = 1, j * 100 do
		local part = {}

		for k = 1, math.random(1, 50) do
			table.insert(part, string.rep("a", math.random(1, 100)) .. "\r\n")
		end

		table.insert(chunks, table.concat(part))
	end

	table.insert(chunks, "final chunk\r\n\r\nAaaaa")

	local start = os.clock()
	local resultA = test_ffi(chunks)
	local timeA = os.clock() - start

	local start = os.clock()
	local resultB = test_naive(chunks)
	local timeB = os.clock() - start

	local start = os.clock()
	local resultC = test_tbl(chunks)
	local timeC = os.clock() - start

	local bytes = #table.concat(chunks)
	print(bytes, f(timeA), f(bytes / timeA / 1024 / 1024), #resultA, f(timeB), f(bytes / timeB / 1024 / 1024), #resultB, f(timeC), f(bytes / timeC / 1024 / 1024), #resultC)
end
