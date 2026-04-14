package.loaded.luv = package.loaded.uv
require('openssl').errors()
require('table.clear')

local server = require('http/server')
local tcp = require('net/tcp')

local fs = require('fs')
local path = require('path')
local uri = require('uri')

local serve_dir = './deps'

local listener = tcp.server()
listener:bind('127.0.0.1', 8080)
server.listen(listener, function(request, response)
	if request.headers:get('host') ~= 'localhost:8080' then
		assert(response:respond(400, 'Bad Request'))
		assert(response:finish())
		return
	end

	if request.method ~= 'GET' then
		assert(response:respond(405, 'Method Not Allowed'))
		assert(response:finish())
		return
	end

	local parsed = uri.decode(request.target)
	if not parsed then
		assert(response:respond(400, 'Bad Request'))
		assert(response:finish())
		return
	end

	local target = path.posix.resolve(parsed.path, '/')
	local host_path = path.join(serve_dir, target)

	if not fs.exists(host_path) then
		assert(response:respond(404, 'Not Found'))
		assert(response:finish())
		return
	end

	local stat = assert(fs.stat(host_path))
	if stat.type == 'directory' then
		assert(response:respond(403, 'Forbidden'))
		assert(response:finish())
		return
	end

	local etag = string.format('%i-%i-%i', stat.ino, stat.size, stat.mtime.sec)
	if request.headers:get('If-None-Match') == etag then
		assert(response:respond(304, 'Not Modified'))
		assert(response:finish())
		return
	end

	local range = request.headers:get('Range')
	local start, finish
	if range then
		start, finish = range:match('bytes=(%d*)%-(%d*)')
		if not start and not finish then
			assert(response:respond(416, 'Range Not Satisfiable'))
			assert(response:finish())
			return
		end

		start = start ~= '' and tonumber(start) or 0
		finish = finish ~= '' and tonumber(finish) or nil

		if start < 0 or (finish and finish < start) or (finish and finish >= stat.size) then
			assert(response:respond(416, 'Range Not Satisfiable'))
			assert(response:finish())
			return
		end
	end

	response.headers:set('Content-Length', finish and (finish - start + 1) or stat.size)
	response.headers:set('Content-Type', 'application/octet-stream')
	response.headers:set('ETag', etag)
	response.headers:set('Last-Modified', os.date('%a, %d %b %Y %H:%M:%S GMT', stat.mtime.sec))

	if start or finish then
		response.headers:set('Content-Range', 'bytes ' .. (start or '') .. '-' .. (finish or '') .. '/' .. stat.size)
		assert(response:respond(206, 'Partial Content'))
	else
		assert(response:respond(200, 'OK'))
	end

	local file = assert(fs.open(host_path, 'r'))
	local offset = start or 0
	local chunk_size = 64 * 1024
	while offset < stat.size and (not finish or offset <= finish) do
		local to_read = chunk_size
		if finish then
			to_read = math.min(to_read, finish - offset + 1)
		end

		local chunk = assert(fs.read(file, to_read, offset))
		assert(response.writer:write(chunk))
		offset = offset + #chunk
	end

	assert(response:finish())
end)
