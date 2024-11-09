---@class sshkey.key
---@field kt string
---@field pk userdata
---@field sk userdata
---@field impl table
local key = {}

---@class sshkey.key.ed25519 : sshkey.key
---@field pk_s string
local key_ed25519 = {}

---@class sshkey.key.rsa : sshkey.key
local key_rsa = {}

---@class sshkey.key.ecdsa : sshkey.key
---@field pk_pt string
