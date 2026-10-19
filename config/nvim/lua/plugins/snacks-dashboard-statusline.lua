-- No status line bar under the start screen. lualine leaves the dashboard's
-- status line empty, in a color with Normal's background - which
-- plugin/after/transparency.lua removes, so Neovim draws the line in
-- StatusLine's background instead: a dark bar along the bottom. The
-- dashboard window maps StatusLine to its own (transparent) background, as
-- it already does for Normal; windows with files keep lualine's colors.
return {
	"folke/snacks.nvim",
	opts = {
		styles = {
			dashboard = {
				wo = {
					winhighlight = "Normal:SnacksDashboardNormal,NormalFloat:SnacksDashboardNormal,"
						.. "StatusLine:SnacksDashboardNormal,StatusLineNC:SnacksDashboardNormal",
				},
			},
		},
	},
}
