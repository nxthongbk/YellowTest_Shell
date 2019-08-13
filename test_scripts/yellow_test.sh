#!/bin/bash
# Note: run on target
source /tmp/yellow_testing/configuration.cfg
echo "MangOH Yellow factory testing"

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
    echo $1 >&2
    read prompt_input
    echo $(echo $prompt_input | tr 'a-z' 'A-Z')
}


#=== FUNCTION ==================================================================
#
#        NAME: triLED
# DESCRIPTION: Turn on/off tri-LED
# PARAMETER 1: led name (red/green/blue)
# PARAMETER 2: led state (on/off)
#
#    RETURNS: None
#
#===============================================================================
triLED() {
	local triLEDRed="/sys/devices/platform/expander.0/tri_led_red"
	local triLEDGreen="/sys/devices/platform/expander.0/tri_led_grn"
	local triLEDBlue="/sys/devices/platform/expander.0/tri_led_blu"

	local ledFile=""
	if [ "$1" = "red" ]
	then
		local ledFile=$triLEDRed
	else
		if [ "$1" = "green" ]
		then
			local ledFile=$triLEDGreen
		else
			if [ "$1" = "blue" ]
			then
				local ledFile=$triLEDBlue
			else
				echo "Unknown tri-LED" >&2
			fi
		fi
	fi

	if [ "$2" = "on" ]
	then
		echo 1 > "$ledFile"
	else
		if [ "$2" = "off" ]
		then
			echo 0 > "$ledFile"
		else
			echo "Unknown LED state" >&2
		fi
	fi
}

#=== FUNCTION ==================================================================
#
#        NAME: genericLED
# DESCRIPTION: Turn on/off generic LED
# PARAMETER 1: led state (on/off)
#
#    RETURNS: None
#
#===============================================================================
genericLED() {
	local genericLEDPath="/sys/devices/platform/expander.0/generic_led"

	if [ "$1" = "on" ]
	then
		echo 1 > "$genericLEDPath"
	else 
		if [ "$1" = "off" ]
		then
			echo 0 > "$genericLEDPath"
		else
			echo "Unknown Generic LED state" >&2
		fi
	fi
}

#=== FUNCTION ==================================================================
#
#        NAME: generic_button_init
# DESCRIPTION: Initial button (GPIO export)
#   PARAMETER: None
#
#     RETURNS: 0  Success
#            : 1 Failure
#
#===============================================================================
generic_button_init() {
	if [ -d "/sys/class/gpio/gpio25" ]
	then
		echo "Button had been intialized, already" >&2
	else
		echo 25 > "/sys/class/gpio/export"
		if [ $? != 0 ]
		then
			return 1
		fi
	fi
	return 0
}

#=== FUNCTION ==================================================================
#
#        NAME: generic_button_deinit
# DESCRIPTION: Deinitial button (GPIO unexport)
#   PARAMETER: None
#
#     RETURNS: 0  Success
#            : -1 Failure
#
#===============================================================================
generic_button_deinit() {
	if [ -d "/sys/class/gpio/gpio25" ]
	then
		echo 25 > "/sys/class/gpio/unexport"
		if [ $? != 0 ]
		then
			return 1
		fi
	else
		echo "Button had been deintialized, already" >&2
	fi
	return 0
}

#=== FUNCTION ==================================================================
#
#        NAME: generic_button_get_state
# DESCRIPTION: Get generic button's state
#   PARAMETER: None
#
#     RETURNS: pressed/released/unknown
#
#===============================================================================
generic_button_get_state() {
	local buttonFile="/sys/class/gpio/gpio25/value"
	local res="unknown"
	r=$(cat $buttonFile)
	if [ "$r" = "1" ]
	then
		local res="pressed"
	else
		if [ "$r" = "0" ]
		then
			local res="released"
		fi
	fi
	echo "$res"
}

#=== FUNCTION ==================================================================
#
#        NAME: buzzer_set
# DESCRIPTION: Set buzzer frequence
# PARAMETER 1: frequence 0/1/1024/2048/4096/8192
#
#     RETURNS: None
#
#===============================================================================
buzzer_set() {
	if [ "$TARGET_TYPE" = "wp85" ]
	then
		echo "$1" > "/sys/bus/i2c/drivers/rtc-pcf85063/4-0051/clkout_freq"
	else
		if [ "$TARGET_TYPE" = "wp76xx" ]
		then
			echo "$1" > "/sys/bus/i2c/drivers/rtc-pcf85063/8-0051/clkout_freq"
		fi
	fi
}

#=== FUNCTION ==================================================================
#
#        NAME: test_buzzer
# DESCRIPTION: Test the buzzer
#   PARAMETER: None
#
#   RETURNS 1: PASSED/FAILED
#   RETURNS 2: Failure message
#
#===============================================================================
test_buzzer() {
	# Press button and listen for buzzer;
	# start background function
	ButtonMonitor &
	local bgid=$!

	local resp=""
	while [ "$resp" != "Y" ] && [ "$resp" != "N" ]
	do
		local resp=$(prompt_char "Press generic button and listen for buzzer. Do you hear the buzzer's sound when pressing button? (Y/N)")
	done
	if [ "$resp" = "N" ]
	then
		echo "Buzzer has problem." >&2
		kill $bgid
		wait $bgid

		failure_msg="Buzzer did not work"
		test_result="FAILED"
		return 1
	fi
	
	kill $bgid
	wait $bgid

	failure_msg=""
	test_result="PASSED"
	return 0
}


#=== FUNCTION ==================================================================
#
#        NAME: test_reset
# DESCRIPTION: Test the reset button
#   PARAMETER: None
#
#   RETURNS 1: PASSED/FAILED
#   RETURNS 2: Failure message
#
#===============================================================================
test_reset() {
	# Press button and listen for buzzer;
	# start background function
	prompt_char "Press reset button then press ENTER"

	local resp=""
	while [ "$resp" != "Y" ] && [ "$resp" != "N" ]
	do
		local resp=$(prompt_char "Confirm hardware-controlled LED goes green (Y/N)")
	done
	if [ "$resp" = "N" ]
	then
		echo "Reset Button has problem." >&2
		failure_msg="Reset Button has problem"
		test_result="FAILED"
		return 1
	fi

	failure_msg=""
	
	return 0
	
}

#=== FUNCTION ==================================================================
#
#        NAME: ButtonMonitor
# DESCRIPTION: Monitor the generic button state then do the action respectively
#            : Should be run in background
#   PARAMETER: None
#
#     RETURNS: None
#
#===============================================================================
ButtonMonitor() {
	local last_state=""
	while true
	do
		button_state=$(generic_button_get_state)
		if [ "$button_state" = "pressed" ]
		then
			if [ "$last_state" != "$button_state" ]
			then
				local last_state=$button_state
				buzzer_set "4096"
			fi
		else
			if [ "$button_state" = "released" ]
			then
				if [ "$last_state" != "$button_state" ]
				then
					local last_state=$button_state
					buzzer_set "0"
				fi
			else
				local last_state=$button_state
			fi
		fi
		# sleep 1
	done
}

#=== FUNCTION ==================================================================
#
#        NAME: read_light_sensor
# DESCRIPTION: Read value of light sensor
#   PARAMETER: None
#
#     RETURNS: Light sensor value in illuminance
#
#===============================================================================
read_light_sensor() {
	local light_sensor_path="/sys/bus/iio/devices/iio:device1/in_illuminance_input"
	local light_value=$(cat $light_sensor_path)
	echo "Light Sensor Value: '$light_value'" >&2
	echo "$light_value"
}

#=== FUNCTION ==================================================================
#
#        NAME: numCompare
# DESCRIPTION: Compare two number
# PARAMETER 1: number1
# PARAMETER 2: number2
#
#    RETURNS: 0 number1 is less than number2 + 100
#             1 number1 is greater than number2 + 100
#
#===============================================================================
numCompare() {
	local res=$(awk -v n1="$1" -v n2="$2" -v res="0" 'BEGIN {print (n1>n2+100?"1":"0") }')
	return $res
}

#=== FUNCTION ==================================================================
#
#        NAME: test_light_sensor
# DESCRIPTION: Test the light sensor
#   PARAMETER: None
#
#   RETURNS 1: PASSED/FAILED
#   RETURNS 2: Failure message
#
#===============================================================================
test_light_sensor() {
	#     Cover light sensor with finger and confirm software-controlled tri-colour LED goes blue;
	#     (On-board test software should look for light sensor interrupt.)
	local before_cover_value=$(read_light_sensor)
	prompt_char "Please cover the light sensor with your finger then press ENTER"
	local after_cover_value=$(read_light_sensor)
	numCompare $before_cover_value $after_cover_value
	if [ $? = 1 ]
	then
		# triLED go blue
		triLED "red" "off"
		triLED "green" "off"
		triLED "blue" "on"
	fi

	local resp=""
	while [ "$resp" != "Y" ] && [ "$resp" != "N" ]
	do
		local resp=$(prompt_char "Do you see blue light of LED? (Y/N)")
	done
	if [ "$resp" = "N" ]
	then
		echo "Light sensor has problem." >&2
		failure_msg="Light sensor has problem"
		test_result="FAILED"
		return 1
	fi

	#     Uncover light sensor and confirm LED returns to yellow;
	local resp=$(prompt_char "Please uncover the light sensor then press ENTER")
	local after_uncover_value=$(read_light_sensor)
	numCompare $after_uncover_value $after_cover_value
	if [ $? = 1 ]
	then
		# triLED go yellow
		triLED "red" "on"
		triLED "green" "on"
		triLED "blue" "off"
	fi
	local resp=""
	while [ "$resp" != "Y" ] && [ "$resp" != "N" ]
	do
		local resp=$(prompt_char "Do you see yellow light of LED? (Y/N)")
	done
	if [ "$resp" = "N" ]
	then
		echo "Light sensor has problem." >&2
		failure_msg="Light sensor has problem"
		test_result="FAILED"
		return 1
	fi

	failure_msg=""
	
	return 0
}

#=== FUNCTION ==================================================================
#
#        NAME: write_eeprom
# DESCRIPTION: test eeprom writing
#   PARAMETER: None
#
#   RETURNS 1: PASSED/FAILED
#   RETURNS 2: Failure message
#
#===============================================================================
write_eeprom() {
	local eeprom_path=""
	if [ "$TARGET_TYPE" = "wp85" ]
	then
		local eeprom_path="/sys/bus/i2c/devices/0-0050/eeprom"
	else
		if [ "$TARGET_TYPE" = "wp76xx" ]
		then
			local eeprom_path="/sys/bus/i2c/devices/4-0050/eeprom"
		fi
	fi

	# msg="mangOH Yellow\\nRev: 1.0\\nDate: $time_str\\nMfg: Talon Communications\\0"
	msg="mangOH Yellow DV3\x00"

	echo -n -e "$msg" > "$eeprom_path"
	if [ $? != 0 ]
	then
		failure_msg="Failed to write to EEPROM"
		test_result="FAILED"
		return 1
	fi

	failure_msg=""
	
	return 0
}


#=== FUNCTION ==================================================================
#
#        NAME: yellowManualTest_initial
# DESCRIPTION: Perform the initial test
#   PARAMETER: None
#
#   RETURNS 1: PASSED/FAILED
#   RETURNS 2: Failure message
#
#===============================================================================
yellowManualTest_initial() {
	# initial generic button
	generic_button_init
	if [ $? != 0 ]
	then
		echo "Failed to initial Generic Button"
		exit -1
	fi
	
	triLED "red" "off"
	triLED "green" "on"
	triLED "blue" "off"

	prompt_char "Wait for software-controlled tri-colour LED to turn green (ready for manual test). press ENTER"

	local resp=""
	while [ "$resp" != "Y" ] && [ "$resp" != "N" ]
	do
		local resp=$(prompt_char "Do you see software-controlled LED goes green? (Y/N)")
	done
	if [ "$resp" = "N" ]
	then
		echo "Software-controller LED has problem." >&2
		failure_msg="Software-controller LED has problem"
		test_result="FAILED"
		return 1
	fi

	failure_msg=""
	test_result="PASSED"
	return 0
}

#=== FUNCTION ==================================================================
#
#        NAME: yellowTest_WifiScan
# DESCRIPTION: Scan WiFi and see dedicated AP
#   PARAMETER: None
#
#   RETURNS 1: PASSED/FAILED
#   RETURNS 2: Failure message
#
#===============================================================================
yellowTest_WifiScan() {
	
	/legato/systems/current/bin/wifi client start >&2
	if [ $? = 0 ]
	then
		echo 'start wifi successflly' >&2
	else
		echo 'Unable to start wifi' >&2
		return 1
	fi

	sleep 2

	/legato/systems/current/bin/wifi client scan | grep "$WIFI_ACCESSPOINT" >&2
	if [ $? = 0 ]
	then
		echo "Able to find wifi Accesspoint $WIFI_ACCESSPOINT" >&2
	else
		echo "Unable to find wifi Accesspoint $WIFI_ACCESSPOINT" >&2
		return 1
	fi

	failure_msg=""
	return 0
}



#=== FUNCTION ==================================================================
#
#        NAME: yellowTest_uSD
# DESCRIPTION: Test Read Write uSD Card
#   PARAMETER: None
#
#   RETURNS 1: PASSED/FAILED
#   RETURNS 2: Failure message
#
#===============================================================================
yellowTest_uSD() {
	
	/bin/mkdir /tmp/sd
	if [ $? = 0 ]
	then
		echo 'Create sd directory successflly' >&2
	else
		echo 'Create sd directory unsuccessflly' >&2
		return 1
	fi

	/bin/mount -ofmask=0111 -odmask=0000 -osmackfsdef=sd /dev/mmcblk0p1 /tmp/sd

	if [ $? = 0 ]
	then
		echo 'Mount sd directory successflly' >&2
	else
		echo 'Mount sd directory unsuccessflly' >&2
		return 1
	fi

	/bin/touch /tmp/sd/log.txt
	if [ $? = 0 ]
	then
		echo 'Create file on SDcard successflly' >&2
	else
		echo 'Create file on SDcard unsuccessflly' >&2
		return 1
	fi

	/bin/echo foo >> /tmp/sd/log.txt
	if [ $? = 0 ]
	then
		echo 'Write file on SDcard successflly' >&2
	else
		echo 'Write file on SDcard unsuccessflly' >&2
		return 1
	fi

	/bin/cat /tmp/sd/log.txt
	if [ $? = 0 ]
	then
		echo 'Read file on SDcard successflly' >&2
	else
		echo 'Read file on SDcard unsuccessflly' >&2
		return 1
	fi

	failure_msg=""
	return 0
}

#=== FUNCTION ==================================================================
#
#        NAME: yellowTest_USB
# DESCRIPTION: Test Read USB
#   PARAMETER: None
#
#   RETURNS 1: PASSED/FAILED
#   RETURNS 2: Failure message
#
#===============================================================================
yellowTest_USB() {
	
	if [ -d "/sys/devices/7c00000.hsic_host/usb1/1-1/1-1.1" ]
	then
		echo "USB device 1-1.1 exist" >&2
	else
		echo "USB device 1-1.1 doesn't exist" >&2
		return 1
	fi

	if [ -d "/sys/devices/7c00000.hsic_host/usb1/1-1/1-1.2" ]
	then
		echo "USB device 1-1.2 exist" >&2
	else
		echo "USB device 1-1.2 doesn't exist" >&2
		return 1
	fi

	if [ -d "/sys/devices/7c00000.hsic_host/usb1/1-1/1-1.3" ]
	then
		echo "USB device 1-1.3 exist" >&2
	else
		echo "USB device 1-1.3 doesn't exist" >&2
		return 1
	fi

	if [ -d "/sys/devices/7c00000.hsic_host/usb1/1-1/1-1:1.0" ]
	then
		echo "USB device 1-1:1.0 exist" >&2
	else
		echo "USB device 1-1:1.0 doesn't exist" >&2
		return 1
	fi
	

	failure_msg=""
	return 0
}

#=== FUNCTION ==================================================================
#
#        NAME: yellowTest_I2CDetect
# DESCRIPTION: Perform the I2C Detect Address test
#   PARAMETER: None
#
#   RETURNS 1: PASSED/FAILED
#   RETURNS 2: Failure message
#
#===============================================================================
yellowTest_I2CDetect() {
	echo "Stop legato ..." >&2
	/legato/systems/current/bin/legato stop
	if [ $? = 0 ]
	then
		echo 'Stop Legato successflly' >&2
	else
		echo 'Unable to stop Legato' >&2
		return 1
	fi

	echo "Enable all the ports on the hub" >&2
	/usr/sbin/i2cset -y 4 0x71 0x0f

	for address in 50 71 08 68 76 44 6b 3e 51
	do
		/usr/sbin/i2cdetect -y -r 4 | grep " $address "
		if [ $? = 0 ]
		then
			echo "Detected I2C address $address" >&2
		else
			echo "I2C address $address does not exist" >&2
			return 1
		fi
	done

	/legato/systems/current/bin/legato start
	sleep 10
	failure_msg=""
	return 0
}

#=== FUNCTION ==================================================================
#
#        NAME: yellowManualTest_final
# DESCRIPTION: Perform the initial test
#   PARAMETER: None
#
#   RETURNS 1: PASSED/FAILED
#   RETURNS 2: Failure message
#
#===============================================================================
yellowManualTest_final() {
	# 18. Switch cellular antenna selection DIP switch;
	#prompt_char "Switch cellular antenna selection DIP switch then press ENTER"
	# 19. Press button to finalize the test;
	echo "Press generic button to finalize the test" >&2
	#     (On-board test software should verify that the correct string has been written to the NFC tag.)
	# 20. Confirm software-controlled tri-colour LED has changed to white;
	while true
	do
		if [ "$(generic_button_get_state)" = "pressed" ]
		then
			triLED "red" "on"
			triLED "green" "on"
			triLED "blue" "on"
			break
		# sleep 1
		fi
	done

	local resp=""
	while [ "$resp" != "Y" ] && [ "$resp" != "N" ]
	do
		local resp=$(prompt_char "Do you see software-controlled LED goes white? (Y/N)")
	done
	if [ "$resp" = "N" ]
	then
		echo "Failed to final the test." >&2
		failure_msg="Failed to final the test"
		test_result="FAILED"
		return 1
	fi
	
	# 21. Confirm hardware-controlled LED is yellow;
	local resp=""
	while [ "$resp" != "Y" ] && [ "$resp" != "N" ]
	do
		local resp=$(prompt_char "Do you see hardware-controlled LED goes yellow? (Y/N)")
	done

	if [ "$resp" = "N" ]
	then
		failure_msg="Wrong hardware-controlled LED state"
		test_result="FAILED"
		return 1
	fi

	# 22. Press reset button;
	# 23. Confirm  rdware-controlled LED goes green;
	# 24. Remove power jumper;
	# 25. Disconnect from USB;
	# 26. Disconnect battery;
	# 27. Unplug SIM, SD card, IoT card and expansion-connector test board.
	failure_msg=""
	return 0
}

#=== FUNCTION ==================================================================
#
#        NAME: test_automation
# DESCRIPTION: Perform the automation test
#   PARAMETER: None
#
#   RETURNS 1: 0 Success
#   RETURNS 2: 1 Failure
#
#===============================================================================
test_automation() {
	echo "Running Automation Test..." >&2

	PATH=/legato/systems/current/bin:/usr/local/bin:/usr/bin:/bin:/usr/local/sbin:/usr/sbin:/sbin /etc/init.d/syslog stop
	sleep 2
	PATH=/legato/systems/current/bin:/usr/local/bin:/usr/bin:/bin:/usr/local/sbin:/usr/sbin:/sbin /etc/init.d/syslog start
	sleep 2
	/legato/systems/current/bin/app restart YellowTestService	
	sleep 2
	/legato/systems/current/bin/app restart YellowTest
	sleep 2

	#echo 'Test SIM state"' >&2
	/sbin/logread | grep "Check SIM state: PASSED"
	if [ $? = 0 ]
	then
		echo 'Check SIM state: PASSED' >&2
	else
		echo 'Check SIM state: FAILED' >&2
		/legato/systems/current/bin/app stop YellowTest
		failure_msg='FAILED: Cannot find: "Check SIM state: PASSED"' 
		test_result="FAILED"
		return 1
	fi

	#echo 'Test signal quality' >&2
	/sbin/logread | grep "Check signal quality: PASSED"
	if [ $? = 0 ]
	then
		echo 'Check signal quality: PASSED' >&2
	else
		echo 'Check signal quality: FAILED' >&2
		/legato/systems/current/bin/app stop YellowTest
		failure_msg='FAILED: Cannot find: "Check signal quality: PASSED"'
		test_result="FAILED"
		return 1
	fi

	#echo 'Test Read Battery Voltage"' >&2
	/sbin/logread | grep "Read Battery Voltage: PASSED"
	if [ $? = 0 ]
	then
		echo 'Read Battery Voltage: PASSED' >&2
	else
		echo 'Read Battery Voltage: FAILED' >&2
		/legato/systems/current/bin/app stop YellowTest
		failure_msg='FAILED: Cannot find: "Read Battery Voltage PASSED"'
		test_result="FAILED"
		return 1
	fi

	#echo 'Test IoTCardReadADCs"' >&2
	/sbin/logread | grep "Check IoTCardReadADCs: PASSED"
	if [ $? = 0 ]
	then
		echo 'Check IoTCardReadADCs: PASSED' >&2
	else
		echo 'Check IoTCardReadADCs: FAILED' >&2
		/legato/systems/current/bin/app stop YellowTest
		failure_msg='FAILED: Cannot find: "Check IoTCardReadADCs: PASSED"'
		test_result="FAILED"
		return 1
	fi

	#echo 'Test IOTCardReset"' >&2
	/sbin/logread | grep "IOTCardReset: PASSED"
	if [ $? = 0 ]
	then
		echo 'IOTCardReset: PASSED' >&2
	else
		echo 'IOTCardReset: FAILED' >&2
		/legato/systems/current/bin/app stop YellowTest
		failure_msg='FAILED: Cannot find: "IOTCardReset: PASSED"'
		test_result="FAILED"
		return 1
	fi

	#echo 'Test IOTCardReset"' >&2
	/sbin/logread | grep "Check UART Loop back: PASSED"
	if [ $? = 0 ]
	then
		echo 'UART LoopBack: PASSED' >&2
	else
		echo 'UART LoopBack: FAILED' >&2
		/legato/systems/current/bin/app stop YellowTest
		failure_msg='FAILED: Cannot find: "UART Loop back: PASSED"'
		test_result="FAILED"
		return 1
	fi

	#echo 'Test Read ADC3' >&2
	/sbin/logread | grep "Read ADC3: PASSED"
	if [ $? = 0 ]
	then
		echo 'Read ADC3: PASSED' >&2
	else
		echo 'Read ADC3: FAILED' >&2
		/legato/systems/current/bin/app stop YellowTest
		failure_msg='FAILED: Cannot find: "Read ADC3: PASSED"'
		test_result="FAILED"
		return 1
	fi

	# Waiting DV4 for SDIO selection on DIP switch to switch between wifi and uSD
	# echo 'Checking message "SDCard Read/Wrire test PASSED"' >&2
	# /sbin/logread | grep "SDCard Read/Wrire test PASSED"
	# if [ $? = 0 ]
	# then
	# 	echo 'Found: "SDCard Read/Wrire test PASSED"' >&2
	# else
	# 	/legato/systems/current/bin/app stop YellowTest
	# 	echo '"SDCard Read/Wrire test FAILED"' >&2
	# 	failure_msg='FAILED: Cannot find: "SDCard Read/Wrire test PASSED"'
	# 	test_result="FAILED"
	# 	return 1
	# fi

	#echo 'Checking message "Read accelerometer and gyroscope connection: PASSED"' >&2
	/sbin/logread | grep "Read accelerometer and gyroscope connection: PASSED"
	if [ $? = 0 ]
	then
		echo 'Read accelerometer and gyroscope: PASSED' >&2
	else
		echo 'Read accelerometer and gyroscope: FAILED' >&2
		/legato/systems/current/bin/app stop YellowTest
		failure_msg='FAILED: Cannot find: "Read accelerometer and gyroscope: PASSED"'
		test_result="FAILED"
		return 1
	fi

	/legato/systems/current/bin/app stop YellowTest
	failure_msg=""
	test_result="PASSED"
	return 0
}

# Main Test
echo '+------------------------------------------------------------------------------+'
echo "|                          mangOH Yellow Test Program                          |"
echo '+------------------------------------------------------------------------------+'

fail_count=0
failure_msg=""
test_result=""

# 8. Wait for software-controlled tri-colour LED to turn green (ready for manual test);
echo "=== yellowManualTest_initial ==="
yellowManualTest_initial
if [ $? != 0 ]
then
	fail_count=$(($fail_count + 1))
	echo "----->               FAILURE           <-----"
	echo "$failure_msg"
else
	echo "$test_result"
fi
echo '======================================================================='

# 9. Press button and listen for buzzer;
echo "=== test_buzzer ==="
test_buzzer
if [ $? != 0 ]
then
	fail_count=$(($fail_count + 1))
	echo "----->               FAILURE           <-----"
	echo "$failure_msg"
	echo "--------------------------------------------"
else
	echo "$test_result"
fi

# 10. Plug in headset;
# 11. Say something into headset, and listen for own voice echoed back through headset;
# 12. Press button to switch audio test mode (software-controlled tri-colour LED goes yellow);
# 13. Say something into the on-board microphone;
# 14. Listen for your own voice echoed back through headset;

# 15. Bring NFC tag reader close to the mangOH board and confirm green LED flashes;
#     (On-board test software should look for the NFC Field Detection interrupt.)

# 16. Cover light sensor with finger and confirm software-controlled tri-colour LED goes blue;
#     (On-board test software should look for light sensor interrupt.)
# 17. Uncover light sensor and confirm LED returns to yellow;
echo "=== test_light_sensor ==="
test_light_sensor
if [ $? != 0 ]
then
	fail_count=$(($fail_count + 1))
	echo "----->               FAILURE           <-----"
	echo "$failure_msg"
else
	echo "$test_result"
fi
echo '======================================================================='

# EEPROM testing
echo "=== Start EEPROM testing ==="
write_eeprom
if [ $? != 0 ]
then
	fail_count=$(($fail_count + 1))
	echo "----->               FAILURE           <-----"
	echo "$failure_msg"
else
	echo "$test_result"
fi
echo '======================================================================='

# 18. Switch cellular antenna selection DIP switch;
# 19. Press button to finalize the test;
#     (On-board test software should verify that the correct string has been written to the NFC tag.)
# 20. Confirm software-controlled tri-colour LED has changed to white;
# 21. Confirm hardware-controlled LED is yellow;

echo "=== yellowManualTest_final ==="
yellowManualTest_final
if [ $? != 0 ]
then
	fail_count=$(($fail_count + 1))
	echo "----->               FAILURE           <-----"
	echo "$failure_msg"
else
	echo "$test_result"
fi
echo '======================================================================='

# 22. Press reset button;
# 23. Confirm hardware-controlled LED goes green;
# 24. Remove power jumper;
# 25. Disconnect from USB;
# 26. Disconnect battery;
# 27. Unplug SIM, SD card, IoT card and expansion-connector test board.

# WaitForDevice "Up" "$rbTimer"

# automation test
# Wifi Test
echo "=== Start Wifi testing ==="
yellowTest_WifiScan
if [ $? != 0 ]
then
	fail_count=$(($fail_count + 1))
	echo "----->               FAILURE           <-----"
	echo "$failure_msg"
else
	echo "$test_result"
fi
echo '======================================================================='

# uSD Test
# USB Test

echo "=== Start USB testing ==="
yellowTest_USB
if [ $? != 0 ]
then
	fail_count=$(($fail_count + 1))
	echo "----->               FAILURE           <-----"
	echo "$failure_msg"
else
	echo "$test_result"
fi
echo '======================================================================='

#Automation test
echo "=== Start automation testing ==="
test_automation
if [ $? != 0 ]
then
	fail_count=$(($fail_count + 1))
	echo "----->               FAILURE           <-----"
	echo "$failure_msg"
else
	echo "$test_result"
fi
echo '======================================================================='

# echo "=== Start uSD Read Write testing ==="
# yellowTest_uSD
# if [ $? != 0 ]
# then
# 	fail_count=$(($fail_count + 1))
# 	echo "----->               FAILURE           <-----"
# 	echo "$failure_msg" 
# else
# 	echo "$test_result"
# fi
# echo '======================================================================='


# I2C address test.
echo "=== Start I2C testing ==="
yellowTest_I2CDetect
if [ $? != 0 ]
then
	fail_count=$(($fail_count + 1))
	echo "----->               FAILURE           <-----"
	echo "$failure_msg"
else
	echo "$test_result"
fi
echo '======================================================================='

# export test result
echo '-----------------------------------------------------------------------'
if [ $fail_count = 0 ]
then
	echo "Completed: success"
else
	echo "Completed: $fail_count tests failed"
fi
echo ""

# deinitial generic button
generic_button_deinit
if [ $? != 0 ]
then
	echo "Failed to deinitial Generic Button"
	exit -1
fi
sleep 1


exit $fail_count