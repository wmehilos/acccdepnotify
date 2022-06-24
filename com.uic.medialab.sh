#!/bin/bash
#
#
#Created by William Mehilos, University of Illinois (wmehilos@uic.edu)
#with heavy inspiration drawn from similar work done by John Mahlman (jmahlman@uarts.edu)
#
#Purpose: Install and run DEPNotify at enrollment time and display policy progress to end user.
#This script gets installed with DEPNotify, the LaunchDaemon plist that will launch it, and any
#supporting files. 
#
#This edition is for the Media Lab Loaners per TDX#389337
# Started:
#06/23/2022
#
#
#Variable Definitions
JAMFBIN=/usr/local/bin/jamf
#Get OS version numbers into their respective variables
OLDIFS=$IFS
IFS='.' read OS_MAJ OS_MIN OS_PAT <<< "$(/usr/bin/sw_vers -productVersion)"
IFS=$OLDIFS
OS_BLD=$(sw_vers -buildVersion)
PROC="$(/usr/sbin/sysctl -n machdep.cpu.brand_string | awk '{print $1}')"
# Moved Apple Silicon/Rosetta checks to preinstall on ACCC DEPNotify-1.1.pkg
setupDone="/Library/Application Support/JAMF/Receipts/.depCompleted"
DNLOG=/var/tmp/depnotify.log
CURRENTUSER=$(/usr/bin/python -c 'from SystemConfiguration import SCDynamicStoreCopyConsoleUser; import sys; username = (SCDynamicStoreCopyConsoleUser(None, None, None) or [None])[0]; username = [username,""][username in [u"loginwindow", None, u""]]; sys.stdout.write(username + "\n");')

#If for some reason DEP setup has already been successfully completed, remove script and LD
if [[ -f "${setupDone}" ]]; then
	#Remove LD
	/bin/rm -Rf /Library/LaunchDaemons/com.uic.acccdep.launch.plist
	#Remove Self
	/bin/rm -Rf "$0"
	exit 0
fi

#Hold...hold..., wait until a user is logged in completely before doing anything.
if pgrep -x "Finder" \
&& pgrep -x "Dock" \
&& [[ "$CURRENTUSER" != "_mbsetupuser" ]] \
&& [[ ! -f "${setupDone}" ]]; then	
	
	#Grab some coffee
	/usr/bin/caffeinate -d -i -m -u -s &
	caffeinatepid=$!
	
	#Preempt any other installers
	killall Installer
	#Then rest to contemplate what you've done, you monster.
	sleep 5
	
	#Configure DEPNotify starting window
	echo "Command: MainTitle: Preparing your Media Lab Loaner..." >> $DNLOG
	echo "Command: Image: /var/tmp/ts.png" >> $DNLOG
	echo "Command: WindowStyle: NotMoveable" >> $DNLOG
	echo "Command: Determinate: 8" >> $DNLOG
	echo "Command: MainText: This Mac is installing all necessary software and running some configuration tasks. \
	Please do not interrupt this process or close the lid. The Mac will restart when it is complete. \
	Additonal software like alternative browsers can be found in Software Center.app found in the Applications folder or Launchpad. \
  Adobe Creative Cloud applications can be downloaded on demand from the Creative Cloud app." >> $DNLOG
	
	#Invoke DEPNotify app binary
	sudo -u "$CURRENTUSER" /var/tmp/DEPNotify.app/Contents/MacOS/DEPNotify -fullScreen &
	echo "Status: Downloading Microsoft Office 365" >> $DNLOG
  ##TODO: Throw in a VL policy too
	"$JAMFBIN" policy -event depNotifyDLO365
	echo "Status: Installing Microsoft Office 365" >> $DNLOG
	"$JAMFBIN" policy -event depNotifyInstO365
	echo "Status: Downloading Microsoft Defender for Endpoint" >> $DNLOG
	"$JAMFBIN" policy -event depNotifyWDAVDL
	echo "Status: Installing Microsoft Defender for Endpoint" >> $DNLOG
	"$JAMFBIN" policy -event depNotifyWDAVIN
	#Changed this from a simple pgrep Microsoft to the actual process names to not interfere with Defender
	#We have to kill MAU here to ensure a successful reboot at the end
	kill $(pgrep Microsoft\ AutoUpdate)
	#Run it again to shut up Error Reporting 
	kill $(pgrep Microsoft\ Error\ Reporting)
	#Unload MAU LaunchDaemon
	launchctl unload /Library/LaunchDaemons/com.microsoft.autoupdate.helper.plist
	echo "Status: Downloading and installing Zoom" >> $DNLOG
	"$JAMFBIN" policy -event depNotifyWebex
	#Quit Zoom in case it tries to launch
	sleep 10
	kill $(pgrep Zoom)
  ## TODO
  # Need a WEPA install policy TODO
  ## TODO
	echo "Status: Downloading and Installing Cisco AnyConnect VPN" >> $DNLOG
	"$JAMFBIN" policy -event depNotifyVPN
	echo "Status: Finalizing and cleaning up." >> $DNLOG
	"$JAMFBIN" policy -event depNotifyFinalize
	#Moving SUS here, since sometimes it can cause unscheduled reboots to complete OS updates
	echo "Status: Checking with Apple for Software Updates. Your Mac will reboot soon." >> $DNLOG
	"$JAMFBIN" policy -event depNotifyAppleSUS


  #Pop an Ambien to counter act that coffee
  kill $caffeinatepid	
	## TODO
  ## Test and modify this behavior below a bit better
  ## TODO
  #Show user a restart button and message
  echo "Command: Alert: Your Mac has completed it's initial setup. " >> $DNLOG
  #echo "Command: MainText: We\'re all done here! To use Adobe products off campus, connect to the UIC VPN first." >> $DNLOG
  #echo "Command: ContinueButtonRestart: Restart" >> $DNLOG



fi
exit 0	
