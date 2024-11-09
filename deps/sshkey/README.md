
# sshkey

A Lua library for loading SSH keys and manipulating SSH signatures.

## Dependencies

- [lua-openssl](https://github.com/zhaozg/lua-openssl)
- Bitwise operations in Lua
  - [luabitop](https://bitop.luajit.org/) (Lua 5.1, LuaJIT)
  - [bit32](https://www.lua.org/manual/5.2/manual.html#6.7) (Lua 5.2, Lua 5.3)
  - Native bitwise operations in Lua 5.3+

## Supported Key Types

- RSA
- ED25519
- ECDSA (P-256, P-384, P-521)

## Supported Key Formats

Private keys in the following formats are supported:

- OpenSSH `-----BEGIN OPENSSH PRIVATE KEY-----`
- PKCS#1 `-----BEGIN RSA PRIVATE KEY-----`
- PKCS#8 `-----BEGIN PRIVATE KEY-----` or `-----BEGIN ENCRYPTED PRIVATE KEY-----`

Public keys in the following formats are supported:

- OpenSSH `ssh-rsa`, `ssh-ed25519`, `ecdsa-sha2-nistp256`, `ecdsa-sha2-nistp384`, `ecdsa-sha2-nistp521`
- PKCS#1 `-----BEGIN RSA PUBLIC KEY-----`
- PKCS#8 `-----BEGIN PUBLIC KEY-----`

## Documentation

### `sshkey.load_private(data[, passphrase])`

Load a private key from a string. The key type is automatically detected from the format and contents of the encoded data.

When loading non-openssh keys and a passphrase is not provided, openssl will attempt to prompt the user for the passphrase.

**Parameters:**

- `data` (string): The private key data.
- `passphrase` (string, optional): The passphrase to decrypt the key if it is encrypted.

**Returns:**

- `key` (table or nil): The loaded `sshkey` object, or `nil` if the key could not be loaded.
- `error_message` (string or nil): The error message if the key could not be loaded, or `nil` if the key was loaded successfully.

----

### `sshkey.load_public(data)`

Load a public key from a string. The key type is automatically detected from the format and contents of the encoded data.

**Parameters:**

- `data` (string): The public key data.

**Returns:**

- `key` (table or nil): The loaded `sshkey` object, or `nil` if the key could not be loaded.
- `error_message` (string or nil): The error message if the key could not be loaded, or `nil` if the key was loaded successfully.

----

### `sshkey.fingerprint(key)`

Calculates the SHA256 fingerprint of a public key.

**Parameters:**

- `key` (table): The `sshkey` object representing the public key.

**Returns:**

- `fingerprint` (string): The SHA256 fingerprint of the public key.

----

### `sshkey.sign(key, data, namespace)`

Creates a SSH signature of the data using the private key.

**Parameters:**

- `key` (table): The `sshkey` object representing the private key.
- `data` (string): The data to sign.
- `namespace` (string): The namespace for this signature, used as part of the signature format to distinguish between different uses of the same key.

**Returns:**

- `signature` (string or nil): The SSH signature, or `nil` if the signature could not be created.
- `error_message` (string or nil): The error message if the signature could not be created, or `nil` if the signature was created successfully.

----

### `sshkey.verify(key, signature, data[, expected_namespace])`

Verifies a SSH signature of the data using the public key.

**Parameters:**

- `key` (table): The `sshkey` object representing the public key.
- `signature` (string): The SSH signature.
- `data` (string): The data that was signed.
- `expected_namespace` (string, optional): The expected namespace for this signature, used to verify that the signature was created for the correct purpose, or `nil` to allow any namespace.

**Returns:**

- `valid` (boolean): `true` if the signature is valid, `false` otherwise.
- `error_message` (string or nil): The error message if the signature could not be verified, or `nil` if the signature was verified successfully.

## Examples

```lua
local data_private = io.open('private_key'):read('*a')      -- the private key, maybe encrypted using `password`
local data_public = io.open('public_key'):read('*a')        -- the public key
local data_signature = io.open('public_key.sig'):read('*a') -- a signature of the `data_public` using the private key

local pk, pk_e = sshkey.load_public(data_public)
if not pk then
  error('decode public key' .. pk_e)
end

local sk, sk_e = sshkey.load_private(data_private, 'password')
if not sk then
  error('decode private key' .. sk_e)
end

local fp_sk, fp_pk = sshkey.fingerprint(sk), sshkey.fingerprint(pk)
if fp_sk ~= fp_pk then
  error("public and private key fingerprints didn't match")
end

local sig, sig_e = sshkey.sign(sk, data_public, 'something')
if not sig then
  error('create signature' .. v1_e)
end

local v1, v1_e = sshkey.verify(pk, sig, data_public, 'something')
if not v1 then
  error('validate created signature' .. v1_e)
end

local v2, v2_e = sshkey.verify(pk, data_signature, data_public, 'something')
if not v2 then
  error('validate existing signature' .. v2_e)
end
```
