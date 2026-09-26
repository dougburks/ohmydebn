-- OhMyDebn installs Neovim's plugins, parsers and Mason's tools from its own
-- tested package, so nothing downloads on its own:
-- - Mason doesn't refresh its registry from GitHub on startup. :MasonUpdate and
--   the :Mason window still do, for adding a language.
-- - LazyVim's own "What's new?" window stays off: OhMyDebn's release notes
--   cover plugin changes.
return {
  { "mason-org/mason.nvim", opts = { registry_cache = { refresh = false } } },
  { "LazyVim/LazyVim", opts = { news = { lazyvim = false, neovim = false } } },
}
