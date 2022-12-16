initSync = {
  maxProcesses = 1,

  action = function(inlet)
        local config = inlet.getConfig()
        local event = inlet.getEvent(function(event) return event.etype ~= "Blanket" end)
        log("Normal", "Event: ", event.etype)
        log("Normal", "Event status: ", event.status)
        log("Normal", "Performing sync:", config.source, config.target," file: ", event.name, " node: ", config.endpoint)
        spawn(
            event,
            '/usr/bin/rsync',
            '-v',
            '-r',
            '--delete',
            '--ignore-existing',
            '--timeout=5',
            '--whole-file',
            '--checksum',
            '--include="*.wav"',
            '--exclude="*"',
            config.source,
            config.endpoint..':'..config.target
        )

        if event.status == "wait" then inlet.discardEvent(event) end
  end,
  
      --
      -- Called when collecting a finished child process
      --

      collect = function(agent, exitcode)

          local config = agent.config

          if not agent.isList and agent.etype == "Blanket" then
              if exitcode == 0 then
                  log("Normal", "Startup of '",agent.source,"' finished.")
              elseif config.exitcodes and
                  config.exitcodes[exitcode] == "again"
              then
                  log("Normal", "Retrying startup of '",agent.source,"'.")
                  return "again"
              else
                  log("Error", "Failure on startup of '",agent.source,"'.")
              end
              return
          end

          local rc = config.exitcodes and config.exitcodes[exitcode]
          if rc == "die" then
              return rc
          end

          if agent.isList then
              if rc == "again" then
                  log("Normal", "Retrying a list on exitcode: ",exitcode)
              else
                  log("Normal", "Finished a list = ",exitcode)
              end
          else
              if rc == "again" then
                  log("Normal", "Retrying ", agent.etype, " on ", agent.name, " sync to: ",config.endpoint, " with exitcode: ", exitcode)
              else
                  log("Normal", "Finished ", agent.etype, " on ", agent.name, " sync to: ",config.endpoint, " with exitcode: ", exitcode)
                  if agent.etype == "Create" then
                          local function file_exists(name)
                              local f=io.open(name,"r")
                              if f~=nil then io.close(f) return true else return false end
                          end
                          
                          -- Local checksum and write to file check
                          local handle = io.popen ("md5sum "..config.source..agent.name.."| awk '{print $1}' ")
                          local file_md5 = handle:read("*a")
                          handle:close()
                          log("Normal", "File Local node, file: ", agent.name, " checksum: ", file_md5)
                          if file_exists(config.check..agent.name..".check") then
                              local handle_append = assert(io.open(config.check..agent.name..".check","a"))
                              handle_append:write("local:"..file_md5)
                              handle_append:close()
                              log("Normal","File: ",config.check..agent.name..".check"," append")
                          else
                              local handle_create = assert(io.open(config.check..agent.name..".check","w"))
                              handle_create:write("local:"..file_md5)
                              handle_create:close()
                              log("Normal","File: ",config.check..agent.name..".check"," create and write")
                          end
                              
                          -- Get node file checksum and write to file check
                          handle = io.popen ("ssh "..config.endpoint.." 'md5sum "..config.target..agent.name.."' | awk '{print $1}'")
                          file_md5 = handle:read("*a")
                          handle:close()
                          log("Normal", "File from node: ", config.endpoint, " file: ", agent.name, " checksum: ", file_md5)
                          if file_exists(config.check..agent.name..".check") then
                              local handle_append = assert(io.open(config.check..agent.name..".check","a"))
                              handle_append:write(config.endpoint..":"..file_md5)
                              handle_append:close()
                              log("Normal","File: ",config.check..agent.name..".check"," append")
                          else
                              local handle_append = assert(io.open(config.check..agent.name..".check","w"))
                              handle_append:write(config.endpoint..":"..file_md5)
                              handle_append:close()
                              log("Normal","File: ",config.check..agent.name..".check"," create and write")
                          end
                  end
              end
          end
          return rc
      end,
  
  prepare = function(config)
    if not config.source then
      error("Script needs 'source' parameter configured.", 4)
    end
    if not config.target then
      error("Script needs 'target' parameter configured.", 4)
    end
  end,
  
  exitcodes = {
    [1] = "again",
    [2] = "die"
  }
}

local nodes = {'voice-tails04','voice-tails05'}

for _, node in ipairs(nodes) do
  sync {
      initSync,
      endpoint = node,
      delay = 0,
      init = false,
      source = "/var/www/public/media",
      target = "/opt/promt/media/",
      check = "/var/www/public/check/"
  }
end

checkSync = {
    action = function(inlet)
        local config = inlet.getConfig()
        local event = inlet.getEvent(function(event) return event.etype ~= "Blanket" end)
        
        log("Normal","Check file: ",event.name)

        -- Func exist
        local function file_exists(name)
            local f=io.open(name,"r")
            if f~=nil then io.close(f) return true else return false end
        end

        if file_exists(config.source..event.name) then
            local handle_check = assert(io.open(config.source..event.name,"r"))
            local arr = {}
            local cnt = 1
            local node
            local sum

            for line in handle_check:lines() do
                node, sum = line:match("([^,]+):([^,]+)")
                table.insert(arr, sum)
            end
            for i = 2,#arr do
              if arr[1] == arr[i] then
                  cnt = cnt + 1
              end
            end
            if cnt == #arr then
                log("Normal", "FILE: ", event.name, " CHECKSUM: OK ")
                local reqbody = '{"files":["'..event.name:gsub("%.check", "")..'"]}'
                log("Normal", "POST_BODY: ", reqbody)
                local handle_post = io.popen ("curl -o /dev/null -s -w '%{http_code}\n' -X POST -d '"..reqbody.."' -H 'Content-Type: application/json' http://127.0.0.1:8080/voicetm/v1/media_object")
                local respcode = handle_post:read("*a")
                handle_post:close()
                if tonumber(respcode) == 204 then
                    log("Normal", "FILE: ", event.name, " SEND POST: OK ")
                else
                    log("Error", "Error sending POST internal API, http code: ", respcode)
                end
            end
            handle_check:close()
        else
            log("Normal","File: ",config.source..event.name," not exist")
        end
        if event.status == "wait" then inlet.discardEvent(event) end
  end,
}

sync {
    checkSync,
    delay = 0,
    init = false,
    source = "/var/www/public/check/"
}
