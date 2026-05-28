--!strict
-- CreditsConfig.lua
-- Attribution entries shown in the Settings hub → Credits section.
-- Schema-driven: adding a credit is a one-line table append below.
--
-- CC BY 4.0 (and most CC licenses) require crediting the author and linking
-- the license (and ideally the source). Keep `author` + `license` + at least
-- one URL populated for every audio/art asset that ships under a license that
-- demands attribution. This list is rendered verbatim by SettingsUI.

export type CreditEntry = {
	title: string,        -- the work, e.g. "The calm theme"
	author: string,       -- who to credit
	license: string,      -- short label, e.g. "CC BY 4.0"
	licenseUrl: string?,  -- link to the license text
	sourceUrl: string?,   -- link to the original work, where available
}

local CreditsConfig: { CreditEntry } = {
	{
		title = "The calm theme",
		author = "BloodPixelHero",
		license = "CC BY 4.0",
		licenseUrl = "https://creativecommons.org/licenses/by/4.0/",
		-- TODO: confirm the source URL for this track before launch.
		sourceUrl = nil,
	},
}

return CreditsConfig
