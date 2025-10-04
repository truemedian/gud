return {
	---@type luvit.writable.Base
	Base = import("base.lua"),
	---@type luvit.writable.File
	File = import("file.lua"),
	---@type luvit.writable.Filtered
	Filtered = import("filtered.lua"),
	---@type luvit.writable.Stream
	Stream = import("stream.lua"),
	---@type luvit.writable.String
	String = import("string.lua"),
}
