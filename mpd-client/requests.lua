local socket = require("socket")
local client = assert(socket.tcp())

local M = {}
local mpd_server = { host = '127.0.0.1', port = 6600 }

local function check_errors(response)
    local no_database = "ACK [50@0] {list} No database"

    if (response == no_database) then
        print('MPD Error: No Database')
        return true
    end

    return false
end

M.setup = function(config)
    for key, value in pairs(config) do
        mpd_server[key] = value
    end
end

M.artists = function()
    assert(client:connect(mpd_server.host, mpd_server.port))
    client:receive()

    local message = "list artist"
    local response
    local artists = {}

    assert(client:send(message .. "\n"))
    while (response ~= 'OK') do
        response, _ = client:receive()

        if check_errors(response) then
            break
        end

        if (response ~= 'OK') then
            response = string.sub(response, 9, -1) -- remove 'Arist: '
            table.insert(artists, response)
        end
    end

    client:close()
    return artists
end

M.albums_from_artist = function(artist)
    assert(client:connect(mpd_server.host, mpd_server.port))
    client:receive()

    local message = string.format("list album \"(artist == '%s')\"", artist)
    local response
    local albums = {}

    assert(client:send(message .. "\n"))
    while (response ~= 'OK') do
        response, _ = client:receive()
        if (response ~= 'OK') then
            response = string.sub(response, 8, -1) -- remove 'Album: ' 
            table.insert(albums, response)
        end
    end

    client:close()
    return albums
end

M.tracks_from_album = function(artist, album)
    assert(client:connect(mpd_server.host, mpd_server.port))
    client:receive()

    local message = string.format("find \"((artist == '%s') AND (album == '%s'))\"", artist, album)
    local response
    local tracks = {}

    assert(client:send(message .. "\n"))
    local title, file
    while (response ~= 'OK') do
        response, _ = client:receive()

        if string.sub(response, 1, 6) == "file: " then
            file = string.sub(response, 7, -1)
        end

        -- title comes after file in the response, so file will be defined
        if string.sub(response, 1, 7) == "Title: " then
            title = string.sub(response, 8, -1)
            local track = { file=file, title=title }
            table.insert(tracks, track)
        end
    end

    client:close()
    return tracks
end

M.queue = function()
    assert(client:connect(mpd_server.host, mpd_server.port))
    client:receive()

    local message = "playlistinfo"
    assert(client:send(message .. "\n"))

    local queue = {}
    local artist, album, title
    local response

    while (response ~= 'OK') do
        response, _ = client:receive()

        if string.sub(response, 1, 8) == "Artist: " then
            artist = string.sub(response, 9, -1)
        end

        if string.sub(response, 1, 7) == "Album: " then
            album = string.sub(response, 8, -1)
        end

        if string.sub(response, 1, 7) == "Title: " then
            title = string.sub(response, 8, -1)
        end

        if string.sub(response, 1, 4) == "Id: " then
            local id = string.sub(response, 5, -1)
            local song = { artist=artist, album=album, title=title, id=id }
            table.insert(queue, song)
        end
    end

    client:close()
    return queue
end

M.add_album_to_queue = function(artist, album)
    assert(client:connect(mpd_server.host, mpd_server.port))
    client:receive()

    local message = string.format("find \"((artist == '%s') AND (album == '%s'))\"", artist, album)
    local response, err
    assert(client:send(message .. "\n"))

    local files = {}
    while (response ~= 'OK') do
        response, err = client:receive()

        if string.sub(response, 1, 6) == "file: " then
            local file = string.sub(response, 7, -1)
            table.insert(files, file)
        end
    end

    message = "command_list_begin"
    for _, file in ipairs(files) do
        message = message .. "\n" .. string.format("add \"%s\"", file)
    end
    message = message .. "\n" .. "command_list_end"
    assert(client:send(message .. "\n"))

    client:close()
end

M.add_file_to_queue = function(file)
    assert(client:connect(mpd_server.host, mpd_server.port))
    client:receive()

    local message = string.format("add \"%s\"", file)
    assert(client:send(message .. "\n"))
    client:receive()

    client:close()
end

M.clear = function()
    assert(client:connect(mpd_server.host, mpd_server.port))
    client:receive()
    local message = "clear"
    assert(client:send(message .. "\n"))
    client:receive()
    client:close()
end

M.state = function()
    assert(client:connect(mpd_server.host, mpd_server.port))
    client:receive()

    local message = "status"
    local response
    local state

    assert(client:send(message .. "\n"))
    while (response ~= 'OK') do
        response, _ = client:receive()
        if string.sub(response, 1, 7) == 'state: ' then
            state = string.sub(response, 8, -1)
        end
    end

    client:close()
    return state
end

M.toggle_state = function()
    local state = M.state()
    assert(client:connect(mpd_server.host, mpd_server.port))
    client:receive()

    local message
    if (state == 'play') then
        message = 'pause'
        assert(client:send(message .. "\n"))
    else
        message = 'play'
        assert(client:send(message .. "\n"))
    end

    client:close()
    return message
end

M.next = function()
    assert(client:connect(mpd_server.host, mpd_server.port))
    client:receive()
    local message = "next"
    assert(client:send(message .. "\n"))
    client:receive()
    client:close()
end

M.prev = function()
    assert(client:connect(mpd_server.host, mpd_server.port))
    client:receive()
    local message = "previous"
    assert(client:send(message .. "\n"))
    client:receive()
    client:close()
end

M.current = function()
    assert(client:connect(mpd_server.host, mpd_server.port))
    client:receive()

    local message = "status"
    local response
    local id

    assert(client:send(message .. "\n"))
    while (response ~= 'OK') do
        response, _ = client:receive()
        if string.sub(response, 1, 8) == "songid: " then
            id = string.sub(response, 9, -1)
        end
    end

    client:close()
    return id
end

M.play = function(songid)
    assert(client:connect(mpd_server.host, mpd_server.port))
    client:receive()

    local message = string.format("playid %s", songid)

    assert(client:send(message .. "\n"))
    client:close()
end

return M
