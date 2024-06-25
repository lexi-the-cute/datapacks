local host = "mqtt.foxgirl.land"
local mqtt = require("mqtt")

local keep_alive = 60

-- ----------

local function is_computercraft()
    return _HOST ~= nil and string.find(_HOST, "ComputerCraft")
end

local computer_id
if is_computercraft() then
    computer_id = tostring(os.getComputerID())
else
    math.randomseed(os.clock()*100000000000)
    computer_id = tostring(math.random(-10000, -1))
end

local user_properties = {
    id = computer_id
}

local uri
if is_computercraft() then
    uri = "wss://" .. host
else
    uri = host
end

-- create mqtt client
local client = mqtt.client {
    -- TODO: Figure out how to get wss:// to work on regular lua MQTT Socket
    uri = uri,
    clean = true,
    keep_alive = keep_alive,
    user_properties = user_properties,
    version = mqtt.v50,
}

local topic = "cc/" .. tostring(computer_id) .. "/example"
local topic_publish = topic .. "/" .. client.args.id
local topic_subscribe = topic .. "/#"
print("> Created MQTT client:", client.args.id)

client:on {
    connect = function(connack)
        local message
        if is_computercraft() then
            message = "Hello from ComputerCraft!"
        else
            message = "Hello from Lua!"
        end

        if connack.rc ~= 0 then
            print("!> Connection to broker failed: ", connack:reason_string(), connack)
            return
        end
        -- print("Connected: ", connack) -- successful connection

        -- subscribe to topic and publish message after it
        assert(client:subscribe { topic = topic_subscribe, qos = 1, callback = function(suback)
            --print("Subscribed: ", suback)
            print("> Subscribed to: " .. topic_subscribe)

            -- publish test message
            print('> Publishing test message "' .. message .. '" to "' .. topic_publish .. '" topic...')
            assert(client:publish {
                topic = topic_publish,
                payload = message,
                qos = 1,
                retain = false,
                properties = {
					payload_format_indicator = 1,
					content_type = "text/plain",
				},
                user_properties = user_properties
            })
            print('----------')
        end })
    end,

    message = function(msg)
        assert(client:acknowledge(msg))

        if msg.topic ~= topic_publish then
            print("Received:", msg.payload)
        end

        if msg.payload == "PING" then
            assert(client:publish {
                topic = topic_publish,
                payload = "PONG",
                user_properties = user_properties,
                retain = false,
                qos = 0
            })
        end

        if msg.payload == "disconnect" then
            print('----------')
            print("Disconnecting...")
            assert(client:disconnect())
        end
    end,

    error = function(err)
        print("!> MQTT client error:", err)
    end,

    close = function()
        print("> MQTT connection closed...")
    end
}

if is_computercraft() then
    parallel.waitForAny(
        function()
            -- run io loop for client until connection close
            -- please note that in sync mode background PINGREQ's are not available, and automatic reconnects too
            --print("Running client in synchronous input/output loop")
            mqtt.run_sync(client)
            --print("Done, synchronous input/output loop is stopped")
        end,

        function()
            while true do
                os.sleep(keep_alive)
                client:send_pingreq()
            end
        end
    )
else
    mqtt.run_ioloop(client)
end