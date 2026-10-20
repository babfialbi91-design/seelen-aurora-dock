var GB = 1073741824;
var n = cores.length < 1 ? 1 : cores.length;
var cpu = cores.reduce((sum, core) => sum + core.usage, 0) / n;

var ramUsed = (memory.total - memory.free) / GB;
var ramTotal = memory.total / GB;

var parts = [
  icon("LuCpu"),
  " " + cpu.toFixed(0) + "%",
  "   ",
  icon("LuMemoryStick"),
  " " + ramUsed.toFixed(1) + "/" + ramTotal.toFixed(1) + "G"
];

if (batteries.length > 0) {
  parts.push("   ", icon("LuBatteryMedium"), " " + batteries[0].percentage + "%");
}

return parts;
