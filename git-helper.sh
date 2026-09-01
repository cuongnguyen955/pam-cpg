#!/bin/bash

# Màu sắc giao diện
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

# Kiểm tra thư mục hiện tại có phải repo git
if [ ! -d .git ]; then
    echo -e "${RED}Lỗi: Thư mục hiện tại không phải là một Git repository!${NC}"
    exit 1
fi

# Lấy tên nhánh hiện tại
get_current_branch() {
    local branch=$(git symbolic-ref --short HEAD 2>/dev/null)
    if [ -z "$branch" ]; then
        branch=$(git rev-parse --short HEAD 2>/dev/null)
    fi
    echo "$branch"
}

# Tự động loại bỏ các tệp video / log khỏi git tracking
cleanup_ignored_files() {
    git rm -r --cached shared/recordings shared/command_logs *.mp4 *.log server.log 2>/dev/null || true
}

show_menu() {
    CURRENT_BRANCH=$(get_current_branch)
    echo -e "\nNhánh hiện tại: ${GREEN}$CURRENT_BRANCH${NC}"
    echo -e "${CYAN}Chọn chức năng:${NC}"
    echo -e "1) ${GREEN}Push code lên GitHub (Tự động bỏ qua video recording & log)${NC}"
    echo -e "2) ${YELLOW}Pull code về máy (Chọn phiên bản/nhánh/commit)${NC}"
    echo -e "3) Thoát"
    read -p "Nhập lựa chọn (1-3): " CHOICE
}

do_push() {
    CURRENT_BRANCH=$(get_current_branch)
    echo -e "\n${GREEN}>>> CHUẨN BỊ PUSH CODE LÊN GITHUB <<<${NC}"
    
    # Loại bỏ file video / log khỏi git index nếu đã vô tình bị track
    cleanup_ignored_files
    
    # Hiển thị trạng thái thay đổi
    echo -e "${CYAN}Trạng thái thay đổi hiện tại (Đã loại bỏ video/log lớn):${NC}"
    git status -s
    
    echo -e "\n${YELLOW}Nhập tên bản cập nhật (Commit Message):${NC}"
    read -p "> " COMMIT_MSG
    
    if [ -z "$COMMIT_MSG" ]; then
        echo -e "${RED}Lỗi: Tên bản cập nhật không được để trống!${NC}"
        return
    fi
    
    echo -e "\nĐang thêm các thay đổi mã nguồn..."
    git add .
    # Đảm bảo không add lại video / log
    cleanup_ignored_files
    
    echo -e "Đang tạo commit..."
    git commit -m "$COMMIT_MSG"
    
    echo -e "Đang push lên GitHub (nhánh $CURRENT_BRANCH)..."
    git push origin "$CURRENT_BRANCH"
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✔ Đã push thành công bản cập nhật \"$COMMIT_MSG\" lên nhánh $CURRENT_BRANCH!${NC}"
    else
        echo -e "${RED}✘ Có lỗi xảy ra trong quá trình push code!${NC}"
    fi
}

do_pull() {
    CURRENT_BRANCH=$(get_current_branch)
    echo -e "\n${YELLOW}>>> CHUẨN BỊ PULL / CHECKOUT BẢN CẬP NHẬT <<<${NC}"
    echo -e "Đang cập nhật danh sách từ remote (git fetch)..."
    git fetch --all --tags --prune
    
    echo -e "\n${CYAN}Bạn muốn kéo bản nào về?${NC}"
    echo -e "1) ${GREEN}Bản mới nhất của nhánh hiện tại ($CURRENT_BRANCH)${NC}"
    echo -e "2) ${BLUE}Chọn một Nhánh (Branch) khác từ remote${NC}"
    echo -e "3) ${PURPLE}Chọn một Phiên bản đã gắn thẻ (Tag)${NC}"
    echo -e "4) ${CYAN}Chọn một Commit cụ thể trong lịch sử gần đây${NC}"
    read -p "Nhập lựa chọn (1-4): " PULL_CHOICE
    
    case $PULL_CHOICE in
        1)
            echo -e "\nĐang pull bản mới nhất từ origin/$CURRENT_BRANCH..."
            git pull origin "$CURRENT_BRANCH"
            ;;
        2)
            echo -e "\n${CYAN}Danh sách các nhánh trên remote:${NC}"
            # Liệt kê các nhánh remote
            git branch -r | grep -v 'HEAD' | cat -n
            
            # Lưu danh sách nhánh vào array
            branches=($(git branch -r | grep -v 'HEAD' | sed 's/origin\///'))
            num_branches=${#branches[@]}
            
            if [ $num_branches -eq 0 ]; then
                echo -e "${RED}Không tìm thấy nhánh nào trên remote!${NC}"
                return
            fi
            
            read -p "Chọn số thứ tự nhánh muốn checkout (1-$num_branches): " BRANCH_IDX
            if [[ "$BRANCH_IDX" =~ ^[0-9]+$ ]] && [ "$BRANCH_IDX" -ge 1 ] && [ "$BRANCH_IDX" -le "$num_branches" ]; then
                selected_branch=${branches[$((BRANCH_IDX-1))]}
                echo -e "\nĐang chuyển sang nhánh: ${GREEN}$selected_branch${NC} và cập nhật..."
                git checkout "$selected_branch"
                git pull origin "$selected_branch"
            else
                echo -e "${RED}Lựa chọn không hợp lệ!${NC}"
            fi
            ;;
        3)
            echo -e "\n${CYAN}Danh sách các phiên bản (Tags) hiện có:${NC}"
            git tag | cat -n
            
            tags=($(git tag))
            num_tags=${#tags[@]}
            
            if [ $num_tags -eq 0 ]; then
                echo -e "${YELLOW}Không tìm thấy thẻ (Tag) nào trong repository!${NC}"
                return
            fi
            
            read -p "Chọn số thứ tự phiên bản muốn chuyển về (1-$num_tags): " TAG_IDX
            if [[ "$TAG_IDX" =~ ^[0-9]+$ ]] && [ "$TAG_IDX" -ge 1 ] && [ "$TAG_IDX" -le "$num_tags" ]; then
                selected_tag=${tags[$((TAG_IDX-1))]}
                echo -e "\nĐang chuyển về phiên bản: ${GREEN}$selected_tag${NC}..."
                git checkout "$selected_tag"
            else
                echo -e "${RED}Lựa chọn không hợp lệ!${NC}"
            fi
            ;;
        4)
            echo -e "\n${CYAN}10 commit gần nhất trên remote branch origin/$CURRENT_BRANCH:${NC}"
            # Lấy 10 commit gần nhất
            git log -n 10 --oneline "origin/$CURRENT_BRANCH" | cat -n
            
            # Lưu commit hashes vào array
            commits=($(git log -n 10 --format="%h" "origin/$CURRENT_BRANCH"))
            num_commits=${#commits[@]}
            
            if [ $num_commits -eq 0 ]; then
                echo -e "${RED}Không tìm thấy commit nào trên nhánh remote!${NC}"
                return
            fi
            
            read -p "Chọn số thứ tự commit muốn chuyển về (1-$num_commits): " COMMIT_IDX
            if [[ "$COMMIT_IDX" =~ ^[0-9]+$ ]] && [ "$COMMIT_IDX" -ge 1 ] && [ "$COMMIT_IDX" -le "$num_commits" ]; then
                selected_commit=${commits[$((COMMIT_IDX-1))]}
                echo -e "\nĐang chuyển trạng thái code về commit: ${GREEN}$selected_commit${NC}..."
                git checkout "$selected_commit"
                echo -e "${YELLOW}Lưu ý: Bạn đang ở trạng thái 'detached HEAD'. Để quay lại nhánh chính, hãy chạy lại script này và chọn Pull nhánh.${NC}"
            else
                echo -e "${RED}Lựa chọn không hợp lệ!${NC}"
            fi
            ;;
        *)
            echo -e "${RED}Lựa chọn không hợp lệ!${NC}"
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
            echo -e "${BLUE}Tạm biệt!${NC}"
            exit 0
            ;;
        *)
            echo -e "${RED}Lựa chọn không hợp lệ, vui lòng chọn lại!${NC}"
            ;;
    esac
done
