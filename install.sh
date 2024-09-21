#!/bin/bash

# Colors
red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
purple='\033[0;35m'
cyan='\033[0;36m'
blue='\033[0;34m'
rest='\033[0m'

# If running in Termux, update and upgrade
if [ -d "$HOME/.termux" ] && [ -z "$(command -v jq)" ]; then
    echo "Running update & upgrade ..."
    pkg update -y
    pkg upgrade -y
fi

# Function to install necessary packages
install_packages() {
    local packages=(curl jq bc)
    local missing_packages=()

    # Check for missing packages
    for pkg in "${packages[@]}"; do
        if ! command -v "$pkg" &> /dev/null; then
            missing_packages+=("$pkg")
        fi
    done

    # If any package is missing, install missing packages
    if [ ${#missing_packages[@]} -gt 0 ]; then
        if [ -n "$(command -v pkg)" ]; then
            pkg install "${missing_packages[@]}" -y
        elif [ -n "$(command -v apt)" ]; then
            sudo apt update -y
            sudo apt install "${missing_packages[@]}" -y
        elif [ -n "$(command -v yum)" ]; then
            sudo yum update -y
            sudo yum install "${missing_packages[@]}" -y
        elif [ -n "$(command -v dnf)" ]; then
            sudo dnf update -y
            sudo dnf install "${missing_packages[@]}" -y
        else
            echo -e "${yellow}Unsupported package manager. Please install required packages manually.${rest}"
        fi
    fi
}

# Install the necessary packages
install_packages

# Clear the screen
clear

# Prompt for Authorization
echo -e "${purple}=======${yellow}Hamster Combat Auto Buy best cards${purple}=======${rest}"
echo ""
echo -en "${green}Enter Authorization [${cyan}Example: ${yellow}Bearer 171852....${green}]: ${rest}"
read -r Authorization
echo -e "${purple}============================${rest}"

# Prompt for minimum balance threshold
echo -en "${green}Enter minimum balance threshold (${yellow}the script will stop purchasing if the balance is below this amount${green}):${rest} "
read -r min_balance_threshold

# Function to define common headers
headers=(
    -H 'accept: application/json'
    -H 'accept-language: en-US,en;q=0.9'
    -H "authorization: $Authorization"
    -H 'cache-control: no-cache'
    -H 'content-type: application/json'
    -H 'origin: https://hamsterkombatgame.io'
    -H 'pragma: no-cache'
    -H 'referer: https://hamsterkombatgame.io/'
    -H 'sec-ch-ua: "Android";v="12", "Chromium";v="128", "Google Chrome";v="128"'
    -H 'sec-ch-ua-mobile: ?1'
    -H 'sec-ch-ua-platform: "Android"'
    -H 'sec-fetch-dest: empty'
    -H 'sec-fetch-mode: cors'
    -H 'sec-fetch-site: same-site'
    -H 'user-agent: Mozilla/5.0 (Linux; Android 12; Pixel 5) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Mobile Safari/537.36'
)

# Variables to keep track of total spent and total profit
total_spent=0
total_profit=0

# Function to purchase upgrade
purchase_upgrade() {
    upgrade_id="$1"
    timestamp=$(date +%s%3N)

    response=$(curl -s -X POST "${headers[@]}" \
        --data-raw "{\"upgradeId\": \"$upgrade_id\", \"timestamp\": $timestamp}" \
        https://api.hamsterkombatgame.io/interlude/buy-upgrade)

    echo "$response"
}

# Function to get the best upgrade item
get_best_item() {
    response=$(curl -s -X POST "${headers[@]}" https://api.hamsterkombatgame.io/interlude/upgrades-for-buy)
    echo "$response" | jq -r '
        .upgradesForBuy | 
        map(select(.isExpired == false and .isAvailable)) | 
        if any(.price == 0) then 
            map(select(.price == 0)) | .[0] 
        else 
            map(select(.profitPerHourDelta != 0 and .price > 0) | . + {profitToPrice: (.profitPerHour / .price)}) | 
            sort_by(-(.profitPerHourDelta / .price)) | 
            .[0] 
        end | 
        {id: .id, section: .section, price: .price, profitPerHourDelta: .profitPerHourDelta, cooldownSeconds: .cooldownSeconds}
    '
}

# Function to wait for cooldown period with countdown
wait_for_cooldown() {
    cooldown_seconds="$1"
    echo -e "${yellow}Upgrade is on cooldown. Waiting for ${cyan}$cooldown_seconds${yellow} seconds...${rest}"
    while [ $cooldown_seconds -gt 0 ]; do
        echo -ne "${cyan}$cooldown_seconds\033[0K\r"
        sleep 1
        ((cooldown_seconds--))
    done
}

# Main script logic
main() {
    while true; do
        # Get current balanceCoins
        current_balance=$(curl -s -X POST "${headers[@]}" https://api.hamsterkombatgame.io/interlude/sync | jq -r '.interludeUser.balanceDiamonds')   
        # Get the best item to buy
        best_item=$(get_best_item)
        best_item_id=$(echo "$best_item" | jq -r '.id')
        section=$(echo "$best_item" | jq -r '.section')
        price=$(echo "$best_item" | jq -r '.price')
        profit=$(echo "$best_item" | jq -r '.profitPerHourDelta')
        cooldown=$(echo "$best_item" | jq -r '.cooldownSeconds')

        echo -e "${purple}============================${rest}"
        echo -e "${blue}Current Balance: ${cyan}$current_balance${rest}"
        echo -e "${green}Best item to buy:${yellow} $best_item_id ${green}in section:${yellow} $section${rest}"
        echo -e "${blue}Price: ${cyan}$price${rest}"
        echo -e "${blue}Profit per Hour: ${cyan}$profit${rest}"
        echo ""

        # Check if current balance is above the threshold after purchase
        if (( $(echo "$current_balance - $price > $min_balance_threshold" | bc -l) )); then
            if [ -n "$best_item_id" ]; then
                if [ "$cooldown" -gt 0 ]; then
                    wait_for_cooldown "$cooldown"
                fi

                echo -e "${green}Attempting to purchase upgrade '${yellow}$best_item_id${green}'...${rest}"
                echo ""

                purchase_status=$(purchase_upgrade "$best_item_id")

                if echo "$purchase_status" | grep -q "error_code"; then
                    echo -e "${red}Error purchasing item. Retrying after cooldown...${rest}"
                    wait_for_cooldown "$cooldown"
                else
                    purchase_time=$(date +"%Y-%m-%d %H:%M:%S")
                    total_spent=$(echo "$total_spent + $price" | bc)
                    total_profit=$(echo "$total_profit + $profit" | bc)
                    current_balance=$(echo "$current_balance - $price" | bc)

                    echo -e "${green}Upgrade ${yellow}'$best_item_id'${green} purchased successfully at ${cyan}$purchase_time${green}.${rest}"
                    echo -e "${green}Total spent so far: ${cyan}$total_spent${green} coins.${rest}"
                    echo -e "${green}Total profit added: ${cyan}$total_profit${green} coins per hour.${rest}"
                    echo -e "${green}Current balance: ${cyan}$current_balance${green} coins.${rest}"
                    
                    sleep_duration=$((RANDOM % 8 + 5))
                    echo -e "${green}Waiting for ${yellow}$sleep_duration${green} seconds before next purchase...${rest}"
                    while [ $sleep_duration -gt 0 ]; do
                        echo -ne "${cyan}$sleep_duration\033[0K\r"
                        sleep 1
                        ((sleep_duration--))
                    done
                fi
            else
                echo -e "${red}No valid item found to buy.${rest}"
                break
            fi
        else
            echo -e "${red}Current balance ${cyan}(${current_balance}) ${red}minus price of item ${cyan}(${price}) ${red}is below the threshold ${cyan}(${min_balance_threshold})${red}. Stopping purchases.${rest}"
            break
        fi
    done
}

# Execute the main function
main