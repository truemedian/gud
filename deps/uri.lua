local re = import("re")

---@class std.uri
local uri = {}

---@class std.uri.parsed
---@field scheme string|nil
---@field userinfo string|nil
---@field hostname string|nil
---@field port integer|nil
---@field path string
---@field query string|nil
---@field fragment string|nil

local function percent_encode(c)
	return string.format("%%%02X", string.byte(c))
end

---@param str string
---@return string
function uri.percentEncode(str)
	return (str:gsub("([^A-Za-z0-9_.-_~])", percent_encode))
end

local function percent_decode(hex)
	return string.char(tonumber(hex, 16))
end

---@param str string
---@return string
function uri.percentDecode(str)
	return (str:gsub("%%(%x%x)", percent_decode))
end

local grammar = re.compile(
	[[
    uri         <-  {| (scheme ':')? hierarchy ('?' query)? ('#' fragment)? !. |}
    scheme      <-  {:scheme: [%a] [%w+.-]* :}
    hierarchy   <-  ('//' authority path) / path

    authority   <-  (userinfo '@')? host (':' port)?
    userinfo    <-  {:user: { ( percent_encoded / unreserved / sub_delims / ':' )* -> percentDecode } :}
    port        <-  {:port: ( [0-9]+ ) -> tonumber :}

    host        <-  ip_literal / {:host: ip4_address :} / {:host: hostname -> percentDecode :}
    hostname    <- ( percent_encoded / unreserved / sub_delims )*

    ip4_address <-  dec_octet '.' dec_octet '.' dec_octet '.' dec_octet
    dec_octet   <-  '25' [0-5] / '2' [0-4] [0-9] / '1' [0-9] [0-9] / [1-9] [0-9]? / '0'

    ip_literal  <-  '[' {:host:  ip6_address :} ']'
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

---@param info std.uri.parsed
---@return string
function uri.encode(info)
	local parts = {}

	if info.scheme then
		parts[#parts + 1] = info.scheme
		parts[#parts + 1] = ":"
	end

	if info.hostname then
		parts[#parts + 1] = "//"

		if info.userinfo then
			parts[#parts + 1] = info.userinfo
			parts[#parts + 1] = "@"
		end

		parts[#parts + 1] = info.hostname

		if info.port then
			parts[#parts + 1] = ":"
			parts[#parts + 1] = tostring(info.port)
		end
	end

	parts[#parts + 1] = info.path

	if info.query then
		parts[#parts + 1] = "?"
		parts[#parts + 1] = info.query
	end

	if info.fragment then
		parts[#parts + 1] = "#"
		parts[#parts + 1] = info.fragment
	end

	return table.concat(parts)
end

---@param str string
---@return std.uri.parsed|nil parsed
function uri.decode(str)
	local parsed = grammar:match(str)
	if not parsed then
		return nil
	end

	return parsed
end

return uri
