#!/bin/bash

# UI Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

echo -e "${BLUE}=======================================${NC}"
echo -e "${BLUE}        GIT PUSH & PULL HELPER         ${NC}"
echo -e "${BLUE}=======================================${NC}"

# Check if current directory is a git repository
if [ ! -d .git ]; then
    echo -e "${RED}Error: Current directory is not a Git repository!${NC}"
    exit 1
fi

# Get current branch name
get_current_branch() {
    local branch=$(git symbolic-ref --short HEAD 2>/dev/null)
    if [ -z "$branch" ]; then
        branch=$(git rev-parse --short HEAD 2>/dev/null)
    fi
    echo "$branch"
}

# Automatically exclude large video/log files from git tracking
cleanup_ignored_files() {
    git rm -r --cached shared/recordings shared/command_logs *.mp4 *.log server.log 2>/dev/null || true
}

show_menu() {
    CURRENT_BRANCH=$(get_current_branch)
    echo -e "\nCurrent Branch: ${GREEN}$CURRENT_BRANCH${NC}"
    echo -e "${CYAN}Select an action:${NC}"
    echo -e "1) ${GREEN}Push code to GitHub (Auto-skips large videos & logs)${NC}"
    echo -e "2) ${YELLOW}Pull / Checkout updates (Select branch / tag / commit)${NC}"
    echo -e "3) Exit"
    read -p "Enter choice (1-3): " CHOICE
}

do_push() {
    CURRENT_BRANCH=$(get_current_branch)
    echo -e "\n${GREEN}>>> PREPARING TO PUSH CODE TO GITHUB <<<${NC}"
    
    # Remove tracked video/log files from git index
    cleanup_ignored_files
    
    # Show status
    echo -e "${CYAN}Current staged changes (large videos/logs excluded):${NC}"
    git status -s
    
    echo -e "\n${YELLOW}Enter Commit Message:${NC}"
    read -p "> " COMMIT_MSG
    
    if [ -z "$COMMIT_MSG" ]; then
        echo -e "${RED}Error: Commit message cannot be empty!${NC}"
        return
    fi
    
    echo -e "\nAdding source code changes..."
    git add .
    # Ensure videos/logs are untracked
    cleanup_ignored_files
    
    echo -e "Creating commit..."
    git commit -m "$COMMIT_MSG"
    
    echo -e "Pushing to GitHub (branch $CURRENT_BRANCH)..."
    git push origin "$CURRENT_BRANCH"
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✔ Successfully pushed update \"$COMMIT_MSG\" to branch $CURRENT_BRANCH!${NC}"
    else
        echo -e "${RED}✘ An error occurred while pushing code!${NC}"
    fi
}

do_pull() {
    CURRENT_BRANCH=$(get_current_branch)
    echo -e "\n${YELLOW}>>> PREPARING TO PULL / CHECKOUT UPDATES <<<${NC}"
    echo -e "Updating remote references (git fetch)..."
    git fetch --all --tags --prune
    
    echo -e "\n${CYAN}Which version do you want to pull?${NC}"
    echo -e "1) ${GREEN}Latest commit on current branch ($CURRENT_BRANCH)${NC}"
    echo -e "2) ${BLUE}Select another Remote Branch${NC}"
    echo -e "3) ${PURPLE}Select a Tagged Release Version${NC}"
    echo -e "4) ${CYAN}Select a specific recent Commit Hash${NC}"
    read -p "Enter choice (1-4): " PULL_CHOICE
    
    case $PULL_CHOICE in
        1)
            echo -e "\nPulling latest commit from origin/$CURRENT_BRANCH..."
            git pull origin "$CURRENT_BRANCH"
            ;;
        2)
            echo -e "\n${CYAN}List of remote branches:${NC}"
            git branch -r | grep -v 'HEAD' | cat -n
            
            branches=($(git branch -r | grep -v 'HEAD' | sed 's/origin\///'))
            num_branches=${#branches[@]}
            
            if [ $num_branches -eq 0 ]; then
                echo -e "${RED}No remote branches found!${NC}"
                return
            fi
            
            read -p "Select branch index (1-$num_branches): " BRANCH_IDX
            if [[ "$BRANCH_IDX" =~ ^[0-9]+$ ]] && [ "$BRANCH_IDX" -ge 1 ] && [ "$BRANCH_IDX" -le "$num_branches" ]; then
                selected_branch=${branches[$((BRANCH_IDX-1))]}
                echo -e "\nSwitching to branch: ${GREEN}$selected_branch${NC} and pulling..."
                git checkout "$selected_branch"
                git pull origin "$selected_branch"
            else
                echo -e "${RED}Invalid choice!${NC}"
            fi
            ;;
        3)
            echo -e "\n${CYAN}List of available tagged versions (Tags):${NC}"
            git tag | cat -n
            
            tags=($(git tag))
            num_tags=${#tags[@]}
            
            if [ $num_tags -eq 0 ]; then
                echo -e "${YELLOW}No tags found in this repository!${NC}"
                return
            fi
            
            read -p "Select tag index (1-$num_tags): " TAG_IDX
            if [[ "$TAG_IDX" =~ ^[0-9]+$ ]] && [ "$TAG_IDX" -ge 1 ] && [ "$TAG_IDX" -le "$num_tags" ]; then
                selected_tag=${tags[$((TAG_IDX-1))]}
                echo -e "\nSwitching to version tag: ${GREEN}$selected_tag${NC}..."
                git checkout "$selected_tag"
            else
                echo -e "${RED}Invalid choice!${NC}"
            fi
            ;;
        4)
            echo -e "\n${CYAN}10 most recent commits on remote branch origin/$CURRENT_BRANCH:${NC}"
            git log -n 10 --oneline "origin/$CURRENT_BRANCH" | cat -n
            
            commits=($(git log -n 10 --format="%h" "origin/$CURRENT_BRANCH"))
            num_commits=${#commits[@]}
            
            if [ $num_commits -eq 0 ]; then
                echo -e "${RED}No commits found on remote branch!${NC}"
                return
            fi
            
            read -p "Select commit index (1-$num_commits): " COMMIT_IDX
            if [[ "$COMMIT_IDX" =~ ^[0-9]+$ ]] && [ "$COMMIT_IDX" -ge 1 ] && [ "$COMMIT_IDX" -le "$num_commits" ]; then
                selected_commit=${commits[$((COMMIT_IDX-1))]}
                echo -e "\nSwitching code state to commit: ${GREEN}$selected_commit${NC}..."
                git checkout "$selected_commit"
                echo -e "${YELLOW}Note: You are in 'detached HEAD' state. To return to the main branch, re-run this script and select Pull branch.${NC}"
            else
                echo -e "${RED}Invalid choice!${NC}"
            fi
            ;;
        *)
            echo -e "${RED}Invalid choice!${NC}"
            ;;
    esac
}

while true; do
    show_menu
    case $CHOICE in
        1)
            do_push
            ;;
        2)
            do_pull
            ;;
        3)
            echo -e "${BLUE}Goodbye!${NC}"
            exit 0
            ;;
        *)
            echo -e "${RED}Invalid choice, please try again!${NC}"
            ;;
    esac
done

