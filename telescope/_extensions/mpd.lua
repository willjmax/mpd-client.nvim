local pickers = require "telescope.pickers"
local finders = require "telescope.finders"
local actions = require "telescope.actions"
local previewers = require "telescope.previewers"
local action_state = require "telescope.actions.state"
local conf = require("telescope.config").values
local requests = require("mpd-client.requests")

requests.setup({
    host = '127.0.0.1',
    port = 6600
})

-- keep track of opened picker
Picker = { picker='', artist='', album='', opts={} }

-- TODO: stop hardcoding this
PREVIEW_BUFFER_LINES = 32

local get_glyph = function(state)
    if (state == "play") then
        return '󰝚'
    else
        return '󰝛'
    end
end

local playlist_previewer = previewers.new_buffer_previewer({
    title = 'Queue',
    define_preview = function(self, entry, status)
        local buf = self.state.bufnr
        local queue = requests.queue()
        local current = requests.current()
        local mpd_state = requests.state()
        local glyph = get_glyph(mpd_state)

        -- 0 indexed
        local cursor = self.state.cursor or 0
        local top = self.state.top or 0

        -- 1 indexed
        local selected_track = self.state.selected_track or 1

        self.state.current = {}
        self.state.qlen = #queue
        self.state.qlookup = {}
        self.state.song_lookup = {}

        -- initialize to 1, change if there is a track playing
        self.state.playing = 1

        if (self.state.first == nil) then
            self.state.first = true
        end

        for key, song in ipairs(queue) do
            table.insert(self.state.qlookup, song)
            table.insert(self.state.song_lookup, song.id, { song=song, key=key })

            local display
            if (song.id == current) then
                display = string.format("%s %s - %s", glyph, song.artist, song.title)
                selected_track = key

                if (selected_track > PREVIEW_BUFFER_LINES) and (selected_track < self.state.qlen - PREVIEW_BUFFER_LINES) then
                    cursor = PREVIEW_BUFFER_LINES / 2
                    top = math.max(0, selected_track - cursor - 1)
                elseif (selected_track >= self.state.qlen - PREVIEW_BUFFER_LINES) then
                    cursor = PREVIEW_BUFFER_LINES - (self.state.qlen - selected_track) - 1
                    top = self.state.qlen - PREVIEW_BUFFER_LINES
                else
                    cursor = selected_track-1
                end

                self.state.playing = key
            else
                display = string.format("  %s - %s", song.artist, song.title)
            end

            vim.api.nvim_buf_set_lines(buf, key-1, key-1, true, { display })
        end

        self.state.cursor = cursor
        self.state.selected_track = selected_track
        self.state.top = top
        self.state.ns_id = vim.api.nvim_buf_add_highlight(buf, 0, "TabLine", self.state.selected_track - 1, 0, -1)

        if (top > 0) then
            vim.schedule(function()
                self:scroll_fn(top)
            end)
        end

    end,
})

local common_mappings = function(prompt_bufnr, map)
    map("n", "<Esc>", function(_prompt_bufnr)
        actions.close(_prompt_bufnr)
    end)

    map("n", "<leader>c", function(_prompt_bufnr)
        requests.clear()

        playlist_previewer.state.cursor = 0
        playlist_previewer.state.selected_track = 1
        playlist_previewer.state.top = 0

        vim.api.nvim_buf_set_lines(playlist_previewer.state.bufnr, 0, -1, true, {})
    end)

    map("n", "<leader>p", function(_prompt_bufnr)
        local key = playlist_previewer.state.selected_track
        local song = playlist_previewer.state.qlookup[key]
        requests.play(song.id)

        local display
        if (playlist_previewer.state.playing) then
            local playing_key = playlist_previewer.state.playing
            local playing = playlist_previewer.state.qlookup[playing_key]
            display = string.format("  %s - %s", playing.artist, playing.title)
            vim.api.nvim_buf_set_lines(playlist_previewer.state.bufnr, playing_key-1, playing_key, true, { display })
        end

        playlist_previewer.state.playing = key
        display = string.format("%s %s - %s", '󰝚', song.artist, song.title)
        vim.api.nvim_buf_set_lines(playlist_previewer.state.bufnr, key-1, key, true, { display })
        vim.api.nvim_buf_add_highlight(playlist_previewer.state.bufnr, playlist_previewer.state.ns_id, "TabLine", key-1, 0, -1)
    end)

    map("n", "<leader>P", function(_prompt_bufnr)
        local state = requests.toggle_state()
        local key = playlist_previewer.state.playing
        local song = playlist_previewer.state.qlookup[key]

        local glyph = get_glyph(state)
        local display = string.format("%s %s - %s", glyph, song.artist, song.title)
        vim.api.nvim_buf_set_lines(playlist_previewer.state.bufnr, key-1, key, true, { display })

        local selected = playlist_previewer.state.selected_track
        if (selected == key) then
            vim.api.nvim_buf_add_highlight(playlist_previewer.state.bufnr, playlist_previewer.state.ns_id, "TabLine", selected-1, 0, -1)
        end
    end)

    map("n", "<S-j>", function(_prompt_bufnr)
        local cursor = playlist_previewer.state.cursor
        local selected_track = playlist_previewer.state.selected_track

        if (selected_track == playlist_previewer.state.qlen) then
            return
        else
            selected_track = selected_track + 1
        end

        if (cursor == PREVIEW_BUFFER_LINES-1) then
            playlist_previewer:scroll_fn(1)
            playlist_previewer.state.top = playlist_previewer.state.top + 1
        else
            cursor = cursor + 1
        end

        print(cursor, selected_track)

        playlist_previewer.state.cursor = cursor
        playlist_previewer.state.selected_track = selected_track
        vim.api.nvim_buf_clear_namespace(playlist_previewer.state.bufnr, playlist_previewer.state.ns_id, 0, -1)
        vim.api.nvim_buf_add_highlight(playlist_previewer.state.bufnr, playlist_previewer.state.ns_id, "TabLine", selected_track-1, 0, -1)
    end)

    map("n", "<S-k>", function(_prompt_bufnr)
        local cursor = playlist_previewer.state.cursor
        local selected_track = playlist_previewer.state.selected_track

        -- do nothing on the first track in the playlist
        if (selected_track == 1) then
            return
        else
            selected_track = selected_track - 1
        end

        if (cursor > 0) then
            cursor = cursor - 1
        else
            playlist_previewer:scroll_fn(-1)
            playlist_previewer.state.top = playlist_previewer.state.top - 1
        end

        print(cursor, selected_track)

        playlist_previewer.state.cursor = cursor
        playlist_previewer.state.selected_track = selected_track
        vim.api.nvim_buf_clear_namespace(playlist_previewer.state.bufnr, playlist_previewer.state.ns_id, 0, -1)
        vim.api.nvim_buf_add_highlight(playlist_previewer.state.bufnr, playlist_previewer.state.ns_id, "TabLine", selected_track-1, 0, -1)
    end)
end

function Artists(opts)
    opts = opts or {}
    Picker.picker = 'Artists'
    Picker.opts = opts

    pickers.new(opts, {
        prompt_title = "Artists",
        finder = finders.new_table {
            results = requests.artists(),
        },
        sorter = conf.generic_sorter(opts),
        attach_mappings = function(prompt_bufnr, map)
            common_mappings(prompt_bufnr, map)

            actions.select_default:replace(function()
                actions.close(prompt_bufnr)
                local selection = action_state.get_selected_entry()
                Albums(opts, selection[1])
            end)

            return true
        end,
        previewer = playlist_previewer,
        initial_mode = 'normal'
    }):find()
end

function Albums(opts, artist)
    opts = opts or {}
    Picker.picker = 'Albums'
    Picker.artist = artist
    Picker.opts = opts

    pickers.new(opts, {
        prompt_title = artist,
        finder = finders.new_table {
            results = requests.albums_from_artist(artist),
        },
        sorter = conf.generic_sorter(opts),
        attach_mappings = function(prompt_bufnr, map)
            common_mappings(prompt_bufnr, map)
            map("n", "<leader>a", function(_prompt_bufnr)
                local album = action_state.get_selected_entry()[1]
                requests.add_album_to_queue(artist, album)
                Albums(opts, artist)
            end)

            map("n", "<S-h>", function(_prompt_bufnr)
                Artists(opts)
            end)

            actions.select_default:replace(function()
                actions.close(prompt_bufnr)
                local selection = action_state.get_selected_entry()
                Tracks(opts, artist, selection[1])
            end)

            return true
        end,
        previewer = playlist_previewer,
        initial_mode = 'normal'
    }):find()
end

function Tracks(opts, artist, album)
    opts = opts or {}
    Picker.picker = 'Tracks'
    Picker.artist = artist
    Picker.album = album
    Picker.opts = opts

    pickers.new(opts, {
        prompt_title = album,
        finder = finders.new_table {
            results = requests.tracks_from_album(artist, album),
            entry_maker = function(entry)
                return {
                    value = entry,
                    display = entry.title,
                    ordinal = entry.title,
                }
            end,
        },
        sorter = conf.generic_sorter(opts),
        attach_mappings = function(prompt_bufnr, map)
            common_mappings(prompt_bufnr, map)

            map("n", "<S-h>", function(prompt_bufnr)
                Albums(opts, artist)
            end)

            map("n", "<leader>a", function(prompt_bufnr)
                local selection = action_state.get_selected_entry()
                requests.add_file_to_queue(selection.value.file)
                playlist_previewer.state.qlen = playlist_previewer.state.qlen + 1

                -- mpd position is zero indexed
                local songid = requests.get_id_from_pos(playlist_previewer.state.qlen - 1)
                local song = requests.song_info(songid)

                table.insert(playlist_previewer.state.qlookup, song)
                table.insert(playlist_previewer.state.song_lookup, { key=playlist_previewer.state.qlen, song=song })

                local display = string.format("  %s - %s", song.artist, song.title)
                local key = playlist_previewer.state.qlen
                vim.api.nvim_buf_set_lines(playlist_previewer.state.bufnr, key-1, key, true, { display })
            end)

            return true
        end,
        previewer = playlist_previewer,
        initial_mode = 'normal'
    }):find()
end

Artists()
