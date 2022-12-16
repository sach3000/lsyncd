local confdir = '/etc/lsyncd/conf-enabled/'
local entries = readdir( confdir )
for name, isdir in pairs( entries ) do
    if not isdir then
        dofile( confdir .. name )
    end
end


settings {
    logfile = "/var/log/lsyncd/lsyncd.log",
    statusFile = "/var/log/lsyncd/lsyncd.status",
    statusInterval = 1
}
