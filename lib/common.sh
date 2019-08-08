#!/bin/sh

export AT_RESP=/tmp/at_resp
export LE_RESP=/tmp/le_resp

# if TARGET_SSH_PORT is defined add the port option to ssh
TARGET_SSH_PORT=${TARGET_SSH_PORT:-22}
TARGET_SSH_OPTS="-p $TARGET_SSH_PORT"

# maximum connection timeout for both ssh and scp; 10 seconds
CONNECTION_TIMEOUT=10


#=== FUNCTION =============================================================================
#
#        NAME: prompt_char
# DESCRIPTION: Prompt a messgae to console.
# PARAMETER 1: message
#
#==========================================================================================
prompt_char() {
    run_time=$(date +"%Y-%m-%d-%H:%M:%S:")
    echo $run_time $1 >&2
    read prompt_input
    echo $(echo $prompt_input | tr 'a-z' 'A-Z')
}


#=== FUNCTION =============================================================================
#
#        NAME: SshToTarget
# DESCRIPTION: Execute commands on selected target.
# PARAMETER 1: SSH command
#
#==========================================================================================
SshToTarget()
{
    if [ -z "$TARGET_IP" ]
    then
        echo "SshToTarget called before SetTargetIP"
        exit 1
    fi

    ssh -o ConnectTimeout=$CONNECTION_TIMEOUT $TARGET_SSH_OPTS root@$TARGET_IP "$@"
}


#=== FUNCTION =============================================================================
#
#        NAME: ScpToTarget
# DESCRIPTION: Transfer a file or dir to target
# PARAMETER 1: Path of a file or dir to transfer on the host
#           2: Path of where the file should be transfered on the target
#
#   RETURNS 0: True
#           1: False
#
#==========================================================================================
ScpToTarget()
{
    FROM=$1
    TO=$2

    if [ -z "$TARGET_IP" ]
    then
        echo "ScpToTarget called before SetTargetIP"
        exit 1
    fi

    unset SCP_DIR_ARG
    if [ -d "$FROM" ]; then
        SCP_DIR_ARG="-r"
    fi

    scp -o ConnectTimeout=$CONNECTION_TIMEOUT -P $TARGET_SSH_PORT $SCP_DIR_ARG $FROM root@$TARGET_IP:$TO
}


#=== FUNCTION =============================================================================
#
#        NAME: ScpFromTarget
# DESCRIPTION: Transfer a file from selected target
# PARAMETER 1: Path of a file to transfer on the target
#           2: Path of where the file should be transfered on the host
#
#   RETURNS 0: True
#           1: False
#
#==========================================================================================
ScpFromTarget()
{
    FROM=$1
    TO=$2

    if [ -z "$TARGET_IP" ]
    then
        echo "SshFromTarget called before SetTargetIP"
        exit 1
    fi

    scp -o ConnectTimeout=$CONNECTION_TIMEOUT -P $TARGET_SSH_PORT root@$TARGET_IP:$FROM $TO
}

# http://stackoverflow.com/questions/7662465/bash-is-there-a-simple-way-to-check-whether-a-string-is-a-valid-sha-1-or-md5
#=== FUNCTION =============================================================================
#
#        NAME: IsMd5
# DESCRIPTION: Checks if version string is md5
# PARAMETER 1: Version string
#
#   RETURNS 0: True
#           1: False
#
#==========================================================================================
IsMd5()
{
    if [[ "$1" =~ [a-f0-9]{32} ]]
    then
        return 0
    else
        return 1
    fi
}

#=== FUNCTION =============================================================================
#
#        NAME: AppExist
# DESCRIPTION: Checks if app exists.
# PARAMETER 1: App name
#           2: App version
#
#   RETURNS 0: True
#           1: False
#
#==========================================================================================
AppExist()
{
    if [ -z "$1" ]
    then
        echo "App name missing. e.g. AppExist [app]"
        return 1
    fi

    for app in $(SshToTarget "/legato/systems/current/bin/app list")
    do
        if [ "$app" == "$1" ]
        then
            # Check app version if not empty and is not the default hash assigned to version if no version is specified
            if [ -n "$2" ]
            then
                # There are cases where the version specified is the md5 because any app with no version is given their md5
                # in their manifest. If this is the case, we just want to check if the app has no version.
                if IsMd5 "$2"
                then
                    ACTUAL_VERSION="$1 has no version"
                else
                    ACTUAL_VERSION="$1 $2"
                fi

                APP_VERSION=$(SshToTarget "/legato/systems/current/bin/app version $1")
                if [[ "$APP_VERSION" == "$ACTUAL_VERSION" ]]
                then
                    return 0
                fi
            else
                return 0
            fi
        fi
    done

    return 1
}

#=== FUNCTION =============================================================================
#
#        NAME: AppRemove
# DESCRIPTION: Remove specified app
# PARAMETER 1: App name
#
#     RETURNS: Removall status
#
#==========================================================================================
AppRemove()
{
    if [ -z "$1" ]
    then
        echo "App name missing. e.g. AppRemove [app]"
        return 1
    fi

    SshToTarget "/legato/systems/current/bin/app remove $1"
    return $?
}


#=== FUNCTION =============================================================================
#
#        NAME: AppCount
# DESCRIPTION: Returns the number of apps installed.
#
#==========================================================================================
AppCount()
{
    count=0
    for app in $(SshToTarget "/legato/systems/current/bin/app list")
    do
        ((count++))
    done

    echo $count
}


#=== FUNCTION =============================================================================
#
#        NAME: GetAppStatus
# DESCRIPTION: Returns the status of app.
# PARAMETER 1: App name
#
#   RETURNS:   App status
#
#==========================================================================================
GetAppStatus()
{
    case $(SshToTarget /legato/systems/current/bin/app "status" "$1") in

    *installed*)
        appStatus='not_installed'
        ;;
    *stopped*)
        appStatus='stopped'
        ;;
    *running*)
        appStatus='running'
        ;;
    *)
        appStatus='unknown'
        ;;
    esac

    echo $appStatus
}


#=== FUNCTION =============================================================================
#
#        NAME: IsAppRunning
# DESCRIPTION: Checks if app is running
# PARAMETER 1: App name
#
#   RETURNS 0: App is running
#           1: App is not running
#==========================================================================================
IsAppRunning()
{
    if AppExist "$1"
    then
        if [ "$(GetAppStatus $1)" != "running" ]
        then
            return 1
        fi
    else
        return 1
    fi

    return 0
}


#=== FUNCTION =============================================================================
#
#        NAME: MakeInstall
# DESCRIPTION: Make and install an app.
# PARAMETER 1: Path to the application definition file.
#
#   RETURNS 0: Success
#           1: Failure
#
#==========================================================================================
MakeInstall()
{
    local fullPath=$(dirname $(readlink -f $1))
    local fileName=$(basename $1)
    local appName=${fileName%.*}
    local buildDir="__mkapp_build_artifact_delete_me"
    if [ "$ENABLE_IMA" == "1" ]; then
        sign=".signed"
    else
        sign=""
    fi

    local serviceNames=(
        audio
        cellNetService
        dataConnectionService
        modemServices
        positioning
        voiceCallService
        powerMgr
        airVantage
        secureStorage
    )

    interfaceSearchPath=""

    # Construct the interface search path for mkapp
    for service in ${serviceNames[@]}
    do
        if [ -z interfaceSearchPath ]
        then
            interfaceSearchPath="-i ${LEGATO_ROOT}/interfaces/${service}"
        else
            interfaceSearchPath="${interfaceSearchPath} -i ${LEGATO_ROOT}/interfaces/${service}"
        fi
    done

    interfaceSearchPath="${interfaceSearchPath} -i ${LEGATO_ROOT}/build/${TARGET_TYPE}/airvantage/runtime/itf"
    ## For ECallDemo, to be compiled correclty with mkapp
    if [ $appName == "eCallDemo" ] ; then
        interfaceSearchPath="${interfaceSearchPath} -i ${LEGATO_ROOT}/apps/sample/eCallDemo/eCallAppComponent"
    fi
    mkdir -p "$fullPath/$buildDir"

    mkappCmd="mkapp $fullPath/$fileName -t $TARGET_TYPE $interfaceSearchPath -o $fullPath -w $fullPath/$buildDir"
    $mkappCmd >/dev/null 2>&1

    if [ $? -ne 0 ]
    then
        echo "Error in building the app ${appName}. Running mkapp again to show the errors."
        echo "mkapp command is: [$mkappCmd]"
        $mkappCmd 2>&1
        return 1
    fi

    app install "$fullPath/$appName.$TARGET_TYPE$sign.update" "$TARGET_IP"

    if [ $? -ne 0 ]
    then
        echo "Error in installing the ${appName}."
        # clean up build artifacts (manifest is temp) before return 1(false) when the app
        # was successfully built and failed to install
        rm -rf "$fullPath/$buildDir" "$fullPath"/*.${TARGET_TYPE}.update "$fullPath"/*.app
        return 1
    fi

    # clean up build artifacts (manifest is temp)
    rm -rf "$fullPath/$buildDir" "$fullPath"/*.${TARGET_TYPE}.update "$fullPath"/*.app

    return $?
}


#=== FUNCTION =============================================================================
#
#        NAME: ClearAppData
# DESCRIPTION: Clears the data of an application
# PARAMETER 1: App name
#
#==========================================================================================
ClearAppData()
{
    SshToTarget "/legato/systems/current/bin/config delete $1:/"
}

#=== FUNCTION =============================================================================
#
#        NAME: RestartApp
# DESCRIPTION: Restart an app.
# PARAMETER 1: App name
#
#   RETURNS 0: Success
#           1: Failure
#
#==========================================================================================
RestartApp()
{
    echo -e "\033[1mrestart app $1\033[0m"
    SshToTarget "/legato/systems/current/bin/app restart $1"
    return $?
}

#=== FUNCTION =============================================================================
#
#        NAME: StartApp
# DESCRIPTION: Start an app.
# PARAMETER 1: App name
#
#   RETURNS 0: Success
#           1: Failure
#
#==========================================================================================
StartApp()
{
    echo -e "\033[1mstart app $1\033[0m"
    SshToTarget "/legato/systems/current/bin/app start $1"
    return $?
}

#=== FUNCTION =============================================================================
#
#        NAME: StopApp
# DESCRIPTION: Stop an app.
# PARAMETER 1: App name
#
#   RETURNS 0: Success
#           1: Failure
#
#==========================================================================================
StopApp()
{
    echo -e "\033[1mstop app $1\033[0m"
    SshToTarget "/legato/systems/current/bin/app stop $1"
    return $?
}

#=== FUNCTION =============================================================================
#
#        NAME: BringUpNetworkInterface
# DESCRIPTION: Bring up network interface
#
#   RETURNS 0: Success
#           1: Failure
#
#==========================================================================================
BringUpNetworkInterface()
{
    echo "TARGET_TYPE: $TARGET_TYPE"

    case $TARGET_TYPE in
    ar75[8-9]x | wp750x | wp76xx | wp85)
            if [ -z "$TARGET_UART" ]; then
                echo "TARGET_UART is not set."
                return 0
            fi

            if [ -z "$QA_ROOT" ]; then
                export QA_ROOT=$(readlink -f $LEGATO_ROOT/../qa)
            fi

            #Boot time
            sleep 20

            python $QA_ROOT/manual/dualSystem/Init_Device -p $TARGET_UART -t $TARGET_TYPE -d eth0 -i dhcp -n
            pythonRet=$?

            # update $TARGET_IP
            if [ -f $QA_ROOT/../.target_ip ]
            then
                TARGET_IP=$(cat $QA_ROOT/../.target_ip)
                echo "TARGET_IP: $TARGET_IP"
            fi

            return $pythonRet
            ;;
    *)
            #nothing to do
            return 0
            ;;
    esac
}

#=== FUNCTION =============================================================================
#
#        NAME: WaitForDevice
# DESCRIPTION: Wait for the target until it's up or down, or when a timeout is reached.
# PARAMETER 1: "Up" / "Down"
#           2: Try for t seconds. If none specified, defaults to 300secs
#
#   RETURNS 0: Success
#           1: Failure
#
#==========================================================================================
WaitForDevice()
{
    if [ $1 == "Up" ]; then
        local posReachMod=""
        local negReachMod="NOT"
        local resExpected="1"  # the expected return status of nc before target is up
    elif [ $1 == "Down" ]; then
        local posReachMod="NOT"
        local negReachMod=""
        local resExpected="0"
    else
        echo "Invalid param. Param 1 should be either Up or Down."
        return 1
    fi

    if [ $2 ]; then
        local timeout=$2
    else
        local timeout=300
    fi


    local res=$resExpected
    local count=0
    echo -n "Checking [$TARGET_IP] and proceed until it's $posReachMod reachable"
    while [ $res -eq $resExpected ] && [ $count -lt $timeout ]; do
        nc -z -w 2 $TARGET_IP $TARGET_SSH_PORT > /dev/null
        res=$?
        echo -n "."
        # MUST have sleep otherwise the while loop cannot be broken out with Ctrl-C if the target is unreachable
        sleep 1
        count=$(( count + 1 ))
    done
    echo


    if [ $count -eq $timeout ]; then
        echo "Target is $negReachMod reachable for [$timeout] secs."
        return 1
    else
        echo "Target is $posReachMod reachable before timeout."
        return 0
    fi
}

#=== FUNCTION =============================================================================
#
#        NAME: WaitForAntennaStatus
# DESCRIPTION: Wait for action with antenna
# PARAMETER 1: expected CONNECTED or DISCONNECTED
#
#   RETURNS 0: Success
#           1: Failure
#
#==========================================================================================
WaitForAntennaStatus()
{
    local waitTime=100
    local timePast=0
    local expectedRadio="unknown"
    local networkStatus=-1

    if [ "$1" = "CONNECTED" ]
    then
        expectedRadio="Status:                Registered"
        echo -e "\033[33mCONNECT THE ANTENNA and wait the notification \033[0m"
    elif [ "$1" = "DISCONNECTED" ]
    then
        expectedRadio="Status:                Not registered"
        echo -e "\033[33mDISCONNECT THE ANTENNA and wait the notification \033[0m"
    else
       exit
    fi

    while [ $timePast -ne $waitTime ]; do
		networkStatus=$(echo "$(GetCurrentRadioStatus)" | grep -o -c "$expectedRadio")

		if [[ ${networkStatus} -gt 0 ]]
		then
            if [ expectedRadio = "Status:                Registered" ]
            then
                echo "<antenna connected>"
            else
                echo "<antenna disconnected>"
            fi
            return 0
        fi

        timePast=$((timePast+1))
        sleep 5
    done

    return 1
}

#=== FUNCTION =============================================================================
#
#        NAME: WaitForSystemToStart
# DESCRIPTION: Wait for the newly installed system to be "online"
# PARAMETER 1: expected new system index
#
#   RETURNS 0: Success
#           1: Failure
#
#==========================================================================================
WaitForSystemToStart()
{
    local waitTime=100
    local timePast=0

    while [ $timePast -ne $waitTime ]; do
        if [ "$(GetCurrentSystemIndex)" == "$1" ]; then
            return 0
        fi

        timePast=$((timePast+1))
        sleep 1
    done

    return 1
}


#=== FUNCTION =============================================================================
#
#        NAME: FetchBinary
# DESCRIPTION: Fetches file from a server into a specified output directory.
# PARAMETER 1: URL of the file
#           2: Local file output location
#
#   RETURNS 0: Success
#           1: Failure
#
#==========================================================================================
FetchBinary()
{
    local fileLocation=$1
    local fileOutput=$2

    mkdir -p $fileLocation
    echo "wget -q -N -P $fileOutput $fileLocation"
    wget -q -N -P $fileOutput $fileLocation

    return $?
}


#=== FUNCTION =============================================================================
#
#        NAME: RunATCommand
# DESCRIPTION: Runs an AT command
# PARAMETER 1: AT command
#
#   RETURNS:   AT command response
#
#==========================================================================================
RunATCommand()
{
    SshToTarget "/bin/echo -e \"$1\r\n\" | /usr/bin/microcom -d 10 -t 1000 /dev/ttyAT"
}


#=== FUNCTION =============================================================================
#
#        NAME: RunAndWaitATCommand
# DESCRIPTION: Runs an AT command and waits 20 seconds for response
# PARAMETER 1: AT command
# PARAMETER 2: Wait time
#
#RETURNS:   AT command response
#
#==========================================================================================
RunAndWaitATCommand()
{
    SshToTarget "/bin/echo -e \"$1\r\n\" | /usr/bin/microcom -d 10 -t \"$2\" /dev/ttyAT"
}
#=== FUNCTION =============================================================================
#
#        NAME: RunAndCheckAT
# DESCRIPTION: Runs an AT command and compares its response to parameters 2 or 3
#              If response(s) match(es) flag gets set to 0 and to 1 if they don't match
# PARAMETER 1: AT command
# PARAMETER 2: Wait time in seconds
# PARAMETER 3: First AT response to compare to
# PARAMETER 4: Second AT response to compare to
# PARAMETER 5: Third AT response to compare to
#
#==========================================================================================
RunAndCheckAT()
{
    w=$(($2 * 1000))
    RunAndWaitATCommand "$1" "$w"  > $AT_RESP
    if grep -q "ERROR" $AT_RESP && [[ "$1" != "at+wdss=1,0" ]] && [[ "$1" != "at+wdss=1,1" ]] ; then
        flag="1"
        echo "AT command returned ERROR"
        return $flag
    elif [[ "$#" -gt "2" ]] ; then
        if ! grep -q "$3" $AT_RESP || ! grep -q "$4" $AT_RESP || ! grep -q "$5" $AT_RESP ; then
            flag="1"
        else
            flag="0"
        fi
    fi
    return $flag
}
#=== FUNCTION =============================================================================
#
#        NAME: EchoPassOrFail
# DESCRIPTION: Echos [PASS] or [FAIL] with colour
#
# PARAMETER 1: p or f
#==========================================================================================
EchoPassOrFail()
{
    if [[ "$1" == p ]] ; then
        echo -e "\033[1m[PASSED]\033[0m"
    else
        echo -e "\033[1m[FAILED]\033[0m"
    fi
}
#=== AT FUNCTION ===========================================================================
#
#        NAME: GetMdmBootLoaderInfo
# DESCRIPTION: Gets modem bootloader info from at!bcinf
#
#   RETURNS:   Modem bootloader info (Addr, Ver, Date, Size and CRC)
#
#==========================================================================================
GetMdmBootLoaderVer()
{
    RunATCommand 'at!bcinf' > $AT_RESP
    echo "$(/bin/grep -A 5 "SBL2" "$AT_RESP")" > $AT_RESP
    SBL2_INFO=$(/bin/grep -o 'Ver: [^,}]*' "$AT_RESP" | /bin/sed 's/^.*: //')
    echo "$SBL2_INFO"
}


#=== AT FUNCTION ===========================================================================
#
#        NAME: GetSerialNumber
# DESCRIPTION: Gets the serial number returned from ATI
#
#   RETURNS:   Serial number
#
#==========================================================================================
GetSerialNumber()
{
    RunATCommand "ati" > $AT_RESP
    SERIAL_NUMBER=$(/bin/grep -o 'FSN: [^,}]*' "$AT_RESP" | /bin/sed 's/^.*: //')
    echo "$SERIAL_NUMBER" | cut -c1-14
}


#=== FUNCTION =============================================================================
#
#        NAME: CheckDeviceFirmware
# DESCRIPTION: Verifies if device firmware information is correct.
# PARAMETER 1: Firmware version (formatting SWI9X15A_${VERSION} where VERSION is the expected firmware version)
#           2: Bootloader version (formatting SWI9X15A_${VERSION} where VERSION is the expected bootloader version)
#           3: Linux version
#
#   RETURNS 0: Success
#           1: Failure
#
#==========================================================================================
CheckDeviceFirmware()
{
    exitCode=0

    # if modem services are available, we can use 'fwupdate query'; otherwise use AT commands.
    if IsAppRunning "audioService" && IsAppRunning "modemService" && IsAppRunning "fwupdateService" && IsAppRunning "cellNetService"
    then
        QUERY_VALUE=$(fwupdate query $TARGET_IP)
        if [ -z "$QUERY_VALUE" ]
        then
            return 1
        fi

        # Check firmware version if not empty
        if [ -n "$1" ]
        then
            if [[ $QUERY_VALUE != *"Firmware Version: ${1}"* ]]
            then
                echo "Mismatch firmware version [expected: $1]."
                exitCode=1
            fi
        fi

        # Check bootloader version if not empty
        if [ -n "$2" ]
        then
            if [[ $QUERY_VALUE != *"Bootloader Version: ${2}"* ]]
            then
                echo "Mismatch bootloader version [expected: $2]."
                exitCode=1
            fi
        fi

        # Check Linux version if not empty
        if [ -n "$3" ]
        then
            if [[ $QUERY_VALUE != *"Linux Version: ${3}"* ]]
            then
                echo "Mismatch linux version [expected: $3]."
                exitCode=1
            fi
        fi
    else
        echo "Fallback to AT commands"
        FW_VALUE=$(RunATCommand "ati")
        BL_VALUE=$(GetMdmBootLoaderVer)
        LINUX_VALUE=$(SshToTarget "/bin/uname -a")
        if [ -z "$FW_VALUE" ] || [ -z "$LINUX_VALUE" ]
        then
            return 1
        fi

        # Check firmware version if not empty
        if [ -n "$1" ]
        then
            if [[ "$FW_VALUE" != *"Revision: ${1}"* ]]
            then
                echo "Mismatch firmware version [expected: $1]."
                echo "$FW_VALUE"
                exitCode=1
            fi
        fi

        # Check bootloader version if not empty
        if [ -n "$2" ]
        then
            if [[ "$BL_VALUE" != *"${2}"* ]]
            then
                echo "Mismatch bootloader version [expected: $2]."
                echo "$BL_VALUE"
                exitCode=1
            fi
        fi

        # Check Linux version if not empty
        if [ -n "$3" ]
        then
            if [[ "$LINUX_VALUE" != *"${3}"* ]]
            then
                echo "Mismatch linux version [expected: $3]."
                echo "$LINUX_VALUE"
                exitCode=1
            fi
        fi
    fi

    return $exitCode
}


#=== FUNCTION =============================================================================
#
#        NAME: CheckLegatoVersion
# DESCRIPTION: Verifies if legato version is correct.
# PARAMETER 1: Legato version
#
#   RETURNS 0: Success
#           1: Failure
#
#==========================================================================================
CheckLegatoVersion()
{
    QUERY_VALUE=$(SshToTarget "/legato/systems/current/bin/legato version")

    # Check legato version if not empty
    if [ -n "$1" ]
    then
        echo "Legato version expected: $1"
        if [ "$QUERY_VALUE" != "$1" ]
        then
            echo "Mismatch legato version."
            echo $QUERY_VALUE
            return 1
        fi
    fi

    return 0
}

#=== FUNCTION =============================================================================
#
#        NAME: ClearTargetLog
# DESCRIPTION: Clears the target's log by creating a script on target and running it
#
#   RETURNS 0: Success
#           1: Failure
#
#==========================================================================================
ClearTargetLog()
{
    # Use init.d script to restart log server - seen with Christophe G. replace restart by stop/start because of random restart issue
    SshToTarget "PATH=/legato/systems/current/bin:/usr/local/bin:/usr/bin:/bin:/usr/local/sbin:/usr/sbin:/sbin /etc/init.d/syslog stop"
    SshToTarget "PATH=/legato/systems/current/bin:/usr/local/bin:/usr/bin:/bin:/usr/local/sbin:/usr/sbin:/sbin /etc/init.d/syslog start"

    return $?
}

#=== FUNCTION =============================================================================
#
#        NAME: GetTargetLog
# DESCRIPTION: Gets the targets log and prints it to the standard output
#
#   RETURNS 0: Success
#           1: Failure
#
#==========================================================================================
GetTargetLog()
{
    SshToTarget "/sbin/logread"
    return $?
}

#=== FUNCTION =============================================================================
#
#        NAME: findInTargetLog
# DESCRIPTION: Searches the target's log for the specified string
# PARAMETER 1: String to find
# PARAMETER 2: String to exclude <optional>
#
#   RETURNS 0: Success
#           1: Failure
#
#==========================================================================================
FindInTargetLog()
{
    if [ -z "$2" ]
    then
        GetTargetLog | grep -q "$1"
        return $?
    else
        GetTargetLog | grep -w "$1" | grep -v "$2" > /dev/null
        return $?
    fi
}

#=== FUNCTION =============================================================================
#
#        NAME: FindInTargetLogWait
# DESCRIPTION: Incremental wait from the logs
# PARAMETER 1: String to be found
#
#   RETURNS 0: True
#           1: False
#
#==========================================================================================
FindInTargetLogWait()
{
    FindInTargetLog "$1"
    findRetVal=$?
    findCount=0
    while [ "$findCount" -lt 20 ] && [ $findRetVal -ne 0 ]
    do
        sleep 10
        FindInTargetLog "$1"
        findRetVal=$?
        ((findCount=findCount+1))
    done
    return $findRetVal
}

#=== FUNCTION =============================================================================
#
#        NAME: FetchQueryStringFromTargetLog
# DESCRIPTION: Searches the target's log for the specified string
# PARAMETER 1: String to find
# PARAMETER 2: String to exclude <optional>
#
#   RETURNS : echo Matched String
#
#==========================================================================================
FetchQueryStringFromTargetLog()
{
    if [ -z "$2" ]
    then
        resultString=$(GetTargetLog | grep -w "$1")
        echo $resultString
    else
        resultString=$(GetTargetLog | grep -w "$1" | grep -v "$2")
        echo $resultString
    fi
}

#=== FUNCTION =============================================================================
#
#        NAME: CheckForErrorMessages
# DESCRIPTION: Searches the target's log for the specified error messages
#
#   RETURNS 0: Success
#           1: Failure
#
#==========================================================================================
CheckForErrorMessages()
{
    errors=("user.emerg Legato:" "user.crit Legato:" "user.err Legato:")
    excluded="avcDaemon" #avcDaemon generate many error exclude thos for now
    for j in "${errors[@]}"
        do
            FindInTargetLog "$j" "$excluded"
            if [ $? -eq 0 ]
                then
                    FetchQueryStringFromTargetLog "$j" "$excluded"
                    echo "[FAILED] Found error messages in log"
            fi
    done
    return $?
}

#=== FUNCTION =============================================================================
#
#        NAME: WaitForTargetReboot
# DESCRIPTION: Wait for target to reboot
# PARAMETER 1: Time to wait for target to go down and up <optional>
#
#   RETURNS 0: Success
#           1: Failure
#
#==========================================================================================
WaitForTargetReboot()
{
    local rbTimer=120

    if [ ! -z "$1" ]
    then
        rbTimer=$1
    fi

    WaitForDevice "Down" "$rbTimer"
    if [ $? -ne 0 ]
    then
        return 1
    fi

    BringUpNetworkInterface
    if [ $? -ne 0 ]
    then
        return 1
    fi

    WaitForDevice "Up" "$rbTimer"
    if [ $? -ne 0 ]
    then
        return 1
    fi

    # give time for legato to start properly
    sleep 5

    return 0
}


#=== FUNCTION =============================================================================
#
#        NAME: RebootTarget
# DESCRIPTION: Reboots the target
#
#   RETURNS 0: Success
#           1: Failure
#
#==========================================================================================
RebootTarget()
{
    echo -e "\033[33mReboot the target, be sure that UART is released ... \033[0m"
    SshToTarget "/sbin/reboot"

    if ! WaitForTargetReboot
    then
        return 1
    fi

    return 0
}


#=== FUNCTION =============================================================================
#
#        NAME: ModifyReadOnlyBin
# DESCRIPTION: Modify binary files from system. If bin files are symlinks to mtd3, we will
#              install a new system in mtd4 and then modify the bin.
#
#==========================================================================================
ModifyReadOnlyBin()
{
    # If the current install-hook is a symlink, it can't be overriden (read-only).
    # Install new temporary system and modify install-hook.
    local bin_path="/legato/systems/current/bin"
    if SshToTarget "[ -L $bin_path ]"
    then
        cd $LEGATO_ROOT
        make $TARGET_TYPE
        local currentSystemIndex=$(GetCurrentSystemIndex)
        app install $LEGATO_ROOT/build/$TARGET_TYPE/system.$TARGET_TYPE.update $TARGET_IP
        cd -

        # wait for the newly installed system to start up
        if ! WaitForSystemToStart "$((currentSystemIndex+1))"; then
            echo "Newly installed system of index $currentSystemIndex can't be started properly"
        fi
    fi

    ScpToTarget "$1" "$bin_path/$2"
}


#=== FUNCTION =============================================================================
#
#        NAME: FullLegatoRestart
# DESCRIPTION: A full legato restart is slightly different from a 'legato restart'.
#              It increments the tried count and also restarts the start program.
#
#==========================================================================================
FullLegatoRestart()
{
    SshToTarget "/legato/systems/current/bin/legato stop"
    SshToTarget "/legato/systems/current/bin/legato start"
    sleep 10 # give time for framework to start
}

#=== FUNCTION =============================================================================
#
#        NAME: LegatoRestart
# DESCRIPTION: Restarts the start program.
#
#==========================================================================================
LegatoRestart()
{
    SshToTarget "/legato/systems/current/bin/legato restart"
    sleep 10 # give time for framework to start
}


#=== FUNCTION =============================================================================
#
#        NAME: RestoreGoldenLegato
# DESCRIPTION: Restores golden legato image from mtd3 to start in clean state
#
#   RETURNS 0: Success
#           1: Failure
#
#==========================================================================================
RestoreGoldenLegato()
{
    SshToTarget "/legato/systems/current/bin/legato stop"
    SshToTarget "/bin/rm -rf /legato/*"

    if ! RebootTarget
    then
        return 1
    fi

    CurrentSystemIndex=$(SshToTarget "/bin/cat /legato/systems/current/index")
    if [ "$CurrentSystemIndex" != "0" ]
    then
        return 1
    fi

    return 0
}


#=== FUNCTION =============================================================================
#
#        NAME: SetProbationPeriod
# DESCRIPTION: Set the probation period for the system
# PARAMETER 1: Probation period in ms
#
#==========================================================================================
SetProbationTimer()
{
    local timer=$(( $1 * 1000 ))
    SshToTarget "export LE_PROBATION_MS=$timer; /legato/systems/current/bin/legato stop; /legato/systems/current/bin/legato start"
}


#=== FUNCTION =============================================================================
#
#        NAME: ResetProbationTimer
# DESCRIPTION: Reset the probation period for the system
#
#==========================================================================================
ResetProbationTimer()
{
    SshToTarget "unset LE_PROBATION_MS; /legato/systems/current/bin/legato stop; /legato/systems/current/bin/legato start"
}



#=== FUNCTION =============================================================================
#
#        NAME: GetCurrentSystemVersion
# DESCRIPTION: Get the version of the current system
#
#==========================================================================================
GetCurrentSystemVersion()
{
    echo $(SshToTarget "/bin/cat /legato/systems/current/version")
}


#=== FUNCTION =============================================================================
#
#        NAME: GetCurrentSystemStatus
# DESCRIPTION: Get the status of the current system
#
#==========================================================================================
GetCurrentSystemStatus()
{
    echo $(SshToTarget "/bin/cat /legato/systems/current/status")
}

#=== FUNCTION =============================================================================
#
#        NAME: GetCurrentRadioStatus
# DESCRIPTION: Get the modem radio status
#
#==========================================================================================
GetCurrentRadioStatus()
{
    SshToTarget "/legato/systems/current/bin/cm radio"
    return $?
}

#=== FUNCTION =============================================================================
#
#        NAME: GetCurrentSystemIndex
# DESCRIPTION: Get the index of the current system
#
#==========================================================================================
GetCurrentSystemIndex()
{
    echo $(SshToTarget "/bin/cat /legato/systems/current/index")
}


#=== FUNCTION =============================================================================
#
#        NAME: CheckCurrentSystemInfo
# DESCRIPTION: Check if the info of the current system matches
# PARAMETER 1: Version
#           2: Status
#           3: Index
#
#   RETURNS 0: Success
#           1: Failure
#
#==========================================================================================
CheckCurrentSystemInfo()
{
    exitCode=0

    if [ ! -z "$1" ]
    then
        if [ "$(GetCurrentSystemVersion)" != "$1" ]
        then
            echo "Mismatch system version [Expected: $1, Actual: $(GetCurrentSystemVersion)]."
            exitCode=1
        fi
    fi

    if [ ! -z "$2" ]
    then
        if [ "$(GetCurrentSystemStatus)" != "$2" ]
        then
            echo "Mismatch system status [Expected: $2, Actual: $(GetCurrentSystemStatus)]."
            exitCode=1
        fi
    fi

    if [ ! -z "$3" ]
    then
        if [ "$(GetCurrentSystemIndex)" != "$3" ]
        then
            echo "Mismatch system index [Expected: $3, Actual: $(GetCurrentSystemIndex)]."
            exitCode=1
        fi
    fi

    return $exitCode
}


#=== FUNCTION =============================================================================
#
#        NAME: CheckLegatoSystemList
# DESCRIPTION: Check if the list of systems matches
# PARAMETER 1: List of systems (e.g. "0 1 current")
#
#   RETURNS 0: Success
#           1: Failure
#
#==========================================================================================
CheckLegatoSystemList()
{
    IFS=' ' read -r -a expectedSystem <<< "$1"
    expectedSystemLength=${#expectedSystem[@]}

    actualSystem=($(SshToTarget "/bin/ls /legato/systems/"))
    actualSystemLength=${#actualSystem[@]}

    if [ "$expectedSystemLength" != "$actualSystemLength" ]
    then
        return 1
    fi

    for (( i=0; i<= "$actualSystemLength"; i++ ))
    do
        if [ "${expectedSystem[$i]}" != "${actualSystem[$i]}" ]
        then
            return 1
        fi
    done

    return 0
}

# Bug with smack. Dir/files created by a process does not inherit the smack labels. Need to set them manually
SetupSecurityUnpackDir()
{
    local security_unpack_dir="/home/SecurityUnpack"

    if SshToTarget "[ ! -d $security_unpack_dir ]"
    then
        SshToTarget "/bin/mkdir $security_unpack_dir"
        SshToTarget "/legato/systems/current/bin/xattr set security.SMACK64 framework $security_unpack_dir"
        SshToTarget "/bin/chown SecurityUnpack $security_unpack_dir"
    fi
}


#=== FUNCTION =============================================================================
#
#        NAME: GetSysLog
# DESCRIPTION: Get System log of module
# PARAMETER 1: IMEI of module
# PARAMETER 2: Run Time
#==========================================================================================
GetSysLog()
{
    mkdir -p ./results/"$1"
    ssh root@$TARGET_IP  '/sbin/logread' > ./results/"$1"/syslog_"$2"
}

#=== FUNCTION =============================================================================
#
#        NAME: GetTestLog
# DESCRIPTION: Get test log of module
# PARAMETER 1: IMEI of module
# PARAMETER 2: Run Time
#==========================================================================================
GetTestLog()
{
    mv test.log ./results/$1/testlog_"$2"
}