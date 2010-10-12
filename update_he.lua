#!/usr/bin/env lua

--[[
Copyright 2010 crest@cyb0rg.org. All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

1.	Redistributions of source code must retain the above copyright notice,
	this list of conditions and the following disclaimer.

2.	Redistributions in binary form must reproduce the above copyright
	notice, this list of conditions and the following disclaimer in the
	documentation and/or other materials provided with the distribution.

THIS SOFTWARE IS PROVIDED BY THE FREEBSD PROJECT ``AS IS'' AND ANY EXPRESS OR
IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF
MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO
EVENT SHALL THE FREEBSD PROJECT OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT,
INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING,
BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF
LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE
OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF
ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
]]

local io     = require("io")
local socket = require("socket")
local dns    = socket.dns
local http   = require("socket.http")
local ltn12  = require("ltn12")
local ssl    = require("ssl")

--------------------------------------------------------------------------------
-- Constants (if you mess with them you're on your own)
--------------------------------------------------------------------------------

prefix		= "/usr/local/"
conf_file	= prefix .. "etc/he_update.conf"
cafile          = prefix .. "etc/he.crt"
callback        = function() end
status          = prefix .. "var/db/he.status"
base		= "https://ipv4.tunnelbroker.net/ipv4_end.php"
verify		= { "client_once", "fail_if_no_peer_cert", "peer" }
http_ok		= 200
missing		= "Configuration is incomplete: "

--------------------------------------------------------------------------------
-- Configure as needed.
--------------------------------------------------------------------------------

function read_config(path)
	local conf = {}
	local err  = ""
	
	function config (c)
		conf = c
	end
	
	dofile(path)
	
	function miss(msg)
		err = err .. missing .. msg .. ".\n"
	end
		
	if     conf.cafile   then cafile = conf.cafile		end
	if     conf.status   then status = conf.status		end
	if     conf.callback then callback = conf.callback	end
	if not conf.user     then miss("UserID")		end
	if not conf.ddns     then miss("DDNS domain")		end
	if not conf.pass     then miss("MD5 hashed password")	end
	if not conf.tunnel   then miss("TunnelID of endpoint")	end
	
	if err ~= "" then error(err) end
	
	user    = conf.user
	ddns	= conf.ddns
	pass	= conf.pass
	tunnel	= conf.tunnel
	status  = conf.status
end

function read_status(path)
	function current(status)
		old_ip = tostring(status)
	end
	
	dofile(path)
end

function write_status(path, ip)
	local file = assert(io.open(status, "w"), "Failed to open status file.")
	file:write("current(\"" .. ip .. "\")\n")
	file:close()
end
	

--------------------------------------------------------------------------------
-- Lookup your endpoint via DNS
--------------------------------------------------------------------------------

function lookup()
	new_ip = dns.toip(ddns)
	if new_ip == nil then
		error("Failed to resolve \"" .. ddns .. "\".")
	end
end

--------------------------------------------------------------------------------
-- Build the HTTPS request
--------------------------------------------------------------------------------

function inform_he()
	local update = base .. "?ipv4b="     .. new_ip .. 
			       "&pass="      .. pass   ..
			       "&user_id="   .. user   ..
			       "&tunnel_id=" .. tunnel

	local sink = {}
	local one, code, headers, status = https.request {
		url    = update,
		sink   = ltn12.sink.table(sink),
		cafile = cafile,
		verify = verify
	}

	msg = table.concat(sink)

	if code ~= http_ok then -- the request failed.
		error("HTTPS request failed with code \"" .. code .. "\".")
	end

	print(msg)
end

function usage()
	error ("Usage: he_update [<config>]\n" ..
	       "  <config> defaults to $prefix/etc/he_update.conf")
end

function die(exit_code, f)
	local ok, err = pcall(f)
	if not ok then
		print(err)
		os.exit(exit_code)
	end
end

function get_options()
	if #arg > 1 then
		usage()
	elseif #arg == 1 then
		conf_file = arg[1]
	end
end

function main()
	die(1, get_options)
	die(2, function() read_config(conf_file) end)
	die(3, lookup)
	die(4, function() read_status(status) end)
	
	if new_ip ~= old_ip then
		die(5, inform_he)
		die(6, function() write_status(status, new_ip) end)
		die(7, callback)
	end
end

main()
