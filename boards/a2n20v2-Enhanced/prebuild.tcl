# Gowin Enhanced prebuild: check every required SSI263 and piano ROM BEFORE
# generating a bitstream. Missing ROMs must never silently synthesize zeroes.
# The SSI263 voice/parameter tables are tracked in Git. Authentic Apple
# SynthLAB sustains are prepared automatically from a verified source disk.
set board_dir [file dirname [file normalize [info script]]]
set prepare_tool [file normalize [file join $board_dir .. .. tools prepare_enhanced_assets.py]]

if {[auto_execok py] ne ""} {
    set python_cmd [list py -3]
} elseif {[auto_execok python3] ne ""} {
    set python_cmd [list python3]
} elseif {[auto_execok python] ne ""} {
    set python_cmd [list python]
} else {
    error "Python 3 required: prepare Enhanced FPGA voice and piano ROMs before Gowin build"
}

if {![file exists $prepare_tool]} {
    error "Missing full ROM preparation tool: $prepare_tool"
}

set prepare_cmd [concat $python_cmd [list $prepare_tool]]
if {[catch {exec {*}$prepare_cmd} result]} {
    error "Enhanced FPGA asset preparation FAILED: $result"
}
puts $result

# Validate all ROM files a second time without network before allowing Gowin.
set verify_cmd [concat $python_cmd [list $prepare_tool --check]]
if {[catch {exec {*}$verify_cmd} result]} {
    error "Enhanced FPGA ROM integrity check FAILED: $result"
}
puts $result

# The existing build timestamp hook is still retained.
set now [clock format [clock seconds] -format "%Y%m%d%H%M%S"]
set out_file [file join $board_dir hdl datetime.svh]
set fp [open $out_file "w"]
puts $fp "// Generated build timestamp"
puts $fp "`define BUILD_DATETIME \"$now\""
close $fp
