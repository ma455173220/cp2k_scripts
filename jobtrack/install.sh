#!/bin/bash
# JobTrack - Installation Script

set -e

echo "╔═══════════════════════════════════════╗"
echo "║   JobTrack Installation Wizard        ║"
echo "╚═══════════════════════════════════════╝"
echo ""

# Default paths
DEFAULT_BIN_DIR="$HOME/.local/bin"
DEFAULT_FISH_FUNC_DIR="$HOME/.config/fish/functions"

# Ask for installation directory
echo "Installation Directory"
echo "──────────────────────────────────────"
echo "Choose where to install jobtrack:"
echo "  1) $DEFAULT_BIN_DIR (default)"
echo "  2) Custom path"
echo ""
read -p "Choice [1]: " install_choice
install_choice=${install_choice:-1}

if [ "$install_choice" = "2" ]; then
    read -p "Enter custom path: " INSTALL_BIN_DIR
    INSTALL_BIN_DIR="${INSTALL_BIN_DIR/#\~/$HOME}"
else
    INSTALL_BIN_DIR="$DEFAULT_BIN_DIR"
fi

echo ""
echo "Installation path: $INSTALL_BIN_DIR"
echo ""

# Create directories
echo "Creating directories..."
mkdir -p "$INSTALL_BIN_DIR"
mkdir -p "$DEFAULT_FISH_FUNC_DIR"
echo "✓ Done"
echo ""

# Install main script
echo "Installing main script..."
if [ -f "jobtrack.sh" ]; then
    cp jobtrack.sh "$INSTALL_BIN_DIR/jobtrack"
    chmod +x "$INSTALL_BIN_DIR/jobtrack"
    echo "✓ jobtrack → $INSTALL_BIN_DIR/jobtrack"
else
    echo "✗ jobtrack.sh not found"
    exit 1
fi
echo ""

# Install Fish functions
echo "Installing Fish functions..."
FISH_INSTALLED=false

if [ -f "jobtrack_fzf.fish" ]; then
    cp jobtrack_fzf.fish "$DEFAULT_FISH_FUNC_DIR/"
    echo "✓ jobtrack_fzf.fish"
    FISH_INSTALLED=true
fi

if [ -f "jobtrack_functions.fish" ]; then
    cp jobtrack_functions.fish "$DEFAULT_FISH_FUNC_DIR/"
    echo "✓ jobtrack_functions.fish"
    FISH_INSTALLED=true
fi

if [ -f "jtg.fish" ]; then
    cp jtg.fish "$DEFAULT_FISH_FUNC_DIR/"
    echo "✓ jtg.fish"
    FISH_INSTALLED=true
fi
echo ""

# Configure aliases
echo "Configuring aliases..."
echo "──────────────────────────────────────"
echo "Add aliases to shell configs?"
echo "  1) Yes (recommended)"
echo "  2) No"
echo ""
read -p "Choice [1]: " alias_choice
alias_choice=${alias_choice:-1}

if [ "$alias_choice" = "1" ]; then
    # Bash aliases
    BASHRC="$HOME/.bashrc"
    if [ -f "$BASHRC" ]; then
        echo ""
        echo "Adding aliases to $BASHRC..."
        
        if ! grep -q "# JobTrack aliases" "$BASHRC" 2>/dev/null; then
            cat >> "$BASHRC" << 'EOF'

# JobTrack aliases
alias jt='jobtrack'
alias jts='jobtrack submit'
alias jtl='jobtrack list'
alias jtt='jobtrack today'
EOF
            echo "✓ Bash aliases added"
        else
            echo "✓ Bash aliases already exist"
        fi
    fi
    
    # Fish aliases
    FISH_CONFIG="$HOME/.config/fish/config.fish"
    if [ -f "$FISH_CONFIG" ] || [ "$FISH_INSTALLED" = true ]; then
        echo "Adding aliases to $FISH_CONFIG..."
        
        touch "$FISH_CONFIG"
        
        if ! grep -q "# JobTrack aliases" "$FISH_CONFIG" 2>/dev/null; then
            cat >> "$FISH_CONFIG" << 'EOF'

# JobTrack aliases
abbr -a jt jobtrack
abbr -a jts jobtrack submit
abbr -a jtl jobtrack list
abbr -a jtf jobtrack_fzf
abbr -a jtt jobtrack today
EOF
            echo "✓ Fish aliases added"
        else
            echo "✓ Fish aliases already exist"
        fi
    fi
fi
echo ""

# Check PATH
echo "Checking PATH..."
if [[ ":$PATH:" != *":$INSTALL_BIN_DIR:"* ]]; then
    echo "⚠ $INSTALL_BIN_DIR not in PATH"
    echo ""
    echo "Add to PATH:"
    echo ""
    echo "For Bash (~/.bashrc):"
    echo "  export PATH=\"$INSTALL_BIN_DIR:\$PATH\""
    echo ""
    echo "For Fish (~/.config/fish/config.fish):"
    echo "  set -Ua fish_user_paths $INSTALL_BIN_DIR"
    echo ""
    read -p "Add to PATH now? (y/n) [y]: " add_path
    add_path=${add_path:-y}
    
    if [[ "$add_path" =~ ^[Yy]$ ]]; then
        if [ -f "$HOME/.bashrc" ]; then
            if ! grep -q "$INSTALL_BIN_DIR" "$HOME/.bashrc"; then
                echo "export PATH=\"$INSTALL_BIN_DIR:\$PATH\"" >> "$HOME/.bashrc"
                echo "✓ Added to ~/.bashrc"
            fi
        fi
        
        if [ -f "$HOME/.config/fish/config.fish" ]; then
            if ! grep -q "$INSTALL_BIN_DIR" "$HOME/.config/fish/config.fish"; then
                echo "set -Ua fish_user_paths $INSTALL_BIN_DIR" >> "$HOME/.config/fish/config.fish"
                echo "✓ Added to ~/.config/fish/config.fish"
            fi
        fi
    fi
else
    echo "✓ PATH configured"
fi
echo ""

# Check dependencies
echo "Checking dependencies..."
if command -v fzf &> /dev/null; then
    echo "✓ fzf installed"
else
    echo "✗ fzf not found"
    echo "  Install: conda install -c conda-forge fzf"
fi
echo ""

# Summary
echo "╔═══════════════════════════════════════╗"
echo "║      Installation Complete!           ║"
echo "╚═══════════════════════════════════════╝"
echo ""
echo "Installation Summary:"
echo "  Main script:  $INSTALL_BIN_DIR/jobtrack"
echo "  Fish funcs:   $DEFAULT_FISH_FUNC_DIR/"
echo "  Log file:     ~/.jobtrack.log"
echo ""
echo "Next Steps:"
echo "  1. Reload shell:"
echo "     source ~/.bashrc         (Bash)"
echo "     source ~/.config/fish/config.fish  (Fish)"
echo ""
echo "  2. Test installation:"
echo "     jobtrack -h"
echo "     jtf              (FZF browser)"
echo ""
echo "Quick Reference:"
echo "  jt          → jobtrack"
echo "  jts job.pbs → submit job"
echo "  jtl         → list jobs"
echo "  jtf         → FZF browser"
echo "  jtt         → today's summary"
echo "  jtg <id>    → go to job directory"
echo ""
echo "Get started: jts job.pbs"
echo ""
