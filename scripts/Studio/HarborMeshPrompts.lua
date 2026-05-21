-- Reference table for generate_mesh prompts (v2 — clearer silhouettes, tier read).
-- PREFIX is prepended to every tier prompt in Studio MCP / Command Bar workflow.

export type TierPrompt = { prompt: string, size: { x: number, y: number, z: number }, maxTriangles: number? }

local PREFIX =
	"Stylized cozy Roblox harbor game building, warm nautical colors, chunky readable silhouette, single cohesive structure, orthogonal straight edges axis-aligned to world grid, no diagonal rotation, no characters, no floating parts, sits on flat ground, game-ready asset"

return {
	PREFIX = PREFIX,

	Dock = {
		footprint = { 4, 6 },
		facingYawExtra = 0,
		tier3Lights = true,
		tiers = {
			{
				prompt = "weathered wooden fishing pier dock tier 1 rundown: dark brown splintered deck planks with gaps, green moss patches, only two crooked wooden pilings on far water end, low flat humble pier, long rectangular platform, water edge on long side +Z",
				size = { x = 16, y = 5, z = 24 },
			},
			{
				prompt = "repaired wooden harbor pier dock tier 2: neat medium oak plank decking, continuous rope railing along water edge, four sturdy wooden posts on far end, clean rectangular pier, noticeably nicer than rundown tier 1",
				size = { x = 16, y = 6, z = 24 },
			},
			{
				prompt = "grand harbor pier dock tier 3: fresh honey-colored wood deck, iron mooring cleats, coiled rope on deck, two vintage lantern posts on water edge, taller richer detail, prestigious fishing dock, long side faces water +Z",
				size = { x = 16, y = 8, z = 24 },
				maxTriangles = 12000,
			},
		},
	},

	MarketStall = {
		footprint = { 3, 3 },
		facingYawExtra = 0,
		tier3Lights = true,
		tiers = {
			{
				prompt = "small open fish market stall tier 1: sagging faded beige canvas awning, rough dark wood sales counter on customer side -Z, two wooden crates with fish on counter, humble harbor vendor booth square footprint",
				size = { x = 12, y = 5, z = 12 },
			},
			{
				prompt = "harbor fish market stall tier 2: teal and white striped fabric awning, polished wood counter facing -Z, brass fish weighing scale on counter corner, tidy organized market stall",
				size = { x = 12, y = 6, z = 12 },
			},
			{
				prompt = "premium fishmonger market stall tier 3: crushed ice display bed on counter, carved golden wood signboard above awning, warm string lights under canopy, clearly grandest tier, customer side -Z",
				size = { x = 12, y = 7, z = 12 },
			},
		},
	},

	Lighthouse = {
		footprint = { 3, 3 },
		facingYawExtra = 0,
		tier3Lights = true,
		tier3LightBrightness = 2.5,
		tier3LightRange = 45,
		tiers = {
			{
				prompt = "compact harbor lighthouse tier 1: short white stucco tower slightly tapered, circular gray stone foundation pad, tiny dark lantern cage on top, peeling paint, humble beacon under 10 studs tall, centered on square base",
				size = { x = 12, y = 10, z = 12 },
			},
			{
				prompt = "classic candy-stripe lighthouse tier 2: medium height white tower with wide red and white horizontal bands, thick stone base ring, metal walkway gallery under lantern, nautical postcard silhouette, taller than tier 1",
				size = { x = 12, y = 14, z = 12 },
			},
			{
				prompt = "grand harbor lighthouse tier 3: very tall slim white tower, oversized glass and metal lantern room on top with glowing lamp inside, red cap roof on lantern, dramatic landmark twice tier 1 height, crisp clean paint",
				size = { x = 12, y = 18, z = 12 },
				maxTriangles = 12000,
			},
		},
	},

	BaitShop = {
		footprint = { 2, 3 },
		facingYawExtra = 0,
		tier3Lights = true,
		tiers = {
			{
				prompt = "humble fishing rod stand tier 1: open-air wooden plank counter facing customer -Z, simple A-frame rod rack with two fishing rods, small hand-carved wood sign post, no walls, narrow rectangular footprint depth along Z",
				size = { x = 8, y = 5, z = 12 },
			},
			{
				prompt = "cozy rod and tackle shop tier 2: sturdy wood deck platform, teal canvas awning over sales counter facing -Z, vertical rack with four fishing rods visible, coil of rope decoration, welcoming harbor storefront",
				size = { x = 8, y = 6, z = 12 },
			},
			{
				prompt = "premium rod shop tier 3: wide teal canopy roof, polished wood counter facing -Z, glass display case with fishing reels, brass hooks, two warm lantern posts beside entrance, clearly nicest tier gear boutique",
				size = { x = 8, y = 8, z = 12 },
			},
		},
	},

	Smokehouse = {
		footprint = { 3, 4 },
		facingYawExtra = 0,
		tier3Lights = false,
		tiers = {
			{
				prompt = "small rustic fish smokehouse tier 1: rough gray stone walls three sides, short brick chimney with soft smoke puff, thatched grass roof, compact cottage footprint longer Z",
				size = { x = 12, y = 6, z = 16 },
			},
			{
				prompt = "brick harbor smokehouse tier 2: red brick walls, arched wooden front door facing +Z, tall brick chimney stack, dark slate roof, working smoker building",
				size = { x = 12, y = 7, z = 16 },
			},
			{
				prompt = "master smokehouse tier 3: refined brick building, tall copper chimney cap, wooden fish drying racks along side wall, small weather vane on roof peak, largest tier",
				size = { x = 12, y = 9, z = 16 },
			},
		},
	},

	Aquarium = {
		footprint = { 3, 4 },
		facingYawExtra = 0,
		tier3Lights = false,
		tiers = {
			{
				prompt = "quaint barrel aquarium exhibit tier 1: wooden barrel tank with curved staves, front glass viewing window facing -Z, blue water visible inside, small harbor attraction",
				size = { x = 12, y = 5, z = 16 },
			},
			{
				prompt = "public aquarium tank building tier 2: rectangular wood and brass frame structure, large front glass panel facing -Z, blue water fill visible, decorative brass trim band",
				size = { x = 12, y = 7, z = 16 },
			},
			{
				prompt = "elegant aquarium pavilion tier 3: marble stone base platform, large central glass tank, decorative teal mosaic front path slab toward +Z, grand gallery landmark tallest tier",
				size = { x = 12, y = 9, z = 16 },
			},
		},
	},

	Guildhall = {
		footprint = { 5, 5 },
		facingYawExtra = 0,
		tier3Lights = true,
		tiers = {
			{
				prompt = "cozy wooden guild hall lodge tier 1: timber walls, peaked dark shingle roof, red fabric banner over front door facing -Z, wooden notice board on wall, fishermen meeting house square footprint",
				size = { x = 20, y = 8, z = 20 },
			},
			{
				prompt = "harbor guild hall tier 2: mixed stone and timber, stone arch entryway facing -Z, bronze bell mounted above door, teal pennant flags on facade, taller than tier 1",
				size = { x = 20, y = 10, z = 20 },
			},
			{
				prompt = "grand guild headquarters tier 3: stone facade, tall colorful glass window panels on front -Z, large golden emblem crest above entrance, prestigious harbor guild building largest tier",
				size = { x = 20, y = 12, z = 20 },
				maxTriangles = 12000,
			},
		},
	},
}
