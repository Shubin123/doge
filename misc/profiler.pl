


#!/usr/bin/perl
use strict;
use warnings;

# Extensible Lua Function Profiler
# Usage: perl profiler.pl input.lua > output.lua
# This script adds non-intrusive profiling to any Lua module

my $input = do { local $/; <> };

# Extract all function definitions and method definitions
my @functions = ();
my @methods = ();

# Find regular functions: function name(...) or local function name(...)
while ($input =~ /(?:^|\n)((?:local\s+)?function\s+([a-zA-Z_][a-zA-Z0-9_.]*)\s*\([^)]*\))/gm) {
    my $full_sig = $1;
    my $func_name = $2;
    
    # Skip functions inside other functions (basic heuristic)
    next if $func_name =~ /\./;  # Skip table.function style for now
    
    push @functions, {
        name => $func_name,
        signature => $full_sig,
        type => 'function'
    };
}

# Find method definitions: function Class:method(...) or function obj.method(...)
while ($input =~ /(?:^|\n)(function\s+([a-zA-Z_][a-zA-Z0-9_]*)[:.])([a-zA-Z_][a-zA-Z0-9_]*)\s*\([^)]*\)/gm) {
    my $class_name = $2;
    my $method_name = $3;
    my $full_name = "$class_name:$method_name";
    
    push @methods, {
        name => $full_name,
        class => $class_name,
        method => $method_name,
        type => 'method'
    };
}

# Find table function assignments: table.function = function(...)
while ($input =~ /(?:^|\n)([a-zA-Z_][a-zA-Z0-9_]*)\.([a-zA-Z_][a-zA-Z0-9_]*)\s*=\s*function\s*\([^)]*\)/gm) {
    my $table_name = $1;
    my $func_name = $2;
    my $full_name = "$table_name.$func_name";
    
    push @functions, {
        name => $full_name,
        table => $table_name,
        function => $func_name,
        type => 'table_function'
    };
}

# Generate profiler setup code
my $profiler_setup = <<'EOF';

-- === AUTO-GENERATED PERFORMANCE PROFILER ===
-- This code was automatically added by the Lua Function Profiler
-- Remove this section to disable profiling

local profiler = {
    times = {},
    calls = {},
    start_times = {},
    enabled = true  -- Set to false to disable profiling
}

function profiler.start(name)
    if not profiler.enabled then return end
    profiler.start_times[name] = love.timer.getTime()
    profiler.calls[name] = (profiler.calls[name] or 0) + 1
end

function profiler.stop(name)
    if not profiler.enabled then return end
    if profiler.start_times[name] then
        local elapsed = love.timer.getTime() - profiler.start_times[name]
        profiler.times[name] = (profiler.times[name] or 0) + elapsed
        profiler.start_times[name] = nil
    end
end

function profiler.reset()
    profiler.times = {}
    profiler.calls = {}
    profiler.start_times = {}
end

function profiler.report(min_time_ms)
    min_time_ms = min_time_ms or 0
    print("\n=== PERFORMANCE PROFILER REPORT ===")
    local sorted_functions = {}
    local total_profiled_time = 0
    
    for name, total_time in pairs(profiler.times) do
        if (total_time * 1000) >= min_time_ms then
            table.insert(sorted_functions, {
                name = name,
                total_time = total_time,
                calls = profiler.calls[name] or 0,
                avg_time = total_time / (profiler.calls[name] or 1)
            })
            total_profiled_time = total_profiled_time + total_time
        end
    end
    
    table.sort(sorted_functions, function(a, b) return a.total_time > b.total_time end)
    
    print(string.format("Total functions profiled: %d", #sorted_functions))
    print(string.format("Total profiled time: %.3f ms", total_profiled_time * 1000))
    print(string.format("%-50s %10s %8s %12s %8s", "Function", "Total(ms)", "Calls", "Avg(ms)", "% Total"))
    print(string.rep("-", 95))
    
    for _, func in ipairs(sorted_functions) do
        local percentage = (func.total_time / total_profiled_time) * 100
        print(string.format("%-50s %10.3f %8d %12.6f %7.1f%%", 
            func.name, 
            func.total_time * 1000, 
            func.calls, 
            func.avg_time * 1000,
            percentage
        ))
    end
    print("=======================================\n")
end

function profiler.enable()
    profiler.enabled = true
end

function profiler.disable()
    profiler.enabled = false
end

-- Store original function pointers
local original_functions = {}

EOF

# Generate function overrides
my $overrides = "";

# Handle regular functions
for my $func (@functions) {
    my $name = $func->{name};
    my $safe_name = $name;
    $safe_name =~ s/[.:]/___/g;  # Replace dots and colons with underscores for storage
    
    if ($func->{type} eq 'table_function') {
        my $table = $func->{table};
        my $function = $func->{function};
        
        $overrides .= <<EOF;
-- Override $name
original_functions.$safe_name = $name
$name = function(...)
    profiler.start('$name')
    local results = {original_functions.$safe_name(...)}
    profiler.stop('$name')
    return unpack(results)
end

EOF
    } else {
        $overrides .= <<EOF;
-- Override $name
original_functions.$safe_name = $name
$name = function(...)
    profiler.start('$name')
    local results = {original_functions.$safe_name(...)}
    profiler.stop('$name')
    return unpack(results)
end

EOF
    }
}

# Handle methods
for my $method (@methods) {
    my $name = $method->{name};
    my $class = $method->{class};
    my $method_name = $method->{method};
    my $safe_name = $name;
    $safe_name =~ s/[.:]/___/g;
    
    $overrides .= <<EOF;
-- Override $name
original_functions.$safe_name = $class.$method_name
$class.$method_name = function(...)
    profiler.start('$name')
    local results = {original_functions.$safe_name(...)}
    profiler.stop('$name')
    return unpack(results)
end

EOF
}

# Add profiler access to the module's return table
my $profiler_access = <<'EOF';

-- Add profiler access to module (insert before return statement)
-- This allows external access via: module.profiler.report()
if type(_G[debug.getinfo(1, "S").source:match("@?(.+)")]) == "table" then
    local module_name = debug.getinfo(1, "S").source:match("@?([^/\\]+)$"):gsub("%.lua$", "")
    _G[module_name] = _G[module_name] or {}
    _G[module_name].profiler = profiler
end

EOF

# Find the return statement and insert profiler access before it
if ($input =~ /(.*)(return\s+\w+)(.*)$/s) {
    my $before_return = $1;
    my $return_statement = $2;
    my $after_return = $3;
    
    $input = $before_return . $profiler_setup . $overrides . $profiler_access . $return_statement . $after_return;
} else {
    # If no return statement found, append at the end
    $input .= $profiler_setup . $overrides . $profiler_access;
}

print $input;

# Print summary to STDERR so it doesn't interfere with output redirection
print STDERR "\n=== PROFILER INJECTION SUMMARY ===\n";
print STDERR "Functions found: " . scalar(@functions) . "\n";
print STDERR "Methods found: " . scalar(@methods) . "\n";
print STDERR "Total hooks added: " . (scalar(@functions) + scalar(@methods)) . "\n";
print STDERR "\nFunction list:\n";
for my $func (@functions, @methods) {
    print STDERR "  - " . $func->{name} . " (" . $func->{type} . ")\n";
}
print STDERR "\nUsage in Lua:\n";
print STDERR "  module.profiler.report()     -- Show full report\n";
print STDERR "  module.profiler.report(1.0)  -- Show only functions > 1ms\n";
print STDERR "  module.profiler.reset()      -- Reset all counters\n";
print STDERR "  module.profiler.disable()    -- Disable profiling\n";
print STDERR "  module.profiler.enable()     -- Re-enable profiling\n";
print STDERR "=====================================\n";
EOF