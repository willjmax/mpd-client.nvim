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

local playlist_previewer = previewers.new_buffer_previewer({
    title = 'Queue',
    define_preview = function(self, entry, status)
        local buf = self.state.bufnr
        local queue = requests.queue()
        local current = requests.current()
        local state = requests.state()

        local glyph
        if (state == "play") then
            glyph = '󰝚'
        else
            glyph = '󰝛'
        end

        for key, song in ipairs(queue) do
            local display
            if (song.id == current) then
                display = string.format("%s %s - %s", glyph, song.artist, song.title)
            else
                display = string.format("  %s - %s", song.artist, song.title)
            end
            vim.api.nvim_buf_set_lines(buf, key, key, true, { display, '' })
        end
    end,
})

local refresh_picker = function()
    if Picker.picker == 'Artists' then
        Artists(Picker.opts)
    end

    if Picker.picker == 'Albums' then
        Albums(Picker.opts, Picker.artist)
    end

    if Picker.picker == 'Tracks' then
        Tracks(Picker.opts, Picker.artist, Picker.album)
    end
end

local common_mappings = function(prompt_bufnr, map)
    map("n", "<leader>c", function(_prompt_bufnr)
        requests.clear()
        refresh_picker()
    end)

    map("n", "<leader>p", function(_prompt_bufnr)
        requests.toggle_state()
        refresh_picker()
    end)

    map("n", "<S-n>", function(_prompt_bufnr)
        requests.next()
        refresh_picker()
    end)

    map("n", "<S-p>", function(_prompt_bufnr)
        requests.prev()
        refresh_picker()
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
                    ordinal = entry.title
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
                Tracks(opts, artist, album)
            end)

            actions.select_default:replace(function()
                actions.close(prompt_bufnr)
                local selection = action_state.get_selected_entry()
                requests.add_file_to_queue(selection.value.file)
                Tracks(opts, artist, album)
            end)

            return true
        end,
        previewer = playlist_previewer,
        initial_mode = 'normal'
    }):find()
end

Artists()
