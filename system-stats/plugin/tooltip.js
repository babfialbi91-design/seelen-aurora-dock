var GB = 1073741824;
var n = cores.length < 1 ? 1 : cores.length;
var cpu = cores.reduce((sum, core) => sum + core.usage, 0) / n;

var lines = [];
lines.push("CPU    " + cores.length + " cores    " + cpu.toFixed(0) + "%");
lines.push("RAM    " + ((memory.total - memory.free) / GB).toFixed(1) + " / " + (memory.total / GB).toFixed(1) + " GB");

if (disks.length > 0) {
  var d = disks[0];
  var dTotal = d.totalSpace / GB;
  var dUsed = (d.totalSpace - d.availableSpace) / GB;
  lines.push("Disk   " + d.mountPoint + "    " + dUsed.toFixed(0) + " / " + dTotal.toFixed(0) + " GB");
}

if (batteries.length > 0) {
  lines.push("Power  " + batteries[0].percentage + "%    " + batteries[0].state);
}

lines.push("Click to open Task Manager");
return lines.join("\n");
