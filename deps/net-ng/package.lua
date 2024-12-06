return {
	name = 'truemedian/net-ng',
	version = '1.0.0',
	description = 'A synchronous TCP/pipe client and server for Luvit',

	license = 'Apache-2.0',
	homepage = 'https://github.com/truemedian/gud/tree/master/deps/net-ng',
	author = 'truemedian <truemedian@gmail.com> (https://github.com/truemedian)',

	dependencies = {
		'luvit/lua-openssl@0.9.0',
	},

	files = {
		'**.lua',
		'!test*',
	},
}
