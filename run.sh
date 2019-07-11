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

echo -e "${COLOR_TITLE}Testing setup${COLOR_RESET}"

declare -a install_driver_modules=(
	"iio"
	"iio-kfifo-buf"
	"iio-triggered-buffer"
	"cp2130"
	"opt300x"
	"expander"
	# "cypwifi"
	"bmi160"
	"bmi160-i2c"
	"bmc150_magn"
	"bmc150_magn_i2c"
	"rtc-pcf85063"
	"rtc_sync"
	"bq25601"
	"bq27xxx_battery"
	"mangoh_yellow_dev"
)
declare -a remove_driver_modules=(
	"mangoh_yellow_dev"
	"bmi160-i2c"
	"bmi160"
	"bmc150_magn_i2c"
	"bmc150_magn"
	"rtc-pcf85063"
	"rtc_sync"
	"bq25601"
	"bq27xxx_battery"
	"opt300x"
	"expander"
	# "cypwifi"
	"cp2130"
	"iio-triggered-buffer"
	"iio-kfifo-buf"
	"iio"
)

target_setup() {
	# create test folder
	echo -e "${COLOR_TITLE}Creating testing folder${COLOR_RESET}"
	SshToTarget "mkdir -p /tmp/yellow_testing/modules"
	SshToTarget "mkdir -p /tmp/yellow_testing/apps"
	SshToTarget "mkdir -p /tmp/yellow_testing/system"

	# push test script
	echo -e "${COLOR_TITLE}Pushing test scripts${COLOR_RESET}"
	ScpToTarget "./configuration.cfg" "/tmp/yellow_testing/"
	ScpToTarget "./test_scripts/yellow_test.sh" "/tmp/yellow_testing/"

	# # push test driver modules
	# echo -e "${COLOR_TITLE}Pushing driver modules${COLOR_RESET}"
	# ScpToTarget "./modules/mangoh_yellow_dev/mangoh_yellow_dev.ko" "/tmp/yellow_testing/modules"
	# ScpToTarget "./modules/iio-triggered-buffer/iio-triggered-buffer.ko" "/tmp/yellow_testing/modules"
	# ScpToTarget "./modules/iio-kfifo-buf/iio-kfifo-buf.ko" "/tmp/yellow_testing/modules"
	# ScpToTarget "./modules/iio/iio.ko" "/tmp/yellow_testing/modules"
	# ScpToTarget "./modules/bmi160-i2c/bmi160-i2c.ko" "/tmp/yellow_testing/modules"
	# ScpToTarget "./modules/bmi160/bmi160.ko" "/tmp/yellow_testing/modules"
	# ScpToTarget "./modules/bmc150_magn_i2c/bmc150_magn_i2c.ko" "/tmp/yellow_testing/modules"
	# ScpToTarget "./modules/bmc150_magn/bmc150_magn.ko" "/tmp/yellow_testing/modules"
	# ScpToTarget "./modules/rtc-pcf85063/rtc-pcf85063.ko" "/tmp/yellow_testing/modules"
	# ScpToTarget "./modules/rtc_sync/rtc_sync.ko" "/tmp/yellow_testing/modules"
	# ScpToTarget "./modules/bq25601/bq25601.ko" "/tmp/yellow_testing/modules"
	# ScpToTarget "./modules/bq27xxx_battery/bq27xxx_battery.ko" "/tmp/yellow_testing/modules"
	# ScpToTarget "./modules/opt300x/opt300x.ko" "/tmp/yellow_testing/modules"
	# ScpToTarget "./modules/expander/expander.ko" "/tmp/yellow_testing/modules"
	# # ScpToTarget "./modules/cypwifi/cypwifi.ko" "/tmp/yellow_testing/modules"
	# ScpToTarget "./modules/cp2130/cp2130.ko" "/tmp/yellow_testing/modules"

	# push system test
	echo -e "${COLOR_TITLE}Pushing Legato system${COLOR_RESET}"
	ScpToTarget "./system/yellow_factory_test.$TARGET_TYPE.update" "/tmp/yellow_testing/system"

	# push legato test apps
	#echo -e "${COLOR_TITLE}Pushing Legato apps${COLOR_RESET}"
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
	echo -e "${COLOR_ERROR}Installing testing system${COLOR_RESET}"
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
	for element in "${TEST_LOG[@]}"
	do
		if [ "$element" = "Completed: success" ]
		then
			return 0
		fi 
	done
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
	echo -e "${COLOR_ERROR}Testing failed${COLOR_RESET}"
fi

if ! target_cleanup
then
	TEST_RESULT="f"
	echo -e "${COLOR_ERROR}Failed to cleanup target${COLOR_RESET}"
fi

echo -e "${COLOR_TITLE}Test is finished${COLOR_RESET}"
EchoPassOrFail $TEST_RESULT
