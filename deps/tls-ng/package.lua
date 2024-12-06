return {
	name = 'truemedian/tls-ng',
	version = '1.0.0',
	description = 'Apply TLS to a Luv stream',

	license = 'Apache-2.0',
	homepage = 'https://github.com/truemedian/gud/tree/master/deps/tls-ng',
	author = 'truemedian <truemedian@gmail.com> (https://github.com/truemedian)',

	dependencies = {
		'luvit/lua-openssl@0.9.0',
	},

	files = {
		'**.lua',
		'!test*',
	},
}
