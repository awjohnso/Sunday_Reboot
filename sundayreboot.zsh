#!/bin/zsh --no-rcs
# set -x

##########################################################################################
#                                   VARIABLES                                            #
##########################################################################################

vers="4.00"
myHost=$( /usr/sbin/scutil --get ComputerName )
myTimeStamp()
{
	/bin/date | /usr/bin/awk  '{ printf "%02s %02s %02s %02s\n", $1,$2,$3,$4 }'
}
scriptName=$( /usr/bin/basename ${0} )
myPID=$$
myLog="/var/log/jamf.log"
Numb_Arguments=$#
argument_1="${1}"
myLog="/Library/Logs/$(/usr/bin/basename ${scriptName} | /usr/bin/cut -d "." -f 1 ).log"

##########################################################################################
#                              SWIFT DIALOG VARIABLES                                    #
##########################################################################################

bannerImage="https://drive.usercontent.google.com/download?id=1kS3AV8BtrLIsqhd2b4EHAvxq16rRlabv"
overlayIcon="https://drive.usercontent.google.com/download?id=1RVqnu_A0PTf2iuaw_qAcGgeLnqkW91Xz"
icon="computer"
Title="Weekly Maintenance Restart"
messageFont="name=Verdana,size=14"
titleFont="name=Verdana,colour=#990000,shadow=1,size=22"
helpMessage="For help with your computer, please contact **Customer Engagement** https://service.stonybrook.edu."
commandFile="/private/tmp/sundayreboot.log"

##########################################################################################
#                                   FUNCTIONS                                            #
##########################################################################################

function logging()
{
    /bin/echo "$(myTimeStamp) ${myHost} ${scriptName}[${myPID}]: ${1}" | /usr/bin/tee -a "${myLog}"
}
function START_SCRIPT()
{
	/bin/echo "" | /usr/bin/tee -a "${myLog}"
	logging "Starting ${scriptName}, Version: ${vers}."
}
function EXIT_SCRIPT()
{
	logging "Ending ${scriptName}, Version: ${vers}."
	/bin/echo "" | /usr/bin/tee -a "${myLog}"
	exit ${i}
}
function MAKE_TEMP_DIR()
{
	logging "MAKE_TEMP_DIR: Starting MAKE_TEMP_DIR."
		# Make a temp directory to store downloaded files and such.
	myTmpDir=$( /usr/bin/mktemp -d )
	logging "MAKE_TEMP_DIR: Making temp directory: ${myTmpDir}"
	logging "MAKE_TEMP_DIR: Ending MAKE_TEMP_DIR."
}
function REMOVE_TEMP_DIR()
{
	logging "REMOVE_TEMP_DIR: Starting REMOVE_TEMP_DIR."
	logging "REMOVE_TEMP_DIR: Removing temp directory: ${myTmpDir}"
	/bin/rm -Rf "${myTmpDir}"
	logging "REMOVE_TEMP_DIR: Ending REMOVE_TEMP_DIR."
}
function MY_VERSION()
{
	if [[ "$1" -eq 1 ]]; then
		case $2 in
			(-v|--version)
				/bin/echo "${vers}"
				exit 0
				;;
			(*)
				exit 0
				;;
		esac
	fi
}
function DIALOG()
{
		# Formatting for the Swift Dialog.
	/usr/local/bin/dialog \
	--overlayicon "${overlayIcon}" \
	--bannerimage "${bannerImage}" \
	--commandfile "${commandFile}" \
	--width 45% \
	--height 40% \
	--ontop \
	--moveable \
	--title "${Title}" \
	--position centre \
	--titlefont "${titleFont}" \
	--icon "${icon}" \
	--iconsize 150 \
	--messagefont "${messageFont}" \
	--button1text "Restart Now" \
	--timer 900 \
	--helpmessage "${helpMessage}" \
	--message "This computer will **restartu automatically in 15 minutes** for scheduled maintenance.\n\nPlease **save your work and cliose any open applications** before the restart.
- Click **Restart Now** to restart immediately.
- Click **Snooze 10 Minutes** to restart in 10 minutes.
- Otherwise, the computer will restart automatically when the countdown reaches zero." \
	--button2 \
	--button2text "Snooze 10 Minutes" \
	--quitkey p 
	dialog_exit_code="$?"
	case ${dialog_exit_code} in
	(0)
		logging "${loggedInUser} clicked Restart Now."
		mySnoozeButton="NO"
		;;
	(2)
		logging "${loggedInUser} clicked Snooze 10 Minutes."
		mySnoozeButton="YES"
		;; 
	(4)
		logging "Timer expired."
		mySnoozeButton="NO" 
		;; 
	(10)
		logging "${loggedInUser} keyed out."
		/bin/rm -Rf /var/tmp/dialog.log
		EXIT_SCRIPT 0
		;;
	esac
}
function CHECK_FOR_IDLE()
{
		# Checks to make sure the computer can idle. Things like YouTube, Zoom, etc will prevent
		# idle, this will ensure we do not disturb meetings and such with the enduser.
	
		# Check to see if a movie, Zoom, or other program is preventing sleep or screensaver action. If so wait...
		# Check PreventUserIdleDisplaySleep: 1 don't sleep, 0 ok to sleep.
		
	PreventUserIdleDisplaySleep=$( /usr/bin/pmset -g assertions | /usr/bin/egrep -iv pid | /usr/bin/awk '/PreventUserIdleDisplaySleep/{print $2}')
	while [[ ${PreventUserIdleDisplaySleep} -gt 0 ]]; do
		logging "Prevent User Idle Display Sleep is set to prevent sleep. Waiting..."
		sleep 15
		PreventUserIdleDisplaySleep=$( /usr/bin/pmset -g assertions | /usr/bin/egrep -iv pid | /usr/bin/awk '/PreventUserIdleDisplaySleep/{print $2}')
	done
	logging "This computer is not preventing idle."
}
function CALCULATE_UPTIME()
{
		# This will calculate the uptime in Unix Epoch time and see if it's more than 7 days.
		# If it is, then it returns true 0, if not false (1).
		# In Unix shells (contrary to many other programming languages) 0 stands for true and 
		# any other (integer) value stands for false. This goes in hand with Unix programs 
		# returning 0 on successful completion and any other value (usually between 1 and 255) 
		# indicates some negative result or error. So you should return 0 if the file exists 
		# and 1 if it does not.
		
	myBootTimeEpoch=$( /usr/sbin/sysctl kern.boottime | /usr/bin/awk '{print $5}' | /usr/bin/sed 's/,//' )
	myCurrentTimeEpoch=$( /bin/date +"%s" )
	myUpTimeEpoch=$(($myCurrentTimeEpoch-$myBootTimeEpoch))
		# 604800seconds equals 7 days.
	if [ ${myUpTimeEpoch} -ge 604800 ]; then
		logging "Uptime is equal or greater to 7 days."
	else
		logging "Uptime is less than 7 days."
		EXIT_SCRIPT 0
	fi
}
function CHECK_FOR_SWIFT_DIALOG()
{
		# Checks to ensure Swift Dialog is installed. If not tries to install it from Jamf.
		# If still unavailable then returns false (1), else if present returns true (0).
		# In Unix shells (contrary to many other programming languages) 0 stands for true and 
		# any other (integer) value stands for false. This goes in hand with Unix programs 
		# returning 0 on successful completion and any other value (usually between 1 and 255) 
		# indicates some negative result or error. So you should return 0 if the file exists 
		# and 1 if it does not.
	if [ ! -e "/usr/local/bin/dialog" ]; then
		logging "Did not find Swift Dialog. Will try to install it."
		/usr/local/bin/jamf -policy -event "InstallDialog" -forceNoRecon -doNotRestart -noInteraction -skipAppUpdates
		if [ ! -e "/usr/local/bin/dialog" ]; then
			logging "Swift Dialog did not install."
		fi
	else
		logging "Swift Dialog has been found."
	fi
}
function CHECK_FOR_USER()
{
		# Checks to see if a user is logged in on the console.
		# If someone is, then it returns true (0) if not false (1).
		# In Unix shells (contrary to many other programming languages) 0 stands for true and 
		# any other (integer) value stands for false. This goes in hand with Unix programs 
		# returning 0 on successful completion and any other value (usually between 1 and 255) 
		# indicates some negative result or error. So you should return 0 if the file exists 
		# and 1 if it does not.
	loggedInUser=$( /usr/sbin/scutil <<< "show State:/Users/ConsoleUser" | /usr/bin/awk '/Name :/ && ! /loginwindow/ { print $3 }' )
	if [ -z ${loggedInUser} ]; then
		logging "There is no user logged into the console."
		return 1
	else
		logging "${loggedInUser} user is logged into the console."
		return 0
	fi
}
function PREVENT_IDLE()
{
		# This will prevent idle/sleep and such as long as on AC power, while the dialog is up.
		# Once the PID of this script ends it will also end the caffeinate process.
		
	/usr/bin/caffeinate -s -w ${myPID} &
}
function REBOOT()
{
		# Checking for a logged in user. If no one is logged in just reboot. If someone is
		# logged in, check for idle prevention. Then caffeinate the system as long as on AC, 
		# and then present the user with a Swift Dialog to allow them to reboot right away,
		# in ten minutes, or when the fifteen minute timer ends.
		
	if (CHECK_FOR_USER); then
			 # User is logged in.
		CHECK_FOR_IDLE
		PREVENT_IDLE
		logging "Presenting Swift Dialog."
		DIALOG
		if [ "${mySnoozeButton}" = "NO" ]; then
				# User did not hit snooze. User clicked reboot or timer ran out.
			logging "Restarting this computer now."

			/usr/bin/defaults write /Library/Preferences/edu.stonybrook.doit.rebootsundaytime restartTimeEpoch -array-add -int $( /bin/date +"%s" )
				# Reboot
			/sbin/shutdown -r +5s
		elif [ "${mySnoozeButton}" = "YES" ]; then
				# User pressed snooze.
			logging "Restarting this computer in 10 minutes."
			/sbin/shutdown -r +10m
			/usr/bin/defaults write /Library/Preferences/edu.stonybrook.doit.rebootsundaytime restartTimeEpoch -array-add -int $(( $(/bin/date +"%s") + 600 ))
		fi
	else
			# No user logged in. Reboot right away.
		logging "Rebooting the computer now."
		/usr/bin/defaults write /Library/Preferences/edu.stonybrook.doit.rebootsundaytime restartTimeEpoch -array-add -int $( /bin/date +"%s" )
			# Reboot
		/sbin/shutdown -r +5s
	fi
}

##########################################################################################
#                                   MAIN                                                 #
##########################################################################################

MY_VERSION ${Numb_Arguments} ${argument_1}
START_SCRIPT

	# Checking for Swift Dialog.
CHECK_FOR_SWIFT_DIALOG
	# Checking for uptime.
CALCULATE_UPTIME
	# Call for reboot.
REBOOT

EXIT_SCRIPT 0
