#!/system/bin/sh
MODDIR=${0%/*}

CONFIG_DIR="/data/adb/bloatwareslayer"

CONFIG_FILE="$CONFIG_DIR/settings.conf"
BRICKED_STATUS="$CONFIG_DIR/bricked"
EMPTY_DIR="$CONFIG_DIR/empty"
TARGET_LIST="$CONFIG_DIR/target.conf"
TARGET_LIST_BSA="$CONFIG_DIR/target_bsa.conf"
LOG_DIR="$CONFIG_DIR/logs"
LOG_FILE="$LOG_DIR/bs_log_core_$(date +"%Y-%m-%d_%H-%M-%S").log"

MODULE_PROP="${MODDIR}/module.prop"
MOD_NAME="$(sed -n 's/^name=\(.*\)/\1/p' "$MODULE_PROP")"
MOD_AUTHOR="$(sed -n 's/^author=\(.*\)/\1/p' "$MODULE_PROP")"
MOD_VER="$(sed -n 's/^version=\(.*\)/\1/p' "$MODULE_PROP") ($(sed -n 's/^versionCode=\(.*\)/\1/p' "$MODULE_PROP"))"

UPDATE_TARGET_LIST=true

BRICK_TIMEOUT=180
AUTO_UPDATE_TARGET_LIST=true
UPDATE_DESC_ON_ACTION=false
DISABLE_MODULE_AS_BRICK=true

SYSTEM_APP_PATHS="/system/app /system/product/app /system/product/priv-app /system/priv-app /system/system_ext/app /system/system_ext/priv-app /system/vendor/app /system/vendor/priv-app"

brick_rescue() {
    
    if [ -f "$BRICKED_STATUS" ]; then
        logowl "Detect flag bricked!" "FATAL"
        logowl "Skip service.sh process"
        DESCRIPTION="[❌Disabled. Auto disabled from brick! Root: $ROOT_SOL] A Magisk module to remove bloatware in systemlessly way 🎉✨"
        sed -i "/^description=/c\description=$DESCRIPTION" "$MODULE_PROP"
        logowl "Update module.prop"
        logowl "Skip mounting"
        rm -rf "$BRICKED_STATUS"
        if [ $? -eq 0 ]; then
            logowl "Bricked status cleared"
        else
            logowl "Failed to clear bricked status" "FATAL"
        fi
        if [ "$DISABLE_MODULE_AS_BRICK" == "true" ]; then
            logowl "Detect flag DISABLE_MODULE_AS_BRICK=true"
            logowl "Will disable $MOD_NAME automatically after reboot"
            touch "$MODDIR/disable"
        fi
        exit 1
    else
        logowl "Flag bricked does not detect"
        logowl "$MOD_NAME will keep going"
    fi
}

config_loader() {

    logowl "Start loading configuration"
    if [[ ! -f "$CONFIG_FILE" ]]; then
        logowl "Configuration file does not exist: $CONFIG_FILE" "ERROR"
        logowl "$MOD_NAME will use default values"
        return 1
    fi
    brick_timeout=$(init_variables "brick_timeout" "$CONFIG_FILE")
    disable_module_as_brick=$(init_variables "disable_module_as_brick" "$CONFIG_FILE")
    auto_update_target_list=$(init_variables "auto_update_target_list" "$CONFIG_FILE")
    update_desc_on_action=$(init_variables "update_desc_on_action" "$CONFIG_FILE")
    system_app_paths=$(init_variables "system_app_paths" "$CONFIG_FILE" "true")

    logowl "brick_timeout: $brick_timeout"
    logowl "disable_module_as_brick: $disable_module_as_brick"
    logowl "auto_update_target_list: $auto_update_target_list"
    logowl "update_desc_on_action: $update_desc_on_action"
    logowl "system_app_paths: ${system_app_paths:0:10}"

    verify_variables "brick_timeout" "$brick_timeout" "^[1-9][0-9]*$" "300"
    verify_variables "disable_module_as_brick" "$disable_module_as_brick" "^(true|false)$" "true"
    verify_variables "auto_update_target_list" "$auto_update_target_list" "^(true|false)$" "false"
    verify_variables "update_desc_on_action" "$update_desc_on_action" "^(true|false)$" "false"
    verify_variables "system_app_paths" "$system_app_paths" "" "/system/app /system/product/app /system/product/priv-app /system/priv-app /system/system_ext/app /system/system_ext/priv-app /system/vendor/app /system/vendor/priv-app"

}

preparation() {

    if [ -d "$EMPTY_DIR" ]; then
        logowl "Detect $EMPTY_DIR existed"
        rm -rf "$EMPTY_DIR"
    fi
    logowl "Create $EMPTY_DIR"
    mkdir -p "$EMPTY_DIR"
    chmod 755 "$EMPTY_DIR"

    if [ ! -f "$TARGET_LIST" ]; then
        logowl "Target list does not exist!" "FATAL"
        DESCRIPTION="[❌Disabled. Target list does not exist! Root: $ROOT_SOL] A Magisk module to remove bloatware in systemlessly way✨"
        update_module_description "$DESCRIPTION" "$MODULE_PROP"
        return 1
    fi

    if [ -f "$TARGET_LIST_BSA" ] && [ "$AUTO_UPDATE_TARGET_LIST" == "true" ]; then
        logowl "target list ($MOD_NAME Arranged) file existed"
        logowl "Detect flag AUTO_UPDATE_TARGET_LIST=true"
        if file_compare "$TARGET_LIST" "$TARGET_LIST_BSA"; then
            logowl "Files are identical, no changes detected"
            UPDATE_TARGET_LIST=false
        else
            logowl "Files are different, changes detected"
            UPDATE_TARGET_LIST=true
        fi
    fi

    if [ "$UPDATE_TARGET_LIST" == true ] && [ "$AUTO_UPDATE_TARGET_LIST" == "true" ]; then
        TARGET_LIST_BSA_HEADER="# $MOD_NAME $MOD_VER
# Generate timestamp: $(date +"%Y-%m-%d %H:%M:%S")
# This file is generated by $MOD_NAME automatically, only to save the paths of the found APP(s)
# This file will update target.conf automatically if don't want to tidy target.conf up manually"
    touch "$TARGET_LIST_BSA"
    echo -e "$TARGET_LIST_BSA_HEADER\n" > "$TARGET_LIST_BSA"
    fi

}

bloatware_slayer() {

    TOTAL_APPS_COUNT=0
    BLOCKED_APPS_COUNT=0
    logowl "Start $MOD_NAME process"
    while IFS= read -r line; do

        line=$(echo "$line" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
        logowl "Current line: $line"
        if [ -z "$line" ]; then
            logowl "Detect empty line, skip processing" "TIPS"
            continue
        elif [ "${line:0:1}" == "#" ]; then
            logowl 'Detect comment symbol "#", skip processing' "TIPS"
            continue
        fi

        package=$(echo "$line" | cut -d '#' -f1)
        package=$(echo "$package" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')

        if [ -z "$package" ]; then
            logowl "Detect only comment contains in this line only, skip processing" "TIPS"
            continue
        fi
        if [[ "$package" =~ \\ ]]; then
            logowl "Replace '\\' with '/' in path: $package" "WARN"
            package=$(echo "$package" | sed -e 's/\\/\//g')
        fi
        logowl "Current processed line: $package"

        TOTAL_APPS_COUNT=$((TOTAL_APPS_COUNT+1))
        for path in $SYSTEM_APP_PATHS; do
            if [[ "${package:0:1}" == "/" ]]; then
                app_path="$package"
                logowl "Detect custom dir: $app_path"
                if [[ ! "$app_path" =~ ^/system ]]; then
                    logowl "Unsupport custom path: $app_path" "WARN"
                    break
                fi
            else
                app_path="$path/$package"
            fi
            logowl "Checking dir: $app_path"
            if [ -d "$app_path" ]; then
                logowl "Execute mount -o bind $EMPTY_DIR $app_path"
                mount -o bind "$EMPTY_DIR" "$app_path"
                if [ $? -eq 0 ]; then
                    logowl "Succeeded"
                    BLOCKED_APPS_COUNT=$((BLOCKED_APPS_COUNT + 1))
                    if [ "$UPDATE_TARGET_LIST" == true ] && [ "$AUTO_UPDATE_TARGET_LIST" == "true" ]; then
                        echo "$app_path" >> "$TARGET_LIST_BSA"
                    fi
                    break
                else
                    logowl "Failed to mount: $app_path, error code: $?" "ERROR"
                fi
            else
                if [[ "${package:0:1}" == "/" ]]; then
                    logowl "Custom dir not found: $app_path" "WARN"
                    break
                else
                    logowl "Dir not found: $app_path" "WARN"
                fi
            fi
        done
    done < "$TARGET_LIST"

    if [ "$UPDATE_TARGET_LIST" == true ] && [ "$AUTO_UPDATE_TARGET_LIST" == "true" ]; then
        logowl "Update target list" "TIPS"
        cp -p "$TARGET_LIST_BSA" "$TARGET_LIST"
        chmod 0644 "$TARGET_LIST_BSA"
        chmod 0644 "$TARGET_LIST"
    fi

}

module_status_update() {

    APP_NOT_FOUND=$((TOTAL_APPS_COUNT - BLOCKED_APPS_COUNT))
    logowl "$TOTAL_APPS_COUNT APP(s) in total"
    logowl "$BLOCKED_APPS_COUNT APP(s) slain"
    logowl "$APP_NOT_FOUND APP(s) not found"

    if [ -f "$MODULE_PROP" ]; then
        if [ $BLOCKED_APPS_COUNT -gt 0 ]; then
            DESCRIPTION="[😋Enabled. $BLOCKED_APPS_COUNT APP(s) slain, $APP_NOT_FOUND APP(s) missing, $TOTAL_APPS_COUNT APP(s) targeted in total, Root: $ROOT_SOL] 勝った、勝った、また勝ったぁーっと！！🎉"
            if [ $APP_NOT_FOUND -eq 0 ]; then
            DESCRIPTION="[😋Enabled. $BLOCKED_APPS_COUNT APP(s) slain. All targets neutralized! Root: $ROOT_SOL] 勝った、勝った、また勝ったぁーっと！！🎉"
            fi
        else
            if [ $TOTAL_APPS_COUNT -gt 0]; then
                DESCRIPTION="[😋Enabled. No APP slain yet, $TOTAL_APPS_COUNT APP(s) targeted in total, Root: $ROOT_SOL] 勝った、勝った、また勝ったぁーっと！！🎉"
            else
                logowl "! Current blocked apps count: $TOTAL_APPS_COUNT <= 0"
                DESCRIPTION="[❌Disabled. Abnormal status! Root: $ROOT_SOL] A Magisk module to remove bloatware in systemlessly way✨"
            fi
        fi
        update_module_description "$DESCRIPTION" "$MODULE_PROP"
    else
        logowl "module.prop not found, skip updating" "WARN"
    fi

}

. "$MODDIR/aautilities.sh"
install_env_check
module_intro >> "$LOG_FILE" 
logowl "Starting service.sh"
init_logowl "$LOG_DIR"
config_loader
print_line >> "$LOG_FILE"
brick_rescue
preparation
logowl "Variables before processing"
debug_print_values >> "$LOG_FILE"
bloatware_slayer
module_status_update
logowl "Variables before case closed"
debug_print_values >> "$LOG_FILE"

{    

    logowl "Current booting timeout: $BRICK_TIMEOUT"
    while [ "$(getprop sys.boot_completed)" != "1" ]; do
        if [ $BRICK_TIMEOUT -le "0" ]; then
            print_line >> "$LOG_FILE"
            logowl "Detect failed to boot after reaching the set limit, your device may be bricked by !" "FATAL"
            logowl "Please make sure no improper APP(s) being blocked!" "FATAL"
            logowl "Mark status as bricked"
            touch "$BRICKED_STATUS"
            logowl "Rebooting"
            sync
            reboot -f
            sleep 5
            logowl "Reboot command did not take effect, exiting"
            exit 1
        fi
        BRICK_TIMEOUT=$((BRICK_TIMEOUT-1))
        sleep 1
    done

    logowl "Boot complete! Final countdown: $BRICK_TIMEOUT s"
    logowl "service.sh case closed!"
    print_line >> "$LOG_FILE"

    MOD_DESC_OLD=$(sed -n 's/^description=//p' "$MODULE_PROP")
    MOD_LAST_STATUS=""
    MOD_CURRENT_STATUS=""
    MOD_REAL_TIME_DESC=""
    while true; do
        if [ "$UPDATE_DESC_ON_ACTION" == "false" ]; then
            logowl "Detect flag UPDATE_DESC_ON_ACTION=false"
            logowl "Exiting the background task"
            exit 0
        fi
        if [ -f "$MODDIR/remove" ]; then
            MOD_CURRENT_STATUS="remove"
        elif [ -f "$MODDIR/disable" ]; then
            MOD_CURRENT_STATUS="disable"
        else
            MOD_CURRENT_STATUS="enabled"
        fi
        if [ "$MOD_CURRENT_STATUS" != "$MOD_LAST_STATUS" ]; then
            logowl "Detect status changed:$MOD_LAST_STATUS -> $MOD_CURRENT_STATUS"
            if [ "$MOD_CURRENT_STATUS" == "remove" ]; then
                logowl "Detect module is set as remove"
                MOD_REAL_TIME_DESC="[🗑️Remove (Reboot to take effect), Root: $ROOT_SOL] A Magisk module to remove bloatware in systemlessly way✨"
            elif [ "$MOD_CURRENT_STATUS" == "disable" ]; then
                logowl "Detect module is set as disable"
                MOD_REAL_TIME_DESC="[❌Disable (Reboot to take effect), Root: $ROOT_SOL] A Magisk module to remove bloatware in systemlessly way✨"
            else
                logowl "Detect module is set as enabled"
                MOD_REAL_TIME_DESC="$MOD_DESC_OLD"
            fi
            update_module_description "$MOD_REAL_TIME_DESC" "$MODULE_PROP"
            MOD_LAST_STATUS="$MOD_CURRENT_STATUS"
        fi
        sleep 3
    done
} &
