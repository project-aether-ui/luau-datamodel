# luau-datamodel

A standalone, in-Luau test double (jsdom) implementing the DataModel Standard.

Archived from [Aether](https://github.com/project-aether-ui/aether) under ADR-002 as an independent headless test double.

## Purpose

LuauDataModel implements Instance.new, AbsolutePosition, AbsoluteSize, property-changed firing, and geometry resolution purely in Luau without requiring the Roblox engine or Dew runtime.

It is a test double for off-engine testing where no native DataModel host is available.