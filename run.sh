#!/bin/bash
# Disable colors if stdout is not a tty
if [ -t 1 ]; then
	COLOR_TITLE="\\033[1;94m"
	COLOR_ERROR="\\033[0;31m"
	COLOR_WARN="\\033[0;93m"
	COLOR_PASS="\\033[0;32m"
	COLOR_RESET="\\033[0m"
else
	COLOR_TITLE=""
	COLOR_ERROR=""
	COLOR_WARN=""
	COLOR_PASS=""
	COLOR_RESET=""
fi

# testing variables
TEST_RESULT="p"

# Configuration loading
source ./configuration.cfg
# Libraries poll
source ./lib/common.sh


target_setup() {
	
	# 1. Plug in SIM, microSD card, IoT test card, and expansion-connector test board;
	# 2. Connect power jumper across pins 2 & 3;
	# 3. Confirm "battery protect" switch is ON (preventing the device from booting on battery power);
	# 4. Connect battery;
	# 5. Switch "battery protect" switch OFF (allowing the device to boot on battery power);

	prompt_char "Plug in SIM, microSD card, IoT test card, and expansion-connector test board then press ENTER"
	prompt_char "Connect power jumper across pins 1 & 2 then press ENTER"
	prompt_char "Confirm \"battery protect\" switch is OFF (preventing the device from booting on battery power)then press ENTER"
	prompt_char "Connect battery press ENTER"
	prompt_char "Switch battery protect switch ON then press ENTER"

	local resp=""
	while [ "$resp" != "Y" ] && [ "$resp" != "N" ]
	do
		local resp=$(prompt_char "Do you see hardware-controlled tri-colour LED goes green? (Y/N)")
	done
	if [ "$resp" = "N" ]
	then
		echo "Hardware-controlled tri-colour LED doens't go green. Switch battery protect doesn't work." >&2
		failure_msg="hardware-controlled tri-colour LED has problem"
		test_result="FAILED"
		return 1
	fi

	prompt_char "Connect unit to USB hub (both console and main USB) then press ENTER"
	WaitForDevice "Up" "$rbTimer"

	#remove and generate ssh key
	ssh-keygen -R $TARGET_IP 

	#Check connection
	SshToTarget "/legato/systems/current/bin/cm info"
	
	# Install .spk
	# install by swflash is faster than fwupdate download
	#swiflash -m "wp76xx" -i "./firmware/yellow_final_$TARGET_TYPE.spk" 
	echo -e "${COLOR_TITLE}Flash Image${COLOR_RESET}"
	cat "./firmware/yellow_final_$TARGET_TYPE.spk" | SshToTarget "/legato/systems/current/bin/fwupdate download -" &
	bgid=$!
	WaitForDevice "Down" "$rbTimer"
	WaitForDevice "Up" "$rbTimer"
	# # Kill flash image process
	pbgid=$(($bgid + 2))
	kill $bgid
	wait $bgid
	kill -9 $pbgid 
	sleep 5

	prompt_char "Press Reset button then press ENTER"

	local resp=""
	while [ "$resp" != "Y" ] && [ "$resp" != "N" ]
	do
		local resp=$(prompt_char "Confirm hardware-controlled LED goes green? (Y/N)")
	done
	if [ "$resp" = "N" ]
	then
		echo  "Reset button has problem." >&2
		failure_msg="Reset button has problem"
		test_result="FAILED"
		return 1
	fi

	WaitForDevice "Up" "$rbTimer"

	# create test folder
	echo -e "${COLOR_TITLE}Creating testing folder${COLOR_RESET}"
	SshToTarget "mkdir -p /tmp/yellow_testing/system"

	# push test script
	echo -e "${COLOR_TITLE}Pushing test scripts${COLOR_RESET}"
	ScpToTarget "./configuration.cfg" "/tmp/yellow_testing/"
	ScpToTarget "./test_scripts/yellow_test.sh" "/tmp/yellow_testing/"

	# install system
	testingSysIndex=$(($(GetCurrentSystemIndex) + 1))
	echo -e "${COLOR_TITLE}Installing testing system${COLOR_TITLE}"
	cat "./system/yellow_factory_test.$TARGET_TYPE.update" | SshToTarget "/legato/systems/current/bin/update"
	WaitForSystemToStart $testingSysIndex
	sleep 40

	# start SPI service before install apps
	SshToTarget "/legato/systems/current/bin/app start spiService"

	run_time=$(date +"%Y-%m-%d-%H:%M:%S")
	imei=$(SshToTarget "/legato/systems/current/bin/cm info imei")

	return 0
}

target_start_test() {

	TEST_LOG=$(SshToTarget "/bin/sh /tmp/yellow_testing/yellow_test.sh")

	#Check all test step is passed 
	if [[ ${TEST_LOG[@]} == *"Completed: success"* ]]; then
	 	write_test_result
	 	#echo $TEST_LOG
	 	return 0
	fi

	return 1
}

target_cleanup() {

	echo -e "${COLOR_TITLE}Get System Log ${COLOR_RESET}"
	GetSysLog $imei $run_time

	echo -e "${COLOR_TITLE}Restoring target${COLOR_RESET}"

	# remove tmp folder?
	echo -e "${COLOR_TITLE}Removing testing folder${COLOR_RESET}"
	SshToTarget "/bin/rm -rf /tmp/yellow_testing"

	# restore golden legato?
	echo -e "${COLOR_TITLE}Restoring Legato${COLOR_RESET}"
	if ! RestoreGoldenLegato
	then
		TEST_RESULT="f"
		echo -e "${COLOR_ERROR}Failed to restore Legato to Golden state${COLOR_RESET}"
	fi

	echo -e "${COLOR_TITLE}Test is finished${COLOR_RESET}"
	prompt_char "Disconnect from USB then press ENTER"
	prompt_char "Disconnect battery,Unplug SIM, SD card, IoT card and expansion-connector test board.then press ENTER"
	prompt_char "Then press ENTER to end testing then press ENTER"

}

write_test_result () {
	local eeprom_path=""

	echo -e "${COLOR_TITLE}Writing Test Result${COLOR_RESET}"

	if [ "$TARGET_TYPE" = "wp85" ]
	then
		local eeprom_path="/sys/bus/i2c/devices/0-0050/eeprom"
	else
		if [ "$TARGET_TYPE" = "wp76xx" ]
		then
			local eeprom_path="/sys/bus/i2c/devices/4-0050/eeprom"
		fi
	fi

	local time_str=$(date +"%Y-%m-%d-%H:%M")

	local msg="mangOH Yellow\\\\nRev: 1.0\\\\nDate: $time_str\\\\nMfg: Talon Communications\\\\0"

	if [ "$TEST_RESULT" = "f" ]
	then
		return 1
	else
		SshToTarget "/bin/echo -n -e $msg > $eeprom_path"
	fi

    return 0
}

# main program
if ! target_setup
then
	TEST_RESULT="f"
	echo -e "${COLOR_ERROR}Failed to setup target${COLOR_RESET}"
	exit
fi

if ! target_start_test
then
	TEST_RESULT="f"
	echo -e "${COLOR_ERROR}Testing Failed${COLOR_RESET}"
fi

if ! target_cleanup
then
	TEST_RESULT="f"
	echo -e "${COLOR_ERROR}Failed to cleanup target${COLOR_RESET}"
fi

EchoPassOrFail $TEST_RESULT

GetTestLog $imei $run_time