--- @meta

--- @class std.stream
--- @field reader std.reader
--- @field writer std.writer
--- @field close fun(stream: std.stream, timeout?: integer)
--- @field shutdown fun(stream: std.stream, timeout?: integer)
--- @field ioctl fun(stream: std.stream, command: string, ...): any

--- @class std.stream.server
--- @field bind fun(server: std.stream.server, ...)
--- @field listen fun(server: std.stream.server, backlog?: integer, callback: fun(client: std.stream))

--- @class openssl.x509 : userdata
--- @field class 'openssl.x509'

--- @class openssl.x509.store : userdata
--- @field class 'openssl.x509.store'

--- @class openssl.pkey : userdata
--- @field class 'openssl.pkey'

--- @class openssl.ssl : userdata
--- @field class 'openssl.ssl'
--- @field write fun(ssl: openssl.ssl, data: string): integer
--- @field read fun(ssl: openssl.ssl, size?: integer): string

--- @class openssl.ssl.ctx : userdata
--- @field class 'openssl.ssl.ctx'
--- @field ssl fun(ctx: openssl.ssl.ctx, bio_in: openssl.bio, bio_out: openssl.bio, server?: boolean): openssl.ssl

--- @class openssl.bio : userdata
--- @field class 'openssl.bio'
--- @field write fun(bio: openssl.bio, data: string): integer
--- @field read fun(bio: openssl.bio, size?: integer): string
--- @field pending fun(bio: openssl.bio): integer
