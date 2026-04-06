local path = require('path')
local re = require('re')

--- @class std.uri
local uri = {}

--- @class std.uri.parsed
--- @field scheme string|nil
--- @field userinfo string|nil
--- @field hostname string|nil
--- @field port integer|nil
--- @field path string
--- @field query string|nil
--- @field fragment string|nil

local function percent_encode(c)
	return string.format('%%%02X', string.byte(c))
end

--- @param str string
--- @return string
function uri.percentEncode(str)
	return (str:gsub('([^A-Za-z0-9._~-])', percent_encode))
end

local function percent_decode(hex)
	return string.char(tonumber(hex, 16))
end

--- @param str string
--- @return string
function uri.percentDecode(str)
	return (str:gsub('%%(%x%x)', percent_decode))
end

local grammar = re.compile(
	[[
    uri         <-  {| (scheme ':')? hierarchy ('?' query)? ('#' fragment)? !. |}
    scheme      <-  {:scheme: [%a] [%w+.-]* :}
    hierarchy   <-  ('//' authority path) / path

    authority   <-  (userinfo '@')? host (':' port)?
    userinfo    <-  {:user: { ( percent_encoded / unreserved / sub_delims / ':' )* -> percentDecode } :}
    port        <-  {:port: ( [0-9]+ ) -> tonumber :}

    host        <-  ip_literal / {:hostname: ip4_address :} / {:hostname: hostname -> percentDecode :}
    hostname    <- ( percent_encoded / unreserved / sub_delims )*

    ip4_address <-  dec_octet '.' dec_octet '.' dec_octet '.' dec_octet
    dec_octet   <-  '25' [0-5] / '2' [0-4] [0-9] / '1' [0-9] [0-9] / [1-9] [0-9]? / '0'

    ip_literal  <-  '[' {:hostname:  ip6_address :} ']'
    ip6_address <-                             ( h16 ':' )^6 ls32
                /                         '::' ( h16 ':' )^5 ls32
                / (                h16 )? '::' ( h16 ':' )^4 ls32
                / ( ( h16 ':' )^-1 h16 )? '::' ( h16 ':' )^3 ls32
                / ( ( h16 ':' )^-2 h16 )? '::' ( h16 ':' )^2 ls32
                / ( ( h16 ':' )^-3 h16 )? '::'   h16 ':'     ls32
                / ( ( h16 ':' )^-4 h16 )? '::'               ls32
                / ( ( h16 ':' )^-5 h16 )? '::'               h16
                / ( ( h16 ':' )^-6 h16 )? '::'
    ls32        <- ( h16 ':' h16 ) / ip4_address
    h16         <- [%x] [%x]^-3

    path        <-  {:path: pchar* ( '/' pchar* )* -> percentDecode :}
    query       <-  {:query: ( '/' / '?' / pchar )* -> percentDecode :}
    fragment    <-  {:fragment: ( '/' / '?' / pchar )* -> percentDecode :}
    pchar       <-  percent_encoded / unreserved / sub_delims / [:@]
    unreserved  <-  [%w._~-]
    sub_delims  <-  [!$&'()*+,;=]

	percent_encoded <- '%' %x %x
]],
	{
		tonumber = tonumber,
		percentDecode = uri.percentDecode,
	}
)

--- @param info std.uri.parsed
--- @return string
function uri.encode(info)
	local parts, n = {}, 0

	if info.scheme then
		parts[n + 1] = info.scheme
		parts[n + 2] = ':'
		n = n + 2
	end

	if info.hostname then
		parts[n + 1] = '//'
		n = n + 1

		if info.userinfo then
			parts[n + 1] = info.userinfo
			parts[n + 2] = '@'
			n = n + 2
		end

		parts[n + 1] = info.hostname

		if info.port then
			parts[n + 1] = ':'
			parts[n + 2] = tostring(info.port)
			n = n + 2
		end
	end

	parts[n + 1] = info.path
	n = n + 1

	if info.query then
		parts[n + 1] = '?'
		parts[n + 2] = info.query
		n = n + 2
	end

	if info.fragment then
		parts[n + 1] = '#'
		parts[n + 2] = info.fragment
		n = n + 2
	end

	return table.concat(parts, nil, 1, n)
end

--- @param str string
--- @return std.uri.parsed|nil parsed
function uri.decode(str)
	local parsed = grammar:match(str)
	if not parsed then
		return nil
	end

	return parsed
end

--- @param base std.uri.parsed
--- @param relative std.uri.parsed
--- @return std.uri.parsed resolved
function uri.resolve(base, relative)
	local target = {
		scheme = relative.scheme,
		userinfo = relative.userinfo,
		hostname = relative.hostname,
		port = relative.port,
		path = relative.path,
		query = relative.query,
		fragment = relative.fragment,
	}

	if relative.scheme then
		target.path = path.posix.normalize(target.path)
		return target
	end

	target.scheme = base.scheme
	if relative.hostname then
		target.path = path.posix.normalize(target.path)
		return target
	end

	target.userinfo = base.userinfo
	target.hostname = base.hostname
	target.port = base.port
	if relative.path == '' then
		target.path = path.posix.normalize(base.path)
		target.query = relative.query or base.query
		return target
	elseif relative.path:sub(1, 1) == '/' then
		target.path = path.posix.normalize(target.path)
		return target
	else
		target.path = path.posix.join(path.posix.dirname(base.path), relative.path)
		return target
	end
end

return uri
