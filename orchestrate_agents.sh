#!/bin/bash

# DogeGame Multi-Agent Orchestrator
# This script launches multiple Claude instances to work on different parts of the migration

echo "🚀 Starting DogeGame Multi-Agent Migration Orchestrator"
echo "=================================================="

PROJECT_ROOT="/Users/amanson/Desktop/Projects_Main_Folder/CanvasTools/doge"
WORKSPACE_ROOT="$PROJECT_ROOT/agent_workspaces"

# Function to launch an agent in a new terminal
launch_agent() {
    local agent_num=$1
    local agent_name=$2
    local workspace=$3
    
    echo "🤖 Launching Agent $agent_num: $agent_name"
    
    # Create agent launch script
    cat > "$workspace/launch.sh" << EOF
#!/bin/bash
cd "$PROJECT_ROOT"
echo "=================================================="
echo "🤖 AGENT $agent_num: $agent_name"
echo "=================================================="
echo ""
echo "📋 Your task is in: $workspace/task.md"
echo ""
echo "Please read your task file and begin work on your assigned migration."
echo "Remember to:"
echo "1. Plan your approach before implementing"
echo "2. Test thoroughly at each step"
echo "3. Ensure compatibility with other agents' work"
echo "4. Document your changes"
echo ""
echo "Project root: $PROJECT_ROOT"
echo "Your workspace: $workspace"
echo ""
# Keep terminal open
exec bash
EOF

    chmod +x "$workspace/launch.sh"
    
    # Launch in new terminal window (macOS)
    osascript -e "tell app \"Terminal\" to do script \"$workspace/launch.sh\""
    
    sleep 2  # Brief pause between launches
}

# Launch Agent 1 - Renderer Transition (CRITICAL)
echo "🔴 CRITICAL: Agent 1 must complete renderer transition first!"
launch_agent 1 "Renderer Transition" "$WORKSPACE_ROOT/agent1_renderer_transition"

# Launch Agent 2 - Combat Systems
launch_agent 2 "Combat & Projectiles" "$WORKSPACE_ROOT/agent2_combat_mods"

# Launch Agent 3 - Enemy & Boss AI
launch_agent 3 "Enemy & Boss AI" "$WORKSPACE_ROOT/agent3_enemy_boss_mods"

echo ""
echo "✅ All agents launched!"
echo ""
echo "📊 Agent Status:"
echo "- Agent 1: Working on CRITICAL renderer transition"
echo "- Agent 2: Modularizing combat systems"
echo "- Agent 3: Converting enemy/boss AI to mods"
echo ""
echo "🔄 Coordination Tips:"
echo "- Agent 1 MUST complete first (renderer blocker)"
echo "- Agents 2 & 3 can work in parallel"
echo "- Coordinate on shared systems (projectiles, entity IDs)"
echo ""
echo "📁 Workspaces created in: $WORKSPACE_ROOT"
echo ""
echo "Monitor progress in each terminal window."
