local host = "mqtt.example.com"
local mc = "example-name"
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
    computer_id = computer_id
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

user_properties["id"] = client.args.id
local topic = mc .. "/cc/" .. tostring(computer_id) .. "/example"
local topic_publish = topic .. "/" .. client.args.id
local topic_subscribe = topic .. "/#"
print("> Created MQTT client:", client.args.id)

local function publish(topic, content_type, payload)
    assert(client:publish {
        topic = topic,
        payload = payload,
        qos = 1,
        retain = false,
        properties = {
            payload_format_indicator = 1,
            content_type = content_type,
        },
        user_properties = user_properties
    })
end

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
            --print('> Publishing test message "' .. message .. '" to "' .. topic_publish .. '" topic...')
            --publish(topic_publish, "text/plain", message)
            print('----------')
        end })
    end,

    message = function(msg)
        assert(client:acknowledge(msg))

        if msg.topic ~= topic_publish then
            print("Received:", msg.payload)
        end

        if msg.payload == "PING" then
            publish(topic_publish, "text/plain", "PONG")
        end

        if msg.payload == "gps" then
            local x, y, z = gps.locate()
            local dimension = dimension.locate()
            local message = {
                gps = {x = x, y = y, z = z},
                dimension = dimension
            }

            publish(topic_publish, "application/json", textutils.serializeJSON(message, { unicode_strings = true }))
        end

        if msg.payload == "disconnect" then
            print('----------')
            print("Disconnecting...")
            
            publish(topic_publish, "text/plain", "disconnecting...")
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
