return {
	name = 'truemedian/sshkey',
	version = '1.0.0',
	description = 'SSH, PKCS#8, and PKCS#1 PKI library for Lua',

	license = 'Apache-2.0',
	homepage = 'https://github.com/truemedian/gud/tree/master/deps/sshkey',
	author = 'truemedian <truemedian@gmail.com> (https://github.com/truemedian)',

	dependencies = {
		'luvit/lua-openssl@0.9.0',
		'luvit/luabitop@1.0.2',
	},

	files = {
		'**.lua',
		'!test*',
	},
}
