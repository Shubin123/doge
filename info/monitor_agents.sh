#!/bin/bash

# Agent Progress Monitor
# Updates the plan.txt with current agent status

PROJECT_ROOT="/Users/amanson/Desktop/Projects_Main_Folder/CanvasTools/doge"
WORKSPACE_ROOT="$PROJECT_ROOT/agent_workspaces"

echo "📊 DogeGame Migration Progress Monitor"
echo "====================================="
echo ""

# Function to check agent workspace for activity
check_agent_progress() {
    local agent_num=$1
    local workspace=$2
    local task_name=$3
    
    echo "🤖 Agent $agent_num - $task_name:"
    
    # Check if any new files have been created
    if [ -d "$workspace" ]; then
        file_count=$(find "$workspace" -name "*.lua" -o -name "*.json" 2>/dev/null | wc -l)
        mod_count=$(find "$PROJECT_ROOT/mods" -newer "$workspace/task.md" 2>/dev/null | wc -l)
        
        echo "   📁 Files in workspace: $file_count"
        echo "   📦 New mod files: $mod_count"
        
        # Check for progress markers
        if [ -f "$workspace/progress.txt" ]; then
            echo "   📝 Progress notes:"
            cat "$workspace/progress.txt" | sed 's/^/      /'
        fi
    else
        echo "   ❌ Workspace not found"
    fi
    echo ""
}

# Monitor each agent
check_agent_progress 1 "$WORKSPACE_ROOT/agent1_renderer_transition" "Renderer Transition"
check_agent_progress 2 "$WORKSPACE_ROOT/agent2_combat_mods" "Combat Systems" 
check_agent_progress 3 "$WORKSPACE_ROOT/agent3_enemy_boss_mods" "Enemy & Boss AI"

echo "🔍 Recent Changes:"
echo "=================="
# Show recent file modifications
find "$PROJECT_ROOT/src" "$PROJECT_ROOT/mods" -type f \( -name "*.lua" -o -name "*.json" \) -mmin -30 2>/dev/null | head -10

echo ""
echo "💡 Tips:"
echo "- Agents should update progress.txt in their workspace"
echo "- Check individual terminals for detailed output"
echo "- Run './orchestrate_agents.sh' to relaunch agents"
echo ""

# Create a progress summary file
cat > "$WORKSPACE_ROOT/migration_status.md" << EOF
# Migration Status - $(date)

## Agent 1: Renderer Transition
Status: ${AGENT1_STATUS:-"In Progress"}
- Critical blocker for other agents
- Must complete main.lua transition

## Agent 2: Combat Systems  
Status: ${AGENT2_STATUS:-"In Progress"}
- weapons_core_mod
- projectiles_mod
- combat_effects_mod

## Agent 3: Enemy & Boss AI
Status: ${AGENT3_STATUS:-"In Progress"}
- basic_enemies_mod
- bear_boss_mod
- ai_behaviors_mod

## Next Steps:
1. Complete renderer transition (Agent 1)
2. Test combat mods (Agent 2)
3. Test enemy AI mods (Agent 3)
4. Integration testing
EOF

echo "📄 Status saved to: $WORKSPACE_ROOT/migration_status.md"
