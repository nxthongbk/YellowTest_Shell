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

	# echo -e "${COLOR_TITLE}Creating testing folder${COLOR_RESET}"
	# 1. Plug in SIM, microSD card, IoT test card, and expansion-connector test board;
	# 2. Connect power jumper across pins 2 & 3;
	# 3. Confirm "battery protect" switch is ON (preventing the device from booting on battery power);
	# 4. Connect battery;
	# 5. Switch "battery protect" switch OFF (allowing the device to boot on battery power);

	prompt_char "Plug in SIM, microSD card, IoT test card, and expansion-connector test board then press ENTER"
	prompt_char "Connect power jumper across pins 2 & 3 then press ENTER"
	prompt_char "Confirm \"battery protect\" switch is ON (preventing the device from booting on battery power)then press ENTER"
	prompt_char "Connect battery press ENTER"
	prompt_char "Switch battery protect switch OFF then press ENTER"

	local resp=""
	while [ "$resp" != "Y" ] && [ "$resp" != "N" ]
	do
		local resp=$(prompt_char "Do you see hardware-controlled tri-colour LED goes green? (Y/N)")
	done
	if [ "$resp" = "N" ]
	then
		failure_msg="hardware-controlled tri-colour LED has problem"
		test_result="FAILED"
		return 1
	fi

	prompt_char "Connect unit to USB hub (both console and main USB) then press ENTER"

	# create test folder
	echo -e "${COLOR_TITLE}Creating testing folder${COLOR_RESET}"


	# SshToTarget "mkdir -p /tmp/yellow_testing/modules"
	# SshToTarget "mkdir -p /tmp/yellow_testing/apps"
	SshToTarget "mkdir -p /tmp/yellow_testing/system"

	# push test script
	echo -e "${COLOR_TITLE}Pushing test scripts${COLOR_RESET}"
	ScpToTarget "./configuration.cfg" "/tmp/yellow_testing/"
	ScpToTarget "./test_scripts/yellow_test.sh" "/tmp/yellow_testing/"

	# push system test
	echo -e "${COLOR_TITLE}Pushing Legato system${COLOR_RESET}"
	ScpToTarget "./system/yellow_factory_test.$TARGET_TYPE.update" "/tmp/yellow_testing/system"

	# push legato test apps
	# echo -e "${COLOR_TITLE}Pushing Legato apps${COLOR_RESET}"
	# ScpToTarget "./apps/YellowTestService.$TARGET_TYPE.update" "/tmp/yellow_testing/apps"
	# ScpToTarget "./apps/YellowTest.$TARGET_TYPE.update" "/tmp/yellow_testing/apps"


	# # load driver modules
	# for driver_module in "${install_driver_modules[@]}"
	# do
	# 	echo -e "${COLOR_TITLE}Loading driver '${driver_module}.ko'...${COLOR_RESET}"
	# 	SshToTarget "/sbin/insmod /tmp/yellow_testing/modules/${driver_module}.ko"
	# done

	# install system
	testingSysIndex=$(($(GetCurrentSystemIndex) + 1))
	echo -e "${COLOR_TITLE}Installing testing system${COLOR_TITLE}"
	SshToTarget "/legato/systems/current/bin/update /tmp/yellow_testing/system/yellow_factory_test.$TARGET_TYPE.update"
	WaitForSystemToStart $testingSysIndex

	# install apps
	# if AppExist "YellowTestService"
	# then
	# 	if ! AppRemove "YellowTestService"
	# 	then
	# 		TEST_RESULT="f"
	# 		echo -e "${COLOR_ERROR}Failed to remove app YellowTestService${COLOR_RESET}"
	# 	fi
	# fi
	# if AppExist "YellowTest"
	# then
	# 	if ! AppRemove "YellowTest"
	# 	then
	# 		TEST_RESULT="f"
	# 		echo -e "${COLOR_ERROR}Failed to remove app YellowTest${COLOR_RESET}"
	# 	fi
	# fi
	#sleep 3
	# start SPI service before install apps
	SshToTarget "/legato/systems/current/bin/app start spiService"

	# echo -e "${COLOR_TITLE}Installing app 'YellowTestService'...${COLOR_RESET}"
	# SshToTarget "/legato/systems/current/bin/update /tmp/yellow_testing/apps/YellowTestService.$TARGET_TYPE.update"

	# echo -e "${COLOR_TITLE}Installling app 'YellowTest'...${COLOR_RESET}"
	# SshToTarget "/legato/systems/current/bin/update /tmp/yellow_testing/apps/YellowTest.$TARGET_TYPE.update"

	# echo -e "${COLOR_TITLE}Installling app 'YellowTest'...${COLOR_RESET}"
	# SshToTarget "/legato/systems/current/bin/update /tmp/yellow_testing/apps/YellowTest.$TARGET_TYPE.update"

	return 0
}

target_start_test() {

	TEST_LOG=$(SshToTarget "/bin/sh /tmp/yellow_testing/yellow_test.sh")
	echo $TEST_LOG
	#for element in "${TEST_LOG[@]}"
	if [[ ${TEST_LOG[@]} == *"Completed: success"* ]]; then
	 	return 0
	fi


	# do
	# 	echo $element
	# 	if [ "$element" = *"Completed: success"* ]
	# 	then
	# 		echo -e "${COLOR_TITLE}Complete success${COLOR_RESET}"
	# 		return 0
	# 	fi 
	# done
	return 1
}

target_cleanup() {
	echo -e "${COLOR_TITLE}Restoring target${COLOR_RESET}"
	# remove legato test app
	# if AppExist "YellowTest"
	# then
	# 	echo -e "${COLOR_TITLE}Installing app 'YellowTest'...${COLOR_RESET}"
	# 	if ! AppRemove "YellowTest"
	# 	then
	# 		TEST_RESULT="f"
	# 		echo -e "${COLOR_ERROR}Failed to remove app 'YellowTest'${COLOR_RESET}"
	# 	fi
	# else
	# 	TEST_RESULT="f"
	# 	echo -e "${COLOR_ERROR}App 'YellowTest' has not been installed${COLOR_RESET}"
	# fi

	# if AppExist "YellowTestService"
	# then
	# 	echo -e "${COLOR_TITLE}Installing app 'YellowTestService'...${COLOR_RESET}"
	# 	if ! AppRemove "YellowTestService"
	# 	then
	# 		TEST_RESULT="f"
	# 		echo -e "${COLOR_ERROR}Failed to remove app 'YellowTestService'${COLOR_RESET}"
	# 	fi
	# else
	# 	TEST_RESULT="f"
	# 	echo -e "${COLOR_ERROR}App 'YellowTestService' has not been installed${COLOR_RESET}"
	# fi

	# # remove driver modules
	# for driver_module in "${remove_driver_modules[@]}"
	# do
	# 	echo -e "${COLOR_TITLE}Removing driver '${driver_module}.ko'${COLOR_RESET}"
	# 	SshToTarget "/sbin/rmmod /tmp/yellow_testing/modules/${driver_module}.ko"
	# done

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
}

# main
if ! target_setup
then
	TEST_RESULT="f"
	echo -e "${COLOR_ERROR}Failed to setup target${COLOR_RESET}"
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

echo -e "${COLOR_TITLE}Test is finished${COLOR_RESET}"
prompt_char "Remove power jumper"
prompt_char "Disconnect from USB"
prompt_char "Disconnect battery,Unplug SIM, SD card, IoT card and expansion-connector test board."
prompt_char "Then press ENTER to end testing"
EchoPassOrFail $TEST_RESULT