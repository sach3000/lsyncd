sync {
    default.rsyncssh,
    source = "/backup",
    targetdir = "/backup/",
    host = "ussd-tails01",
    delete = running,
    delay=10,
    rsync = {
        perms = true,
        owner = true,
        group = true,
        verbose = false
    },
    
    default.rsyncssh,
    source = "/backup",
    targetdir = "/backup/",
    host = "ussd-tails01",
    delete = running,
    delay=10,
    rsync = {
        perms = true,
        owner = true,
        group = true,
        verbose = false
    }
}
