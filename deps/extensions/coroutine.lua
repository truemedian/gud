local function assertresume_aux(co, success, ...)
	if success then
		return ...
	else
		return error(debug.traceback(co, (...)), 1)
	end
end

--- Resumes the given coroutine, asserting that it does not fail.
---
--- If the coroutine does error, the error is augmented with a stack trace of the coroutine itself, and then re-raised.
--- @param co thread
--- @param ... any
--- @return any
function coroutine.assertresume(co, ...)
	return assertresume_aux(co, coroutine.resume(co, ...))
end

if not coroutine.isyieldable then
	--- @return boolean
	function coroutine.isyieldable()
		local co, ismain = coroutine.running()
		return co and not ismain
	end
end
