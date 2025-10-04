return {
	---@type luvit.readable.Base
	Base = import("base.lua"),
	---@type luvit.readable.File
	File = import("file.lua"),
	---@type luvit.readable.Filtered
	Filtered = import("filtered.lua"),
	---@type luvit.readable.Limited
	Limited = import("limited.lua"),
	---@type luvit.readable.Stream
	Stream = import("stream.lua"),
	---@type luvit.readable.String
	String = import("string.lua"),
}
