--!strict
--[=[
	LuauDataModel -- test suite for the standalone DataModel Standard test double.

	Asserts that the test double faithfully provides:
	- Mock instances with property, parentage, child traversal and class reflection
	- Value vocabulary (UDim2, Vector2, Color3, Rect, etc.)
	- Scene contract (Bounds, ZIndex, IsVisible, Parent, ChildIndex, Clips, LayerRoots, Attributes)
	- Simulated Clock with deterministic frame stepping
	- Reactive binding and cleanup hooks
	- Abstract geometry resolution
]=]
local T = require("@testkit")
local Headless = require("./LuauDataModel")

local function testPropsTableAccessShape()
	local host = Headless.new()
	local frame = host.create("Frame")({
		Name = "Root",
		ZIndex = 4,
		host.create("TextLabel")({ Name = "Label" }),
		host.create("UIPadding")({}),
	})

	assert(frame._ClassName == "Frame", "_ClassName answers, as the shim's props table did")
	assert(frame.ClassName == "Frame", "ClassName answers, as a real Instance does")
	assert(frame.ZIndex == 4, "properties read back by name")
	assert(#frame == 2, `children live in the array part, got #{#frame}`)
	assert(frame[1]._ClassName == "TextLabel", "children indexable by position")

	local walked = {}
	for _, child in ipairs(frame) do
		table.insert(walked, child._ClassName)
	end
	assert(table.concat(walked, ",") == "TextLabel,UIPadding", "ipairs walks children in order")

	assert(host.classOf(frame) == "Frame", "classOf resolves the class")
	assert(frame[1].Parent == frame, "children know their parent")
	assert(frame:FindFirstChildOfClass("UIPadding") ~= nil, "FindFirstChildOfClass finds it")
	assert(frame:IsA("GuiObject") and frame:IsA("Instance"), "IsA walks the ancestry")
	assert(not frame:IsA("ScrollingFrame"), "IsA does not over-claim")
end

local function testReactiveProperties()
	local host = Headless.new()
	local text = host.source("hello")
	local frame = host.create("Frame")({
		host.create("TextLabel")({ Name = "Label", Text = text }),
	})
	local label = frame[1]

	assert(label.Text == "hello", "function-valued property resolved at construction")
	text("world")
	assert(label.Text == "world", "and RE-RESOLVED when the source changed")

	frame:Destroy()
	text("ignored")
	assert(label.Text == "world", "binding stopped after Destroy")
end

local function testCleanupRegistersRatherThanRuns()
	local host = Headless.new()
	local ran = false

	host.cleanup(function()
		ran = true
	end)
	assert(ran == false, "cleanup must NOT run the teardown when registering it")

	local scopedRan = false
	local destroy = host.root(function()
		host.cleanup(function()
			scopedRan = true
		end)
	end)
	assert(scopedRan == false, "still not run while the scope is alive")
	destroy()
	assert(scopedRan == true, "run when the owning scope is destroyed")
end

local function testGeometryContract()
	local host = Headless.new()
	local frame = host.create("Frame")({ Name = "Panel", ZIndex = 7 })

	host.SetBounds(frame, 40, 60, 200, 120)
	local geo = host.Resolve(frame)
	local b = geo.GetBounds()

	assert(b.X == 40 and b.Y == 60, `bounds origin, got {b.X},{b.Y}`)
	assert(b.Width == 200 and b.Height == 120, `bounds extent, got {b.Width}x{b.Height}`)
	assert(geo.GetZIndex() == 7, "GetZIndex reads the node")
	assert(geo.IsVisible() == true, "a node with no Visible set is visible")

	frame.Visible = false
	assert(geo.IsVisible() == false, "Resolve reads LIVE, not a snapshot taken at Resolve time")
end

local function testClock()
	local host = Headless.new()
	assert(host.Clock.Name == "Simulated", "the headless clock identifies itself")

	local ticks, seen = 0, 0
	local unsubscribe = host.Clock.OnFrame(function(dt: number)
		ticks += 1
		seen += dt
	end)

	assert(host.Clock._ListenerCount() == 1, "the listener is registered")
	host.Clock.Step(1 / 60)
	host.Clock.Step(1 / 60)
	assert(ticks == 2, `two steps ran two frames, got {ticks}`)
	assert(math.abs(seen - 2 / 60) < 1e-9, "each frame carried its own dt")
	assert(math.abs(host.Clock.Now() - 2 / 60) < 1e-9, "Now accumulates the simulated time")

	unsubscribe()
	host.Clock.Step(1 / 60)
	assert(ticks == 2, "an unsubscribed listener stops receiving frames")
	assert(host.Clock._ListenerCount() == 0, "and is no longer counted")
end

local function testVocabulary()
	local host = Headless.new()
	local V = host.Vocabulary

	for _, name in
		ipairs({
			"UDim",
			"UDim2",
			"Vector2",
			"Color3",
			"Rect",
			"NumberSequence",
			"NumberSequenceKeypoint",
			"ColorSequence",
			"Font",
			"Enum",
		})
	do
		assert((V :: any)[name] ~= nil, `the host provides {name}`)
	end

	local u = V.UDim2.fromScale(0.25, 1)
	assert(u.X.Scale == 0.25 and u.Y.Scale == 1, "UDim2 arithmetic is real, not a stub")
	local c = V.Color3.fromRGB(255, 128, 0)
	assert(math.abs(c.R - 1) < 1e-6 and math.abs(c.G - 128 / 255) < 1e-6, "Color3 converts as the engine does")
end

local function testSceneContract()
	local host = Headless.new()
	local S = host.Scene

	local screen = host.create("ScreenGui")({ Name = "Layer", DisplayOrder = 5 })
	local clip = host.create("ScrollingFrame")({ Name = "Clip", Parent = screen })
	local card = host.create("Frame")({ Name = "Card", ZIndex = 3, Parent = clip })

	host.SetBounds(clip, 0, 0, 200, 100)
	host.SetBounds(card, 10, 20, 50, 40)

	local x, y, w, h = S.Bounds(card)
	assert(x == 10 and y == 20 and w == 50 and h == 40, "Bounds returns four numbers, not a rectangle")
	assert(S.ZIndex(card) == 3, "ZIndex reads through")
	assert(S.IsVisible(card) == true, "a node with no Visible set is visible")
	assert(S.Parent(card) == clip, "Parent walks the tree")
	assert(S.ChildIndex(card) == 1, "ChildIndex is declaration order within the parent")

	assert(S.Clips(clip) == true, "a ScrollingFrame clips regardless of the flag")
	assert(S.Clips(card) == false, "a plain Frame does not")

	assert(S.IsLayerRoot(screen) == true, "a ScreenGui is a layer root")
	assert(S.IsLayerRoot(card) == false, "a Frame is not")
	assert(S.IsSurface(card) == true, "a Frame is a surface")
	assert(S.DisplayOrder(screen) == 5, "DisplayOrder reads through")
	assert(S.IsEnabled(screen) == true, "a layer root with no Enabled set is enabled")

	card:SetAttribute("SpektrHitCornerScale", 0.5)
	assert(S.Attribute(card, "SpektrHitCornerScale") == 0.5, "attributes read through")
	assert(S.Attribute(card, "Absent") == nil, "and an absent one is nil, not an error")
end

T.test("the scene contract answers what Layer 2 asks", testSceneContract)
T.test("the simulated clock steps exactly and unsubscribes", testClock)
T.test("the value vocabulary is real, not stubbed", testVocabulary)
T.test("mock instances keep the shim's props-table access shape", testPropsTableAccessShape)
T.test("function-valued properties are live reactive bindings", testReactiveProperties)
T.test("cleanup registers a teardown rather than running it", testCleanupRegistersRatherThanRuns)
T.test("Resolve yields a live GeometrySource", testGeometryContract)

return T.run("LuauDataModel")